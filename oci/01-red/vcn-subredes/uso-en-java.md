# Oracle OCI · Red · VCN y subredes · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Se construye un **planificador de subredes** (puro, sin red) y un **inventario/creación idempotente** con el SDK. El planificador reserva las 3 direcciones que OCI no entrega, alinea los bloques y evita solapes con lo ya existente.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance          # config | instance | oke | resource
  region: sa-saopaulo-1
  compartimento-red: ocid1.compartment.oc1..aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
oci.compartimento-red=ocid1.compartment.oc1..aaaa
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

    /** config = laptop (~/.oci/config); instance = VM; oke = pod con workload identity; resource = OCI Functions. */
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

### 2.2 Planificador de subredes (puro)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public record Bloque(long inicio, int prefijo) {

    public static Bloque parse(String cidr) {
        String[] p = cidr.trim().split("/");
        if (p.length != 2) {
            throw new IllegalArgumentException("CIDR inválido: " + cidr);
        }
        String[] o = p[0].split("\\.");
        if (o.length != 4) {
            throw new IllegalArgumentException("CIDR inválido: " + cidr);
        }
        long ip = 0;
        for (String x : o) {
            int v = Integer.parseInt(x);
            if (v < 0 || v > 255) {
                throw new IllegalArgumentException("octeto fuera de rango en " + cidr);
            }
            ip = ip << 8 | v;
        }
        int prefijo = Integer.parseInt(p[1]);
        if (prefijo < 8 || prefijo > 30) {
            throw new IllegalArgumentException("prefijo fuera de rango (8-30): " + cidr);
        }
        long tam = 1L << (32 - prefijo);
        if (ip % tam != 0) {
            throw new IllegalArgumentException("el bloque no está alineado a su tamaño: " + cidr);
        }
        return new Bloque(ip, prefijo);
    }

    public long tamano() {
        return 1L << (32 - prefijo);
    }

    /** OCI reserva 3 direcciones por subred: red, gateway y difusión. */
    public long utilizables() {
        return tamano() - 3;
    }

    public long fin() {
        return inicio + tamano();
    }

    public boolean solapa(Bloque o) {
        return inicio < o.fin() && o.inicio < fin();
    }

    public boolean contiene(Bloque o) {
        return inicio <= o.inicio && o.fin() <= fin();
    }

    public String texto() {
        return (inicio >> 24 & 255) + "." + (inicio >> 16 & 255) + "." + (inicio >> 8 & 255) + "." + (inicio & 255) + "/" + prefijo;
    }
}

public record NecesidadDeSubred(String nombre, long hosts, boolean publica) { }

public record SubredPlanificada(String nombre, String cidr, long utilizables, boolean publica) { }

public record PeticionDePlan(String cidrVcn, List<NecesidadDeSubred> necesidades, List<String> ocupados) { }

public final class PlanificadorDeSubredes {

    private PlanificadorDeSubredes() { }

    /** Prefijo más largo (bloque más pequeño) cuyas IP utilizables alcanzan para los hosts pedidos. */
    static int prefijoPara(long hosts) {
        if (hosts < 1) {
            throw new IllegalArgumentException("hosts debe ser positivo");
        }
        for (int p = 30; p >= 8; p--) {
            if ((1L << (32 - p)) - 3 >= hosts) {
                return p;
            }
        }
        throw new IllegalArgumentException("demasiados hosts: " + hosts);
    }

    public static List<SubredPlanificada> planificar(PeticionDePlan peticion) {
        Bloque vcn = Bloque.parse(peticion.cidrVcn());
        List<Bloque> usados = new ArrayList<>();
        for (String o : peticion.ocupados()) {
            Bloque b = Bloque.parse(o);
            if (!vcn.contiene(b)) {
                throw new IllegalArgumentException("ocupado fuera de la VCN: " + o);
            }
            usados.add(b);
        }
        // Los bloques grandes primero: así se mantienen alineados y se desperdicia menos espacio
        var ordenadas = peticion.necesidades().stream()
                .sorted(Comparator.comparingLong(NecesidadDeSubred::hosts).reversed().thenComparing(NecesidadDeSubred::nombre))
                .toList();
        var plan = new ArrayList<SubredPlanificada>();
        for (NecesidadDeSubred n : ordenadas) {
            int prefijo = prefijoPara(n.hosts());
            long tam = 1L << (32 - prefijo);
            Bloque elegido = null;
            for (long inicio = vcn.inicio(); inicio + tam <= vcn.fin(); inicio += tam) {
                Bloque candidato = new Bloque(inicio, prefijo);
                if (usados.stream().noneMatch(candidato::solapa)) {
                    elegido = candidato;
                    break;
                }
            }
            if (elegido == null) {
                throw new IllegalStateException("no queda espacio para «" + n.nombre() + "» (/" + prefijo + ") en " + vcn.texto());
            }
            usados.add(elegido);
            plan.add(new SubredPlanificada(n.nombre(), elegido.texto(), elegido.utilizables(), n.publica()));
        }
        return plan;
    }
}
```

### 2.3 Inventario y creación idempotente con el SDK
`ListSubnets` pagina con un token; el SDK trae iteradores que lo ocultan. Crear dos veces la misma subred daría error de CIDR solapado, así que **primero se consulta**.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.CreateSubnetDetails;
import com.oracle.bmc.core.requests.CreateSubnetRequest;
import com.oracle.bmc.core.requests.ListSubnetsRequest;

public record SubredExistente(String id, String nombre, String cidr, boolean privada) { }

public final class RedOci {

    private final VirtualNetworkClient cliente;
    private final String compartimento;

    public RedOci(VirtualNetworkClient cliente, String compartimento) {
        this.cliente = cliente;
        this.compartimento = compartimento;
    }

    public List<SubredExistente> subredes(String vcnId) {
        var peticion = ListSubnetsRequest.builder().compartmentId(compartimento).vcnId(vcnId).build();
        var lista = new ArrayList<SubredExistente>();
        for (var s : cliente.getPaginators().listSubnetsRecordIterator(peticion)) {
            lista.add(new SubredExistente(s.getId(), s.getDisplayName(), s.getCidrBlock(), Boolean.TRUE.equals(s.getProhibitPublicIpOnVnic())));
        }
        return lista;
    }

    /** Crea la subred solo si no existe una con ese nombre; devuelve el id. */
    public String asegurarSubred(String vcnId, SubredPlanificada plan, String tablaDeRutas) {
        for (SubredExistente e : subredes(vcnId)) {
            if (e.nombre().equals(plan.nombre())) {
                if (!e.cidr().equals(plan.cidr())) {
                    throw new IllegalStateException("«" + plan.nombre() + "» ya existe con otro CIDR: " + e.cidr());
                }
                return e.id();
            }
        }
        var detalles = CreateSubnetDetails.builder()
                .compartmentId(compartimento).vcnId(vcnId).displayName(plan.nombre()).cidrBlock(plan.cidr())
                .prohibitPublicIpOnVnic(!plan.publica()).routeTableId(tablaDeRutas).build();
        return cliente.createSubnet(CreateSubnetRequest.builder().createSubnetDetails(detalles).build()).getSubnet().getId();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class RedConfiguracion {

    @Bean(destroyMethod = "close")
    VirtualNetworkClient redCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    RedOci redOci(VirtualNetworkClient cliente, @Value("${oci.compartimento-red}") String compartimento) {
        return new RedOci(cliente, compartimento);
    }
}

@RestController
@RequestMapping("/red")
class RedControlador {

    private final RedOci red;

    RedControlador(RedOci red) {
        this.red = red;
    }

    @PostMapping("/plan")
    ResponseEntity<?> plan(@RequestBody PeticionDePlan peticion) {
        try {
            return ResponseEntity.ok(PlanificadorDeSubredes.planificar(peticion));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", e.getMessage()));
        } catch (IllegalStateException e) {
            return ResponseEntity.status(409).body(java.util.Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/subredes")
    List<SubredExistente> subredes(@RequestParam String vcn) {
        return red.subredes(vcn);
    }
}
```

## 4. Spring WebFlux (reactivo)
El planificador es CPU puro; el SDK síncrono bloquea, así que va a `boundedElastic`. (El SDK también ofrece clientes `…AsyncClient` con `AsyncHandler`; para un solo servicio, aislar el síncrono es más simple.)
```java
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red")
class RedReactivoControlador {

    private final RedOci red;

    RedReactivoControlador(RedOci red) {
        this.red = red;
    }

    @PostMapping("/plan")
    Mono<List<SubredPlanificada>> plan(@RequestBody PeticionDePlan peticion) {
        return Mono.fromCallable(() -> PlanificadorDeSubredes.planificar(peticion));
    }

    @GetMapping("/subredes")
    Mono<List<SubredExistente>> subredes(@RequestParam String vcn) {
        return Mono.fromCallable(() -> red.subredes(vcn)).subscribeOn(Schedulers.boundedElastic());
    }
}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class RedProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "oci.compartimento-red")
    String compartimento;

    @jakarta.enterprise.inject.Produces
    @Singleton
    RedOci red() {
        var cliente = VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new RedOci(cliente, compartimento);
    }
}

@Path("/red")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class RedRecurso {

    @Inject
    RedOci red;

    @POST
    @Path("/plan")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response plan(PeticionDePlan peticion) {
        try {
            return Response.ok(PlanificadorDeSubredes.planificar(peticion)).build();
        } catch (IllegalArgumentException e) {
            return Response.status(400).entity(Map.of("error", e.getMessage())).build();
        } catch (IllegalStateException e) {
            return Response.status(409).entity(Map.of("error", e.getMessage())).build();
        }
    }

    @GET
    @Path("/subredes")
    public List<SubredExistente> subredes(@QueryParam("vcn") String vcn) {
        return red.subredes(vcn);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/red")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class RedRecursoReactivo {

    @Inject
    RedOci red;

    @POST
    @Path("/plan")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<SubredPlanificada>> plan(PeticionDePlan peticion) {
        return Uni.createFrom().item(() -> PlanificadorDeSubredes.planificar(peticion));
    }

    @GET
    @Path("/subredes")
    public Uni<List<SubredExistente>> subredes(@QueryParam("vcn") String vcn) {
        return Uni.createFrom().item(() -> red.subredes(vcn)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 7. Permisos
| Acción en Java | Política (en el compartimento de red) |
|---|---|
| `ListSubnets`, `GetSubnet` | `Allow dynamic-group app-tienda to inspect virtual-network-family in compartment red` |
| `CreateSubnet` (solo el servicio de aprovisionamiento) | `Allow dynamic-group provisionador to manage subnets in compartment red` |
| Usar subredes al crear VNIC/instancias | `Allow group desarrollo to use subnets in compartment red` |

## 8. Qué NO hacer desde Java
- No crees subredes sin consultar primero (CIDR solapado = error y estado a medias).
- No uses `config` (archivo de claves) fuera de tu laptop; en OCI usa `instance`, `oke` o `resource`.
- No llames al SDK síncrono en el bucle de eventos de WebFlux/Vert.x.
- No olvides cerrar el cliente (`destroyMethod = "close"`).
- No des `manage virtual-network-family` a las aplicaciones: bastan `inspect` o `use`.
