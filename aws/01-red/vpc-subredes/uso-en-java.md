# AWS · VPC y subredes · Uso desde Java

La red no se «programa» desde Java, pero **cómo está hecha la red decide cómo debes configurar la aplicación**. Cuatro puntos que más fallan: timeouts, caché DNS, conexiones inactivas y **quedarte sin IP**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK for Java v2 (BOM 2.56).

## 1. Clientes del SDK con timeouts explícitos

Sin timeouts, una llamada a un destino bloqueado por un grupo de seguridad espera mucho. En el SDK v2 hay dos niveles: el **cliente HTTP** (conexión y lectura) y el **intento/llamada completa** (`apiCallAttemptTimeout`, `apiCallTimeout`).

### Spring Boot: clientes síncrono y asíncrono
```java
import java.time.Duration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ec2.Ec2AsyncClient;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Configuration
public class RedAwsConfig {

    @Bean(destroyMethod = "close")
    Ec2Client ec2() {
        return Ec2Client.builder()
                .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")))
                .httpClientBuilder(ApacheHttpClient.builder()
                        .connectionTimeout(Duration.ofSeconds(2))
                        .socketTimeout(Duration.ofSeconds(5))
                        .connectionMaxIdleTime(Duration.ofSeconds(60)) // menor que el idle de NAT/NLB (350 s)
                        .tcpKeepAlive(true))
                .overrideConfiguration(o -> o
                        .apiCallAttemptTimeout(Duration.ofSeconds(5))
                        .apiCallTimeout(Duration.ofSeconds(15)))
                .build();
    }

    @Bean(destroyMethod = "close")
    Ec2AsyncClient ec2Async() {
        return Ec2AsyncClient.builder()
                .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")))
                .overrideConfiguration(o -> o
                        .apiCallAttemptTimeout(Duration.ofSeconds(5))
                        .apiCallTimeout(Duration.ofSeconds(15)))
                .build();
    }
}
```

### Quarkus: productor CDI
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import java.time.Duration;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ec2.Ec2AsyncClient;
import software.amazon.awssdk.services.ec2.Ec2Client;

@ApplicationScoped
public class RedAwsProductores {

    @Produces
    @ApplicationScoped
    Ec2Client ec2() {
        return Ec2Client.builder()
                .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")))
                .httpClientBuilder(ApacheHttpClient.builder()
                        .connectionTimeout(Duration.ofSeconds(2))
                        .socketTimeout(Duration.ofSeconds(5))
                        .connectionMaxIdleTime(Duration.ofSeconds(60))
                        .tcpKeepAlive(true))
                .overrideConfiguration(o -> o
                        .apiCallAttemptTimeout(Duration.ofSeconds(5))
                        .apiCallTimeout(Duration.ofSeconds(15)))
                .build();
    }

    @Produces
    @ApplicationScoped
    Ec2AsyncClient ec2Async() {
        return Ec2AsyncClient.builder()
                .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")))
                .overrideConfiguration(o -> o.apiCallTimeout(Duration.ofSeconds(15)))
                .build();
    }
}
```
> Con la extensión Quarkiverse `quarkus-amazon-ec2` los clientes se configuran en `application.properties` (`quarkus.ec2.*`). Los nombres cambian entre versiones: verifica en la guía de tu versión.

## 2. Caché DNS de la JVM
Si un nombre cambia de IP (una conmutación por error de Aurora, un endpoint de interfaz recreado), la JVM puede seguir usando la IP vieja. Con un *Security Manager* el valor por defecto es infinito; sin él, unos 30 s.
```java
// Al inicio de la aplicación (antes de cualquier resolución)
java.security.Security.setProperty("networkaddress.cache.ttl", "30");
java.security.Security.setProperty("networkaddress.cache.negative.ttl", "5");
```
Los endpoints del clúster de Aurora, los balanceadores y los endpoints de PrivateLink **cambian de IP**: usa siempre el **nombre**, nunca la IP.

## 3. Conexiones inactivas: NAT Gateway, NLB y ALB
| Componente | Cierra una conexión inactiva a los… | Qué ve tu app |
|---|---|---|
| **NAT Gateway** | 350 s | `Connection reset` al reutilizar una conexión «dormida» (el NAT responde con RST) |
| **Network Load Balancer** (TCP) | 350 s | Igual |
| **Application Load Balancer** | 60 s por defecto (configurable) | `502/504` o reset en la primera petición tras el silencio |

*Verifica los valores vigentes en la documentación.* Regla: **el tiempo máximo de inactividad del pool debe ser menor que el del eslabón más corto del camino**, y el servidor (tu aplicación detrás de un ALB) debe tener un *keep-alive* **mayor** que el del ALB.

```properties
# Spring Boot: Tomcat detrás de un ALB con idle de 60 s
server.tomcat.keep-alive-timeout=75s
# Quarkus detrás de un ALB
quarkus.http.idle-timeout=75S
```
```java
import java.time.Duration;
import reactor.netty.resources.ConnectionProvider;

// Cliente reactivo que sale por NAT a un tercero: libera conexiones antes de los 350 s
class PoolSaliente {
    static final ConnectionProvider PROVEEDOR = ConnectionProvider.builder("externo")
            .maxIdleTime(Duration.ofSeconds(60))
            .maxLifeTime(Duration.ofMinutes(10))
            .evictInBackground(Duration.ofSeconds(30))
            .build();
}
```

## 4. Quedarte sin IP: un monitor de subredes
Contenedores y pods consumen IP de la VPC. Un monitor barato evita el incidente «EKS no crea pods». Separamos **la lógica pura** (se prueba sin AWS) del **lector** (usa el SDK).

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.ec2.model.DescribeSubnetsRequest;
import software.amazon.awssdk.services.ec2.model.DescribeSubnetsResponse;
import software.amazon.awssdk.services.ec2.model.Filter;
import software.amazon.awssdk.services.ec2.model.Subnet;

enum Nivel { OK, ATENCION, CRITICO }

record EstadoSubred(String id, String zona, String cidr, int libres, int utilizables, double usoPct, Nivel nivel) {}

final class CalculoRed {
    private CalculoRed() {}

    /** AWS reserva 5 direcciones por subred. */
    static int utilizables(String cidr) {
        int prefijo = Integer.parseInt(cidr.substring(cidr.indexOf('/') + 1));
        if (prefijo < 16 || prefijo > 28) throw new IllegalArgumentException("Prefijo fuera de rango AWS: " + cidr);
        return (int) (Math.pow(2, 32 - prefijo)) - 5;
    }

    static EstadoSubred evaluar(String id, String zona, String cidr, int libres) {
        int total = utilizables(cidr);
        double uso = total == 0 ? 100 : 100.0 * (total - libres) / total;
        Nivel nivel = libres < 20 || uso >= 90 ? Nivel.CRITICO : uso >= 75 ? Nivel.ATENCION : Nivel.OK;
        return new EstadoSubred(id, zona, cidr, libres, total, Math.round(uso * 10) / 10.0, nivel);
    }

    /** ¿Dos CIDR IPv4 se solapan? (para validar un plan de direcciones) */
    static boolean solapan(String a, String b) {
        long[] ra = rango(a), rb = rango(b);
        return ra[0] <= rb[1] && rb[0] <= ra[1];
    }

    private static long[] rango(String cidr) {
        String[] p = cidr.split("/");
        String[] o = p[0].split("\\.");
        long base = 0;
        for (String x : o) base = (base << 8) + Integer.parseInt(x);
        int prefijo = Integer.parseInt(p[1]);
        long tam = 1L << (32 - prefijo);
        long ini = base & ~(tam - 1);
        return new long[]{ini, ini + tam - 1};
    }
}

final class LectorSubredes {
    private final Ec2Client ec2;

    LectorSubredes(Ec2Client ec2) { this.ec2 = ec2; }

    List<EstadoSubred> estado(String vpcId) {
        DescribeSubnetsResponse r = ec2.describeSubnets(DescribeSubnetsRequest.builder()
                .filters(Filter.builder().name("vpc-id").values(vpcId).build()).build());
        return aEstados(r);
    }

    static List<EstadoSubred> aEstados(DescribeSubnetsResponse r) {
        return r.subnets().stream()
                .map((Subnet s) -> CalculoRed.evaluar(s.subnetId(), s.availabilityZone(), s.cidrBlock(), s.availableIpAddressCount()))
                .sorted((x, y) -> Double.compare(y.usoPct(), x.usoPct()))
                .toList();
    }
}
```

### Spring MVC (imperativo)
```java
import io.micrometer.core.instrument.MeterRegistry;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
@EnableScheduling
public class RedController {
    private final LectorSubredes lector;
    private final AtomicInteger criticas = new AtomicInteger();
    private final String vpcId = System.getenv().getOrDefault("VPC_ID", "vpc-0123456789abcdef0");

    RedController(Ec2Client ec2, MeterRegistry metricas) {
        this.lector = new LectorSubredes(ec2);
        metricas.gauge("red.subredes.criticas", criticas);   // alerta si > 0
    }

    @GetMapping("/red/subredes")
    List<EstadoSubred> subredes(@RequestParam(required = false) String vpc) {
        return lector.estado(vpc != null ? vpc : vpcId);
    }

    @Scheduled(fixedDelayString = "PT5M", initialDelayString = "PT30S")
    void refrescar() {
        try {
            criticas.set((int) lector.estado(vpcId).stream().filter(e -> e.nivel() == Nivel.CRITICO).count());
        } catch (RuntimeException e) {
            // no tirar la app por un monitor: registrar y reintentar en el próximo ciclo
        }
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import software.amazon.awssdk.services.ec2.Ec2AsyncClient;
import software.amazon.awssdk.services.ec2.model.DescribeSubnetsRequest;
import software.amazon.awssdk.services.ec2.model.Filter;

@RestController
public class RedReactivoController {
    private final Ec2AsyncClient ec2;

    RedReactivoController(Ec2AsyncClient ec2) { this.ec2 = ec2; }

    @GetMapping("/red/reactivo/subredes")
    Mono<List<EstadoSubred>> subredes() {
        String vpc = System.getenv().getOrDefault("VPC_ID", "vpc-0123456789abcdef0");
        return Mono.fromFuture(() -> ec2.describeSubnets(DescribeSubnetsRequest.builder()
                        .filters(Filter.builder().name("vpc-id").values(vpc).build()).build()))
                .map(LectorSubredes::aEstados);
    }
}
```
El cliente asíncrono del SDK no bloquea ningún hilo del bucle de eventos; si usas el cliente síncrono dentro de un flujo reactivo, envuélvelo con `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`.

### Quarkus (imperativo)
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Path("/red/subredes")
public class RedResource {
    @Inject
    Ec2Client ec2;

    @GET
    public List<EstadoSubred> subredes(@QueryParam("vpc") String vpc) {
        String id = vpc != null ? vpc : System.getenv().getOrDefault("VPC_ID", "vpc-0123456789abcdef0");
        return new LectorSubredes(ec2).estado(id);
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2AsyncClient;
import software.amazon.awssdk.services.ec2.model.DescribeSubnetsRequest;
import software.amazon.awssdk.services.ec2.model.Filter;

@Path("/red/reactivo/subredes")
public class RedReactivaResource {
    @Inject
    Ec2AsyncClient ec2;

    @GET
    public Uni<List<EstadoSubred>> subredes() {
        String vpc = System.getenv().getOrDefault("VPC_ID", "vpc-0123456789abcdef0");
        return Uni.createFrom().completionStage(() -> ec2.describeSubnets(DescribeSubnetsRequest.builder()
                        .filters(Filter.builder().name("vpc-id").values(vpc).build()).build()))
                .map(LectorSubredes::aEstados);
    }
}
```

## 5. Permisos del monitor
La identidad de la aplicación necesita solo `ec2:DescribeSubnets` (lectura, sin recurso específico: la acción no admite restringir por recurso). Úsala con **rol de tarea / IRSA / Pod Identity** (ver el capítulo de IAM), nunca con claves fijas.

## 6. Qué NO hacer desde Java
- No dejar timeouts en `0` ni usar los valores por defecto sin mirarlos.
- No fijar IP en el código: usa nombres DNS.
- No desactivar la validación TLS «porque en la red privada da error»: arregla el nombre o el certificado.
- No llamar a `Describe*` en cada petición de usuario: cuotas de API y latencia. Cachea y refresca en segundo plano.
