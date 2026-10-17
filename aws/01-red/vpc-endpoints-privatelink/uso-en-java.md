# AWS · VPC Endpoints, PrivateLink y Route 53 · Uso desde Java

Con **DNS privado** activo, tu código Java **no cambia**: `SqsClient.create()` resuelve `sqs.us-east-1.amazonaws.com` a la IP privada del endpoint. Lo que sí haces desde Java: (1) **comprobar** que el DNS resuelve a IP privada, (2) **auditar** que existen los endpoints esperados, (3) usar `endpointOverride` **solo** cuando no hay DNS privado. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Comprobar DNS privado y endpoints esperados

### Núcleo común (funciones puras + lector)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.ec2.model.DescribeVpcEndpointsRequest;
import software.amazon.awssdk.services.ec2.model.Filter;

record ResultadoDns(String host, List<String> ips, boolean privada, String detalle) {}

record EndpointExistente(String servicio, String estado, boolean dnsPrivado) {}

final class ComprobadorDns {
    private ComprobadorDns() {}

    /** Resuelve el nombre y dice si TODAS las direcciones son privadas (10/8, 172.16/12, 192.168/16). */
    static ResultadoDns comprobar(String host) {
        try {
            InetAddress[] dirs = InetAddress.getAllByName(host);
            List<String> ips = new ArrayList<>();
            boolean todasPrivadas = true;
            for (InetAddress d : dirs) {
                ips.add(d.getHostAddress());
                todasPrivadas &= d.isSiteLocalAddress();
            }
            return new ResultadoDns(host, ips, todasPrivadas,
                    todasPrivadas ? "OK: resuelve por el endpoint" : "Resuelve a IP pública: ¿DNS privado apagado o VPC sin DNS?");
        } catch (UnknownHostException e) {
            return new ResultadoDns(host, List.of(), false, "No resuelve: " + e.getMessage());
        }
    }

    static String hostDe(String servicio, String region) {
        return servicio + "." + region + ".amazonaws.com";
    }
}

final class ChecklistEndpoints {
    private ChecklistEndpoints() {}

    /** Endpoints de interfaz que necesita un Fargate/EKS sin NAT que lee secretos y usa colas. */
    static final Set<String> FARGATE_SIN_NAT = Set.of("ecr.api", "ecr.dkr", "logs", "sts", "secretsmanager", "sqs");

    /** Qué falta: compara los servicios esperados contra los nombres de servicio existentes (com.amazonaws.<region>.<servicio>). */
    static List<String> faltantes(String region, Set<String> esperados, Collection<String> existentes) {
        String prefijo = "com.amazonaws." + region + ".";
        Set<String> presentes = new TreeSet<>();
        for (String s : existentes) {
            if (s.startsWith(prefijo)) presentes.add(s.substring(prefijo.length()));
        }
        Set<String> faltan = new TreeSet<>(esperados);
        faltan.removeAll(presentes);
        if (!presentes.contains("s3")) faltan.add("s3 (gateway)");   // las capas de ECR salen de S3
        return List.copyOf(faltan);
    }
}

final class LectorEndpoints {
    private final Ec2Client ec2;

    LectorEndpoints(Ec2Client ec2) { this.ec2 = ec2; }

    List<EndpointExistente> listar(String vpcId) {
        List<EndpointExistente> r = new ArrayList<>();
        ec2.describeVpcEndpointsPaginator(DescribeVpcEndpointsRequest.builder()
                        .filters(Filter.builder().name("vpc-id").values(vpcId).build()).build())
                .vpcEndpoints()
                .forEach(e -> r.add(new EndpointExistente(e.serviceName(), e.stateAsString(), Boolean.TRUE.equals(e.privateDnsEnabled()))));
        return r;
    }
}
```

### Spring MVC (imperativo)
```java
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
public class EndpointsController {
    private final LectorEndpoints lector;

    EndpointsController(Ec2Client ec2) { this.lector = new LectorEndpoints(ec2); }

    /** DNS: ¿esta app llega a los servicios por IP privada? (se ejecuta DENTRO de la VPC) */
    @GetMapping("/red/dns-privado")
    List<ResultadoDns> dns(@RequestParam(defaultValue = "us-east-1") String region) {
        return ChecklistEndpoints.FARGATE_SIN_NAT.stream().sorted()
                .map(s -> ComprobadorDns.comprobar(ComprobadorDns.hostDe(s, region))).toList();
    }

    @GetMapping("/red/endpoints/faltantes")
    Map<String, Object> faltantes(@RequestParam String vpc, @RequestParam(defaultValue = "us-east-1") String region) {
        var existentes = lector.listar(vpc);
        return Map.of("faltantes", ChecklistEndpoints.faltantes(region, ChecklistEndpoints.FARGATE_SIN_NAT,
                existentes.stream().map(EndpointExistente::servicio).toList()));
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.scheduler.Schedulers;

@RestController
public class EndpointsReactivoController {

    /** La resolución DNS de la JVM bloquea: cada consulta va a un hilo elástico. */
    @GetMapping("/red/reactivo/dns-privado")
    Flux<ResultadoDns> dns(@RequestParam(defaultValue = "us-east-1") String region) {
        List<String> servicios = ChecklistEndpoints.FARGATE_SIN_NAT.stream().sorted().toList();
        return Flux.fromIterable(servicios)
                .flatMap(s -> reactor.core.publisher.Mono
                        .fromCallable(() -> ComprobadorDns.comprobar(ComprobadorDns.hostDe(s, region)))
                        .subscribeOn(Schedulers.boundedElastic()), 4);
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Path("/red")
public class EndpointsResource {
    @Inject
    Ec2Client ec2;

    @GET
    @Path("/dns-privado")
    public List<ResultadoDns> dns(@QueryParam("region") String region) {
        String r = region != null ? region : "us-east-1";
        return ChecklistEndpoints.FARGATE_SIN_NAT.stream().sorted()
                .map(s -> ComprobadorDns.comprobar(ComprobadorDns.hostDe(s, r))).toList();
    }

    @GET
    @Path("/endpoints/faltantes")
    public List<String> faltantes(@QueryParam("vpc") String vpc, @QueryParam("region") String region) {
        String r = region != null ? region : "us-east-1";
        var existentes = new LectorEndpoints(ec2).listar(vpc);
        return ChecklistEndpoints.faltantes(r, ChecklistEndpoints.FARGATE_SIN_NAT,
                existentes.stream().map(EndpointExistente::servicio).toList());
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/red/reactivo/dns-privado")
public class EndpointsReactivoResource {

    @GET
    public Uni<List<ResultadoDns>> dns(@QueryParam("region") String region) {
        String r = region != null ? region : "us-east-1";
        return Multi.createFrom().iterable(ChecklistEndpoints.FARGATE_SIN_NAT.stream().sorted().toList())
                .onItem().transformToUniAndMerge(s -> Uni.createFrom()
                        .item(() -> ComprobadorDns.comprobar(ComprobadorDns.hostDe(s, r)))
                        .runSubscriptionOn(Infrastructure.getDefaultWorkerPool()))
                .collect().asList();
    }
}
```

## 2. `endpointOverride`: solo si NO hay DNS privado
Cuando el endpoint está en **otra VPC** (sin la zona privada asociada) o el DNS privado no se puede activar, apunta el cliente al nombre propio del endpoint (`vpce-xxxx.sqs.us-east-1.vpce.amazonaws.com`, visible en la consola o en `describe-vpc-endpoints`).

```java
import java.net.URI;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sqs.SqsClient;

@Configuration
public class SqsClienteConfig {
    @Bean(destroyMethod = "close")
    SqsClient sqs(@Value("${app.sqs.endpoint:}") String endpoint) {
        var b = SqsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")));
        if (!endpoint.isBlank()) b = b.endpointOverride(URI.create(endpoint));   // solo con endpoint explícito
        return b.build();
    }
}
```
```properties
# Spring: dejar vacío cuando hay DNS privado
app.sqs.endpoint=

# Quarkus (extensión quarkus-amazon-sqs): solo si hace falta
# quarkus.sqs.endpoint-override=https://vpce-0123456789.sqs.us-east-1.vpce.amazonaws.com
```
> Con `endpointOverride`, TLS valida contra el nombre DNS del endpoint (incluido en el certificado). **Nunca** desactives la validación TLS. Los nombres de propiedades de Quarkus cambian entre versiones: verifica en la guía de tu versión.

## 3. S3 y regiones
El endpoint de puerta de enlace de S3 solo cubre buckets de **la misma región**. Un bucket de otra región por el mismo endpoint falla o sale por NAT: crea el cliente con la región del bucket o activa `crossRegionAccessEnabled(true)` en el builder de `S3Client` (verifica el comportamiento y el costo de la transferencia entre regiones).

## 4. Qué NO hacer desde Java
- No poner IP del endpoint en el código ni en `/etc/hosts`.
- No usar `endpointOverride` «por si acaso» cuando el DNS privado funciona.
- No desactivar TLS.
- No cachear DNS para siempre: baja `networkaddress.cache.ttl` (ver [VPC y subredes](../vpc-subredes/uso-en-java.md)).
