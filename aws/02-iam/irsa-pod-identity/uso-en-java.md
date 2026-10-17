# AWS · IRSA y Pod Identity · Uso desde Java

Para tu código Java, **IRSA y Pod Identity son transparentes**: `SqsClient.create()` encuentra las credenciales solo (cadena por defecto del SDK). Lo que sí conviene construir: (1) **verificar al arrancar** qué identidad está usando el pod, para detectar el temido «cayó al rol del nodo» o «hay claves en el entorno», y (2) exponerlo como **indicador de salud**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Lo que NO escribes
```java
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sqs.SqsClient;

// Correcto: sin credenciales en el código. El SDK usa IRSA, Pod Identity, rol de tarea, etc.
SqsClient sqs = SqsClient.builder().region(Region.US_EAST_1).build();
```
- No pases `credentialsProvider(...)` fijos ni claves por variables de entorno.
- Mantén el SDK **actualizado**: Pod Identity usa credenciales de contenedor con un token de autorización que versiones antiguas no entienden *(verifica la versión mínima)*.
- Crea el cliente **una vez** y reutilízalo: refresca solo.

## 2. Detectar la fuente de credenciales y verificar la identidad

### Núcleo común (función pura + verificación)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.GetCallerIdentityRequest;
import software.amazon.awssdk.services.sts.model.GetCallerIdentityResponse;

enum FuenteCredenciales { IRSA, POD_IDENTITY, ECS_ROL_DE_TAREA, LAMBDA, CLAVES_EN_ENTORNO, PERFIL, IMDS_O_DESCONOCIDA }

record Diagnostico(String cuenta, String arn, FuenteCredenciales fuente, boolean aceptable, List<String> avisos) {}

final class Identidad {
    private Identidad() {}

    /** Mira las variables de entorno que inyectan IRSA, Pod Identity, ECS, Lambda... (orden importa). */
    static FuenteCredenciales detectar(Map<String, String> env) {
        if (hay(env, "AWS_WEB_IDENTITY_TOKEN_FILE") && hay(env, "AWS_ROLE_ARN")) return FuenteCredenciales.IRSA;
        if (hay(env, "AWS_CONTAINER_CREDENTIALS_FULL_URI") && hay(env, "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")) return FuenteCredenciales.POD_IDENTITY;
        if (hay(env, "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")) return FuenteCredenciales.ECS_ROL_DE_TAREA;
        if (hay(env, "AWS_LAMBDA_FUNCTION_NAME")) return FuenteCredenciales.LAMBDA;           // Lambda también define AWS_ACCESS_KEY_ID
        if (hay(env, "AWS_ACCESS_KEY_ID")) return FuenteCredenciales.CLAVES_EN_ENTORNO;
        if (hay(env, "AWS_PROFILE")) return FuenteCredenciales.PERFIL;
        return FuenteCredenciales.IMDS_O_DESCONOCIDA;
    }

    static boolean aceptableEnProduccion(FuenteCredenciales f) {
        return f == FuenteCredenciales.IRSA || f == FuenteCredenciales.POD_IDENTITY
                || f == FuenteCredenciales.ECS_ROL_DE_TAREA || f == FuenteCredenciales.LAMBDA;
    }

    /** Heurística: el ARN de sesión contiene el rol del nodo (nombre con "node"). */
    static boolean pareceRolDelNodo(String arn) {
        String a = arn.toLowerCase();
        return a.contains(":assumed-role/") && (a.contains("node") || a.contains("nodegroup"));
    }

    static Diagnostico evaluar(String cuenta, String arn, Map<String, String> env) {
        FuenteCredenciales f = detectar(env);
        List<String> avisos = new ArrayList<>();
        if (f == FuenteCredenciales.CLAVES_EN_ENTORNO) avisos.add("Hay claves de larga duración en el entorno: elimínalas y usa un rol");
        if (f == FuenteCredenciales.IMDS_O_DESCONOCIDA) avisos.add("Sin variables de identidad del pod: probablemente usa el IMDS (rol del nodo o de la instancia)");
        if (pareceRolDelNodo(arn)) avisos.add("La identidad parece el ROL DEL NODO: falta la asociación o el SDK no la entiende");
        boolean ok = Identidad.aceptableEnProduccion(f) && !pareceRolDelNodo(arn);
        return new Diagnostico(cuenta, arn, f, ok, avisos);
    }

    private static boolean hay(Map<String, String> env, String clave) {
        String v = env.get(clave);
        return v != null && !v.isBlank();
    }
}

final class VerificadorIdentidad {
    private final StsClient sts;
    private volatile Diagnostico cache;
    private volatile Instant cargado = Instant.EPOCH;

    VerificadorIdentidad(StsClient sts) { this.sts = sts; }

    /** GetCallerIdentity no necesita permisos. Se cachea 5 minutos. */
    Diagnostico verificar() {
        if (cache != null && Duration.between(cargado, Instant.now()).toMinutes() < 5) return cache;
        GetCallerIdentityResponse r = sts.getCallerIdentity(GetCallerIdentityRequest.builder().build());
        cache = Identidad.evaluar(r.account(), r.arn(), System.getenv());
        cargado = Instant.now();
        return cache;
    }
}
```

### Spring MVC (imperativo): endpoint + indicador de salud
```java
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sts.StsClient;

@Configuration
class IdentidadConfig {
    @Bean(destroyMethod = "close")
    StsClient sts() {
        return StsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    VerificadorIdentidad verificador(StsClient sts) {
        return new VerificadorIdentidad(sts);
    }
}

@RestController
class IdentidadController {
    private final VerificadorIdentidad verificador;

    IdentidadController(VerificadorIdentidad verificador) { this.verificador = verificador; }

    @GetMapping("/iam/identidad")
    Diagnostico identidad() { return verificador.verificar(); }
}

@Component("identidadAws")
class IdentidadHealth implements HealthIndicator {
    private final VerificadorIdentidad verificador;

    IdentidadHealth(VerificadorIdentidad verificador) { this.verificador = verificador; }

    @Override
    public Health health() {
        try {
            Diagnostico d = verificador.verificar();
            Health.Builder b = d.aceptable() ? Health.up() : Health.status("WARN");
            return b.withDetail("fuente", d.fuente().name()).withDetail("arn", d.arn()).withDetail("avisos", d.avisos()).build();
        } catch (RuntimeException e) {
            return Health.down(e).build();
        }
    }
}
```

### Spring WebFlux (reactivo)
```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class IdentidadReactivoController {
    private final VerificadorIdentidad verificador;

    IdentidadReactivoController(VerificadorIdentidad verificador) { this.verificador = verificador; }

    @GetMapping("/reactivo/iam/identidad")
    Mono<Diagnostico> identidad() {
        return Mono.fromCallable(verificador::verificar).subscribeOn(Schedulers.boundedElastic());
    }
}
```

### Quarkus (imperativo): endpoint + readiness
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sts.StsClient;

@ApplicationScoped
class IdentidadProductores {
    @Produces
    @ApplicationScoped
    StsClient sts() {
        return StsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Produces
    @ApplicationScoped
    VerificadorIdentidad verificador(StsClient sts) {
        return new VerificadorIdentidad(sts);
    }
}

@Path("/iam/identidad")
public class IdentidadResource {
    @Inject
    VerificadorIdentidad verificador;

    @GET
    public Diagnostico identidad() { return verificador.verificar(); }
}

@Readiness
@ApplicationScoped
class IdentidadReadiness implements HealthCheck {
    @Inject
    VerificadorIdentidad verificador;

    @Override
    public HealthCheckResponse call() {
        try {
            Diagnostico d = verificador.verificar();
            return HealthCheckResponse.named("identidad-aws").status(d.aceptable())
                    .withData("fuente", d.fuente().name()).withData("arn", d.arn()).build();
        } catch (RuntimeException e) {
            return HealthCheckResponse.down("identidad-aws");
        }
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

@Path("/reactivo/iam/identidad")
public class IdentidadReactivaResource {
    @Inject
    VerificadorIdentidad verificador;

    @GET
    public Uni<Diagnostico> identidad() {
        return Uni.createFrom().item(verificador::verificar).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 3. Cómo usarlo
- **Al desplegar:** `GET /iam/identidad` desde el pipeline de humo; si `aceptable=false`, el despliegue se detiene.
- **Readiness:** en producción, un pod con `CLAVES_EN_ENTORNO` o con el rol del nodo **no debe recibir tráfico**.
- **Atribución:** registra `arn` y `fuente` al arrancar (sin credenciales).

## 4. Qué NO hacer desde Java
- No mostrar el token de `AWS_WEB_IDENTITY_TOKEN_FILE` ni el de `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE` en logs ni endpoints.
- No exponer `/iam/identidad` a internet: es una herramienta interna.
- No construir el cliente con `ContainerCredentialsProvider` a mano «para ir más rápido»: deja la cadena por defecto.
