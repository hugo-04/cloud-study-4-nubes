# AWS · ECS Fargate · Uso desde Java

Dos cosas distintas: **(1)** cómo debe **comportarse tu aplicación** dentro de una tarea (apagado ordenado, probes, JVM consciente del contenedor, saber en qué tarea está) y **(2)** cómo **operar ECS desde Java** con el SDK (estado del servicio, tareas únicas, forzar despliegue). Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. La aplicación dentro de la tarea

### Configuración que no puede faltar
```yaml
# Spring Boot (application.yml)
server:
  shutdown: graceful                  # termina las peticiones en curso al recibir SIGTERM
spring:
  lifecycle:
    timeout-per-shutdown-phase: 45s   # menor que stopTimeout de la tarea (60 s)
management:
  endpoint:
    health:
      probes:
        enabled: true                 # /actuator/health/liveness y /readiness
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
```
```properties
# Quarkus (application.properties)
quarkus.shutdown.timeout=45S
quarkus.http.port=8080
quarkus.smallrye-health.root-path=/q/health
```
Regla: `timeout de apagado de la app < stopTimeout de la tarea < deregistration_delay del target group` (o iguales), para no quedar cortado por SIGKILL.

**JVM en contenedor:** `-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError` (el contenedor se reinicia limpio en vez de quedar medio muerto). Usa el health check de **readiness** para el balanceador y el de **liveness** solo dentro de la tarea.

## 2. Operar ECS desde Java

### Núcleo común
Un lector del SDK, una **función pura de diagnóstico** (se prueba sin AWS) y los metadatos de la propia tarea (el endpoint v4 se anuncia en `ECS_CONTAINER_METADATA_URI_V4`).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import software.amazon.awssdk.services.ecs.EcsClient;
import software.amazon.awssdk.services.ecs.model.AssignPublicIp;
import software.amazon.awssdk.services.ecs.model.AwsVpcConfiguration;
import software.amazon.awssdk.services.ecs.model.ContainerOverride;
import software.amazon.awssdk.services.ecs.model.DescribeServicesRequest;
import software.amazon.awssdk.services.ecs.model.LaunchType;
import software.amazon.awssdk.services.ecs.model.NetworkConfiguration;
import software.amazon.awssdk.services.ecs.model.RunTaskRequest;
import software.amazon.awssdk.services.ecs.model.Service;
import software.amazon.awssdk.services.ecs.model.TaskOverride;
import software.amazon.awssdk.services.ecs.model.UpdateServiceRequest;

record Despliegue(String estado, String definicion, int corriendo, Instant creado) {}

record EstadoServicio(String cluster, String servicio, int deseadas, int corriendo, int pendientes,
                      List<Despliegue> despliegues, List<String> eventosRecientes) {}

enum Diagnostico { OK, DESPLEGANDO, ATASCADO, DEGRADADO, FALLO }

record MetadatosTarea(String tareaArn, String zona, String familia, String revision) {
    private static final Pattern CAMPO = Pattern.compile("\"%s\"\\s*:\\s*\"([^\"]*)\"");

    /** Extrae un campo de texto del JSON de metadatos sin depender de Jackson. */
    static String campo(String json, String nombre) {
        Matcher m = Pattern.compile(CAMPO.pattern().formatted(Pattern.quote(nombre))).matcher(json);
        return m.find() ? m.group(1) : "";
    }

    static MetadatosTarea desdeJson(String json) {
        return new MetadatosTarea(campo(json, "TaskARN"), campo(json, "AvailabilityZone"),
                campo(json, "Family"), campo(json, "Revision"));
    }

    /** Fuera de ECS (desarrollo local) no existe la variable: devuelve valores neutros. */
    static MetadatosTarea leer() {
        String base = System.getenv("ECS_CONTAINER_METADATA_URI_V4");
        if (base == null) return new MetadatosTarea("local", "local", "local", "0");
        try {
            HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
            HttpRequest req = HttpRequest.newBuilder(URI.create(base + "/task")).timeout(Duration.ofSeconds(2)).GET().build();
            return desdeJson(http.send(req, HttpResponse.BodyHandlers.ofString()).body());
        } catch (IOException e) {
            return new MetadatosTarea("desconocida", "desconocida", "desconocida", "0");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return new MetadatosTarea("desconocida", "desconocida", "desconocida", "0");
        }
    }
}

final class Diagnosticador {
    static final Duration ATASCO = Duration.ofMinutes(15);

    private Diagnosticador() {}

    /** Reglas puras: se prueban con datos inventados. */
    static Diagnostico clasificar(EstadoServicio e, Instant ahora) {
        if (e.despliegues().stream().anyMatch(d -> "FAILED".equals(d.estado()))) return Diagnostico.FALLO;
        boolean enCurso = e.despliegues().stream().anyMatch(d -> "IN_PROGRESS".equals(d.estado()));
        if (enCurso) {
            boolean viejo = e.despliegues().stream().anyMatch(d -> "IN_PROGRESS".equals(d.estado())
                    && d.creado() != null && Duration.between(d.creado(), ahora).compareTo(ATASCO) > 0);
            return viejo ? Diagnostico.ATASCADO : Diagnostico.DESPLEGANDO;
        }
        if (e.corriendo() < e.deseadas()) return Diagnostico.DEGRADADO;
        return Diagnostico.OK;
    }
}

final class OperadorEcs {
    private final EcsClient ecs;

    OperadorEcs(EcsClient ecs) {
        this.ecs = ecs;
    }

    EstadoServicio estado(String cluster, String servicio) {
        var r = ecs.describeServices(DescribeServicesRequest.builder().cluster(cluster).services(servicio).build());
        if (r.services().isEmpty()) {
            throw new IllegalArgumentException("No existe el servicio " + servicio + " en " + cluster);
        }
        Service s = r.services().get(0);
        List<Despliegue> despliegues = s.deployments().stream()
                .map(d -> new Despliegue(d.rolloutStateAsString(), d.taskDefinition(), d.runningCount(), d.createdAt()))
                .toList();
        List<String> eventos = s.events().stream().limit(5).map(ev -> ev.message()).toList();
        return new EstadoServicio(cluster, servicio, s.desiredCount(), s.runningCount(), s.pendingCount(),
                despliegues, eventos);
    }

    /** Tarea única (p. ej. migraciones): misma definición, otro comando, sin IP pública. */
    String ejecutarTareaUnica(String cluster, String definicion, String contenedor, List<String> comando,
                              List<String> subredes, List<String> gruposSeguridad) {
        var r = ecs.runTask(RunTaskRequest.builder()
                .cluster(cluster).taskDefinition(definicion).launchType(LaunchType.FARGATE).count(1)
                .networkConfiguration(NetworkConfiguration.builder().awsvpcConfiguration(
                        AwsVpcConfiguration.builder().subnets(subredes).securityGroups(gruposSeguridad)
                                .assignPublicIp(AssignPublicIp.DISABLED).build()).build())
                .overrides(TaskOverride.builder().containerOverrides(
                        ContainerOverride.builder().name(contenedor).command(comando).build()).build())
                .build());
        if (!r.failures().isEmpty()) {
            throw new IllegalStateException("RunTask falló: " + r.failures().get(0).reason());
        }
        return r.tasks().get(0).taskArn();
    }

    /** Mismo código y definición, tareas nuevas (re-lee secretos y variables inyectadas). */
    void forzarDespliegue(String cluster, String servicio) {
        ecs.updateService(UpdateServiceRequest.builder().cluster(cluster).service(servicio)
                .forceNewDeployment(true).build());
    }
}
```

### Spring MVC (imperativo)
```java
import java.time.Clock;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ecs.EcsClient;

@Configuration
class EcsConfig {
    @Bean(destroyMethod = "close")
    EcsClient ecs() {
        return EcsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    OperadorEcs operadorEcs(EcsClient ecs) {
        return new OperadorEcs(ecs);
    }

    @Bean
    MetadatosTarea metadatosTarea() {
        return MetadatosTarea.leer();      // una vez, al arrancar
    }
}

@RestController
class EcsController {
    private final OperadorEcs operador;
    private final MetadatosTarea yo;
    private final String cluster;

    EcsController(OperadorEcs operador, MetadatosTarea yo, @Value("${ecs.cluster:prod}") String cluster) {
        this.operador = operador;
        this.yo = yo;
        this.cluster = cluster;
    }

    /** Protege estos endpoints (red interna / autorización): operan sobre la infraestructura. */
    @GetMapping("/interno/ecs/estado")
    Map<String, Object> estado(@RequestParam String servicio) {
        EstadoServicio e = operador.estado(cluster, servicio);
        return Map.of("diagnostico", Diagnosticador.clasificar(e, Clock.systemUTC().instant()).name(),
                "deseadas", e.deseadas(), "corriendo", e.corriendo(), "pendientes", e.pendientes(),
                "eventos", e.eventosRecientes(), "estaTarea", yo.tareaArn(), "zona", yo.zona());
    }

    @PostMapping("/interno/ecs/redesplegar")
    Map<String, String> redesplegar(@RequestParam String servicio) {
        operador.forzarDespliegue(cluster, servicio);
        return Map.of("resultado", "despliegue solicitado");
    }
}
```

### Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`.
```java
import java.time.Clock;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class EcsReactivoController {
    private final OperadorEcs operador;

    EcsReactivoController(OperadorEcs operador) {
        this.operador = operador;
    }

    @GetMapping("/interno/ecs/estado")
    Mono<Map<String, Object>> estado(@RequestParam String servicio) {
        return Mono.fromCallable(() -> {
            EstadoServicio e = operador.estado("prod", servicio);
            return Map.<String, Object>of("diagnostico",
                    Diagnosticador.clasificar(e, Clock.systemUTC().instant()).name(),
                    "corriendo", e.corriendo(), "deseadas", e.deseadas());
        }).subscribeOn(Schedulers.boundedElastic());
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.time.Clock;
import java.util.Map;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ecs.EcsClient;

@Singleton
class EcsProductores {
    @Produces
    @Singleton
    EcsClient ecs() {
        return EcsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    void cerrar(@Disposes EcsClient ecs) {
        ecs.close();
    }

    @Produces
    @Singleton
    OperadorEcs operador(EcsClient ecs) {
        return new OperadorEcs(ecs);
    }
}

@Path("/interno/ecs")
class EcsRecurso {
    @Inject
    OperadorEcs operador;

    @GET
    @Path("/estado")
    @jakarta.ws.rs.Produces("application/json")
    Map<String, Object> estado(@QueryParam("servicio") String servicio) {
        EstadoServicio e = operador.estado("prod", servicio);
        return Map.of("diagnostico", Diagnosticador.clasificar(e, Clock.systemUTC().instant()).name(),
                "corriendo", e.corriendo(), "deseadas", e.deseadas(), "eventos", e.eventosRecientes());
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.time.Clock;
import java.util.Map;

@Path("/interno/ecs-reactivo")
class EcsReactivoRecurso {
    @Inject
    OperadorEcs operador;

    @GET
    @Path("/estado")
    @jakarta.ws.rs.Produces("application/json")
    Uni<Map<String, Object>> estado(@QueryParam("servicio") String servicio) {
        return Uni.createFrom().item(() -> {
            EstadoServicio e = operador.estado("prod", servicio);
            return Map.<String, Object>of("diagnostico",
                    Diagnosticador.clasificar(e, Clock.systemUTC().instant()).name(),
                    "corriendo", e.corriendo(), "deseadas", e.deseadas());
        }).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 3. Permisos del código que opera ECS
La identidad (task role o rol de la herramienta) necesita solo: `ecs:DescribeServices` (lectura), `ecs:RunTask` + `iam:PassRole` sobre **los dos roles de la tarea** (tarea única) y `ecs:UpdateService` (redespliegue). Separa lectura de escritura en roles distintos.

## 4. Qué NO hacer desde Java
- ❌ Dejar endpoints que redesplieguen o ejecuten tareas **sin autenticación**.
- ❌ Poblar la tarea con un bucle `describeServices` por petición: cachea el estado unos segundos.
- ❌ Ignorar `failures()` de `RunTask` (la llamada «tiene éxito» aunque no se lance nada).
- ❌ Bloquear el *event loop* con el SDK síncrono.
- ❌ Tratar `ECS_CONTAINER_METADATA_URI_V4` como siempre presente (en local no existe).
