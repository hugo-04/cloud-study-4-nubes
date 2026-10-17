# Google Cloud · Mensajería · Cloud Tasks · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **programador de recordatorios idempotente**: la lógica pura genera un **nombre de tarea determinista** por carrito y día, valida la agenda (≤ 30 días) y el tamaño; el adaptador crea la tarea HTTP con `CloudTasksClient.createTask`, hora programada y **token OIDC** de la cuenta de despacho, y trata `ALREADY_EXISTS` como éxito (la tarea ya estaba programada).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
tareas:
  region: southamerica-west1
  cola: recordatorios
  url: https://correos-abc123-tl.a.run.app/recordatorio
  cuenta: tasks-despacho@modalima-prod.iam.gserviceaccount.com
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
tareas.region=southamerica-west1
tareas.cola=recordatorios
tareas.url=https://correos-abc123-tl.a.run.app/recordatorio
tareas.cuenta=tasks-despacho@modalima-prod.iam.gserviceaccount.com
```

## 2. Núcleo común

### 2.1 Credenciales según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ImpersonatedCredentials;
import java.io.IOException;
import java.util.List;

public final class Credenciales {

    private static final List<String> ALCANCE = List.of("https://www.googleapis.com/auth/cloud-platform");

    private Credenciales() { }

    /**
     * ADC (Application Default Credentials): en la laptop, «gcloud auth application-default login»;
     * en GKE, Cloud Run, Functions o Compute Engine, la cuenta de servicio adjunta (sin llaves).
     * suplantar = correo de una cuenta de servicio para actuar como ella, o "ninguna".
     */
    public static GoogleCredentials crear(String suplantar) {
        try {
            var base = GoogleCredentials.getApplicationDefault().createScoped(ALCANCE);
            if (suplantar == null || suplantar.isBlank() || "ninguna".equals(suplantar)) {
                return base;
            }
            return ImpersonatedCredentials.create(base, suplantar, null, ALCANCE, 3600);
        } catch (IOException e) {
            throw new IllegalStateException("no hay credenciales ADC disponibles", e);
        }
    }
}
```

### 2.2 Planificador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;

/** Planifica tareas: nombre determinista (idempotencia), agenda acotada y tamaño máximo. Puro. */
public class PlanificadorDeTareas {

    public record Plan(String nombre, Instant ejecutarEn, byte[] cuerpo) { }

    private final Clock reloj;

    public PlanificadorDeTareas(Clock reloj) {
        this.reloj = reloj;
    }

    /** Un recordatorio por carrito y día: crear dos veces el mismo plan da el mismo nombre. */
    public Plan recordatorioDeCarrito(String idCarrito, Duration espera, String cuerpoJson) {
        if (!idCarrito.matches("C-[0-9]{1,12}")) {
            throw new IllegalArgumentException("carrito inválido");
        }
        if (espera.isNegative() || espera.compareTo(Duration.ofDays(30)) > 0) {
            throw new IllegalArgumentException("la agenda máxima es de 30 días");
        }
        byte[] cuerpo = cuerpoJson.getBytes(StandardCharsets.UTF_8);
        if (cuerpo.length > 100 * 1024) {
            throw new IllegalArgumentException("cuerpo demasiado grande: guarda los datos y envía una referencia");
        }
        Instant ahora = reloj.instant();
        String dia = LocalDate.ofInstant(ahora, ZoneOffset.UTC).toString().replace("-", "");
        return new Plan("recordatorio-" + idCarrito + "-" + dia, ahora.plus(espera), cuerpo);
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.api.gax.rpc.AlreadyExistsException;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.tasks.v2.CloudTasksClient;
import com.google.cloud.tasks.v2.CloudTasksSettings;
import com.google.cloud.tasks.v2.HttpMethod;
import com.google.cloud.tasks.v2.HttpRequest;
import com.google.cloud.tasks.v2.OidcToken;
import com.google.cloud.tasks.v2.QueueName;
import com.google.cloud.tasks.v2.Task;
import com.google.cloud.tasks.v2.TaskName;
import com.google.protobuf.ByteString;
import com.google.protobuf.Timestamp;
import java.io.IOException;
import java.io.UncheckedIOException;

/** Adaptador: crea tareas HTTP con OIDC; el nombre repetido se trata como éxito idempotente. */
public class TareasGcp implements AutoCloseable {

    public record Creada(String nombre, boolean nueva) { }

    private final CloudTasksClient cliente;
    private final String proyecto;
    private final String region;
    private final String cola;
    private final String url;
    private final String cuentaDespacho;

    public TareasGcp(GoogleCredentials cred, String proyecto, String region, String cola, String url, String cuentaDespacho) {
        try {
            this.cliente = CloudTasksClient.create(CloudTasksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
        this.region = region;
        this.cola = cola;
        this.url = url;
        this.cuentaDespacho = cuentaDespacho;
    }

    public Creada crear(PlanificadorDeTareas.Plan p) {
        var nombre = TaskName.of(proyecto, region, cola, p.nombre()).toString();
        var tarea = Task.newBuilder().setName(nombre)
            .setScheduleTime(Timestamp.newBuilder().setSeconds(p.ejecutarEn().getEpochSecond()))
            .setHttpRequest(HttpRequest.newBuilder().setUrl(url).setHttpMethod(HttpMethod.POST)
                .putHeaders("Content-Type", "application/json").setBody(ByteString.copyFrom(p.cuerpo()))
                .setOidcToken(OidcToken.newBuilder().setServiceAccountEmail(cuentaDespacho).setAudience(url.replaceFirst("(https://[^/]+).*", "$1"))))
            .build();
        try {
            cliente.createTask(QueueName.of(proyecto, region, cola), tarea);
            return new Creada(p.nombre(), true);
        } catch (AlreadyExistsException e) {
            return new Creada(p.nombre(), false); // ya estaba programada: idempotente
        }
    }

    @Override
    public void close() {
        cliente.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;

public class ServicioDeRecordatorios {

    private final TareasGcp tareas;
    private final PlanificadorDeTareas planificador = new PlanificadorDeTareas(Clock.systemUTC());

    public ServicioDeRecordatorios(TareasGcp tareas) {
        this.tareas = tareas;
    }

    public TareasGcp.Creada programar(String idCarrito) {
        var plan = planificador.recordatorioDeCarrito(idCarrito, Duration.ofHours(24), "{\"carrito\":\"" + idCarrito + "\"}");
        return tareas.crear(plan);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class RecordatoriosConfiguracion {

    @Bean(destroyMethod = "close")
    TareasGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${tareas.region}") String region, @Value("${tareas.cola}") String cola, @Value("${tareas.url}") String url, @Value("${tareas.cuenta}") String cuenta) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new TareasGcp(cred, proyecto, region, cola, url, cuenta);
    }

    @Bean
    ServicioDeRecordatorios servicio(TareasGcp a) {
        return new ServicioDeRecordatorios(a);
    }
}

@RestController
@RequestMapping("/mensajeria/recordatorios")
class RecordatoriosControlador {

    private final ServicioDeRecordatorios s;

    RecordatoriosControlador(ServicioDeRecordatorios s) {
        this.s = s;
    }

    @PostMapping("/{carrito}")
    TareasGcp.Creada programar(@PathVariable String carrito) {
        return s.programar(carrito);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/mensajeria/recordatorios")
class RecordatoriosReactivoControlador {

    private final ServicioDeRecordatorios s;

    RecordatoriosReactivoControlador(ServicioDeRecordatorios s) {
        this.s = s;
    }

    @PostMapping("/{carrito}")
    Mono<TareasGcp.Creada> programar(@PathVariable String carrito) {
        return Mono.fromCallable(() -> s.programar(carrito)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.google.auth.oauth2.GoogleCredentials;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class RecordatoriosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "tareas.region")
    String region;

    @ConfigProperty(name = "tareas.cola")
    String cola;

    @ConfigProperty(name = "tareas.url")
    String url;

    @ConfigProperty(name = "tareas.cuenta")
    String cuenta;

    @jakarta.enterprise.inject.Produces
    @Singleton
    TareasGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new TareasGcp(cred, proyecto, region, cola, url, cuenta);
    }

    void cerrar(@Disposes TareasGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeRecordatorios servicio(TareasGcp a) {
        return new ServicioDeRecordatorios(a);
    }
}

@Path("/mensajeria/recordatorios")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class RecordatoriosRecurso {

    @Inject
    ServicioDeRecordatorios s;

    @POST
    @Path("/{carrito}")
    public TareasGcp.Creada programar(@PathParam("carrito") String carrito) {
        return s.programar(carrito);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/mensajeria/recordatorios")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class RecordatoriosRecursoReactivo {

    @Inject
    ServicioDeRecordatorios s;

    @POST
    @Path("/{carrito}")
    public Uni<TareasGcp.Creada> programar(@PathParam("carrito") String carrito) {
        return Uni.createFrom().item(() -> s.programar(carrito)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Crear tareas | `roles/cloudtasks.enqueuer` en la cola + `roles/iam.serviceAccountUser` sobre la SA de despacho |
| Despachar al destino | `roles/run.invoker` para la SA de despacho |

## 8. Qué NO hacer desde Java
- No crees tareas sin nombre si el productor puede reintentar.
- No pongas datos personales completos ni secretos en el cuerpo.
- No respondas 500 en el destino ante datos inválidos: reintentará hasta el tope.
- No uses Cloud Tasks para difundir a varios sistemas: eso es Pub/Sub.
