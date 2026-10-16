# Azure · Bloqueos de recursos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3, `azure-resourcemanager-resources` 2.55**. Verifica las vigentes.

## Qué puede hacer una aplicación Java con los bloqueos (y qué no)

Los bloqueos **no se "usan" desde la aplicación de negocio**: los aplica ARM. Tu código sirve para tareas **de plataforma**:

| Caso | Qué haces desde Java |
|---|---|
| **Entender el rechazo** | Cuando tu servicio de autoservicio borra o modifica algo y recibe `ScopeLocked`, devolver un mensaje claro: *qué alcance* está bloqueado y *cuál es el procedimiento* |
| **Proteger como parte del aprovisionamiento** | Al crear un entorno de cliente, ponerle el bloqueo `CanNotDelete` (idempotente) |
| **Auditar** | Listar los grupos de producción **sin** bloqueo y publicar una métrica |
| **Borrado controlado** | Quitar el bloqueo, borrar y restaurar si algo falla, **solo con un ticket aprobado** |
| **Pilas de despliegue** | Crear o consultar pilas con `denySettings` (protección de todo un entorno) |

> Estos SDK son **de administración** (plano de control): síncronos, con latencias de cientos de milisegundos a segundos y cuotas de ARM. **No los pongas en el camino caliente** de una API de clientes. Y **tu código nunca debe quitar bloqueos por su cuenta**: solo dentro de un procedimiento con aprobación y registro.

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-resources</artifactId></dependency>
```

**Permisos de la identidad de la aplicación** (identidad administrada, sin claves):

| Operación | Rol mínimo | Alcance |
|---|---|---|
| Listar bloqueos y auditar | *Reader* | Suscripción |
| Crear bloqueos de protección (aprovisionamiento) | Rol personalizado con `Microsoft.Authorization/locks/write` | Suscripción de entornos |
| Quitar bloqueos (borrado controlado) | Rol personalizado con `Microsoft.Authorization/locks/delete` **y** *Contributor* en el grupo; asignada a una identidad **distinta** de la del servicio de lectura | Grupo de recursos |
| Listar o crear pilas de despliegue | `Microsoft.Resources/deploymentStacks/*` (más los permisos de los recursos que despliega la plantilla) | Grupo o suscripción |

## 1. El error `ScopeLocked`: qué alcances están bloqueados

Cuando un bloqueo impide la operación, ARM responde con el código **`ScopeLocked`** y un mensaje que indica el alcance de la operación y los alcances bloqueados (por ejemplo, `…because following scope(s) are locked: '/subscriptions/…/resourceGroups/…'`). El código es el dato estable; la lista de alcances sale del texto del mensaje, así que el lector es tolerante: si el formato cambia, devuelve la lista vacía y conserva el mensaje.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.management.exception.ManagementError;
import com.azure.core.management.exception.ManagementException;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Un bloqueo impidió la operación: código, mensaje de Azure y alcances que tienen el bloqueo. */
record BloqueoDetectado(String codigo, String mensaje, List<String> alcancesBloqueados) { }

final class ErroresDeBloqueo {

    private static final String CODIGO = "ScopeLocked";
    private static final Pattern ALCANCE = Pattern.compile("(/subscriptions/[^'\"\\s,;]+)", Pattern.CASE_INSENSITIVE);

    private ErroresDeBloqueo() { }

    /** ¿Es un rechazo por bloqueo (en la raíz o anidado, como en los despliegues)? */
    static boolean esBloqueo(ManagementException e) {
        return e.getValue() != null && buscar(e.getValue()) != null;
    }

    static Optional<BloqueoDetectado> analizar(ManagementException e) {
        ManagementError error = e.getValue() == null ? null : buscar(e.getValue());
        if (error == null) {
            return Optional.empty();
        }
        String mensaje = error.getMessage() == null ? "" : error.getMessage();
        return Optional.of(new BloqueoDetectado(error.getCode(), mensaje, alcances(mensaje)));
    }

    private static ManagementError buscar(ManagementError error) {
        if (CODIGO.equalsIgnoreCase(error.getCode())) {
            return error;
        }
        if (error.getDetails() != null) {
            for (ManagementError hijo : error.getDetails()) {
                ManagementError encontrado = buscar(hijo);
                if (encontrado != null) {
                    return encontrado;
                }
            }
        }
        return null;
    }

    /** Alcances que aparecen DESPUÉS de "are locked" (los anteriores son el alcance de la operación). */
    static List<String> alcances(String mensaje) {
        List<String> resultado = new ArrayList<>();
        int desde = mensaje.toLowerCase(Locale.ROOT).indexOf("are locked");
        if (desde < 0) {
            return resultado;
        }
        Matcher m = ALCANCE.matcher(mensaje.substring(desde));
        while (m.find()) {
            String alcance = m.group(1);
            while (alcance.endsWith(".")) {
                alcance = alcance.substring(0, alcance.length() - 1);
            }
            if (!resultado.contains(alcance)) {
                resultado.add(alcance);
            }
        }
        return resultado;
    }
}
```

## 2. Listar, proteger y auditar bloqueos

`ResourceManager.managementLocks()` ofrece la API fluida. Tres ideas importantes:
- **Crear es idempotente en tu servicio:** si ya existe un bloqueo con ese nombre en el grupo, lo devuelve (así el aprovisionamiento se puede repetir).
- **`ReadOnly` exige decisión explícita:** el servicio lo rechaza salvo que la configuración lo permita (recuerda la tabla de efectos del [README](README.md#24-lo-que-se-rompe-con-los-bloqueos-leerlo-antes-de-aplicarlos)).
- **Auditar = comparar:** grupos de producción (etiqueta `env=prod`) frente a los alcances que tienen bloqueo (propio o heredado de la suscripción).

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.resources.ResourceManager;
import com.azure.resourcemanager.resources.models.LockLevel;
import com.azure.resourcemanager.resources.models.ManagementLock;
import com.azure.resourcemanager.resources.models.ResourceGroup;

import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/** Un bloqueo tal como lo ve la aplicación. */
record InfoBloqueo(String id, String nombre, String nivel, String notas, String alcanceBloqueado) { }

/** Resultado de la auditoría: cuántos grupos de producción hay y cuáles no están protegidos. */
record InformeDeBloqueos(int gruposDeProduccion, List<String> sinBloqueo) { }

final class BloqueosServicio {

    private final ResourceManager recursos;
    private final boolean permitirSoloLectura;

    BloqueosServicio(ResourceManager recursos, boolean permitirSoloLectura) {
        this.recursos = recursos;
        this.permitirSoloLectura = permitirSoloLectura;
    }

    /** Todos los bloqueos de la suscripción (de cualquier alcance). */
    List<InfoBloqueo> todos() {
        return recursos.managementLocks().list().stream().map(BloqueosServicio::aInfo).toList();
    }

    List<InfoBloqueo> delGrupo(String grupo) {
        return recursos.managementLocks().listByResourceGroup(grupo).stream().map(BloqueosServicio::aInfo).toList();
    }

    List<InfoBloqueo> delRecurso(String idDelRecurso) {
        return recursos.managementLocks().listForResource(idDelRecurso).stream().map(BloqueosServicio::aInfo).toList();
    }

    /** Protege un grupo de recursos. Si ya existe un bloqueo con ese nombre, lo devuelve sin crear otro. */
    InfoBloqueo protegerGrupo(String grupo, String nombre, LockLevel nivel, String notas) {
        validar(nivel, notas);
        Optional<InfoBloqueo> existente = delGrupo(grupo).stream()
                .filter(b -> b.nombre().equalsIgnoreCase(nombre) && esDelGrupo(b, grupo))
                .findFirst();
        if (existente.isPresent()) {
            return existente.get();
        }
        ManagementLock creado = recursos.managementLocks().define(nombre)
                .withLockedResourceGroup(grupo)
                .withLevel(nivel)
                .withNotes(notas)
                .create();
        return aInfo(creado);
    }

    /** Protege un recurso concreto (por su identificador completo de ARM). */
    InfoBloqueo protegerRecurso(String idDelRecurso, String nombre, LockLevel nivel, String notas) {
        validar(nivel, notas);
        ManagementLock creado = recursos.managementLocks().define(nombre)
                .withLockedResource(idDelRecurso)
                .withLevel(nivel)
                .withNotes(notas)
                .create();
        return aInfo(creado);
    }

    /** Quita un bloqueo. Úsalo SOLO desde un procedimiento aprobado (ver BorradoControlado). */
    void quitar(String idDelBloqueo) {
        recursos.managementLocks().deleteById(idDelBloqueo);
    }

    /** Grupos de producción sin bloqueo propio ni heredado de la suscripción. */
    InformeDeBloqueos auditarProduccion() {
        Set<String> bloqueados = new HashSet<>();
        for (InfoBloqueo b : todos()) {
            bloqueados.add(normalizar(b.alcanceBloqueado()));
        }
        List<String> sinBloqueo = new ArrayList<>();
        int total = 0;
        for (ResourceGroup grupo : recursos.resourceGroups().list()) {
            Map<String, String> etiquetas = grupo.tags();
            if (etiquetas == null || !"prod".equalsIgnoreCase(etiquetas.get("env"))) {
                continue;
            }
            total++;
            boolean protegido = bloqueados.contains(normalizar(grupo.id()))
                    || bloqueados.contains(normalizar(suscripcionDe(grupo.id())));
            if (!protegido) {
                sinBloqueo.add(grupo.name());
            }
        }
        return new InformeDeBloqueos(total, List.copyOf(sinBloqueo));
    }

    static boolean esDelGrupo(InfoBloqueo bloqueo, String grupo) {
        return normalizar(bloqueo.alcanceBloqueado()).endsWith("/resourcegroups/" + grupo.toLowerCase(Locale.ROOT));
    }

    private void validar(LockLevel nivel, String notas) {
        if (LockLevel.NOT_SPECIFIED.equals(nivel)) {
            throw new IllegalArgumentException("Indica el nivel del bloqueo");
        }
        if (LockLevel.READ_ONLY.equals(nivel) && !permitirSoloLectura) {
            throw new IllegalArgumentException("ReadOnly no está permitido por configuración: usa CanNotDelete o pide una excepción");
        }
        if (notas == null || notas.isBlank()) {
            throw new IllegalArgumentException("Todo bloqueo lleva notas: motivo, dueño y ticket");
        }
    }

    private static InfoBloqueo aInfo(ManagementLock b) {
        return new InfoBloqueo(b.id(), b.name(), String.valueOf(b.level()), b.notes(), b.lockedResourceId());
    }

    private static String suscripcionDe(String idDeGrupo) {
        int i = idDeGrupo.toLowerCase(Locale.ROOT).indexOf("/resourcegroups/");
        return i < 0 ? idDeGrupo : idDeGrupo.substring(0, i);
    }

    private static String normalizar(String id) {
        if (id == null) {
            return "";
        }
        String bajo = id.toLowerCase(Locale.ROOT);
        return bajo.endsWith("/") ? bajo.substring(0, bajo.length() - 1) : bajo;
    }
}
```

## 3. Borrado controlado: quitar el bloqueo, borrar y restaurar si falla

El procedimiento del [README](README.md#5-cómo-se-usa) hecho código. Reglas de seguridad:
- **Sin ticket aprobado no se hace nada** (`SistemaDeTickets` es la puerta; conéctalo a tu herramienta de tickets).
- **Solo quita los bloqueos del propio grupo.** Si hay otros (en la suscripción o en recursos hijos), **no los toca**: devuelve el resultado "bloqueado por otros alcances" para que decida su dueño.
- **Si el borrado falla, restaura** los bloqueos que quitó.
- La ventana entre quitar y borrar es de segundos; el grupo queda sin freno durante ese tiempo. Por eso la identidad que ejecuta esto es **distinta** y tiene alertas (el borrado del bloqueo dispara la alerta del registro de actividad).

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.resources.models.LockLevel;

/** Puerta de aprobación: conéctala a Jira, ServiceNow, etc. */
interface SistemaDeTickets {
    boolean aprobado(String ticket, String recurso);
}

/** Resultado del borrado controlado: estado, bloqueos que se quitaron y, si aplica, los alcances que lo impiden. */
record ResultadoDeBorrado(String estado, String grupo, List<String> bloqueosQuitados, List<String> alcancesBloqueados, String detalle) {

    static ResultadoDeBorrado borrado(String grupo, List<String> quitados) {
        return new ResultadoDeBorrado("BORRADO", grupo, quitados, List.of(), "Grupo eliminado");
    }

    static ResultadoDeBorrado noAprobado(String grupo) {
        return new ResultadoDeBorrado("NO_APROBADO", grupo, List.of(), List.of(), "El ticket no está aprobado para este grupo");
    }

    static ResultadoDeBorrado bloqueadoPorOtros(String grupo, List<String> alcances, String detalle) {
        return new ResultadoDeBorrado("BLOQUEADO", grupo, List.of(), alcances, detalle);
    }
}

final class BorradoControlado {

    private final ResourceManager recursos;
    private final BloqueosServicio bloqueos;
    private final SistemaDeTickets tickets;

    BorradoControlado(ResourceManager recursos, BloqueosServicio bloqueos, SistemaDeTickets tickets) {
        this.recursos = recursos;
        this.bloqueos = bloqueos;
        this.tickets = tickets;
    }

    ResultadoDeBorrado borrarGrupo(String grupo, String ticket) {
        if (ticket == null || !tickets.aprobado(ticket, grupo)) {
            return ResultadoDeBorrado.noAprobado(grupo);
        }
        List<InfoBloqueo> propios = bloqueos.delGrupo(grupo).stream()
                .filter(b -> BloqueosServicio.esDelGrupo(b, grupo))
                .toList();
        for (InfoBloqueo bloqueo : propios) {
            bloqueos.quitar(bloqueo.id());
        }
        try {
            recursos.resourceGroups().deleteByName(grupo);
            return ResultadoDeBorrado.borrado(grupo, propios.stream().map(InfoBloqueo::nombre).toList());
        } catch (ManagementException e) {
            restaurar(grupo, propios);
            Optional<BloqueoDetectado> otro = ErroresDeBloqueo.analizar(e);
            if (otro.isPresent()) {
                return ResultadoDeBorrado.bloqueadoPorOtros(grupo, otro.get().alcancesBloqueados(), otro.get().mensaje());
            }
            throw e;
        }
    }

    /** Vuelve a dejar el grupo protegido: el borrado no ocurrió. */
    private void restaurar(String grupo, List<InfoBloqueo> quitados) {
        for (InfoBloqueo b : quitados) {
            LockLevel nivel = LockLevel.fromString(b.nivel());
            recursos.managementLocks().define(b.nombre())
                    .withLockedResourceGroup(grupo)
                    .withLevel(nivel)
                    .withNotes(b.notas() == null ? "Restaurado tras un borrado fallido" : b.notas())
                    .create();
        }
    }
}
```

## 4. Pilas de despliegue con `denySettings`

Para proteger **un entorno completo** (no recursos sueltos), despliégalo como pila. El SDK expone el cliente de pilas en `ResourceManager.deploymentStackClient()`. La pila:
- gestiona los recursos de la plantilla como una unidad;
- con `denyWriteAndDelete`, **nadie** (salvo los principales excluidos, máximo 5) puede modificar ni borrar lo que gestiona;
- con `actionOnUnmanage = DELETE`, si quitas un recurso de la plantilla, se borra de verdad.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.resources.fluent.models.DeploymentStackInner;
import com.azure.resourcemanager.resources.models.ActionOnUnmanage;
import com.azure.resourcemanager.resources.models.DenySettings;
import com.azure.resourcemanager.resources.models.DenySettingsMode;
import com.azure.resourcemanager.resources.models.DeploymentParameter;
import com.azure.resourcemanager.resources.models.DeploymentStacksDeleteDetachEnum;

import java.util.HashMap;

/** Resumen de una pila de despliegue. */
record InfoPila(String nombre, String modoDeDenegacion, boolean aplicaAHijos, List<String> principalesExcluidos,
                String estado, int recursosGestionados) { }

final class PilasDeDespliegue {

    private static final int MAXIMO_EXCLUIDOS = 5;

    private final ResourceManager recursos;

    PilasDeDespliegue(ResourceManager recursos) {
        this.recursos = recursos;
    }

    List<InfoPila> delGrupo(String grupo) {
        return recursos.deploymentStackClient().getDeploymentStacks().listByResourceGroup(grupo).stream()
                .map(PilasDeDespliegue::aInfo)
                .toList();
    }

    /** Crea o actualiza una pila que protege todo lo que despliega la plantilla. */
    InfoPila protegerEntorno(String grupo, String nombre, Map<String, Object> plantilla, Map<String, Object> parametros,
                             List<String> principalesExcluidos) {
        if (principalesExcluidos.size() > MAXIMO_EXCLUIDOS) {
            throw new IllegalArgumentException("Una pila admite como máximo " + MAXIMO_EXCLUIDOS + " principales excluidos");
        }
        Map<String, DeploymentParameter> valores = new HashMap<>();
        parametros.forEach((clave, valor) -> valores.put(clave, new DeploymentParameter().withValue(valor)));

        DeploymentStackInner pila = new DeploymentStackInner()
                .withTemplate(plantilla)
                .withParameters(valores)
                .withActionOnUnmanage(new ActionOnUnmanage().withResources(DeploymentStacksDeleteDetachEnum.DELETE))
                .withDenySettings(new DenySettings()
                        .withMode(DenySettingsMode.DENY_WRITE_AND_DELETE)
                        .withExcludedPrincipals(principalesExcluidos)
                        .withApplyToChildScopes(true));

        return aInfo(recursos.deploymentStackClient().getDeploymentStacks().createOrUpdateAtResourceGroup(grupo, nombre, pila));
    }

    private static InfoPila aInfo(DeploymentStackInner pila) {
        DenySettings deny = pila.denySettings();
        return new InfoPila(
                pila.name(),
                deny == null || deny.mode() == null ? "none" : deny.mode().toString(),
                deny != null && Boolean.TRUE.equals(deny.applyToChildScopes()),
                deny == null || deny.excludedPrincipals() == null ? List.of() : List.copyOf(deny.excludedPrincipals()),
                String.valueOf(pila.provisioningState()),
                pila.resources() == null ? 0 : pila.resources().size());
    }
}
```

## 5. Métrica: grupos de producción sin bloqueo (refresco en segundo plano)

La auditoría recorre grupos y bloqueos: **no la hagas en cada solicitud**. Refréscala cada 30 minutos y expón un *gauge* para alertar ("más de 0 grupos de producción sin bloqueo").

```java
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicInteger;

@Component
@EnableScheduling
class MetricasDeBloqueos {

    private final BloqueosServicio bloqueos;
    private final AtomicInteger sinBloqueo = new AtomicInteger();
    private final AtomicInteger gruposDeProduccion = new AtomicInteger();

    MetricasDeBloqueos(MeterRegistry registro, BloqueosServicio bloqueos) {
        this.bloqueos = bloqueos;
        Gauge.builder("modalima.bloqueos.grupos_prod_sin_bloqueo", sinBloqueo, AtomicInteger::get).register(registro);
        Gauge.builder("modalima.bloqueos.grupos_prod_total", gruposDeProduccion, AtomicInteger::get).register(registro);
    }

    @Scheduled(initialDelayString = "PT45S", fixedDelayString = "PT30M")
    void refrescar() {
        try {
            InformeDeBloqueos informe = bloqueos.auditarProduccion();
            gruposDeProduccion.set(informe.gruposDeProduccion());
            sinBloqueo.set(informe.sinBloqueo().size());
        } catch (RuntimeException e) {
            // conserva el último valor: un fallo de ARM no debe borrar la métrica
        }
    }
}
```

## 6. Clientes de Azure (un solo `TokenCredential` y un solo perfil)

`DefaultAzureCredential` toma la identidad administrada en Azure y tu sesión de `az login` en el computador. Crea **un `ResourceManager`** y reutilízalo.

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class AzureBloqueosConfig {

    @Bean
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Bean
    AzureProfile perfil(@Value("${azure.tenant-id}") String tenant,
                        @Value("${azure.subscription-id}") String suscripcion) {
        return new AzureProfile(tenant, suscripcion, AzureEnvironment.AZURE);
    }

    @Bean
    ResourceManager recursos(TokenCredential credencial, AzureProfile perfil) {
        return ResourceManager.authenticate(credencial, perfil).withDefaultSubscription();
    }

    @Bean
    BloqueosServicio bloqueos(ResourceManager recursos,
                              @Value("${gobierno.bloqueos.permitir-solo-lectura:false}") boolean permitirSoloLectura) {
        return new BloqueosServicio(recursos, permitirSoloLectura);
    }

    @Bean
    BorradoControlado borradoControlado(ResourceManager recursos, BloqueosServicio bloqueos, SistemaDeTickets tickets) {
        return new BorradoControlado(recursos, bloqueos, tickets);
    }

    @Bean
    PilasDeDespliegue pilas(ResourceManager recursos) {
        return new PilasDeDespliegue(recursos);
    }
}
```
```yaml
# application.yml
azure:
  tenant-id: ${AZURE_TENANT_ID}
  subscription-id: ${AZURE_SUBSCRIPTION_ID}
gobierno:
  bloqueos:
    permitir-solo-lectura: false   # ReadOnly solo con decisión explícita
```

## 7. Spring MVC: controlador y traducción del error

El consejo global convierte `ScopeLocked` en un **409 con detalle** (los alcances bloqueados y el procedimiento), en lugar de un 500 opaco. Los demás errores de ARM se traducen sin exponer detalles internos.

```java
import com.azure.core.http.HttpHeaderName;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestController
@RequestMapping("/gobierno")
class BloqueosControlador {

    record PeticionDeProteccion(String notas) { }

    private final BloqueosServicio bloqueos;
    private final BorradoControlado borrado;
    private final PilasDeDespliegue pilas;

    BloqueosControlador(BloqueosServicio bloqueos, BorradoControlado borrado, PilasDeDespliegue pilas) {
        this.bloqueos = bloqueos;
        this.borrado = borrado;
        this.pilas = pilas;
    }

    @GetMapping("/bloqueos")
    List<InfoBloqueo> listar(@RequestParam(required = false) String grupo) {
        return grupo == null ? bloqueos.todos() : bloqueos.delGrupo(grupo);
    }

    @GetMapping("/bloqueos/auditoria")
    InformeDeBloqueos auditoria() {
        return bloqueos.auditarProduccion();
    }

    @GetMapping("/grupos/{grupo}/pilas")
    List<InfoPila> pilasDelGrupo(@PathVariable String grupo) {
        return pilas.delGrupo(grupo);
    }

    @PostMapping("/grupos/{grupo}/proteccion")
    InfoBloqueo proteger(@PathVariable String grupo, @RequestBody PeticionDeProteccion peticion) {
        return bloqueos.protegerGrupo(grupo, "lock-cannotdelete-" + grupo, LockLevel.CAN_NOT_DELETE, peticion.notas());
    }

    @DeleteMapping("/grupos/{grupo}")
    org.springframework.http.ResponseEntity<ResultadoDeBorrado> borrar(@PathVariable String grupo, @RequestParam String ticket) {
        ResultadoDeBorrado resultado = borrado.borrarGrupo(grupo, ticket);
        return switch (resultado.estado()) {
            case "BORRADO" -> org.springframework.http.ResponseEntity.ok(resultado);
            case "NO_APROBADO" -> org.springframework.http.ResponseEntity.status(HttpStatus.FORBIDDEN).body(resultado);
            default -> org.springframework.http.ResponseEntity.status(HttpStatus.CONFLICT).body(resultado);
        };
    }
}

@RestControllerAdvice
class ErroresDeAzureAdvice {

    @ExceptionHandler(IllegalArgumentException.class)
    ProblemDetail solicitudInvalida(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(ManagementException.class)
    ProblemDetail errorDeAzure(ManagementException e) {
        var bloqueo = ErroresDeBloqueo.analizar(e);
        if (bloqueo.isPresent()) {
            ProblemDetail problema = ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT,
                    "El recurso está protegido por un bloqueo. Pide el borrado controlado con un ticket aprobado.");
            problema.setTitle("Recurso bloqueado");
            problema.setProperty("alcancesBloqueados", bloqueo.get().alcancesBloqueados());
            return problema;
        }
        int estado = e.getResponse() == null ? 502 : e.getResponse().getStatusCode();
        HttpStatus http = estado == 403 ? HttpStatus.FORBIDDEN : estado == 404 ? HttpStatus.NOT_FOUND : HttpStatus.BAD_GATEWAY;
        ProblemDetail problema = ProblemDetail.forStatusAndDetail(http, "Azure rechazó la operación");
        if (e.getResponse() != null) {
            String correlacion = e.getResponse().getHeaders().getValue(HttpHeaderName.fromString("x-ms-correlation-request-id"));
            if (correlacion != null) {
                problema.setProperty("correlacion", correlacion);
            }
        }
        return problema;
    }
}
```

## 8. Spring WebFlux (reactivo): envolver los SDK bloqueantes

Los SDK de administración son **bloqueantes**. En WebFlux nunca los llames directamente en el hilo de eventos: envuélvelos en `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`. Con Java 21 también puedes usar **hilos virtuales** (`spring.threads.virtual.enabled=true`) y escribir código imperativo.

```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno")
class BloqueosReactivoControlador {

    private final BloqueosServicio bloqueos;

    BloqueosReactivoControlador(BloqueosServicio bloqueos) {
        this.bloqueos = bloqueos;
    }

    @GetMapping("/bloqueos")
    Mono<List<InfoBloqueo>> listar() {
        return Mono.fromCallable(bloqueos::todos).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/bloqueos/auditoria")
    Mono<InformeDeBloqueos> auditoria() {
        return Mono.fromCallable(bloqueos::auditarProduccion).subscribeOn(Schedulers.boundedElastic());
    }
}
```

## 9. Quarkus · imperativo

Productores CDI para el administrador de Azure y los servicios (las clases de las secciones 1 a 4 no dependen de ningún marco). El *mapper* de excepciones hace lo mismo que el consejo de Spring.

```java
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AzureBloqueosProductores {

    @ConfigProperty(name = "azure.tenant-id")
    String tenant;

    @ConfigProperty(name = "azure.subscription-id")
    String suscripcion;

    @ConfigProperty(name = "gobierno.bloqueos.permitir-solo-lectura", defaultValue = "false")
    boolean permitirSoloLectura;

    @Produces
    @Singleton
    ResourceManager recursos() {
        TokenCredential credencial = new DefaultAzureCredentialBuilder().build();
        AzureProfile perfil = new AzureProfile(tenant, suscripcion, AzureEnvironment.AZURE);
        return ResourceManager.authenticate(credencial, perfil).withDefaultSubscription();
    }

    @Produces
    @Singleton
    BloqueosServicio bloqueos(ResourceManager recursos) {
        return new BloqueosServicio(recursos, permitirSoloLectura);
    }

    @Produces
    @Singleton
    BorradoControlado borrado(ResourceManager recursos, BloqueosServicio bloqueos, SistemaDeTickets tickets) {
        return new BorradoControlado(recursos, bloqueos, tickets);
    }
}
```

```java
import jakarta.inject.Inject;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.reactive.server.ServerExceptionMapper;

import java.util.Map;

@Path("/gobierno")
@Produces(MediaType.APPLICATION_JSON)
class BloqueosRecurso {

    @Inject
    BloqueosServicio bloqueos;

    @Inject
    BorradoControlado borrado;

    @GET
    @Path("/bloqueos")
    List<InfoBloqueo> listar(@QueryParam("grupo") String grupo) {
        return grupo == null ? bloqueos.todos() : bloqueos.delGrupo(grupo);
    }

    @GET
    @Path("/bloqueos/auditoria")
    InformeDeBloqueos auditoria() {
        return bloqueos.auditarProduccion();
    }

    @DELETE
    @Path("/grupos/{grupo}")
    Response borrar(@PathParam("grupo") String grupo, @QueryParam("ticket") String ticket) {
        ResultadoDeBorrado resultado = borrado.borrarGrupo(grupo, ticket);
        int estado = switch (resultado.estado()) {
            case "BORRADO" -> 200;
            case "NO_APROBADO" -> 403;
            default -> 409;
        };
        return Response.status(estado).entity(resultado).build();
    }

    @ServerExceptionMapper
    Response errorDeAzure(ManagementException e) {
        return ErroresDeBloqueo.analizar(e)
                .map(b -> Response.status(409).entity(Map.of(
                        "titulo", "Recurso bloqueado",
                        "detalle", "Pide el borrado controlado con un ticket aprobado.",
                        "alcancesBloqueados", b.alcancesBloqueados())).build())
                .orElseGet(() -> Response.status(502).entity(Map.of("titulo", "Azure rechazó la operación")).build());
    }

    @ServerExceptionMapper
    Response solicitudInvalida(IllegalArgumentException e) {
        return Response.status(400).entity(Map.of("titulo", e.getMessage())).build();
    }
}
```

## 10. Quarkus · reactivo (Mutiny)

Para no bloquear el hilo de eventos, ejecuta la llamada del SDK en el *pool* de trabajadores y devuelve un `Uni`. (Con Java 21 también está `@RunOnVirtualThread` en recursos imperativos, que suele ser más simple para SDK bloqueantes.)

```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/reactivo/gobierno")
@Produces(MediaType.APPLICATION_JSON)
class BloqueosRecursoReactivo {

    @Inject
    BloqueosServicio bloqueos;

    @GET
    @Path("/bloqueos")
    Uni<List<InfoBloqueo>> listar() {
        return Uni.createFrom().item(bloqueos::todos)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/bloqueos/auditoria")
    Uni<InformeDeBloqueos> auditoria() {
        return Uni.createFrom().item(bloqueos::auditarProduccion)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 11. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Lector de errores** | Prueba unitaria con el **JSON real** de un `ScopeLocked` (guárdalo de un rechazo verdadero en un laboratorio) | Sin red; valida que la lista de alcances sale bien y que un mensaje distinto no rompe nada |
| **Borrado controlado** | Dobles de `BloqueosServicio` y de `SistemaDeTickets` | Comprueba: sin ticket no se toca nada; si el borrado falla, se restauran los bloqueos |
| **Integración** | Suscripción de laboratorio: crear grupo, protegerlo, intentar borrarlo (debe dar `ScopeLocked`), ejecutar el procedimiento | Es la única forma de ver los efectos reales del servicio |
| **Auditoría** | Dos grupos `env=prod`, uno con bloqueo y otro sin él | La métrica debe valer 1 |

```java
// nocheck — requiere JUnit 5
class ErroresDeBloqueoTest {

    @Test
    void extraeLosAlcancesBloqueados() throws Exception {
        String json = """
            {"code":"ScopeLocked",
             "message":"The scope '/subscriptions/0000/resourceGroups/rg-prod-datos/providers/Microsoft.DocumentDB/databaseAccounts/cosmos1' cannot perform delete operation because following scope(s) are locked: '/subscriptions/0000/resourceGroups/rg-prod-datos'. Please remove the lock and try again."}
            """;
        ManagementError error = ManagementError.fromJson(JsonProviders.createReader(json));
        ManagementException e = new ManagementException("locked", null, error);

        var bloqueo = ErroresDeBloqueo.analizar(e).orElseThrow();

        assertEquals(List.of("/subscriptions/0000/resourceGroups/rg-prod-datos"), bloqueo.alcancesBloqueados());
    }

    @Test
    void sinTicketNoSeToca() {
        var tickets = (SistemaDeTickets) (ticket, recurso) -> false;
        var borrado = new BorradoControlado(null, null, tickets);

        assertEquals("NO_APROBADO", borrado.borrarGrupo("rg-prod-datos", "TCK-1").estado());
    }
}
```

## 12. Buenas prácticas de código

- **Identidad administrada**, nunca claves ni *secrets* de aplicación en la configuración.
- **Identidades distintas** para leer/auditar (Reader) y para quitar bloqueos (rol de bloqueos, solo en el procedimiento aprobado).
- **Nunca quites un bloqueo "para que el despliegue pase".** Si el despliegue choca con `ScopeLocked`, es un asunto de proceso, no de código.
- **Idempotencia** al crear bloqueos: el aprovisionamiento se puede repetir sin duplicar.
- **`ReadOnly` bloqueado por configuración**; permítelo solo tras probar los efectos.
- **Notas obligatorias** en cada bloqueo (motivo, dueño, ticket): el servicio lo exige.
- **Cachea y refresca en segundo plano** la auditoría; ARM tiene cuotas de lectura.
- Trata `ScopeLocked` como un resultado esperable (409 con detalle), no como un fallo del servidor.
- En reactivo, **no bloquees** el hilo de eventos: `boundedElastic` / pool de trabajadores / hilos virtuales.
- Registra el identificador de correlación (`x-ms-correlation-request-id`) para el soporte y el registro de actividad.
