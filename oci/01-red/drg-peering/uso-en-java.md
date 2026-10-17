# Oracle OCI · Red · DRG, peering e híbrido · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Lo que más duele de una DRG es descubrir un **CIDR solapado** después de crear los adjuntos. Se construye un **verificador de solapes** (puro) que toma las VCN reales del tenancy (leídas con el SDK) y las redes on-premises conocidas, y dice si una red nueva puede conectarse.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
  compartimento-red: ocid1.compartment.oc1..aaaa
  on-premises: 192.168.0.0/16,172.16.0.0/20
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
oci.compartimento-red=ocid1.compartment.oc1..aaaa
oci.on-premises=192.168.0.0/16,172.16.0.0/20
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

### 2.2 Verificador de solapes (puro)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

public record Bloque(long inicio, int prefijo) {

    public static Bloque parse(String cidr) {
        String[] p = cidr.trim().split("/");
        String[] o = p[0].split("\\.");
        if (p.length != 2 || o.length != 4) {
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
        if (prefijo < 8 || prefijo > 30 || ip % (1L << (32 - prefijo)) != 0) {
            throw new IllegalArgumentException("prefijo o alineación inválidos: " + cidr);
        }
        return new Bloque(ip, prefijo);
    }

    long fin() {
        return inicio + (1L << (32 - prefijo));
    }

    public boolean solapa(Bloque o) {
        return inicio < o.fin() && o.inicio < fin();
    }

    public String texto() {
        return (inicio >> 24 & 255) + "." + (inicio >> 16 & 255) + "." + (inicio >> 8 & 255) + "." + (inicio & 255) + "/" + prefijo;
    }
}

public record RedConocida(String nombre, String cidr) { }

public record Conflicto(String a, String b, String detalle) { }

public final class VerificadorDeSolapes {

    private VerificadorDeSolapes() { }

    /** Todos los pares que se pisan (cada par una sola vez). */
    public static List<Conflicto> verificar(List<RedConocida> redes) {
        var conflictos = new ArrayList<Conflicto>();
        for (int i = 0; i < redes.size(); i++) {
            for (int j = i + 1; j < redes.size(); j++) {
                Bloque x = Bloque.parse(redes.get(i).cidr());
                Bloque y = Bloque.parse(redes.get(j).cidr());
                if (x.solapa(y)) {
                    conflictos.add(new Conflicto(redes.get(i).nombre(), redes.get(j).nombre(),
                            x.texto() + " solapa con " + y.texto()));
                }
            }
        }
        return conflictos;
    }

    /** ¿Puede conectarse una red nueva sin pisar a ninguna de las existentes? */
    public static List<Conflicto> candidata(RedConocida nueva, List<RedConocida> existentes) {
        var todas = new ArrayList<RedConocida>(existentes);
        todas.add(nueva);
        return verificar(todas).stream().filter(c -> c.a().equals(nueva.nombre()) || c.b().equals(nueva.nombre())).toList();
    }
}
```

### 2.3 Inventario de VCN con el SDK
Una VCN puede tener **varios bloques CIDR**: cada uno cuenta. Si el inventario falla, se lanza la excepción: **no se debe decir «sin solapes» con datos incompletos**.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.requests.ListVcnsRequest;

public final class ConectividadOci {

    private final VirtualNetworkClient cliente;
    private final String compartimento;
    private final List<RedConocida> onPremises;

    public ConectividadOci(VirtualNetworkClient cliente, String compartimento, List<RedConocida> onPremises) {
        this.cliente = cliente;
        this.compartimento = compartimento;
        this.onPremises = onPremises;
    }

    public List<RedConocida> redes() {
        var redes = new ArrayList<RedConocida>(onPremises);
        var peticion = ListVcnsRequest.builder().compartmentId(compartimento).build();
        for (var vcn : cliente.getPaginators().listVcnsRecordIterator(peticion)) {
            int n = 0;
            for (String cidr : vcn.getCidrBlocks()) {
                redes.add(new RedConocida(vcn.getDisplayName() + (vcn.getCidrBlocks().size() > 1 ? "#" + (++n) : ""), cidr));
            }
        }
        return redes;
    }

    public List<Conflicto> conflictos() {
        return VerificadorDeSolapes.verificar(redes());
    }

    public List<Conflicto> puedeConectar(String nombre, String cidr) {
        return VerificadorDeSolapes.candidata(new RedConocida(nombre, cidr), redes());
    }

    public static List<RedConocida> desdeLista(String csv) {
        var l = new ArrayList<RedConocida>();
        int i = 1;
        for (String c : csv.split(",")) {
            if (!c.isBlank()) {
                l.add(new RedConocida("on-premises-" + i++, c.trim()));
            }
        }
        return l;
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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ConectividadConfiguracion {

    @Bean(destroyMethod = "close")
    VirtualNetworkClient redCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ConectividadOci conectividad(VirtualNetworkClient cliente, @Value("${oci.compartimento-red}") String compartimento,
                                 @Value("${oci.on-premises:}") String onPremises) {
        return new ConectividadOci(cliente, compartimento, ConectividadOci.desdeLista(onPremises));
    }
}

@RestController
@RequestMapping("/red/conectividad")
class ConectividadControlador {

    private final ConectividadOci s;

    ConectividadControlador(ConectividadOci s) {
        this.s = s;
    }

    @GetMapping("/conflictos")
    List<Conflicto> conflictos() {
        return s.conflictos();
    }

    @GetMapping("/candidata")
    List<Conflicto> puedeConectar(@RequestParam String nombre, @RequestParam String cidr) {
        return s.puedeConectar(nombre, cidr);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/conectividad")
class ConectividadReactivoControlador {

    private final ConectividadOci s;

    ConectividadReactivoControlador(ConectividadOci s) {
        this.s = s;
    }

    @GetMapping("/conflictos")
    Mono<List<Conflicto>> conflictos() {
        return Mono.fromCallable(() -> s.conflictos()).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/candidata")
    Mono<List<Conflicto>> puedeConectar(@RequestParam String nombre, @RequestParam String cidr) {
        return Mono.fromCallable(() -> s.puedeConectar(nombre, cidr)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ConectividadProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "oci.compartimento-red")
    String compartimento;

    @ConfigProperty(name = "oci.on-premises")
    String onPremises;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ConectividadOci conectividad() {
        var cliente = VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ConectividadOci(cliente, compartimento, ConectividadOci.desdeLista(onPremises));
    }
}

@Path("/red/conectividad")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ConectividadRecurso {

    @Inject
    ConectividadOci s;

    @GET
    @Path("/conflictos")
    public List<Conflicto> conflictos() {
        return s.conflictos();
    }

    @GET
    @Path("/candidata")
    public List<Conflicto> puedeConectar(@QueryParam("nombre") String nombre, @QueryParam("cidr") String cidr) {
        return s.puedeConectar(nombre, cidr);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/red/conectividad")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ConectividadRecursoReactivo {

    @Inject
    ConectividadOci s;

    @GET
    @Path("/conflictos")
    public Uni<List<Conflicto>> conflictos() {
        return Uni.createFrom().item(() -> s.conflictos()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/candidata")
    public Uni<List<Conflicto>> puedeConectar(@QueryParam("nombre") String nombre, @QueryParam("cidr") String cidr) {
        return Uni.createFrom().item(() -> s.puedeConectar(nombre, cidr)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `ListVcns` | `Allow dynamic-group auditor-red to inspect vcns in compartment red` |
| Crear adjuntos/DRG | Solo el pipeline de red: `manage drgs`, `manage drg-attachments` |

## 8. Qué NO hacer desde Java
- No digas «sin solapes» si el inventario falló o incluye pocos compartimentos: revisa **todos** los compartimentos de red.
- No olvides los CIDR secundarios de cada VCN ni las redes on-premises.
- No conectes automáticamente: el verificador **informa**, la creación pasa por Terraform y revisión.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
