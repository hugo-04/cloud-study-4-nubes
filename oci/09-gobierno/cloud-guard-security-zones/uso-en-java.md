# Oracle OCI · Gobierno · Cloud Guard y Security Zones · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **triaje de problemas con SLA**: trae los problemas abiertos de Cloud Guard de todo el subárbol (`CloudGuardClient.listProblems`, paginando) y los ordena: primero los que vencieron su SLA, luego por riesgo y fecha de vencimiento (CRITICAL 24 h, HIGH 7 días, MEDIUM 30, LOW 90). Ideal para el reporte diario del equipo de seguridad.

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

### 2.2 Triaje (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/** Triaje de problemas: SLA por riesgo, vencidos primero. Puro: reloj inyectado. */
public class TriajeDeProblemas {

    public record Problema(String id, String riesgo, String regla, String recurso, Instant detectado) { }

    public record Prioridad(Problema problema, Instant vence, boolean vencido, long horasRestantes) { }

    private static final Map<String, Duration> SLA = Map.of(
        "CRITICAL", Duration.ofHours(24), "HIGH", Duration.ofDays(7),
        "MEDIUM", Duration.ofDays(30), "LOW", Duration.ofDays(90));
    private static final List<String> ORDEN = List.of("CRITICAL", "HIGH", "MEDIUM", "LOW", "MINOR");

    private final Clock reloj;

    public TriajeDeProblemas(Clock reloj) {
        this.reloj = reloj;
    }

    public List<Prioridad> priorizar(List<Problema> problemas) {
        Instant ahora = reloj.instant();
        return problemas.stream()
            .map(p -> {
                Instant vence = p.detectado().plus(SLA.getOrDefault(p.riesgo(), Duration.ofDays(180)));
                return new Prioridad(p, vence, vence.isBefore(ahora), Duration.between(ahora, vence).toHours());
            })
            .sorted(Comparator.comparing((Prioridad x) -> !x.vencido())
                .thenComparing(x -> rango(x.problema().riesgo()))
                .thenComparing(Prioridad::vence))
            .toList();
    }

    private static int rango(String riesgo) {
        int i = ORDEN.indexOf(riesgo);
        return i < 0 ? ORDEN.size() : i;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.cloudguard.CloudGuardClient;
import com.oracle.bmc.cloudguard.model.ProblemLifecycleDetail;
import com.oracle.bmc.cloudguard.requests.ListProblemsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: problemas abiertos de todo el subárbol (paginando). */
public class CloudGuardOci implements AutoCloseable {

    private final CloudGuardClient cliente;

    public CloudGuardOci(CloudGuardClient cliente) {
        this.cliente = cliente;
    }

    public List<TriajeDeProblemas.Problema> abiertos(String compartimentoId) {
        var out = new ArrayList<TriajeDeProblemas.Problema>();
        String pagina = null;
        do {
            var r = cliente.listProblems(ListProblemsRequest.builder().compartmentId(compartimentoId)
                .compartmentIdInSubtree(true).accessLevel(ListProblemsRequest.AccessLevel.Accessible)
                .lifecycleDetail(ProblemLifecycleDetail.Open).page(pagina).build());
            r.getProblemCollection().getItems().forEach(p -> out.add(new TriajeDeProblemas.Problema(
                p.getId(), p.getRiskLevel().getValue(), p.getDetectorRuleId(), p.getResourceName(),
                p.getTimeFirstDetected().toInstant())));
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
import java.time.Clock;
import java.util.List;

public class ServicioDeTriaje {

    private final CloudGuardOci cloudGuard;
    private final TriajeDeProblemas triaje = new TriajeDeProblemas(Clock.systemUTC());

    public ServicioDeTriaje(CloudGuardOci cloudGuard) {
        this.cloudGuard = cloudGuard;
    }

    public List<TriajeDeProblemas.Prioridad> pendientes(String compartimentoId, int max) {
        return triaje.priorizar(cloudGuard.abiertos(compartimentoId)).stream().limit(max).toList();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.cloudguard.CloudGuardClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class TriajeConfiguracion {

    @Bean(destroyMethod = "close")
    CloudGuardOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CloudGuardOci(CloudGuardClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeTriaje servicio(CloudGuardOci a) {
        return new ServicioDeTriaje(a);
    }
}

@RestController
@RequestMapping("/gobierno/cloud-guard")
class TriajeControlador {

    private final ServicioDeTriaje s;

    TriajeControlador(ServicioDeTriaje s) {
        this.s = s;
    }

    @GetMapping("/pendientes")
    List<TriajeDeProblemas.Prioridad> pendientes(@RequestParam String compartimento, @RequestParam int max) {
        return s.pendientes(compartimento, max);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.cloudguard.CloudGuardClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/cloud-guard")
class TriajeReactivoControlador {

    private final ServicioDeTriaje s;

    TriajeReactivoControlador(ServicioDeTriaje s) {
        this.s = s;
    }

    @GetMapping("/pendientes")
    Mono<List<TriajeDeProblemas.Prioridad>> pendientes(@RequestParam String compartimento, @RequestParam int max) {
        return Mono.fromCallable(() -> s.pendientes(compartimento, max)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.cloudguard.CloudGuardClient;
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
class TriajeProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CloudGuardOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CloudGuardOci(CloudGuardClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes CloudGuardOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeTriaje servicio(CloudGuardOci a) {
        return new ServicioDeTriaje(a);
    }
}

@Path("/gobierno/cloud-guard")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class TriajeRecurso {

    @Inject
    ServicioDeTriaje s;

    @GET
    @Path("/pendientes")
    public List<TriajeDeProblemas.Prioridad> pendientes(@QueryParam("compartimento") String compartimento, @QueryParam("max") int max) {
        return s.pendientes(compartimento, max);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.cloudguard.CloudGuardClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/gobierno/cloud-guard")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class TriajeRecursoReactivo {

    @Inject
    ServicioDeTriaje s;

    @GET
    @Path("/pendientes")
    public Uni<List<TriajeDeProblemas.Prioridad>> pendientes(@QueryParam("compartimento") String compartimento, @QueryParam("max") int max) {
        return Uni.createFrom().item(() -> s.pendientes(compartimento, max)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer problemas | `Allow dynamic-group seguridad-reportes to read cloud-guard-problems in tenancy` |

## 8. Qué NO hacer desde Java
- No uses la región local si los problemas se consolidan en la región de reporte: apunta el cliente allí.
- No descartes problemas desde código sin motivo ni dueño.
- No automatices correcciones destructivas desde un servicio de reporte.
- No olvides paginar.
