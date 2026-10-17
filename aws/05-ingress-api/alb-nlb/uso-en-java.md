# AWS · ALB y NLB · Uso desde Java

Una aplicación detrás de un balanceador debe saber tres cosas: **quién es realmente el cliente** (cabeceras de reenvío), **cuándo cerrar conexiones y cuándo apagarse** (timeouts coherentes) y, para herramientas de operación, **qué destinos están sanos** (SDK). Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Configuración de la aplicación

```yaml
# Spring Boot (application.yml) — MVC (Tomcat)
server:
  forward-headers-strategy: native           # Tomcat aplica X-Forwarded-* con RemoteIpValve
  tomcat:
    keep-alive-timeout: 75s                  # MAYOR que el idle timeout del ALB (60 s)
    max-keep-alive-requests: -1
    remoteip:
      internal-proxies: "10\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"   # solo confía en proxies de tu red
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```
```yaml
# Spring Boot — WebFlux (Netty)
server:
  forward-headers-strategy: framework        # ForwardedHeaderTransformer
  netty:
    idle-timeout: 75s
  shutdown: graceful
```
```properties
# Quarkus (application.properties)
quarkus.http.proxy.proxy-address-forwarding=true
quarkus.http.proxy.allow-x-forwarded=true
quarkus.http.proxy.trusted-proxies=10.0.0.0/8
quarkus.http.idle-timeout=75S
quarkus.shutdown.timeout=30S
```
> **Confía solo en el balanceador.** Sin lista de proxies de confianza, cualquier cliente puede enviar `X-Forwarded-For: 1.2.3.4` y hacerse pasar por otra IP (saltarse límites de peticiones y auditorías).

## 2. Núcleo común

Tres piezas puras o casi puras: la IP real del cliente, los tiempos coherentes y el resumen de salud de un target group.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import software.amazon.awssdk.services.elasticloadbalancingv2.ElasticLoadBalancingV2Client;
import software.amazon.awssdk.services.elasticloadbalancingv2.model.DescribeTargetHealthRequest;

final class ClienteReal {
    private static final Pattern IPV4 = Pattern.compile("^(\\d{1,3}\\.){3}\\d{1,3}$");
    private static final Pattern IPV6 = Pattern.compile("^[0-9a-fA-F:]+$");

    private ClienteReal() {}

    /**
     * La IP del cliente según X-Forwarded-For, contando desde la DERECHA los saltos que tú controlas.
     * Solo ALB: saltosConfiables = 1. CloudFront + ALB: 2. Lo que esté a la izquierda lo pone el cliente (falsificable).
     * Si la cabecera falta o es inválida, devuelve la IP de la conexión.
     */
    static String desde(String xForwardedFor, String ipConexion, int saltosConfiables) {
        if (xForwardedFor == null || xForwardedFor.isBlank() || saltosConfiables < 1) return ipConexion;
        String[] partes = xForwardedFor.split(",");
        int indice = partes.length - saltosConfiables;
        if (indice < 0) return ipConexion;
        String candidata = partes[indice].trim();
        return esIp(candidata) ? candidata : ipConexion;
    }

    static boolean esIp(String s) {
        if (IPV4.matcher(s).matches()) {
            for (String o : s.split("\\.")) {
                if (Integer.parseInt(o) > 255) return false;
            }
            return true;
        }
        return s.contains(":") && IPV6.matcher(s).matches();
    }
}

final class PlanDeTiempos {
    private PlanDeTiempos() {}

    /** Segundos. Devuelve advertencias; lista vacía = coherente. */
    static List<String> validar(int keepAliveApp, int idleTimeoutAlb, int deregistrationDelay,
                                int preStop, int apagadoApp, int stopTimeoutTarea) {
        List<String> avisos = new ArrayList<>();
        if (keepAliveApp <= idleTimeoutAlb) {
            avisos.add("keep-alive de la app (" + keepAliveApp + " s) debe ser MAYOR que el idle timeout del ALB ("
                    + idleTimeoutAlb + " s): si no, aparecen 502 esporádicos");
        }
        if (deregistrationDelay < apagadoApp) {
            avisos.add("deregistration delay (" + deregistrationDelay + " s) menor que el apagado de la app ("
                    + apagadoApp + " s): se cortan peticiones en curso");
        }
        if (preStop + apagadoApp > stopTimeoutTarea) {
            avisos.add("preStop + apagado (" + (preStop + apagadoApp) + " s) supera el stopTimeout/terminationGracePeriod ("
                    + stopTimeoutTarea + " s): SIGKILL a mitad del apagado");
        }
        if (deregistrationDelay > 120) {
            avisos.add("deregistration delay de " + deregistrationDelay + " s: los despliegues serán lentos");
        }
        return avisos;
    }
}

record ResumenSalud(int sanos, int noSanos, Map<String, Integer> motivos) {
    boolean tieneCapacidad(int minimoSanos) {
        return sanos >= minimoSanos;
    }
}

final class LectorSalud {
    private final ElasticLoadBalancingV2Client elb;

    LectorSalud(ElasticLoadBalancingV2Client elb) {
        this.elb = elb;
    }

    ResumenSalud leer(String targetGroupArn) {
        var r = elb.describeTargetHealth(DescribeTargetHealthRequest.builder().targetGroupArn(targetGroupArn).build());
        int sanos = 0;
        int noSanos = 0;
        Map<String, Integer> motivos = new LinkedHashMap<>();
        for (var d : r.targetHealthDescriptions()) {
            if ("healthy".equals(d.targetHealth().stateAsString())) {
                sanos++;
            } else {
                noSanos++;
                // "unused" y "draining" no son fallos; igual se cuentan aparte por su motivo
                motivos.merge(d.targetHealth().reasonAsString(), 1, Integer::sum);
            }
        }
        return new ResumenSalud(sanos, noSanos, motivos);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.elasticloadbalancingv2.ElasticLoadBalancingV2Client;

@Configuration
class ElbConfig {
    @Bean(destroyMethod = "close")
    ElasticLoadBalancingV2Client elb() {
        return ElasticLoadBalancingV2Client.builder()
                .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    LectorSalud lectorSalud(ElasticLoadBalancingV2Client elb) {
        return new LectorSalud(elb);
    }
}

@RestController
class ElbController {
    private final LectorSalud salud;

    ElbController(LectorSalud salud) {
        this.salud = salud;
    }

    /** Con forward-headers-strategy=native, getRemoteAddr() ya devuelve la IP real. Este ejemplo lo hace explícito. */
    @GetMapping("/interno/yo")
    Map<String, String> yo(HttpServletRequest req) {
        String ip = ClienteReal.desde(req.getHeader("X-Forwarded-For"), req.getRemoteAddr(), 1);
        return Map.of("ip", ip, "esquema", req.getHeader("X-Forwarded-Proto") == null ? req.getScheme()
                : req.getHeader("X-Forwarded-Proto"));
    }

    @GetMapping("/interno/tiempos")
    List<String> tiempos(@RequestParam int keepAlive, @RequestParam int idle, @RequestParam int dereg,
                         @RequestParam int preStop, @RequestParam int apagado, @RequestParam int stopTimeout) {
        return PlanDeTiempos.validar(keepAlive, idle, dereg, preStop, apagado, stopTimeout);
    }

    @GetMapping("/interno/alb/salud")
    ResumenSalud salud(@RequestParam String targetGroupArn) {
        return salud.leer(targetGroupArn);
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.util.Map;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class ElbReactivoController {
    private final LectorSalud salud;

    ElbReactivoController(LectorSalud salud) {
        this.salud = salud;
    }

    @GetMapping("/interno/yo")
    Mono<Map<String, String>> yo(ServerHttpRequest req) {
        String conexion = req.getRemoteAddress() == null ? "desconocida" : req.getRemoteAddress().getAddress().getHostAddress();
        String ip = ClienteReal.desde(req.getHeaders().getFirst("X-Forwarded-For"), conexion, 1);
        return Mono.just(Map.of("ip", ip));
    }

    @GetMapping("/interno/alb/salud")
    Mono<ResumenSalud> salud(@RequestParam String targetGroupArn) {
        return Mono.fromCallable(() -> salud.leer(targetGroupArn)).subscribeOn(Schedulers.boundedElastic());
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.vertx.core.http.HttpServerRequest;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Context;
import java.util.Map;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.elasticloadbalancingv2.ElasticLoadBalancingV2Client;

@Singleton
class ElbProductores {
    @Produces
    @Singleton
    ElasticLoadBalancingV2Client elb() {
        return ElasticLoadBalancingV2Client.builder()
                .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    void cerrar(@Disposes ElasticLoadBalancingV2Client elb) {
        elb.close();
    }

    @Produces
    @Singleton
    LectorSalud lector(ElasticLoadBalancingV2Client elb) {
        return new LectorSalud(elb);
    }
}

@Path("/interno")
class ElbRecurso {
    @Inject
    LectorSalud salud;

    @GET
    @Path("/yo")
    @jakarta.ws.rs.Produces("application/json")
    Map<String, String> yo(@Context HttpServerRequest req) {
        String ip = ClienteReal.desde(req.getHeader("X-Forwarded-For"), req.remoteAddress().host(), 1);
        return Map.of("ip", ip);
    }

    @GET
    @Path("/alb/salud")
    @jakarta.ws.rs.Produces("application/json")
    ResumenSalud salud(@QueryParam("targetGroupArn") String targetGroupArn) {
        return salud.leer(targetGroupArn);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;

@Path("/interno/reactivo")
class ElbReactivoRecurso {
    @Inject
    LectorSalud salud;

    @GET
    @Path("/alb/salud")
    @jakarta.ws.rs.Produces("application/json")
    Uni<ResumenSalud> salud(@QueryParam("targetGroupArn") String targetGroupArn) {
        return Uni.createFrom().item(() -> salud.leer(targetGroupArn))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 7. Permisos de la herramienta
`elasticloadbalancing:DescribeTargetHealth` (y `DescribeTargetGroups`/`DescribeLoadBalancers` si listas): solo lectura. Un endpoint que cambie pesos o registre destinos necesita permisos de escritura y debe ir a otra identidad con aprobación.

## 8. Qué NO hacer desde Java
- ❌ Leer `X-Forwarded-For` sin saber **cuántos saltos** confiables hay (el primer elemento lo controla el cliente).
- ❌ Redirigir a HTTPS sin mirar `X-Forwarded-Proto` (bucle de redirecciones).
- ❌ Dejar el keep-alive de la app en 5-30 s: provoca 502 con el ALB.
- ❌ Cerrar el proceso al recibir SIGTERM sin esperar a las peticiones en curso.
- ❌ Usar el SDK de ELB en el camino de cada petición: cachea el resumen de salud.
- ❌ Guardar la IP del cliente sin base legal ni anonimización cuando aplique la normativa de datos personales.
