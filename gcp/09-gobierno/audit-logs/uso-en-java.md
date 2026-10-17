# Google Cloud · Gobierno · Cloud Audit Logs · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: un **constructor puro de filtros** del lenguaje de Logging para los cuatro tipos de auditoría (con escape de valores, para no inyectar condiciones), y un adaptador que lee entradas con `Logging.listLogEntries` y **desempaqueta el `AuditLog`** del `protoPayload` para devolver quién, qué método y sobre qué recurso. Ideal para un panel de investigación interno.

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

### 2.2 Filtros (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Arma filtros del lenguaje de consultas de Logging para auditoría, escapando valores. Puro.
 */
public final class FiltroDeAuditoria {

    public enum Tipo { ACTIVIDAD, ACCESO_A_DATOS, SISTEMA, POLITICA }

    private FiltroDeAuditoria() {
    }

    public static String de(String proyecto, Tipo tipo, String metodo, String principal, Instant desde) {
        String log = switch (tipo) {
            case ACTIVIDAD -> "activity";
            case ACCESO_A_DATOS -> "data_access";
            case SISTEMA -> "system_event";
            case POLITICA -> "policy";
        };
        var partes = new ArrayList<String>(List.of(
            "logName=\"projects/" + proyecto + "/logs/cloudaudit.googleapis.com%2F" + log + "\""));
        if (metodo != null && !metodo.isBlank()) {
            partes.add("protoPayload.methodName:\"" + escapar(metodo) + "\"");
        }
        if (principal != null && !principal.isBlank()) {
            partes.add("protoPayload.authenticationInfo.principalEmail=\"" + escapar(principal) + "\"");
        }
        if (desde != null) {
            partes.add("timestamp>=\"" + desde + "\"");
        }
        return String.join(" AND ", partes);
    }

    static String escapar(String v) {
        return v.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.audit.AuditLog;
import com.google.cloud.logging.Logging;
import com.google.cloud.logging.LoggingOptions;
import com.google.cloud.logging.Payload;
import com.google.protobuf.InvalidProtocolBufferException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee entradas de auditoría y extrae quién, qué y sobre qué recurso. */
public class AuditoriaGcp implements AutoCloseable {

    public record Evento(Instant momento, String principal, String servicio, String metodo, String recurso) { }

    private final Logging logging;
    private final String proyecto;

    public AuditoriaGcp(GoogleCredentials cred, String proyecto) {
        this.proyecto = proyecto;
        this.logging = LoggingOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
    }

    public List<Evento> buscar(String filtro, int maximo) {
        var out = new ArrayList<Evento>();
        var pagina = logging.listLogEntries(Logging.EntryListOption.filter(filtro),
            Logging.EntryListOption.sortOrder(Logging.SortingField.TIMESTAMP, Logging.SortingOrder.DESCENDING),
            Logging.EntryListOption.pageSize(Math.min(maximo, 100)));
        for (var e : pagina.iterateAll()) {
            if (out.size() >= maximo) {
                break;
            }
            if (e.getPayload() instanceof Payload.ProtoPayload p) {
                try {
                    var a = p.getData().unpack(AuditLog.class);
                    out.add(new Evento(Instant.ofEpochMilli(e.getTimestamp()), a.getAuthenticationInfo().getPrincipalEmail(),
                        a.getServiceName(), a.getMethodName(), a.getResourceName()));
                } catch (InvalidProtocolBufferException ex) {
                    // entrada que no es AuditLog: se omite
                }
            }
        }
        return out;
    }

    public String proyecto() {
        return proyecto;
    }

    @Override
    public void close() {
        try {
            logging.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.List;

public class ServicioDeAuditoria {

    private final AuditoriaGcp gcp;
    private final String proyecto;

    public ServicioDeAuditoria(AuditoriaGcp gcp) {
        this.gcp = gcp;
        this.proyecto = gcp.proyecto();
    }

    /** Cambios de IAM de las últimas N horas. */
    public List<AuditoriaGcp.Evento> cambiosIam(int horas) {
        var f = FiltroDeAuditoria.de(proyecto, FiltroDeAuditoria.Tipo.ACTIVIDAD, "SetIamPolicy", null,
            Instant.now().minus(Duration.ofHours(horas)));
        return gcp.buscar(f, 50);
    }

    public String filtro(String metodo, String principal) {
        return FiltroDeAuditoria.de(proyecto, FiltroDeAuditoria.Tipo.ACCESO_A_DATOS, metodo, principal, null);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class AuditoriaConfiguracion {

    @Bean(destroyMethod = "close")
    AuditoriaGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new AuditoriaGcp(cred, proyecto);
    }

    @Bean
    ServicioDeAuditoria servicio(AuditoriaGcp a) {
        return new ServicioDeAuditoria(a);
    }
}

@RestController
@RequestMapping("/gobierno/auditoria")
class AuditoriaControlador {

    private final ServicioDeAuditoria s;

    AuditoriaControlador(ServicioDeAuditoria s) {
        this.s = s;
    }

    @GetMapping("/iam")
    java.util.List<AuditoriaGcp.Evento> cambiosIam(@RequestParam int horas) {
        return s.cambiosIam(horas);
    }

    @GetMapping("/filtro")
    String filtro(@RequestParam String metodo, @RequestParam String principal) {
        return s.filtro(metodo, principal);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/auditoria")
class AuditoriaReactivoControlador {

    private final ServicioDeAuditoria s;

    AuditoriaReactivoControlador(ServicioDeAuditoria s) {
        this.s = s;
    }

    @GetMapping("/iam")
    Mono<java.util.List<AuditoriaGcp.Evento>> cambiosIam(@RequestParam int horas) {
        return Mono.fromCallable(() -> s.cambiosIam(horas)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/filtro")
    Mono<String> filtro(@RequestParam String metodo, @RequestParam String principal) {
        return Mono.fromCallable(() -> s.filtro(metodo, principal));
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AuditoriaProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    AuditoriaGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new AuditoriaGcp(cred, proyecto);
    }

    void cerrar(@Disposes AuditoriaGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeAuditoria servicio(AuditoriaGcp a) {
        return new ServicioDeAuditoria(a);
    }
}

@Path("/gobierno/auditoria")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class AuditoriaRecurso {

    @Inject
    ServicioDeAuditoria s;

    @GET
    @Path("/iam")
    public java.util.List<AuditoriaGcp.Evento> cambiosIam(@QueryParam("horas") int horas) {
        return s.cambiosIam(horas);
    }

    @GET
    @Path("/filtro")
    public String filtro(@QueryParam("metodo") String metodo, @QueryParam("principal") String principal) {
        return s.filtro(metodo, principal);
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
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/gobierno/auditoria")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class AuditoriaRecursoReactivo {

    @Inject
    ServicioDeAuditoria s;

    @GET
    @Path("/iam")
    public Uni<java.util.List<AuditoriaGcp.Evento>> cambiosIam(@QueryParam("horas") int horas) {
        return Uni.createFrom().item(() -> s.cambiosIam(horas)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/filtro")
    public Uni<String> filtro(@QueryParam("metodo") String metodo, @QueryParam("principal") String principal) {
        return Uni.createFrom().item(() -> s.filtro(metodo, principal));
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer Admin Activity | `roles/logging.viewer` |
| Leer Data Access | `roles/logging.privateLogViewer` |

## 8. Qué NO hacer desde Java
- No concatenes valores del usuario en el filtro sin escapar.
- No expongas el panel fuera del equipo de seguridad.
- No pidas páginas enormes: acota por tiempo y método.
- No copies entradas de Data Access a sistemas sin control de acceso.
