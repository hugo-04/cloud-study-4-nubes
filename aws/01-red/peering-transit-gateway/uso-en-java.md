# AWS · Peering y Transit Gateway · Uso desde Java

Cómo se conectan las VPC no se programa desde la aplicación; lo que sí aporta Java es **validar el plan** (solapes de CIDR y reglas de segmentos) antes de aplicar Terraform, **leer el estado** de los adjuntos del TGW y **entender qué cambia en tu servicio**: más saltos, latencia entre AZ/regiones y tiempos de espera. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Qué cambia para tu servicio
- **Latencia:** cada salto por TGW suma poco, pero entre **regiones** son decenas de ms: no encadenes llamadas síncronas entre regiones.
- **Tiempo de espera de conexión:** un bloqueo de ruta o SG se ve como timeout; configura `connect timeout` corto (2–3 s) y reintentos acotados.
- **Nombres, no IP:** usa DNS (zonas privadas compartidas) para que un cambio de topología no obligue a recompilar.
- **Idle de conexiones:** las conexiones que cruzan firewalls en línea pueden cortarse antes de lo esperado; mantén el pool con vida corta (ver [VPC y subredes](../vpc-subredes/uso-en-java.md)).

## 2. Validar el plan de redes y leer los adjuntos del TGW

### Núcleo común (reglas puras + lector)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.ec2.model.DescribeTransitGatewayAttachmentsRequest;
import software.amazon.awssdk.services.ec2.model.Filter;

record VpcPlan(String nombre, String cidr, String segmento) {}

record Conflicto(String a, String b, String motivo) {}

record Adjunto(String id, String tipo, String recurso, String estado, String tablaAsociada) {}

final class PlanRedes {
    private PlanRedes() {}

    /** Pares de VPC cuyos CIDR se solapan (no se pueden conectar por peering ni TGW). */
    static List<Conflicto> solapes(List<VpcPlan> vpcs) {
        List<Conflicto> r = new ArrayList<>();
        for (int i = 0; i < vpcs.size(); i++) {
            for (int j = i + 1; j < vpcs.size(); j++) {
                if (solapan(vpcs.get(i).cidr(), vpcs.get(j).cidr())) {
                    r.add(new Conflicto(vpcs.get(i).nombre(), vpcs.get(j).nombre(),
                            "CIDR solapados: " + vpcs.get(i).cidr() + " y " + vpcs.get(j).cidr()));
                }
            }
        }
        return r;
    }

    /**
     * Valida la segmentación: cada segmento solo debe alcanzar los segmentos que se le permiten.
     * "propagaciones" dice, por tabla de segmento, qué segmentos publica en ella (lo que la tabla "ve").
     */
    static List<Conflicto> segmentos(List<VpcPlan> vpcs, Map<String, Set<String>> propagaciones, Map<String, Set<String>> permitidos) {
        List<Conflicto> r = new ArrayList<>();
        for (Map.Entry<String, Set<String>> e : propagaciones.entrySet()) {
            String tabla = e.getKey();
            Set<String> ok = permitidos.getOrDefault(tabla, Set.of());
            for (String visto : e.getValue()) {
                if (!ok.contains(visto)) {
                    r.add(new Conflicto(tabla, visto, "La tabla '" + tabla + "' ve el segmento '" + visto + "' y no debería"));
                }
            }
        }
        Set<String> declarados = new java.util.HashSet<>();
        vpcs.forEach(v -> declarados.add(v.segmento()));
        for (String s : propagaciones.keySet()) {
            if (!declarados.contains(s)) r.add(new Conflicto(s, s, "Tabla sin VPC en ese segmento"));
        }
        return r;
    }

    static boolean solapan(String a, String b) {
        long[] ra = rango(a), rb = rango(b);
        return ra[0] <= rb[1] && rb[0] <= ra[1];
    }

    private static long[] rango(String cidr) {
        String[] p = cidr.split("/");
        long base = 0;
        for (String o : p[0].split("\\.")) base = (base << 8) + Integer.parseInt(o);
        long tam = 1L << (32 - Integer.parseInt(p[1]));
        long ini = base & ~(tam - 1);
        return new long[]{ini, ini + tam - 1};
    }
}

final class LectorTgw {
    private final Ec2Client ec2;

    LectorTgw(Ec2Client ec2) { this.ec2 = ec2; }

    List<Adjunto> adjuntos(String tgwId) {
        List<Adjunto> r = new ArrayList<>();
        ec2.describeTransitGatewayAttachmentsPaginator(DescribeTransitGatewayAttachmentsRequest.builder()
                        .filters(Filter.builder().name("transit-gateway-id").values(tgwId).build()).build())
                .transitGatewayAttachments()
                .forEach(a -> r.add(new Adjunto(a.transitGatewayAttachmentId(), a.resourceTypeAsString(), a.resourceId(),
                        a.stateAsString(), a.association() == null ? null : a.association().transitGatewayRouteTableId())));
        return r;
    }

    /** Adjuntos que no están disponibles o no tienen tabla asociada (no enrutan nada). */
    static List<Adjunto> sospechosos(List<Adjunto> todos) {
        return todos.stream().filter(a -> !"available".equals(a.estado()) || a.tablaAsociada() == null).toList();
    }
}
```

### Spring MVC (imperativo)
```java
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
public class PlanRedesController {
    private final LectorTgw lector;

    PlanRedesController(Ec2Client ec2) { this.lector = new LectorTgw(ec2); }

    record Plan(List<VpcPlan> vpcs, Map<String, Set<String>> propagaciones, Map<String, Set<String>> permitidos) {}

    /** Se llama desde el pipeline ANTES de terraform apply. */
    @PostMapping("/red/plan/validar")
    List<Conflicto> validar(@RequestBody Plan plan) {
        List<Conflicto> todos = new java.util.ArrayList<>(PlanRedes.solapes(plan.vpcs()));
        todos.addAll(PlanRedes.segmentos(plan.vpcs(), plan.propagaciones(), plan.permitidos()));
        return todos;
    }

    @GetMapping("/red/tgw/{id}/sospechosos")
    List<Adjunto> sospechosos(@PathVariable String id) {
        return LectorTgw.sospechosos(lector.adjuntos(id));
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
public class PlanRedesReactivoController {
    private final LectorTgw lector;

    PlanRedesReactivoController(Ec2Client ec2) { this.lector = new LectorTgw(ec2); }

    @PostMapping("/red/reactivo/plan/solapes")
    Mono<List<Conflicto>> solapes(@RequestBody Mono<List<VpcPlan>> vpcs) {
        return vpcs.map(PlanRedes::solapes);   // función pura: no necesita hilo aparte
    }

    @GetMapping("/red/reactivo/tgw/{id}/sospechosos")
    Mono<List<Adjunto>> sospechosos(@PathVariable String id) {
        return Mono.fromCallable(() -> LectorTgw.sospechosos(lector.adjuntos(id)))
                .subscribeOn(Schedulers.boundedElastic());   // SDK síncrono: fuera del bucle de eventos
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Path("/red")
public class PlanRedesResource {
    @Inject
    Ec2Client ec2;

    @POST
    @Path("/plan/solapes")
    public List<Conflicto> solapes(List<VpcPlan> vpcs) {
        return PlanRedes.solapes(vpcs);
    }

    @GET
    @Path("/tgw/{id}/sospechosos")
    public List<Adjunto> sospechosos(@PathParam("id") String id) {
        return LectorTgw.sospechosos(new LectorTgw(ec2).adjuntos(id));
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
import jakarta.ws.rs.PathParam;
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Path("/red/reactivo/tgw")
public class TgwReactivoResource {
    @Inject
    Ec2Client ec2;

    @GET
    @Path("/{id}/sospechosos")
    public Uni<List<Adjunto>> sospechosos(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> LectorTgw.sospechosos(new LectorTgw(ec2).adjuntos(id)))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```
> El `Ec2Client` es el de [VPC y subredes](../vpc-subredes/uso-en-java.md). Permisos de lectura: `ec2:DescribeTransitGatewayAttachments`.

## 3. Cómo usar la validación
- Un paso del *pipeline* (antes de `terraform apply`) llama a `/red/plan/validar` con el plan de CIDR y las propagaciones deseadas; si devuelve conflictos, **falla el cambio**.
- Un chequeo programado lista los adjuntos «sospechosos» y alerta.

## 4. Qué NO hacer desde Java
- No «arreglar» rutas o adjuntos desde la aplicación: cambios de red van por Terraform, revisados.
- No dar permisos `ec2:*TransitGateway*` de escritura a identidades de aplicación.
- No llamar a `Describe*` por petición de usuario.
