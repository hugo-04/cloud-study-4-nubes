# Google Cloud · Gobierno · Security Command Center · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: un **triaje puro** que asigna un plazo de remediación por severidad (24 h críticos, 7 días altos…), marca vencidos y ordena por vencimiento; y un adaptador que trae los **hallazgos activos y no silenciados** de severidad crítica o alta de toda la organización con `v2.SecurityCenterClient.listFindings` (todas las fuentes con `sources/-`).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
scc:
  organizacion: 123456789012
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
scc.organizacion=123456789012
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

### 2.2 Triaje (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/**
 * Triaje: plazo de remediación por severidad, vencidos y orden de atención. Puro.
 */
public final class Triaje {

    public record Hallazgo(String categoria, String severidad, String recurso, Instant detectado) { }

    public record Priorizado(Hallazgo hallazgo, Instant vence, boolean vencido, long horasRestantes) { }

    private static final Map<String, Duration> SLA = Map.of(
        "CRITICAL", Duration.ofHours(24),
        "HIGH", Duration.ofDays(7),
        "MEDIUM", Duration.ofDays(30),
        "LOW", Duration.ofDays(90));

    private Triaje() {
    }

    public static List<Priorizado> priorizar(List<Hallazgo> hallazgos, Instant ahora) {
        return hallazgos.stream().map(h -> {
            var vence = h.detectado().plus(SLA.getOrDefault(h.severidad(), Duration.ofDays(90)));
            long horas = Duration.between(ahora, vence).toHours();
            return new Priorizado(h, vence, vence.isBefore(ahora), horas);
        }).sorted(Comparator.comparing(Priorizado::vence)).toList();
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.securitycenter.v2.ListFindingsRequest;
import com.google.cloud.securitycenter.v2.SecurityCenterClient;
import com.google.cloud.securitycenter.v2.SecurityCenterSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: hallazgos activos, no silenciados, de severidad alta o crítica en la organización. */
public class SccGcp implements AutoCloseable {

    private final SecurityCenterClient cliente;
    private final String organizacion;

    public SccGcp(GoogleCredentials cred, String organizacion) {
        try {
            this.cliente = SecurityCenterClient.create(SecurityCenterSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.organizacion = organizacion;
    }

    public List<Triaje.Hallazgo> activos(int maximo) {
        var req = ListFindingsRequest.newBuilder()
            .setParent("organizations/" + organizacion + "/sources/-/locations/global")
            .setFilter("state=\"ACTIVE\" AND mute!=\"MUTED\" AND (severity=\"CRITICAL\" OR severity=\"HIGH\")")
            .setPageSize(Math.min(maximo, 100))
            .build();
        var out = new ArrayList<Triaje.Hallazgo>();
        for (var r : cliente.listFindings(req).iterateAll()) {
            if (out.size() >= maximo) {
                break;
            }
            var f = r.getFinding();
            out.add(new Triaje.Hallazgo(f.getCategory(), f.getSeverity().name(), f.getResourceName(),
                Instant.ofEpochSecond(f.getEventTime().getSeconds())));
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
import java.time.Instant;
import java.util.List;

public class ServicioDeTriaje {

    private final SccGcp scc;

    public ServicioDeTriaje(SccGcp scc) {
        this.scc = scc;
    }

    public List<Triaje.Priorizado> pendientes() {
        return Triaje.priorizar(scc.activos(200), Instant.now());
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class TriajeConfiguracion {

    @Bean(destroyMethod = "close")
    SccGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${scc.organizacion}") String organizacion) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SccGcp(cred, organizacion);
    }

    @Bean
    ServicioDeTriaje servicio(SccGcp a) {
        return new ServicioDeTriaje(a);
    }
}

@RestController
@RequestMapping("/gobierno/hallazgos")
class TriajeControlador {

    private final ServicioDeTriaje s;

    TriajeControlador(ServicioDeTriaje s) {
        this.s = s;
    }

    @GetMapping("")
    java.util.List<Triaje.Priorizado> pendientes() {
        return s.pendientes();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/hallazgos")
class TriajeReactivoControlador {

    private final ServicioDeTriaje s;

    TriajeReactivoControlador(ServicioDeTriaje s) {
        this.s = s;
    }

    @GetMapping("")
    Mono<java.util.List<Triaje.Priorizado>> pendientes() {
        return Mono.fromCallable(() -> s.pendientes()).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class TriajeProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "scc.organizacion")
    String organizacion;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SccGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SccGcp(cred, organizacion);
    }

    void cerrar(@Disposes SccGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeTriaje servicio(SccGcp a) {
        return new ServicioDeTriaje(a);
    }
}

@Path("/gobierno/hallazgos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class TriajeRecurso {

    @Inject
    ServicioDeTriaje s;

    @GET
    @Path("")
    public java.util.List<Triaje.Priorizado> pendientes() {
        return s.pendientes();
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
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/gobierno/hallazgos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class TriajeRecursoReactivo {

    @Inject
    ServicioDeTriaje s;

    @GET
    @Path("")
    public Uni<java.util.List<Triaje.Priorizado>> pendientes() {
        return Uni.createFrom().item(() -> s.pendientes()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer hallazgos | `roles/securitycenter.findingsViewer` en la organización |
| Cambiar estado o mute | `roles/securitycenter.findingsEditor` (no para este servicio) |

## 8. Qué NO hacer desde Java
- No muestres descripciones de amenazas a todo el mundo.
- No silencies desde la app: el mute es una decisión revisada.
- No traigas todas las severidades a la vez.
- No uses el triaje como sustituto de prevenir con Org Policy.
