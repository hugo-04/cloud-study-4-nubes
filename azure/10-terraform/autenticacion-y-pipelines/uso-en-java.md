# Azure · Terraform · Autenticación y pipelines · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, `azure-json` 1.5**. Verifica las vigentes.

## Qué haces (y qué no) con Terraform desde Java

Terraform **no tiene SDK para Java** y tu microservicio **no** debe ejecutarlo. Lo que sí se construye en Java es **plataforma**:

| Caso | Qué haces desde Java |
|---|---|
| **Puerta de seguridad del plan** | Leer la salida de `terraform show -json` y devolver `APROBAR`, `REVISION_MANUAL` o `BLOQUEAR` según reglas propias |
| **Portal de autoservicio** | Un formulario genera `tfvars`, un ejecutor aislado corre `plan`, el análisis decide si necesita revisión y una persona aprueba |
| **Informe para el PR** | Convertir el plan en un resumen legible (cuántos recursos, qué es peligroso) |

> Reglas de oro: el código **jamás registra valores** del plan (contiene secretos), el ejecutor **solo corre `init`, `validate`, `plan` y `show`** (el `apply` lo hace el pipeline con aprobación) y se ejecuta en un **ejecutor aislado** con la identidad de **plan** (solo lectura).

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-json</artifactId></dependency>
```
(El analizador solo necesita `azure-json`; el ejecutor, solo el JDK.)

**Permisos de la identidad del ejecutor de planes:**

| Operación | Rol | Alcance |
|---|---|---|
| Refrescar el estado en `plan` | *Reader* | Suscripciones que planifica |
| Leer el estado y tomar el candado | *Storage Blob Data Owner* (o *Reader* con `-lock=false`) | Contenedor del estado de ese entorno |
| Aplicar | **Ninguno** (el apply no se hace desde aquí) | — |

## 1. El analizador de planes (función pura)

`terraform show -json plan` entrega un JSON con `resource_changes[]`: cada elemento trae `address`, `type`, `mode`, `change.actions` (`["create"]`, `["update"]`, `["delete"]`, `["delete","create"]`, `["no-op"]`…), `change.before` y `change.after`. El analizador solo mira **tipos, acciones y nombres de atributos**; nunca copia valores a los mensajes.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.json.JsonProviders;
import com.azure.json.JsonReader;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class AnalizadorDePlan {

    public enum Severidad { INFO, REVISION, BLOQUEO }

    public enum Veredicto { APROBAR, REVISION_MANUAL, BLOQUEAR }

    public record Hallazgo(Severidad severidad, String regla, String direccion, String detalle) { }

    public record Resumen(int crear, int actualizar, int borrar, int reemplazar, int sinCambios) { }

    public record Resultado(Veredicto veredicto, Resumen resumen, List<Hallazgo> hallazgos) { }

    public record Politica(Set<String> tiposProtegidos, Set<String> rolesBloqueados,
                           Set<String> rolesDeRevision, int maximoDeBorrados) {

        public static Politica porDefecto() {
            return new Politica(
                    Set.of("azurerm_key_vault", "azurerm_storage_account", "azurerm_mssql_server",
                            "azurerm_mssql_database", "azurerm_mssql_managed_instance", "azurerm_cosmosdb_account",
                            "azurerm_postgresql_flexible_server", "azurerm_mysql_flexible_server",
                            "azurerm_virtual_network", "azurerm_resource_group", "azurerm_log_analytics_workspace",
                            "azurerm_kubernetes_cluster", "azurerm_servicebus_namespace",
                            "azurerm_eventhub_namespace", "azurerm_user_assigned_identity"),
                    Set.of("Owner"),
                    Set.of("User Access Administrator", "Role Based Access Control Administrator", "Contributor"),
                    5);
        }
    }

    private enum Accion { NADA, CREAR, ACTUALIZAR, BORRAR, REEMPLAZAR }

    // Roles integrados por GUID (verifica en la documentación de roles integrados)
    private static final Map<String, String> ROLES_POR_GUID = Map.of(
            "8e3af657-a8ff-443c-a75c-2fe8c4bcb635", "Owner",
            "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", "User Access Administrator",
            "f58310d9-a9f6-439a-9e8d-f62e7b41a168", "Role Based Access Control Administrator",
            "b24988ac-6180-42a0-ab88-20f7382dd24c", "Contributor");

    private static final Set<String> ORIGENES_ABIERTOS = Set.of("*", "0.0.0.0/0", "Internet", "Any");
    private static final Set<String> PUERTOS_DE_ADMINISTRACION = Set.of("22", "3389", "*");

    private final Politica politica;

    public AnalizadorDePlan(Politica politica) {
        this.politica = politica;
    }

    public Resultado analizar(String planJson) {
        if (planJson == null || planJson.isBlank()) {
            throw new IllegalArgumentException("El plan está vacío");
        }
        Object raiz;
        try (JsonReader lector = JsonProviders.createReader(planJson)) {
            raiz = lector.readUntyped();
        } catch (IOException | RuntimeException e) {
            // el origen es un String: aquí una IOException solo puede ser JSON mal formado
            throw new IllegalArgumentException("El texto no es un JSON válido");
        }
        if (!(raiz instanceof Map<?, ?> plan) || !plan.containsKey("format_version")) {
            throw new IllegalArgumentException("No parece la salida de 'terraform show -json'");
        }

        List<Hallazgo> hallazgos = new ArrayList<>();
        if (Boolean.TRUE.equals(plan.get("errored"))) {
            hallazgos.add(new Hallazgo(Severidad.BLOQUEO, "PLAN_CON_ERRORES", "-", "El plan terminó con errores"));
        }

        int crear = 0, actualizar = 0, borrar = 0, reemplazar = 0, sinCambios = 0;
        for (Object elemento : lista(plan.get("resource_changes"))) {
            Map<?, ?> recurso = mapa(elemento);
            if (!"managed".equals(recurso.get("mode"))) {
                continue; // los data sources no cambian nada
            }
            String tipo = texto(recurso.get("type"));
            String direccion = texto(recurso.get("address"));
            Map<?, ?> cambio = mapa(recurso.get("change"));
            Accion accion = clasificar(lista(cambio.get("actions")));
            switch (accion) {
                case CREAR -> crear++;
                case ACTUALIZAR -> actualizar++;
                case BORRAR -> borrar++;
                case REEMPLAZAR -> reemplazar++;
                case NADA -> sinCambios++;
            }
            if (accion == Accion.NADA) {
                continue;
            }
            boolean destruye = accion == Accion.BORRAR || accion == Accion.REEMPLAZAR;
            if (destruye && politica.tiposProtegidos().contains(tipo)) {
                hallazgos.add(new Hallazgo(Severidad.BLOQUEO, "BORRADO_PROTEGIDO", direccion,
                        "Se borraría o reemplazaría un recurso de un tipo protegido (" + tipo + ")"));
            }
            if (destruye && "azurerm_management_lock".equals(tipo)) {
                hallazgos.add(new Hallazgo(Severidad.REVISION, "BLOQUEO_DE_RECURSO_QUITADO", direccion,
                        "Se quitaría un bloqueo de recurso"));
            }
            Map<?, ?> despues = mapa(cambio.get("after"));
            if (despues.isEmpty()) {
                continue;
            }
            if ("azurerm_role_assignment".equals(tipo)) {
                revisarRol(direccion, despues, hallazgos);
            }
            revisarExposicion(tipo, direccion, despues, hallazgos);
        }

        int destruidos = borrar + reemplazar;
        if (destruidos > politica.maximoDeBorrados()) {
            hallazgos.add(new Hallazgo(Severidad.REVISION, "BORRADOS_MASIVOS", "-",
                    destruidos + " recursos se borrarían o reemplazarían (máximo sin revisión: "
                            + politica.maximoDeBorrados() + ")"));
        }

        Veredicto veredicto = Veredicto.APROBAR;
        for (Hallazgo h : hallazgos) {
            if (h.severidad() == Severidad.BLOQUEO) {
                veredicto = Veredicto.BLOQUEAR;
                break;
            }
            if (h.severidad() == Severidad.REVISION) {
                veredicto = Veredicto.REVISION_MANUAL;
            }
        }
        return new Resultado(veredicto, new Resumen(crear, actualizar, borrar, reemplazar, sinCambios),
                List.copyOf(hallazgos));
    }

    private void revisarRol(String direccion, Map<?, ?> despues, List<Hallazgo> hallazgos) {
        String rol = nombreDelRol(despues);
        if (rol == null) {
            hallazgos.add(new Hallazgo(Severidad.REVISION, "ROL_NO_DETERMINADO", direccion,
                    "El rol se conocerá recién al aplicar; revísalo a mano"));
        } else if (politica.rolesBloqueados().contains(rol)) {
            hallazgos.add(new Hallazgo(Severidad.BLOQUEO, "ROL_PROHIBIDO", direccion,
                    "Se asignaría el rol " + rol));
        } else if (politica.rolesDeRevision().contains(rol)) {
            hallazgos.add(new Hallazgo(Severidad.REVISION, "ROL_PRIVILEGIADO", direccion,
                    "Se asignaría el rol " + rol));
        }
    }

    private static String nombreDelRol(Map<?, ?> despues) {
        if (despues.get("role_definition_name") instanceof String nombre && !nombre.isBlank()) {
            return nombre;
        }
        if (despues.get("role_definition_id") instanceof String id && !id.isBlank()) {
            String guid = id.substring(id.lastIndexOf('/') + 1).toLowerCase();
            return ROLES_POR_GUID.getOrDefault(guid, guid);
        }
        return null;
    }

    private void revisarExposicion(String tipo, String direccion, Map<?, ?> despues, List<Hallazgo> hallazgos) {
        if (Boolean.TRUE.equals(despues.get("public_network_access_enabled"))) {
            hallazgos.add(new Hallazgo(Severidad.REVISION, "ACCESO_PUBLICO", direccion,
                    "El atributo public_network_access_enabled quedaría en true"));
        }
        if ("azurerm_storage_account".equals(tipo) && Boolean.TRUE.equals(despues.get("allow_nested_items_to_be_public"))) {
            hallazgos.add(new Hallazgo(Severidad.REVISION, "BLOBS_PUBLICOS", direccion,
                    "El atributo allow_nested_items_to_be_public quedaría en true"));
        }
        if ("azurerm_network_security_rule".equals(tipo)
                && "Inbound".equalsIgnoreCase(texto(despues.get("direction")))
                && "Allow".equalsIgnoreCase(texto(despues.get("access")))
                && algunoEn(despues.get("source_address_prefix"), despues.get("source_address_prefixes"), ORIGENES_ABIERTOS)) {
            boolean administracion = algunoEn(despues.get("destination_port_range"),
                    despues.get("destination_port_ranges"), PUERTOS_DE_ADMINISTRACION);
            hallazgos.add(administracion
                    ? new Hallazgo(Severidad.BLOQUEO, "ADMINISTRACION_ABIERTA_A_INTERNET", direccion,
                            "Regla de entrada abierta a cualquier origen en un puerto de administración (22, 3389 o todos)")
                    : new Hallazgo(Severidad.REVISION, "ENTRADA_ABIERTA_A_INTERNET", direccion,
                            "Regla de entrada abierta a cualquier origen"));
        }
    }

    private static boolean algunoEn(Object unico, Object varios, Set<String> conjunto) {
        if (unico instanceof String s && conjunto.contains(s)) {
            return true;
        }
        for (Object o : lista(varios)) {
            if (o instanceof String s && conjunto.contains(s)) {
                return true;
            }
        }
        return false;
    }

    private static Accion clasificar(List<?> acciones) {
        boolean borra = acciones.contains("delete");
        boolean crea = acciones.contains("create");
        if (borra && crea) {
            return Accion.REEMPLAZAR;
        }
        if (borra) {
            return Accion.BORRAR;
        }
        if (crea) {
            return Accion.CREAR;
        }
        return acciones.contains("update") ? Accion.ACTUALIZAR : Accion.NADA;
    }

    private static List<?> lista(Object o) {
        return o instanceof List<?> l ? l : List.of();
    }

    private static Map<?, ?> mapa(Object o) {
        return o instanceof Map<?, ?> m ? m : Map.of();
    }

    private static String texto(Object o) {
        return o instanceof String s ? s : "";
    }
}
```

**Qué cubre y qué no** (dilo en voz alta en tu equipo):
- Cubre los **recursos sueltos** (`azurerm_network_security_rule`, `azurerm_role_assignment`…). Las reglas **dentro** de un `azurerm_network_security_group` (bloque `security_rule`) o los atributos anidados necesitan reglas propias.
- Un valor **desconocido hasta aplicar** (`after_unknown`) no se puede evaluar: por eso `ROL_NO_DETERMINADO` pide revisión.
- Es una **red de seguridad**, no un sustituto de las políticas de Azure ni de la revisión humana.

## 2. El ejecutor de Terraform (proceso aislado, tiempo límite, entorno mínimo)

Solo para portales internos de autoservicio. Observa cinco decisiones: **lista blanca de subcomandos** (sin `apply`), **entorno limpio** (no heredas secretos del servicio), **salida a archivos temporales** (permisos solo del propietario y sin carreras al leer tuberías de un proceso que muere), **tiempo límite** y **cierre amable** (`destroy()` envía SIGTERM y Terraform intenta soltar el candado del estado; `destroyForcibly()` lo deja huérfano).

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;

public final class EjecutorDeTerraform {

    public record Salida(int codigo, String salida, String error, boolean agotoTiempo, boolean truncada) { }

    private static final Set<String> PERMITIDOS = Set.of("init", "validate", "plan", "show");

    private final String binario;
    private final Duration limite;
    private final int maximoDeBytes;
    private final Map<String, String> variables;

    public EjecutorDeTerraform(String binario, Duration limite, int maximoDeBytes, Map<String, String> variables) {
        this.binario = binario;
        this.limite = limite;
        this.maximoDeBytes = maximoDeBytes;
        this.variables = Map.copyOf(variables);
    }

    public Salida ejecutar(java.nio.file.Path directorio, List<String> argumentos) throws IOException, InterruptedException {
        if (argumentos.isEmpty() || !PERMITIDOS.contains(argumentos.get(0))) {
            throw new IllegalArgumentException("Subcomando no permitido: solo init, validate, plan y show");
        }
        List<String> orden = new ArrayList<>();
        orden.add(binario);
        orden.addAll(argumentos);

        ProcessBuilder pb = new ProcessBuilder(orden).directory(directorio.toFile());
        Map<String, String> entorno = pb.environment();
        String path = entorno.get("PATH");
        String home = entorno.get("HOME");
        entorno.clear(); // nada de secretos heredados del servicio
        if (path != null) {
            entorno.put("PATH", path);
        }
        if (home != null) {
            entorno.put("HOME", home);
        }
        entorno.put("TF_IN_AUTOMATION", "true");
        entorno.put("TF_INPUT", "false");
        entorno.put("CHECKPOINT_DISABLE", "1");
        entorno.putAll(variables); // ARM_USE_MSI, ARM_SUBSCRIPTION_ID… decididos por quien configura el servicio

        // La salida va a archivos temporales: sin tuberías que leer en paralelo (evita carreras al cerrarse el proceso)
        java.nio.file.Path archivoSalida = Files.createTempFile("tf-salida-", ".txt");
        java.nio.file.Path archivoError = Files.createTempFile("tf-error-", ".txt");
        try {
            pb.redirectOutput(archivoSalida.toFile());
            pb.redirectError(archivoError.toFile());
            pb.redirectInput(ProcessBuilder.Redirect.from(new java.io.File("/dev/null")));

            Process proceso = pb.start();
            boolean termino = proceso.waitFor(limite.toMillis(), TimeUnit.MILLISECONDS);
            if (!termino) {
                proceso.destroy(); // SIGTERM: Terraform intenta soltar el candado
                if (!proceso.waitFor(15, TimeUnit.SECONDS)) {
                    proceso.destroyForcibly(); // último recurso: puede dejar el candado huérfano
                    proceso.waitFor();
                }
            }
            String salida = leer(archivoSalida, maximoDeBytes);
            boolean truncada = Files.size(archivoSalida) > maximoDeBytes;
            String error = leer(archivoError, 64_000);
            return new Salida(termino ? proceso.exitValue() : -1, salida, error, !termino, truncada);
        } finally {
            Files.deleteIfExists(archivoSalida);
            Files.deleteIfExists(archivoError);
        }
    }

    private static String leer(java.nio.file.Path archivo, int maximo) throws IOException {
        try (InputStream in = Files.newInputStream(archivo)) {
            return new String(in.readNBytes(maximo), StandardCharsets.UTF_8);
        }
    }

    /** init + plan guardado + show -json. Devuelve el plan en JSON (contiene secretos: no lo registres). */
    public String planComoJson(java.nio.file.Path directorio, String archivoDeVariables) throws IOException, InterruptedException {
        if (!java.nio.file.Path.of(archivoDeVariables).getFileName().toString().equals(archivoDeVariables)) {
            throw new IllegalArgumentException("El archivo de variables debe estar en el directorio de trabajo");
        }
        exigir(ejecutar(directorio, List.of("init", "-input=false")), "init", 0);
        Salida plan = ejecutar(directorio, List.of("plan", "-input=false", "-lock-timeout=2m",
                "-detailed-exitcode", "-out=tfplan", "-var-file=" + archivoDeVariables));
        exigir(plan, "plan", 0, 2); // 0 = sin cambios, 2 = con cambios, 1 = error
        Salida json = ejecutar(directorio, List.of("show", "-json", "tfplan"));
        exigir(json, "show", 0);
        if (json.truncada()) {
            throw new IllegalStateException("El plan en JSON superó el máximo permitido");
        }
        return json.salida();
    }

    private static void exigir(Salida salida, String paso, int... codigosValidos) {
        if (salida.agotoTiempo()) {
            throw new IllegalStateException("Terraform " + paso + " superó el tiempo límite");
        }
        for (int c : codigosValidos) {
            if (salida.codigo() == c) {
                return;
            }
        }
        // El error de Terraform puede citar fragmentos de la configuración: se recorta y no se devuelve al cliente final.
        String detalle = salida.error().length() > 2000 ? salida.error().substring(0, 2000) : salida.error();
        throw new IllegalStateException("Terraform " + paso + " falló (código " + salida.codigo() + "): " + detalle);
    }
}
```

## 3. Servicio de revisión (portal de autoservicio)

Une ambas piezas: genera el plan en el directorio de trabajo y devuelve el veredicto. **El directorio de trabajo es una copia temporal** del módulo con el `terraform.tfvars.json` del formulario, nunca el repositorio original.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;

public final class ServicioDeRevisionDePlanes {

    private final EjecutorDeTerraform ejecutor;
    private final AnalizadorDePlan analizador;

    public ServicioDeRevisionDePlanes(EjecutorDeTerraform ejecutor, AnalizadorDePlan analizador) {
        this.ejecutor = ejecutor;
        this.analizador = analizador;
    }

    public AnalizadorDePlan.Resultado revisar(java.nio.file.Path copiaDelModulo, String tfvars) throws IOException, InterruptedException {
        String planJson = ejecutor.planComoJson(copiaDelModulo, tfvars);
        return analizador.analizar(planJson); // el JSON no se guarda ni se registra
    }
}
```

## 4. Configuración de Spring

```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class PlanesConfiguracion {

    @Bean
    AnalizadorDePlan analizadorDePlan(@Value("${plan.maximo-de-borrados:5}") int maximoDeBorrados) {
        var base = AnalizadorDePlan.Politica.porDefecto();
        return new AnalizadorDePlan(new AnalizadorDePlan.Politica(
                base.tiposProtegidos(), base.rolesBloqueados(), base.rolesDeRevision(), maximoDeBorrados));
    }
}
```
```yaml
# application.yml
plan:
  maximo-de-borrados: 5
spring:
  codec:
    max-in-memory-size: 20MB   # WebFlux limita por defecto a 256 KB: un plan real pesa megabytes
```

## 5. Spring MVC

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/plataforma/terraform/planes")
class PlanesControlador {

    private final AnalizadorDePlan analizador;

    PlanesControlador(AnalizadorDePlan analizador) {
        this.analizador = analizador;
    }

    @PostMapping(path = "/analisis", consumes = MediaType.APPLICATION_JSON_VALUE)
    AnalizadorDePlan.Resultado analizar(@RequestBody String plan) {
        return analizador.analizar(plan);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ProblemDetail planInvalido(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }
}
```

## 6. Spring WebFlux (reactivo)

El análisis es **CPU y memoria** (se parsea un JSON grande): se saca del hilo de eventos con `boundedElastic`.

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/plataforma/terraform/planes")
class PlanesReactivoControlador {

    private final AnalizadorDePlan analizador;

    PlanesReactivoControlador(AnalizadorDePlan analizador) {
        this.analizador = analizador;
    }

    @PostMapping(path = "/analisis", consumes = MediaType.APPLICATION_JSON_VALUE)
    Mono<AnalizadorDePlan.Resultado> analizar(@RequestBody Mono<String> plan) {
        return plan
                .flatMap(texto -> Mono.fromCallable(() -> analizador.analizar(texto))
                        .subscribeOn(Schedulers.boundedElastic()))
                .onErrorMap(IllegalArgumentException.class,
                        e -> new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()));
    }
}
```

## 7. Quarkus · imperativo

```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class PlanesProductores {

    @ConfigProperty(name = "plan.maximo-de-borrados", defaultValue = "5")
    int maximoDeBorrados;

    @Produces
    @Singleton
    AnalizadorDePlan analizador() {
        var base = AnalizadorDePlan.Politica.porDefecto();
        return new AnalizadorDePlan(new AnalizadorDePlan.Politica(
                base.tiposProtegidos(), base.rolesBloqueados(), base.rolesDeRevision(), maximoDeBorrados));
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/plataforma/terraform/planes")
@Produces(MediaType.APPLICATION_JSON)
class PlanesRecurso {

    @Inject
    AnalizadorDePlan analizador;

    @POST
    @Path("/analisis")
    @Consumes(MediaType.APPLICATION_JSON)
    public AnalizadorDePlan.Resultado analizar(String plan) {
        try {
            return analizador.analizar(plan);
        } catch (IllegalArgumentException e) {
            throw new BadRequestException(e.getMessage());
        }
    }
}
```
```properties
# application.properties — el límite por defecto del cuerpo es de 10 MB; ajústalo a tus planes
quarkus.http.limits.max-body-size=50M
plan.maximo-de-borrados=5
```

## 8. Quarkus · reactivo (Mutiny)

```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/reactivo/plataforma/terraform/planes")
@Produces(MediaType.APPLICATION_JSON)
class PlanesRecursoReactivo {

    @Inject
    AnalizadorDePlan analizador;

    @POST
    @Path("/analisis")
    @Consumes(MediaType.APPLICATION_JSON)
    public Uni<AnalizadorDePlan.Resultado> analizar(String plan) {
        return Uni.createFrom().item(() -> analizador.analizar(plan))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .onFailure(IllegalArgumentException.class)
                .transform(e -> new BadRequestException(e.getMessage()));
    }
}
```

## 9. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Reglas del analizador** | Un JSON mínimo por regla ([`plan-seguro.json`](ejemplos/json/plan-seguro.json), [`plan-peligroso.json`](ejemplos/json/plan-peligroso.json)) | Funciones puras: milisegundos |
| **Plan real** | `tofu plan` / `terraform plan` sobre `terraform_data` (no necesita Azure) y `show -json` | Garantiza que la estructura del plan sigue siendo la que esperas al subir de versión |
| **Ejecutor** | Un binario falso (script) que imprime JSON, se cuelga o devuelve el código 1 | Cubre tiempo límite, truncado y subcomandos prohibidos |
| **Contrato de privacidad** | Una prueba que comprueba que ningún `detalle` contiene valores del plan | Evita filtrar secretos por los mensajes |
| **Integración** | Un módulo de laboratorio con un cambio por regla | La única forma de ver todo el flujo |

```java
// nocheck — requiere JUnit 5
class AnalizadorDePlanTest {

    private final AnalizadorDePlan analizador = new AnalizadorDePlan(AnalizadorDePlan.Politica.porDefecto());

    @Test
    void bloqueaElBorradoDeUnaBaseDeDatos() throws Exception {
        String plan = Files.readString(Path.of("src/test/resources/plan-peligroso.json"));

        var resultado = analizador.analizar(plan);

        assertEquals(AnalizadorDePlan.Veredicto.BLOQUEAR, resultado.veredicto());
        assertTrue(resultado.hallazgos().stream().anyMatch(h -> h.regla().equals("BORRADO_PROTEGIDO")));
    }

    @Test
    void aprueba_un_plan_de_solo_etiquetas() throws Exception {
        String plan = Files.readString(Path.of("src/test/resources/plan-seguro.json"));

        assertEquals(AnalizadorDePlan.Veredicto.APROBAR, analizador.analizar(plan).veredicto());
    }

    @Test
    void rechaza_texto_que_no_es_un_plan() {
        assertThrows(IllegalArgumentException.class, () -> analizador.analizar("{\"hola\":1}"));
    }

    @Test
    void los_mensajes_no_contienen_valores_del_plan() throws Exception {
        String plan = Files.readString(Path.of("src/test/resources/plan-peligroso.json"));

        var resultado = analizador.analizar(plan);

        resultado.hallazgos().forEach(h -> assertFalse(h.detalle().contains("P@ssw0rd-secreta")));
    }
}
```

## 10. Buenas prácticas de código
- **Nunca registres el plan** ni copies valores a mensajes: contiene secretos.
- **Sin `apply`** en el ejecutor: lo hace el pipeline con aprobación.
- **Entorno limpio** para el proceso y **tiempo límite** con cierre amable (SIGTERM antes que `destroyForcibly`).
- **Copia temporal** del módulo para cada solicitud y borrado al terminar (`tfplan` incluido).
- **Reglas como datos** (`Politica`) en configuración, para ajustarlas sin recompilar.
- **Falla cerrado:** si algo no se puede evaluar (`ROL_NO_DETERMINADO`), pide revisión; no apruebes por omisión.
- **Límite de tamaño** del cuerpo (WebFlux: `max-in-memory-size`; Quarkus: `max-body-size`).
- En reactivo, **no bloquees** el hilo de eventos: `boundedElastic` / pool de trabajadores / hilos virtuales.
