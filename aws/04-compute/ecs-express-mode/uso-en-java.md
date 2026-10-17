# AWS · ECS Express Mode · Uso desde Java

Dos usos: **(1)** adaptar tu aplicación a lo que Express Mode espera (puerto, health check, apagado) y **(2)** construir una **herramienta de plataforma** en Java que crea, consulta, actualiza y borra servicios Express con el SDK, **validando la especificación antes** de llamar a AWS. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56; el API `*ExpressGatewayService` es reciente, verifica tu versión del SDK).

## 1. La aplicación

Los valores por defecto de Express Mode (puerto 80, health check en `/`) casi nunca coinciden con una app Java. Ajusta ambos lados:
```yaml
# Spring Boot (application.yml)
server:
  port: 8080
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
management:
  endpoint:
    health:
      probes:
        enabled: true     # health_check_path = /actuator/health/readiness
```
```properties
# Quarkus (application.properties)
quarkus.http.port=8080
quarkus.http.host=0.0.0.0
quarkus.shutdown.timeout=30S
# health_check_path = /q/health/ready
```
Y en el servicio Express: `containerPort = 8080` y `healthCheckPath` igual a la ruta de *readiness*.

## 2. Núcleo común: especificación validada + operador del SDK

La validación es **pura** (se prueba sin AWS) y detecta los errores caros antes de crear nada: red por defecto, `latest`, secretos en variables, mínimo de réplicas.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import software.amazon.awssdk.services.ecs.EcsClient;
import software.amazon.awssdk.services.ecs.model.CreateExpressGatewayServiceRequest;
import software.amazon.awssdk.services.ecs.model.DeleteExpressGatewayServiceRequest;
import software.amazon.awssdk.services.ecs.model.DescribeExpressGatewayServiceRequest;
import software.amazon.awssdk.services.ecs.model.ECSExpressGatewayService;
import software.amazon.awssdk.services.ecs.model.ExpressGatewayContainer;
import software.amazon.awssdk.services.ecs.model.ExpressGatewayScalingTarget;
import software.amazon.awssdk.services.ecs.model.ExpressGatewayServiceNetworkConfiguration;
import software.amazon.awssdk.services.ecs.model.ExpressGatewayServiceScalingMetric;
import software.amazon.awssdk.services.ecs.model.KeyValuePair;
import software.amazon.awssdk.services.ecs.model.Secret;
import software.amazon.awssdk.services.ecs.model.Tag;
import software.amazon.awssdk.services.ecs.model.UpdateExpressGatewayServiceRequest;

record EspecificacionExpress(String nombre, String imagen, int puerto, String rutaSalud, String cpu, String memoria,
                             List<String> subredes, List<String> gruposSeguridad, int minTareas, int maxTareas,
                             Map<String, String> variables, Map<String, String> secretos,
                             String rolEjecucionArn, String rolInfraestructuraArn, String rolTareaArn,
                             Map<String, String> etiquetas) {}

record EstadoExpress(String estado, String motivo, List<String> endpoints) {}

final class ValidadorExpress {
    private static final Pattern NOMBRE = Pattern.compile("[a-z0-9][a-z0-9-]{0,62}");
    private static final Pattern ROL = Pattern.compile("arn:aws:iam::\\d{12}:role/.+");
    private static final Pattern PINTA_A_SECRETO = Pattern.compile("(?i).*(PASSWORD|SECRET|TOKEN|API_?KEY|PRIVATE_?KEY).*");

    private ValidadorExpress() {}

    /** Lista de errores; vacía = válida. Reglas puras. */
    static List<String> validar(EspecificacionExpress e) {
        List<String> errores = new ArrayList<>();
        if (e.nombre() == null || !NOMBRE.matcher(e.nombre()).matches()) {
            errores.add("nombre: minúsculas, números y guiones (máx. 63)");
        }
        if (e.imagen() == null || e.imagen().isBlank()) {
            errores.add("imagen: obligatoria");
        } else if (e.imagen().endsWith(":latest") || (!e.imagen().contains(":") && !e.imagen().contains("@"))) {
            errores.add("imagen: usa un digest o una etiqueta inmutable, no 'latest'");
        }
        if (e.puerto() < 1 || e.puerto() > 65535) errores.add("puerto: fuera de rango");
        if (e.rutaSalud() == null || !e.rutaSalud().startsWith("/")) errores.add("rutaSalud: debe empezar con '/'");
        if (e.subredes() == null || e.subredes().size() < 2) {
            errores.add("subredes: indica al menos 2 (explícitas, en zonas distintas); sin ellas se usa la VPC por defecto");
        }
        if (e.minTareas() < 1) errores.add("minTareas: Express Mode no escala a cero (mínimo 1)");
        if (e.maxTareas() < e.minTareas()) errores.add("maxTareas: menor que minTareas");
        try {
            if (Integer.parseInt(e.cpu()) < 256) errores.add("cpu: mínimo 256");
            if (Integer.parseInt(e.memoria()) < 512) errores.add("memoria: mínimo 512");
        } catch (NumberFormatException ex) {
            errores.add("cpu/memoria: deben ser números como '1024' y '2048'");
        }
        for (String nombreVar : e.variables().keySet()) {
            if (PINTA_A_SECRETO.matcher(nombreVar).matches()) {
                errores.add("variables: '" + nombreVar + "' parece un secreto; usa 'secretos' (Secrets Manager/Parameter Store)");
            }
        }
        e.secretos().forEach((n, arn) -> {
            if (!arn.startsWith("arn:aws:secretsmanager:") && !arn.startsWith("arn:aws:ssm:")) {
                errores.add("secretos: '" + n + "' debe apuntar a Secrets Manager o Parameter Store");
            }
        });
        for (var par : Map.of("rolEjecucionArn", String.valueOf(e.rolEjecucionArn()),
                "rolInfraestructuraArn", String.valueOf(e.rolInfraestructuraArn())).entrySet()) {
            if (!ROL.matcher(par.getValue()).matches()) errores.add(par.getKey() + ": no es un ARN de rol de IAM");
        }
        if (e.etiquetas().isEmpty()) {
            errores.add("etiquetas: añádelas ahora; solo se pueden fijar al crear el servicio");
        }
        return errores;
    }
}

final class OperadorExpress {
    private final EcsClient ecs;

    OperadorExpress(EcsClient ecs) {
        this.ecs = ecs;
    }

    static ExpressGatewayContainer contenedor(EspecificacionExpress e) {
        return ExpressGatewayContainer.builder().image(e.imagen()).containerPort(e.puerto())
                .environment(e.variables().entrySet().stream()
                        .map(v -> KeyValuePair.builder().name(v.getKey()).value(v.getValue()).build()).toList())
                .secrets(e.secretos().entrySet().stream()
                        .map(s -> Secret.builder().name(s.getKey()).valueFrom(s.getValue()).build()).toList())
                .build();
    }

    /** Valida y crea. Devuelve el ARN del servicio. */
    String crear(EspecificacionExpress e) {
        List<String> errores = ValidadorExpress.validar(e);
        if (!errores.isEmpty()) {
            throw new IllegalArgumentException("Especificación inválida: " + String.join("; ", errores));
        }
        var req = CreateExpressGatewayServiceRequest.builder()
                .serviceName(e.nombre()).executionRoleArn(e.rolEjecucionArn())
                .infrastructureRoleArn(e.rolInfraestructuraArn()).taskRoleArn(e.rolTareaArn())
                .primaryContainer(contenedor(e)).healthCheckPath(e.rutaSalud())
                .cpu(e.cpu()).memory(e.memoria())
                .networkConfiguration(ExpressGatewayServiceNetworkConfiguration.builder()
                        .subnets(e.subredes()).securityGroups(e.gruposSeguridad()).build())
                .scalingTarget(ExpressGatewayScalingTarget.builder().minTaskCount(e.minTareas())
                        .maxTaskCount(e.maxTareas()).autoScalingMetric(ExpressGatewayServiceScalingMetric.AVERAGE_CPU)
                        .autoScalingTargetValue(60).build())
                .tags(e.etiquetas().entrySet().stream()
                        .map(t -> Tag.builder().key(t.getKey()).value(t.getValue()).build()).toList())
                .build();
        return ecs.createExpressGatewayService(req).service().serviceArn();
    }

    EstadoExpress estado(String serviceArn) {
        ECSExpressGatewayService s = ecs.describeExpressGatewayService(
                DescribeExpressGatewayServiceRequest.builder().serviceArn(serviceArn).build()).service();
        List<String> endpoints = s.activeConfigurations().stream()
                .flatMap(c -> c.ingressPaths().stream()).map(p -> p.endpoint()).toList();
        String codigo = s.status() == null ? "DESCONOCIDO" : s.status().statusCodeAsString();
        String motivo = s.status() == null || s.status().statusReason() == null ? "" : s.status().statusReason();
        return new EstadoExpress(codigo, motivo, endpoints);
    }

    /** Nueva imagen = nueva revisión con despliegue canary. */
    void actualizarImagen(String serviceArn, String imagen, int puerto) {
        ecs.updateExpressGatewayService(UpdateExpressGatewayServiceRequest.builder().serviceArn(serviceArn)
                .primaryContainer(ExpressGatewayContainer.builder().image(imagen).containerPort(puerto).build())
                .build());
    }

    void eliminar(String serviceArn) {
        ecs.deleteExpressGatewayService(DeleteExpressGatewayServiceRequest.builder().serviceArn(serviceArn).build());
    }
}
```

### Spring MVC (imperativo)
```java
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ecs.EcsClient;

@Configuration
class ExpressConfig {
    @Bean(destroyMethod = "close")
    EcsClient ecs() {
        return EcsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    OperadorExpress operadorExpress(EcsClient ecs) {
        return new OperadorExpress(ecs);
    }
}

@RestController
class ExpressController {
    private final OperadorExpress operador;

    ExpressController(OperadorExpress operador) {
        this.operador = operador;
    }

    /** Ensayo: valida sin crear nada. */
    @PostMapping("/interno/express/validar")
    List<String> validar(@RequestBody EspecificacionExpress spec) {
        return ValidadorExpress.validar(spec);
    }

    @PostMapping("/interno/express/servicios")
    ResponseEntity<Map<String, Object>> crear(@RequestBody EspecificacionExpress spec) {
        List<String> errores = ValidadorExpress.validar(spec);
        if (!errores.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("errores", errores));
        }
        return ResponseEntity.accepted().body(Map.of("serviceArn", operador.crear(spec)));
    }

    @GetMapping("/interno/express/estado")
    EstadoExpress estado(@RequestParam String serviceArn) {
        return operador.estado(serviceArn);
    }
}
```

### Spring WebFlux (reactivo)
```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class ExpressReactivoController {
    private final OperadorExpress operador;

    ExpressReactivoController(OperadorExpress operador) {
        this.operador = operador;
    }

    @GetMapping("/interno/express/estado")
    Mono<EstadoExpress> estado(@RequestParam String serviceArn) {
        return Mono.fromCallable(() -> operador.estado(serviceArn)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ecs.EcsClient;

@Singleton
class ExpressProductores {
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
    OperadorExpress operador(EcsClient ecs) {
        return new OperadorExpress(ecs);
    }
}

@Path("/interno/express")
class ExpressRecurso {
    @Inject
    OperadorExpress operador;

    @POST
    @Path("/validar")
    @jakarta.ws.rs.Consumes("application/json")
    @jakarta.ws.rs.Produces("application/json")
    List<String> validar(EspecificacionExpress spec) {
        return ValidadorExpress.validar(spec);
    }

    @GET
    @Path("/estado")
    @jakarta.ws.rs.Produces("application/json")
    EstadoExpress estado(@QueryParam("serviceArn") String serviceArn) {
        return operador.estado(serviceArn);
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

@Path("/interno/express-reactivo")
class ExpressReactivoRecurso {
    @Inject
    OperadorExpress operador;

    @GET
    @Path("/estado")
    @jakarta.ws.rs.Produces("application/json")
    Uni<EstadoExpress> estado(@QueryParam("serviceArn") String serviceArn) {
        return Uni.createFrom().item(() -> operador.estado(serviceArn))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 3. Permisos de la herramienta
`ecs:CreateExpressGatewayService`, `ecs:UpdateExpressGatewayService`, `ecs:DescribeExpressGatewayService`, `ecs:DeleteExpressGatewayService` y `iam:PassRole` **sobre los tres roles** con la condición del servicio. Separa en dos identidades: una de **solo lectura** (estado) y otra de **escritura** (crear/actualizar/borrar) con aprobación.

## 4. Qué NO hacer desde Java
- ❌ Crear servicios sin validar: la red por defecto y `latest` salen caros.
- ❌ Pasar secretos como variables de entorno (`secretos` existe para eso).
- ❌ Olvidar las etiquetas: no se pueden añadir después.
- ❌ Exponer `/interno/**` sin autenticación: crea infraestructura real.
- ❌ Llamar a `describe` en un bucle apretado esperando el estado: consulta cada pocos segundos con tope.
- ❌ Cambiar el nombre del contenedor «Main» a mano en el servicio y luego actualizarlo con esta herramienta.
