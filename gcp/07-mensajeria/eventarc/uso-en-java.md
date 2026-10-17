# Google Cloud · Mensajería · Eventarc · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: un **receptor de CloudEvents en modo binario** (lee `ce-id`, `ce-source`, `ce-type`, `ce-time`, valida, filtra por tipo y deduplica por `source|id`) y un adaptador que **audita los disparadores** con `EventarcClient.listTriggers` en todas las ubicaciones: cuenta de servicio por defecto, filtros de Audit Logs demasiado amplios y destino. En el ejemplo las cabeceras llegan como mapa para no atar la lógica al framework.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
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

### 2.2 Receptor (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Receptor de CloudEvents en modo binario: lee las cabeceras ce-*, valida, deduplica por (source, id)
 * y decide si el evento interesa. Puro: no depende del framework web.
 */
public class ReceptorDeEventos {

    public record Evento(String id, String source, String type, String subject, Instant time) { }

    public record Decision(String accion, Evento evento, List<String> motivos) { }

    private final Set<String> tiposAceptados;
    private final Map<String, Boolean> vistos = new ConcurrentHashMap<>();

    public ReceptorDeEventos(Set<String> tiposAceptados) {
        this.tiposAceptados = Set.copyOf(tiposAceptados);
    }

    public Decision recibir(Map<String, String> cabeceras) {
        var c = new LinkedHashMap<String, String>();
        cabeceras.forEach((k, v) -> c.put(k.toLowerCase(), v));
        var motivos = new ArrayList<String>();
        for (String obligatoria : List.of("ce-id", "ce-source", "ce-type", "ce-specversion")) {
            if (c.get(obligatoria) == null || c.get(obligatoria).isBlank()) {
                motivos.add("falta " + obligatoria);
            }
        }
        if (!motivos.isEmpty()) {
            return new Decision("descartar", null, motivos);   // 2xx igualmente: reintentar no lo arregla
        }
        Instant t = c.containsKey("ce-time") ? Instant.parse(c.get("ce-time")) : null;
        var e = new Evento(c.get("ce-id"), c.get("ce-source"), c.get("ce-type"), c.get("ce-subject"), t);
        if (!tiposAceptados.contains(e.type())) {
            return new Decision("ignorar", e, List.of("tipo no aceptado: " + e.type()));
        }
        if (vistos.putIfAbsent(e.source() + "|" + e.id(), Boolean.TRUE) != null) {
            return new Decision("duplicado", e, List.of("ya procesado"));
        }
        return new Decision("procesar", e, List.of());
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.eventarc.v1.EventarcClient;
import com.google.cloud.eventarc.v1.EventarcSettings;
import com.google.cloud.eventarc.v1.Trigger;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: audita los disparadores del proyecto (cuenta de servicio, filtros y destino). */
public class EventarcGcp implements AutoCloseable {

    public record Hallazgo(String disparador, String destino, List<String> filtros, List<String> problemas) { }

    private final EventarcClient cliente;
    private final String proyecto;

    public EventarcGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = EventarcClient.create(EventarcSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Hallazgo> auditar() {
        var out = new ArrayList<Hallazgo>();
        for (Trigger t : cliente.listTriggers("projects/" + proyecto + "/locations/-").iterateAll()) {
            var filtros = t.getEventFiltersList().stream().map(f -> f.getAttribute() + "=" + f.getValue()).toList();
            var problemas = new ArrayList<String>();
            if (t.getServiceAccount().isBlank() || t.getServiceAccount().contains("-compute@")) {
                problemas.add("usa la cuenta por defecto de Compute (o ninguna)");
            }
            boolean auditLogs = filtros.contains("type=google.cloud.audit.log.v1.written");
            if (auditLogs && filtros.stream().noneMatch(f -> f.startsWith("methodName="))) {
                problemas.add("Audit Logs sin filtro de methodName: mucho ruido");
            }
            var d = t.getDestination();
            String destino = d.hasCloudRun() ? "run:" + d.getCloudRun().getService() + d.getCloudRun().getPath()
                : d.hasWorkflow() ? "workflow:" + d.getWorkflow() : d.hasGke() ? "gke:" + d.getGke().getService() : "otro";
            out.add(new Hallazgo(t.getName().substring(t.getName().lastIndexOf('/') + 1), destino, filtros, problemas));
        }
        return out;
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
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ServicioDeEventos {

    private final EventarcGcp gcp;
    private final ReceptorDeEventos receptor = new ReceptorDeEventos(Set.of("google.cloud.audit.log.v1.written"));

    public ServicioDeEventos(EventarcGcp gcp) {
        this.gcp = gcp;
    }

    /** Siempre se responde 2xx salvo error transitorio propio: así Eventarc no reintenta lo ya decidido. */
    public ReceptorDeEventos.Decision recibir(Map<String, String> cabeceras) {
        return receptor.recibir(cabeceras);
    }

    public List<EventarcGcp.Hallazgo> auditar() {
        return gcp.auditar();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EventosConfiguracion {

    @Bean(destroyMethod = "close")
    EventarcGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new EventarcGcp(cred, proyecto);
    }

    @Bean
    ServicioDeEventos servicio(EventarcGcp a) {
        return new ServicioDeEventos(a);
    }
}

@RestController
@RequestMapping("/mensajeria/eventos")
class EventosControlador {

    private final ServicioDeEventos s;

    EventosControlador(ServicioDeEventos s) {
        this.s = s;
    }

    @PostMapping("/iam")
    ReceptorDeEventos.Decision recibir(@RequestBody java.util.Map<String, String> cabeceras) {
        return s.recibir(cabeceras);
    }

    @GetMapping("/disparadores")
    java.util.List<EventarcGcp.Hallazgo> auditar() {
        return s.auditar();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/mensajeria/eventos")
class EventosReactivoControlador {

    private final ServicioDeEventos s;

    EventosReactivoControlador(ServicioDeEventos s) {
        this.s = s;
    }

    @PostMapping("/iam")
    Mono<ReceptorDeEventos.Decision> recibir(@RequestBody java.util.Map<String, String> cabeceras) {
        return Mono.fromCallable(() -> s.recibir(cabeceras));
    }

    @GetMapping("/disparadores")
    Mono<java.util.List<EventarcGcp.Hallazgo>> auditar() {
        return Mono.fromCallable(() -> s.auditar()).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EventosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    EventarcGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new EventarcGcp(cred, proyecto);
    }

    void cerrar(@Disposes EventarcGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEventos servicio(EventarcGcp a) {
        return new ServicioDeEventos(a);
    }
}

@Path("/mensajeria/eventos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EventosRecurso {

    @Inject
    ServicioDeEventos s;

    @POST
    @Path("/iam")
    @Consumes(MediaType.APPLICATION_JSON)
    public ReceptorDeEventos.Decision recibir(java.util.Map<String, String> cabeceras) {
        return s.recibir(cabeceras);
    }

    @GET
    @Path("/disparadores")
    public java.util.List<EventarcGcp.Hallazgo> auditar() {
        return s.auditar();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/mensajeria/eventos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EventosRecursoReactivo {

    @Inject
    ServicioDeEventos s;

    @POST
    @Path("/iam")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ReceptorDeEventos.Decision> recibir(java.util.Map<String, String> cabeceras) {
        return Uni.createFrom().item(() -> s.recibir(cabeceras));
    }

    @GET
    @Path("/disparadores")
    public Uni<java.util.List<EventarcGcp.Hallazgo>> auditar() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Recibir eventos | La SA del disparador con `roles/run.invoker` sobre el destino |
| Auditar disparadores | `roles/eventarc.viewer` en el proyecto |

## 8. Qué NO hacer desde Java
- No dependas de entrega única: deduplica.
- No respondas 500 a eventos inválidos: los reintentos no los arreglan.
- No registres el cuerpo completo de Audit Logs (puede traer datos sensibles).
- En producción guarda los `vistos` en un almacén compartido con caducidad, no en memoria.
