# Azure · Terraform · Estado remoto · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3, `azure-core` 1.60, `azure-storage-blob` 12.36, `azure-resourcemanager-storage` 2.58**. Verifica las vigentes.

## Qué haces (y qué no) con el estado desde Java

Terraform **no tiene SDK para Java**: es un programa de línea de comandos. Tu aplicación Java no "ejecuta Terraform" ni "lee el estado" para tomar decisiones de negocio. Lo que **sí** construyen los equipos de plataforma en Java es **la vigilancia** del almacén de estados:

| Caso | Qué haces desde Java |
|---|---|
| **Inventario de estados** | Listar los blobs `*.tfstate` con tamaño, último cambio y si están bloqueados |
| **Detección de bloqueos largos** | Avisar si un estado lleva bloqueado más de lo normal (candado huérfano) |
| **Higiene de la cuenta** | Comprobar que la cuenta sigue endurecida: sin claves, TLS 1.2, firewall cerrado, versionado y borrado suave |
| **Convención de nombres** | Señalar estados fuera de `<entorno>/<componente>.tfstate` |
| **Estados inactivos** | Listar candidatos a limpiar (nadie los toca hace meses) |
| **Métricas** | *Gauges* para tableros y alertas |

> Reglas de oro: este servicio **nunca descarga el contenido** de un estado (contiene secretos), **nunca escribe** en el contenedor y **nunca libera bloqueos**: observa y avisa. Es un servicio de **plataforma**, con su propia identidad.

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-blob</artifactId></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-storage</artifactId></dependency>
```

**Permisos de la identidad del auditor** (identidad administrada, sin claves):

| Operación | Rol mínimo | Alcance |
|---|---|---|
| Listar blobs y ver tamaño, fecha y estado del bloqueo | *Storage Blob Data Reader* | El contenedor `tfstate` |
| Leer la configuración de la cuenta (claves, TLS, firewall, versionado) | *Reader* | La cuenta de almacenamiento |

> **Una limitación honesta:** con RBAC no puedes separar "listar blobs" de "leer su contenido". Quien tenga *Storage Blob Data Reader* sobre el contenedor **podría** descargar los estados. Por eso este servicio lo opera plataforma, su código se revisa con cuidado y, si lo necesitas, puedes limitar el rol con condiciones (ABAC) o dejar el inventario en manos del propio pipeline. Y recuerda: **este código jamás llama a `download`**.

## 1. Reglas de auditoría (funciones puras, sin red)

Las reglas viven en clases sin dependencias de Azure: se prueban en milisegundos y se reutilizan en Spring y Quarkus. `SeguimientoDeBloqueos` resuelve un detalle importante: el *lease* de un blob no dice **desde cuándo** está tomado, así que el auditor recuerda **la primera vez que lo vio bloqueado** y calcula cuánto lleva así.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

/** Un estado tal como aparece en el contenedor (nunca su contenido). */
record EstadoRemoto(String clave, long bytes, OffsetDateTime modificado, boolean bloqueado) { }

/** Lo que importa de la configuración de la cuenta de estados. */
record ConfiguracionDeLaCuenta(String cuenta, boolean claveCompartidaPermitida, boolean accesoPublicoDeBlobs,
                               String tlsMinimo, boolean firewallAbierto, boolean versionado,
                               int diasBorradoSuaveBlobs, int diasBorradoSuaveContenedores) { }

record HallazgoDeEstado(String objeto, String regla, String detalle) { }

/** Recuerda desde cuándo vemos bloqueado cada estado. */
final class SeguimientoDeBloqueos {

    private final Map<String, Instant> vistoBloqueadoDesde = new ConcurrentHashMap<>();

    /** Actualiza con la última lectura y devuelve cuánto lleva bloqueado cada estado que lo está ahora. */
    Map<String, Duration> actualizar(List<EstadoRemoto> estados, Instant ahora) {
        Map<String, Duration> bloqueados = new LinkedHashMap<>();
        List<String> vigentes = new ArrayList<>();
        for (EstadoRemoto e : estados) {
            if (e.bloqueado()) {
                vigentes.add(e.clave());
                Instant desde = vistoBloqueadoDesde.computeIfAbsent(e.clave(), k -> ahora);
                bloqueados.put(e.clave(), Duration.between(desde, ahora));
            }
        }
        vistoBloqueadoDesde.keySet().retainAll(vigentes);   // los que ya se soltaron se olvidan
        return bloqueados;
    }
}

final class ReglasDelEstado {

    /** <entorno>/<componente>.tfstate */
    static final Pattern CONVENCION = Pattern.compile("(plataforma|dev|qa|prod)/[a-z0-9][a-z0-9-]*\\.tfstate");

    private final long bytesMaximos;
    private final Duration inactividad;
    private final Duration bloqueoMaximo;

    ReglasDelEstado(long bytesMaximos, Duration inactividad, Duration bloqueoMaximo) {
        this.bytesMaximos = bytesMaximos;
        this.inactividad = inactividad;
        this.bloqueoMaximo = bloqueoMaximo;
    }

    List<HallazgoDeEstado> auditarCuenta(ConfiguracionDeLaCuenta c) {
        List<HallazgoDeEstado> h = new ArrayList<>();
        if (c.claveCompartidaPermitida()) {
            h.add(new HallazgoDeEstado(c.cuenta(), "CLAVE_COMPARTIDA", "La cuenta permite acceso por clave: desactívalo y usa solo Entra ID"));
        }
        if (c.accesoPublicoDeBlobs()) {
            h.add(new HallazgoDeEstado(c.cuenta(), "ACCESO_ANONIMO", "La cuenta permite acceso anónimo a blobs"));
        }
        if (c.tlsMinimo() == null || !(c.tlsMinimo().equals("TLS1_2") || c.tlsMinimo().equals("TLS1_3"))) {
            h.add(new HallazgoDeEstado(c.cuenta(), "TLS_BAJO", "El TLS mínimo debe ser 1.2 o superior (actual: " + c.tlsMinimo() + ")"));
        }
        if (c.firewallAbierto()) {
            h.add(new HallazgoDeEstado(c.cuenta(), "FIREWALL_ABIERTO", "La acción por defecto del firewall es permitir"));
        }
        if (!c.versionado()) {
            h.add(new HallazgoDeEstado(c.cuenta(), "SIN_VERSIONADO", "Sin versionado no hay forma de recuperar un estado sobrescrito"));
        }
        if (c.diasBorradoSuaveBlobs() <= 0) {
            h.add(new HallazgoDeEstado(c.cuenta(), "SIN_BORRADO_SUAVE_DE_BLOBS", "Un estado borrado no se podría restaurar"));
        }
        if (c.diasBorradoSuaveContenedores() <= 0) {
            h.add(new HallazgoDeEstado(c.cuenta(), "SIN_BORRADO_SUAVE_DE_CONTENEDORES", "Un contenedor borrado no se podría restaurar"));
        }
        return h;
    }

    List<HallazgoDeEstado> auditarEstados(List<EstadoRemoto> estados, Instant ahora, Map<String, Duration> bloqueadosDesde) {
        List<HallazgoDeEstado> h = new ArrayList<>();
        for (EstadoRemoto e : estados) {
            if (!CONVENCION.matcher(e.clave()).matches()) {
                h.add(new HallazgoDeEstado(e.clave(), "FUERA_DE_CONVENCION", "Use <entorno>/<componente>.tfstate"));
            }
            if (e.bytes() > bytesMaximos) {
                h.add(new HallazgoDeEstado(e.clave(), "ESTADO_GRANDE",
                        e.bytes() + " bytes: considere dividirlo (los planes serán lentos)"));
            }
            if (e.modificado() != null && Duration.between(e.modificado().toInstant(), ahora).compareTo(inactividad) > 0) {
                h.add(new HallazgoDeEstado(e.clave(), "SIN_ACTIVIDAD",
                        "Sin cambios desde " + e.modificado().toLocalDate() + ": ¿sigue siendo necesario?"));
            }
            Duration bloqueado = bloqueadosDesde.get(e.clave());
            if (bloqueado != null && bloqueado.compareTo(bloqueoMaximo) > 0) {
                h.add(new HallazgoDeEstado(e.clave(), "BLOQUEO_LARGO",
                        "Bloqueado desde hace " + bloqueado.toMinutes() + " min: ¿candado huérfano?"));
            }
        }
        return h;
    }
}
```

## 2. El auditor: inventario con el SDK de blobs y configuración con el de almacenamiento

- **Inventario:** `listBlobs` devuelve, por cada blob, `getContentLength()`, `getLastModified()` y `getLeaseStatus()` (`LOCKED` / `UNLOCKED`). Solo se leen **propiedades**, nunca el contenido.
- **Configuración:** se leen las propiedades de la cuenta (`isSharedKeyAccessAllowed`, `isBlobPublicAccessAllowed`, `minimumTlsVersion`, regla por defecto del firewall) y las del servicio de blobs (versionado y borrado suave).
- Todo el SDK es **bloqueante**: va en un refresco en segundo plano, no en el camino de una solicitud.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.storage.StorageManager;
import com.azure.resourcemanager.storage.models.BlobServiceProperties;
import com.azure.resourcemanager.storage.models.DefaultAction;
import com.azure.resourcemanager.storage.models.StorageAccount;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobItemProperties;
import com.azure.storage.blob.models.LeaseStatusType;
import com.azure.storage.blob.models.ListBlobsOptions;

final class AuditorDelEstado {

    private final BlobContainerClient contenedor;
    private final StorageManager almacenamiento;
    private final String grupoDeRecursos;
    private final String cuenta;

    AuditorDelEstado(BlobContainerClient contenedor, StorageManager almacenamiento, String grupoDeRecursos, String cuenta) {
        this.contenedor = contenedor;
        this.almacenamiento = almacenamiento;
        this.grupoDeRecursos = grupoDeRecursos;
        this.cuenta = cuenta;
    }

    /** Solo propiedades de los blobs: jamás se descarga el contenido de un estado. */
    List<EstadoRemoto> inventario() {
        List<EstadoRemoto> estados = new ArrayList<>();
        ListBlobsOptions opciones = new ListBlobsOptions().setMaxResultsPerPage(500);
        for (BlobItem blob : contenedor.listBlobs(opciones, Duration.ofSeconds(30))) {
            if (!blob.getName().contains(".tfstate")) {
                continue;
            }
            BlobItemProperties p = blob.getProperties();
            estados.add(new EstadoRemoto(blob.getName(),
                    p.getContentLength() == null ? 0L : p.getContentLength(),
                    p.getLastModified(),
                    LeaseStatusType.LOCKED.equals(p.getLeaseStatus())));
        }
        return List.copyOf(estados);
    }

    ConfiguracionDeLaCuenta configuracion() {
        StorageAccount c = almacenamiento.storageAccounts().getByResourceGroup(grupoDeRecursos, cuenta);
        BlobServiceProperties blobs = almacenamiento.blobServices().getServicePropertiesAsync(grupoDeRecursos, cuenta).block();

        boolean firewallAbierto = c.innerModel().networkRuleSet() == null
                || !DefaultAction.DENY.equals(c.innerModel().networkRuleSet().defaultAction());
        return new ConfiguracionDeLaCuenta(cuenta,
                c.isSharedKeyAccessAllowed(),
                c.isBlobPublicAccessAllowed(),
                c.minimumTlsVersion() == null ? null : c.minimumTlsVersion().toString(),
                firewallAbierto,
                blobs != null && Boolean.TRUE.equals(blobs.isBlobVersioningEnabled()),
                dias(blobs == null ? null : blobs.deleteRetentionPolicy()),
                dias(blobs == null ? null : blobs.containerDeleteRetentionPolicy()));
    }

    private static int dias(com.azure.resourcemanager.storage.models.DeleteRetentionPolicy politica) {
        return politica != null && Boolean.TRUE.equals(politica.enabled()) && politica.days() != null ? politica.days() : 0;
    }
}
```

## 3. Métricas: estados, bloqueados y hallazgos (refresco en segundo plano)

Un bloqueo largo es la señal más útil: refresca **cada 5 minutos** (el listado de blobs es barato) y deja la configuración de la cuenta para **una vez por hora**.

```java
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

@Component
@EnableScheduling
class MetricasDelEstado {

    private final AuditorDelEstado auditor;
    private final ReglasDelEstado reglas;
    private final SeguimientoDeBloqueos seguimiento = new SeguimientoDeBloqueos();
    private final Clock reloj;

    private final AtomicInteger total = new AtomicInteger();
    private final AtomicInteger bloqueados = new AtomicInteger();
    private final AtomicInteger hallazgos = new AtomicInteger();
    private final AtomicReference<List<HallazgoDeEstado>> deLaCuenta = new AtomicReference<>(List.of());
    private final AtomicReference<List<HallazgoDeEstado>> deLosEstados = new AtomicReference<>(List.of());

    MetricasDelEstado(MeterRegistry registro, AuditorDelEstado auditor, ReglasDelEstado reglas, Clock reloj) {
        this.auditor = auditor;
        this.reglas = reglas;
        this.reloj = reloj;
        Gauge.builder("modalima.terraform.estados", total, AtomicInteger::get).register(registro);
        Gauge.builder("modalima.terraform.estados_bloqueados", bloqueados, AtomicInteger::get).register(registro);
        Gauge.builder("modalima.terraform.hallazgos", hallazgos, AtomicInteger::get).register(registro);
    }

    @Scheduled(initialDelayString = "PT30S", fixedDelayString = "PT5M")
    void refrescarEstados() {
        try {
            List<EstadoRemoto> estados = auditor.inventario();
            Instant ahora = reloj.instant();
            Map<String, Duration> bloqueadosDesde = seguimiento.actualizar(estados, ahora);
            total.set(estados.size());
            bloqueados.set(bloqueadosDesde.size());
            deLosEstados.set(reglas.auditarEstados(estados, ahora, bloqueadosDesde));
            hallazgos.set(deLaCuenta.get().size() + deLosEstados.get().size());
        } catch (RuntimeException e) {
            // conserva el último valor: un fallo de red no debe borrar la métrica
        }
    }

    @Scheduled(initialDelayString = "PT1M", fixedDelayString = "PT1H")
    void refrescarCuenta() {
        try {
            deLaCuenta.set(reglas.auditarCuenta(auditor.configuracion()));
            hallazgos.set(deLaCuenta.get().size() + deLosEstados.get().size());
        } catch (RuntimeException e) {
            // idem
        }
    }
}
```

## 4. Clientes de Azure (un solo `TokenCredential`)

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class AzureEstadoConfig {

    @Bean
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Bean
    Clock reloj() {
        return Clock.systemUTC();
    }

    @Bean
    AuditorDelEstado auditor(TokenCredential credencial,
                             @Value("${azure.tenant-id}") String tenant,
                             @Value("${azure.subscription-id}") String suscripcion,
                             @Value("${terraform.estado.cuenta}") String cuenta,
                             @Value("${terraform.estado.contenedor:tfstate}") String contenedor,
                             @Value("${terraform.estado.grupo-de-recursos}") String grupoDeRecursos) {
        BlobContainerClient blobs = new BlobContainerClientBuilder()
                .endpoint("https://" + cuenta + ".blob.core.windows.net/" + contenedor)
                .credential(credencial)
                .buildClient();
        StorageManager almacenamiento = StorageManager.authenticate(credencial,
                new AzureProfile(tenant, suscripcion, AzureEnvironment.AZURE));
        return new AuditorDelEstado(blobs, almacenamiento, grupoDeRecursos, cuenta);
    }

    @Bean
    ReglasDelEstado reglas(@Value("${terraform.estado.bytes-maximos:20971520}") long bytesMaximos,
                           @Value("${terraform.estado.inactividad:P180D}") Duration inactividad,
                           @Value("${terraform.estado.bloqueo-maximo:PT45M}") Duration bloqueoMaximo) {
        return new ReglasDelEstado(bytesMaximos, inactividad, bloqueoMaximo);
    }
}
```
```yaml
# application.yml
azure:
  tenant-id: ${AZURE_TENANT_ID}
  subscription-id: ${AZURE_SUBSCRIPTION_ID}
terraform:
  estado:
    cuenta: stmodalimatfstate001
    contenedor: tfstate
    grupo-de-recursos: rg-tfstate-modalima
    bytes-maximos: 20971520     # 20 MB
    inactividad: P180D
    bloqueo-maximo: PT45M       # un apply largo puede durar; ajusta a tu realidad
```

## 5. Spring MVC: controlador de consulta

Solo lectura y de uso interno (detrás de autenticación). Devuelve **metadatos**, nunca contenido.

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.azure.core.exception.HttpResponseException;

@RestController
@RequestMapping("/plataforma/terraform")
class EstadosControlador {

    private final AuditorDelEstado auditor;
    private final ReglasDelEstado reglas;
    private final SeguimientoDeBloqueos seguimiento = new SeguimientoDeBloqueos();
    private final Clock reloj;

    EstadosControlador(AuditorDelEstado auditor, ReglasDelEstado reglas, Clock reloj) {
        this.auditor = auditor;
        this.reglas = reglas;
        this.reloj = reloj;
    }

    @GetMapping("/estados")
    List<EstadoRemoto> estados() {
        return auditor.inventario();
    }

    @GetMapping("/hallazgos")
    List<HallazgoDeEstado> hallazgos() {
        List<EstadoRemoto> estados = auditor.inventario();
        Instant ahora = reloj.instant();
        List<HallazgoDeEstado> todos = new ArrayList<>(reglas.auditarCuenta(auditor.configuracion()));
        todos.addAll(reglas.auditarEstados(estados, ahora, seguimiento.actualizar(estados, ahora)));
        return todos;
    }
}

@RestControllerAdvice
class ErroresDelEstadoAdvice {

    @ExceptionHandler(HttpResponseException.class)
    ProblemDetail errorDeAzure(HttpResponseException e) {
        int estado = e.getResponse() == null ? 502 : e.getResponse().getStatusCode();
        HttpStatus http = switch (estado) {
            case 403 -> HttpStatus.FORBIDDEN;
            case 404 -> HttpStatus.NOT_FOUND;
            default -> HttpStatus.BAD_GATEWAY;
        };
        return ProblemDetail.forStatusAndDetail(http, "Azure rechazó la lectura del almacén de estados");
    }
}
```

## 6. Spring WebFlux (reactivo)

Blobs y ARM son **bloqueantes**: se envuelven con `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`. El inventario y la configuración son independientes, así que `Mono.zip` los corre en paralelo. (Con Java 21 puedes activar **hilos virtuales** y escribir código imperativo.)

```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/plataforma/terraform")
class EstadosReactivoControlador {

    private final AuditorDelEstado auditor;
    private final ReglasDelEstado reglas;
    private final SeguimientoDeBloqueos seguimiento = new SeguimientoDeBloqueos();
    private final Clock reloj;

    EstadosReactivoControlador(AuditorDelEstado auditor, ReglasDelEstado reglas, Clock reloj) {
        this.auditor = auditor;
        this.reglas = reglas;
        this.reloj = reloj;
    }

    @GetMapping("/hallazgos")
    Mono<List<HallazgoDeEstado>> hallazgos() {
        Mono<List<EstadoRemoto>> estados = Mono.fromCallable(auditor::inventario).subscribeOn(Schedulers.boundedElastic());
        Mono<ConfiguracionDeLaCuenta> cuenta = Mono.fromCallable(auditor::configuracion).subscribeOn(Schedulers.boundedElastic());
        return Mono.zip(estados, cuenta).map(par -> {
            Instant ahora = reloj.instant();
            List<HallazgoDeEstado> todos = new ArrayList<>(reglas.auditarCuenta(par.getT2()));
            todos.addAll(reglas.auditarEstados(par.getT1(), ahora, seguimiento.actualizar(par.getT1(), ahora)));
            return todos;
        });
    }
}
```

## 7. Quarkus · imperativo

```java
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClientBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.time.Clock;

@ApplicationScoped
class AzureEstadoProductores {

    @ConfigProperty(name = "azure.tenant-id")
    String tenant;

    @ConfigProperty(name = "azure.subscription-id")
    String suscripcion;

    @ConfigProperty(name = "terraform.estado.cuenta")
    String cuenta;

    @ConfigProperty(name = "terraform.estado.contenedor", defaultValue = "tfstate")
    String contenedor;

    @ConfigProperty(name = "terraform.estado.grupo-de-recursos")
    String grupoDeRecursos;

    @ConfigProperty(name = "terraform.estado.bytes-maximos", defaultValue = "20971520")
    long bytesMaximos;

    @ConfigProperty(name = "terraform.estado.inactividad", defaultValue = "P180D")
    Duration inactividad;

    @ConfigProperty(name = "terraform.estado.bloqueo-maximo", defaultValue = "PT45M")
    Duration bloqueoMaximo;

    @Produces
    @Singleton
    Clock reloj() {
        return Clock.systemUTC();
    }

    @Produces
    @Singleton
    AuditorDelEstado auditor() {
        TokenCredential credencial = new DefaultAzureCredentialBuilder().build();
        return new AuditorDelEstado(
                new BlobContainerClientBuilder()
                        .endpoint("https://" + cuenta + ".blob.core.windows.net/" + contenedor)
                        .credential(credencial)
                        .buildClient(),
                StorageManager.authenticate(credencial, new AzureProfile(tenant, suscripcion, AzureEnvironment.AZURE)),
                grupoDeRecursos, cuenta);
    }

    @Produces
    @Singleton
    ReglasDelEstado reglas() {
        return new ReglasDelEstado(bytesMaximos, inactividad, bloqueoMaximo);
    }
}
```

```java
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.reactive.server.ServerExceptionMapper;

import com.azure.core.exception.HttpResponseException;

@Path("/plataforma/terraform")
@Produces(MediaType.APPLICATION_JSON)
class EstadosRecurso {

    @Inject
    AuditorDelEstado auditor;

    @Inject
    ReglasDelEstado reglas;

    @Inject
    Clock reloj;

    private final SeguimientoDeBloqueos seguimiento = new SeguimientoDeBloqueos();

    @GET
    @Path("/estados")
    List<EstadoRemoto> estados() {
        return auditor.inventario();
    }

    @GET
    @Path("/hallazgos")
    List<HallazgoDeEstado> hallazgos() {
        List<EstadoRemoto> estados = auditor.inventario();
        Instant ahora = reloj.instant();
        List<HallazgoDeEstado> todos = new ArrayList<>(reglas.auditarCuenta(auditor.configuracion()));
        todos.addAll(reglas.auditarEstados(estados, ahora, seguimiento.actualizar(estados, ahora)));
        return todos;
    }

    @ServerExceptionMapper
    Response errorDeAzure(HttpResponseException e) {
        int estado = e.getResponse() == null ? 502 : e.getResponse().getStatusCode();
        int http = estado == 403 || estado == 404 ? estado : 502;
        return Response.status(http).entity(Map.of("titulo", "Azure rechazó la lectura del almacén de estados")).build();
    }
}
```

> En Quarkus, las métricas de la sección 3 se montan con `quarkus-micrometer` y `@Scheduled(every = "5m")` de `quarkus-scheduler`, con la misma lógica de refresco.

## 8. Quarkus · reactivo (Mutiny)

```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/reactivo/plataforma/terraform")
@Produces(MediaType.APPLICATION_JSON)
class EstadosRecursoReactivo {

    @Inject
    AuditorDelEstado auditor;

    @Inject
    ReglasDelEstado reglas;

    @Inject
    Clock reloj;

    private final SeguimientoDeBloqueos seguimiento = new SeguimientoDeBloqueos();

    @GET
    @Path("/hallazgos")
    Uni<List<HallazgoDeEstado>> hallazgos() {
        Uni<List<EstadoRemoto>> estados = Uni.createFrom().item(auditor::inventario)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
        Uni<ConfiguracionDeLaCuenta> cuenta = Uni.createFrom().item(auditor::configuracion)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
        return Uni.combine().all().unis(estados, cuenta).asTuple().map(par -> {
            Instant ahora = reloj.instant();
            List<HallazgoDeEstado> todos = new ArrayList<>(reglas.auditarCuenta(par.getItem2()));
            todos.addAll(reglas.auditarEstados(par.getItem1(), ahora, seguimiento.actualizar(par.getItem1(), ahora)));
            return todos;
        });
    }
}
```

## 9. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Reglas de la cuenta y de los estados** | Registros armados a mano, una prueba por regla | Sin red: son funciones puras |
| **Seguimiento de bloqueos** | Reloj controlado: primera lectura, segunda lectura, estado liberado | Comprueba que un estado liberado se "olvida" |
| **Inventario** | `HttpClient` falso de azure-core que devuelve el XML real de un listado de blobs | Comprueba que solo se piden propiedades y que no hay llamadas de descarga |
| **Configuración** | Respuestas guardadas de ARM para la cuenta y el servicio de blobs | Cubre `networkRuleSet` ausente (se trata como abierto) |
| **Integración** | Una cuenta de laboratorio con estados de prueba y un bloqueo provocado | La única forma de ver permisos y bloqueos reales |

```java
// nocheck — requiere JUnit 5
class EstadoTest {

    private final ReglasDelEstado reglas = new ReglasDelEstado(1_000_000, Duration.ofDays(180), Duration.ofMinutes(45));

    @Test
    void marcaBloqueoLargoYFueraDeConvencion() {
        Instant ahora = Instant.parse("2026-10-16T12:00:00Z");
        var estado = new EstadoRemoto("raro.tfstate", 10, OffsetDateTime.parse("2026-10-16T10:00:00Z"), true);

        var hallazgos = reglas.auditarEstados(List.of(estado), ahora, Map.of("raro.tfstate", Duration.ofMinutes(90)));

        assertTrue(hallazgos.stream().anyMatch(h -> h.regla().equals("BLOQUEO_LARGO")));
        assertTrue(hallazgos.stream().anyMatch(h -> h.regla().equals("FUERA_DE_CONVENCION")));
    }

    @Test
    void elSeguimientoOlvidaLosEstadosLiberados() {
        var seguimiento = new SeguimientoDeBloqueos();
        Instant t0 = Instant.parse("2026-10-16T12:00:00Z");
        var bloqueado = new EstadoRemoto("dev/red.tfstate", 1, null, true);
        var libre = new EstadoRemoto("dev/red.tfstate", 1, null, false);

        seguimiento.actualizar(List.of(bloqueado), t0);
        assertEquals(Duration.ofMinutes(10), seguimiento.actualizar(List.of(bloqueado), t0.plusSeconds(600)).get("dev/red.tfstate"));
        assertTrue(seguimiento.actualizar(List.of(libre), t0.plusSeconds(700)).isEmpty());
        assertEquals(Duration.ZERO, seguimiento.actualizar(List.of(bloqueado), t0.plusSeconds(800)).get("dev/red.tfstate"));
    }

    @Test
    void unaCuentaConClavesYSinVersionadoGeneraHallazgos() {
        var cuenta = new ConfiguracionDeLaCuenta("st", true, false, "TLS1_2", false, false, 30, 30);

        var reglasDisparadas = reglas.auditarCuenta(cuenta).stream().map(HallazgoDeEstado::regla).toList();

        assertEquals(List.of("CLAVE_COMPARTIDA", "SIN_VERSIONADO"), reglasDisparadas);
    }
}
```

## 10. Buenas prácticas de código

- **Observar, no tocar:** este servicio no descarga estados, no escribe y no libera bloqueos.
- **Identidad administrada propia** (*Storage Blob Data Reader* sobre el contenedor y *Reader* sobre la cuenta); nada de claves ni SAS.
- **Funciones puras** para las reglas y un reloj inyectable: las pruebas no dependen de la hora ni de la red.
- **Refresco en segundo plano** y métricas que conservan el último valor ante un fallo de Azure.
- **Un bloqueo largo se detecta por observación** (primera vez visto), no por supuestos sobre el *lease*.
- **Umbrales por configuración:** el tamaño, la inactividad y el bloqueo máximo cambian con tu realidad.
- Los errores de Azure (`403`, `404`) se traducen a respuestas claras; el detalle va a los registros, **sin volcar nombres de estados sensibles** a clientes que no los necesitan.
- En reactivo, **no bloquees** el hilo de eventos: `boundedElastic` / pool de trabajadores / hilos virtuales.
