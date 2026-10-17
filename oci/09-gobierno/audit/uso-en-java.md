# Oracle OCI · Gobierno · Audit · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **detector de actividad sensible**: trae los eventos de Audit de una ventana acotada (`AuditClient.listEvents`, paginando) y marca operaciones sensibles (políticas, borrados, llaves de API, buckets) hechas fuera de horario en la zona horaria del negocio, desde IP no habitual o denegadas. Útil como tarea cada hora que publica en un tema de seguridad.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
```

## 2. Núcleo común

### 2.1 Autenticación según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
        }
    }
}
```

### 2.2 Detector (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Señala eventos sensibles fuera de horario, desde IP no habitual o fallidos repetidos. Puro. */
public class DetectorDeActividad {

    public record Evento(String nombre, String principal, String ip, String recurso, Instant cuando, int estado) { }

    public record Alerta(Evento evento, List<String> motivos) { }

    private final Set<String> sensibles;
    private final Set<String> prefijosIpConocidos;
    private final ZoneId zona;

    public DetectorDeActividad(Set<String> sensibles, Set<String> prefijosIpConocidos, ZoneId zona) {
        this.sensibles = Set.copyOf(sensibles);
        this.prefijosIpConocidos = Set.copyOf(prefijosIpConocidos);
        this.zona = zona;
    }

    public List<Alerta> analizar(List<Evento> eventos) {
        var out = new ArrayList<Alerta>();
        for (Evento e : eventos) {
            boolean sensible = sensibles.stream().anyMatch(s -> e.nombre().startsWith(s));
            if (!sensible) {
                continue;
            }
            var motivos = new ArrayList<String>();
            var local = e.cuando().atZone(zona);
            LocalTime hora = local.toLocalTime();
            boolean finDeSemana = local.getDayOfWeek() == DayOfWeek.SATURDAY || local.getDayOfWeek() == DayOfWeek.SUNDAY;
            if (finDeSemana || hora.isBefore(LocalTime.of(7, 0)) || hora.isAfter(LocalTime.of(21, 0))) {
                motivos.add("fuera de horario (" + local.getDayOfWeek() + " " + hora.withNano(0) + ")");
            }
            if (e.ip() != null && prefijosIpConocidos.stream().noneMatch(e.ip()::startsWith)) {
                motivos.add("IP no habitual " + e.ip());
            }
            if (e.estado() == 401 || e.estado() == 403 || e.estado() == 404) {
                motivos.add("intento denegado (" + e.estado() + ")");
            }
            if (!motivos.isEmpty()) {
                out.add(new Alerta(e, motivos));
            }
        }
        return out;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.audit.AuditClient;
import com.oracle.bmc.audit.requests.ListEventsRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/** Adaptador del SDK: eventos de auditoría de una ventana (paginando). */
public class AuditOci implements AutoCloseable {

    private final AuditClient cliente;

    public AuditOci(AuditClient cliente) {
        this.cliente = cliente;
    }

    public List<DetectorDeActividad.Evento> eventos(String compartimentoId, Instant desde, Instant hasta) {
        var out = new ArrayList<DetectorDeActividad.Evento>();
        String pagina = null;
        do {
            var r = cliente.listEvents(ListEventsRequest.builder().compartmentId(compartimentoId)
                .startTime(Date.from(desde)).endTime(Date.from(hasta)).page(pagina).build());
            for (var e : r.getItems()) {
                var d = e.getData();
                int estado = d.getResponse() == null || d.getResponse().getStatus() == null ? 0 : Integer.parseInt(d.getResponse().getStatus());
                out.add(new DetectorDeActividad.Evento(d.getEventName(),
                    d.getIdentity() == null ? null : d.getIdentity().getPrincipalName(),
                    d.getIdentity() == null ? null : d.getIdentity().getIpAddress(),
                    d.getResourceName(), e.getEventTime().toInstant(), estado));
            }
            pagina = r.getOpcNextPage();
        } while (pagina != null);
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
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;

public class ServicioDeAuditoria {

    private final AuditOci audit;
    private final DetectorDeActividad detector = new DetectorDeActividad(
        Set.of("CreatePolicy", "UpdatePolicy", "DeletePolicy", "UpdateSecurityList", "Delete", "UpdateBucket", "CreateApiKey"),
        Set.of("10.", "200.48."), ZoneId.of("America/Lima"));

    public ServicioDeAuditoria(AuditOci audit) {
        this.audit = audit;
    }

    public List<DetectorDeActividad.Alerta> revisar(String compartimentoId, int horas) {
        if (horas < 1 || horas > 72) {
            throw new IllegalArgumentException("ventana de 1 a 72 horas");
        }
        Instant hasta = Instant.now();
        return detector.analizar(audit.eventos(compartimentoId, hasta.minus(Duration.ofHours(horas)), hasta));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.audit.AuditClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.List;
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
    AuditOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new AuditOci(AuditClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeAuditoria servicio(AuditOci a) {
        return new ServicioDeAuditoria(a);
    }
}

@RestController
@RequestMapping("/gobierno/audit")
class AuditoriaControlador {

    private final ServicioDeAuditoria s;

    AuditoriaControlador(ServicioDeAuditoria s) {
        this.s = s;
    }

    @GetMapping("/revision")
    List<DetectorDeActividad.Alerta> revisar(@RequestParam String compartimento, @RequestParam int horas) {
        return s.revisar(compartimento, horas);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.audit.AuditClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/audit")
class AuditoriaReactivoControlador {

    private final ServicioDeAuditoria s;

    AuditoriaReactivoControlador(ServicioDeAuditoria s) {
        this.s = s;
    }

    @GetMapping("/revision")
    Mono<List<DetectorDeActividad.Alerta>> revisar(@RequestParam String compartimento, @RequestParam int horas) {
        return Mono.fromCallable(() -> s.revisar(compartimento, horas)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.audit.AuditClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AuditoriaProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    AuditOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new AuditOci(AuditClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes AuditOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeAuditoria servicio(AuditOci a) {
        return new ServicioDeAuditoria(a);
    }
}

@Path("/gobierno/audit")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class AuditoriaRecurso {

    @Inject
    ServicioDeAuditoria s;

    @GET
    @Path("/revision")
    public List<DetectorDeActividad.Alerta> revisar(@QueryParam("compartimento") String compartimento, @QueryParam("horas") int horas) {
        return s.revisar(compartimento, horas);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.audit.AuditClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/gobierno/audit")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class AuditoriaRecursoReactivo {

    @Inject
    ServicioDeAuditoria s;

    @GET
    @Path("/revision")
    public Uni<List<DetectorDeActividad.Alerta>> revisar(@QueryParam("compartimento") String compartimento, @QueryParam("horas") int horas) {
        return Uni.createFrom().item(() -> s.revisar(compartimento, horas)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer eventos de auditoría | `Allow dynamic-group seguridad-reportes to read audit-events in tenancy` |

## 8. Qué NO hacer desde Java
- No pidas ventanas enormes: acota por horas y compartimento.
- No olvides la región *home* para eventos de IAM.
- No expongas IPs y nombres de Audit en endpoints públicos.
- No compares horas sin zona horaria: los eventos vienen en UTC.
