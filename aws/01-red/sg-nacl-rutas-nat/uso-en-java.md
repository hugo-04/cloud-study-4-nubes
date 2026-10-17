# AWS · SG, NACL, rutas y NAT · Uso desde Java

Dos usos reales desde Java: (1) **configurar la app para que el NAT y los balanceadores no la tumben** y (2) **auditar reglas de grupos de seguridad** con el SDK, con las reglas de decisión como funciones puras (se prueban sin AWS). Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. La app y el NAT: reutilizar conexiones
El síntoma «timeouts intermitentes hacia una API de terceros» suele ser **puertos de origen del NAT agotados** por abrir una conexión nueva por petición. En Java:

- Un **cliente HTTP único** (singleton) con **pool**; nunca crear un cliente por petición.
- `maxIdleTime` del pool **menor a 350 s** (el NAT corta a los 350 s inactivos).
- Reintentos con *backoff* y límite (no tormentas de conexiones nuevas).

```java
import java.time.Duration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;
import reactor.netty.resources.ConnectionProvider;

@Configuration
public class PagosClienteConfig {
    @Bean
    WebClient pagos() {
        ConnectionProvider pool = ConnectionProvider.builder("pagos")
                .maxConnections(100)
                .maxIdleTime(Duration.ofSeconds(60))
                .maxLifeTime(Duration.ofMinutes(10))
                .pendingAcquireTimeout(Duration.ofSeconds(5))
                .evictInBackground(Duration.ofSeconds(30))
                .build();
        HttpClient http = HttpClient.create(pool).responseTimeout(Duration.ofSeconds(5));
        return WebClient.builder()
                .baseUrl("https://api.pagos.example")
                .clientConnector(new ReactorClientHttpConnector(http))
                .build();
    }
}
```
```properties
# Quarkus: cliente REST con pool y tiempos
quarkus.rest-client.pagos.url=https://api.pagos.example
quarkus.rest-client.pagos.connect-timeout=3000
quarkus.rest-client.pagos.read-timeout=5000
quarkus.rest-client.pagos.connection-ttl=600000
quarkus.rest-client.pagos.connection-pool-size=100
```
> Los nombres de propiedades de Quarkus cambian entre versiones: verifica en la guía de tu versión.

## 2. Auditar grupos de seguridad con el SDK

### Núcleo común (reglas puras + lector)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.ec2.model.DescribeSecurityGroupRulesRequest;
import software.amazon.awssdk.services.ec2.model.DescribeSecurityGroupsRequest;
import software.amazon.awssdk.services.ec2.model.Filter;
import software.amazon.awssdk.services.ec2.model.SecurityGroup;
import software.amazon.awssdk.services.ec2.model.SecurityGroupRule;

enum Gravedad { BAJA, MEDIA, ALTA, CRITICA }

/** origen: un CIDR, un "pl-..." (lista de prefijos) o un "sg-..." (referencia a grupo). */
record Regla(String sg, boolean salida, String protocolo, int desde, int hasta, String origen, String descripcion) {
    boolean abiertaAlMundo() { return "0.0.0.0/0".equals(origen) || "::/0".equals(origen); }
    boolean todosLosPuertos() { return "-1".equals(protocolo); }
    boolean incluye(int puerto) { return todosLosPuertos() || (desde <= puerto && puerto <= hasta); }
}

record Hallazgo(String sg, Gravedad gravedad, String motivo) {}

final class AuditoriaSg {
    private AuditoriaSg() {}

    static final Set<Integer> ADMINISTRACION = Set.of(22, 3389);
    static final Set<Integer> DATOS = Set.of(1433, 1521, 3306, 5432, 6379, 9092, 9094, 27017);

    static List<Hallazgo> evaluar(List<Regla> reglas) {
        List<Hallazgo> r = new ArrayList<>();
        for (Regla x : reglas) {
            if (x.salida()) continue;                       // este análisis mira solo la entrada
            if (x.abiertaAlMundo()) {
                if (x.todosLosPuertos()) {
                    r.add(new Hallazgo(x.sg(), Gravedad.CRITICA, "Todos los puertos abiertos a internet"));
                    continue;
                }
                for (int p : ADMINISTRACION) {
                    if (x.incluye(p)) r.add(new Hallazgo(x.sg(), Gravedad.CRITICA, "Puerto de administración " + p + " abierto a internet"));
                }
                for (int p : DATOS) {
                    if (x.incluye(p)) r.add(new Hallazgo(x.sg(), Gravedad.CRITICA, "Puerto de datos " + p + " abierto a internet"));
                }
                boolean soloWeb = x.desde() >= 80 && x.hasta() <= 443 && (x.desde() == 80 || x.desde() == 443) && (x.hasta() == 80 || x.hasta() == 443);
                if (!soloWeb && r.stream().noneMatch(h -> h.sg().equals(x.sg()) && h.gravedad() == Gravedad.CRITICA)) {
                    r.add(new Hallazgo(x.sg(), Gravedad.ALTA, "Puertos " + x.desde() + "-" + x.hasta() + " abiertos a internet"));
                }
            } else if (x.hasta() - x.desde() > 100 && !x.todosLosPuertos()) {
                r.add(new Hallazgo(x.sg(), Gravedad.MEDIA, "Rango amplio de puertos " + x.desde() + "-" + x.hasta()));
            } else if (x.origen().contains("/") && DATOS.stream().anyMatch(x::incluye)) {
                r.add(new Hallazgo(x.sg(), Gravedad.MEDIA, "Puerto de datos por CIDR: usa referencia a grupo de seguridad"));
            }
            if (x.descripcion() == null || x.descripcion().isBlank()) {
                r.add(new Hallazgo(x.sg(), Gravedad.BAJA, "Regla sin descripción"));
            }
        }
        return r.stream().sorted((a, b) -> b.gravedad().compareTo(a.gravedad())).toList();
    }
}

final class LectorReglas {
    private final Ec2Client ec2;

    LectorReglas(Ec2Client ec2) { this.ec2 = ec2; }

    List<Regla> leer(String vpcId) {
        List<String> grupos = new ArrayList<>();
        ec2.describeSecurityGroupsPaginator(DescribeSecurityGroupsRequest.builder()
                        .filters(Filter.builder().name("vpc-id").values(vpcId).build()).build())
                .securityGroups().forEach((SecurityGroup g) -> grupos.add(g.groupId()));

        List<Regla> reglas = new ArrayList<>();
        for (int i = 0; i < grupos.size(); i += 50) {                  // el filtro admite pocos valores por llamada
            List<String> lote = grupos.subList(i, Math.min(i + 50, grupos.size()));
            ec2.describeSecurityGroupRulesPaginator(DescribeSecurityGroupRulesRequest.builder()
                            .filters(Filter.builder().name("group-id").values(lote).build()).build())
                    .securityGroupRules().forEach(r -> reglas.add(aRegla(r)));
        }
        return reglas;
    }

    static Regla aRegla(SecurityGroupRule r) {
        String origen = r.cidrIpv4() != null ? r.cidrIpv4()
                : r.cidrIpv6() != null ? r.cidrIpv6()
                : r.prefixListId() != null ? r.prefixListId()
                : r.referencedGroupInfo() != null ? r.referencedGroupInfo().groupId() : "?";
        int desde = r.fromPort() == null ? 0 : r.fromPort();
        int hasta = r.toPort() == null ? 65535 : r.toPort();
        return new Regla(r.groupId(), Boolean.TRUE.equals(r.isEgress()), r.ipProtocol(), desde, hasta, origen, r.description());
    }
}
```
Dos detalles del SDK: los resultados son **paginados** (usa los *paginators*, no la primera página) y con protocolo `-1` los puertos vienen como `-1`; el código lo trata con `todosLosPuertos()`.

### Spring MVC (imperativo)
```java
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
public class AuditoriaSgController {
    private final LectorReglas lector;
    private volatile List<Hallazgo> cache = List.of();
    private volatile Instant cargado = Instant.EPOCH;

    AuditoriaSgController(Ec2Client ec2) { this.lector = new LectorReglas(ec2); }

    @GetMapping("/red/auditoria-sg")
    List<Hallazgo> auditar(@RequestParam String vpc) {
        if (Duration.between(cargado, Instant.now()).toMinutes() >= 10) {   // la API tiene cuotas: cachea
            cache = AuditoriaSg.evaluar(lector.leer(vpc));
            cargado = Instant.now();
        }
        return cache;
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
public class AuditoriaSgReactivoController {
    private final LectorReglas lector;

    AuditoriaSgReactivoController(Ec2Client ec2) { this.lector = new LectorReglas(ec2); }

    @GetMapping("/red/reactivo/auditoria-sg")
    Mono<List<Hallazgo>> auditar(@RequestParam String vpc) {
        return Mono.fromCallable(() -> AuditoriaSg.evaluar(lector.leer(vpc)))
                .subscribeOn(Schedulers.boundedElastic());   // el SDK síncrono bloquea: fuera del bucle de eventos
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

@Path("/red/auditoria-sg")
public class AuditoriaSgResource {
    @Inject
    Ec2Client ec2;

    @GET
    public List<Hallazgo> auditar(@QueryParam("vpc") String vpc) {
        return AuditoriaSg.evaluar(new LectorReglas(ec2).leer(vpc));
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
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Path("/red/reactivo/auditoria-sg")
public class AuditoriaSgReactivaResource {
    @Inject
    Ec2Client ec2;

    @GET
    public Uni<List<Hallazgo>> auditar(@QueryParam("vpc") String vpc) {
        return Uni.createFrom().item(() -> AuditoriaSg.evaluar(new LectorReglas(ec2).leer(vpc)))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```
> El `Ec2Client` de estos ejemplos es el de [VPC y subredes](../vpc-subredes/uso-en-java.md) (con timeouts explícitos). La identidad necesita solo `ec2:DescribeSecurityGroups` y `ec2:DescribeSecurityGroupRules`.

## 3. Dónde usar esta auditoría
- **En el pipeline**, antes de aplicar Terraform: falla el cambio si aparece un hallazgo `CRITICA`.
- **Programada** (cada hora) y publicada como métrica; alerta por `CRITICA`.
- **No** en el camino de una petición de usuario: llamada de administración, cuotas y latencia.

## 4. Qué NO hacer desde Java
- No «arreglar» reglas automáticamente desde la aplicación: audita; el cambio va por Terraform y revisión.
- No dar `ec2:AuthorizeSecurityGroupIngress` a la identidad de la aplicación.
- No ignorar la paginación del SDK.
