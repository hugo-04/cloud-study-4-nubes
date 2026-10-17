# Oracle OCI · Caso integrado · Landing zone · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

El **planificador de direcciones** de la landing zone: recorre todos los compartimentos y lee los CIDR de cada VCN (`IdentityClient` + `VirtualNetworkClient.listVcns`, paginando), suma las redes locales conectadas y propone el primer /16 libre de `10.0.0.0/8`; el verificador reporta solapes existentes. La propuesta alimenta `cidr_unidad` del Terraform del caso.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
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

### 2.2 Planificador de CIDR (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/** Planificador de direcciones: propone el primer bloque libre del tamaño pedido dentro de un rango. Puro. */
public class PlanificadorDeCidr {

    public record Bloque(long inicio, int prefijo) {
        public long fin() {
            return inicio + (1L << (32 - prefijo)) - 1;
        }

        public boolean solapa(Bloque o) {
            return inicio <= o.fin() && o.inicio() <= fin();
        }

        public static Bloque de(String cidr) {
            String[] p = cidr.split("/");
            String[] o = p[0].split("\\.");
            if (o.length != 4) {
                throw new IllegalArgumentException("CIDR inválido: " + cidr);
            }
            long ip = 0;
            for (String x : o) {
                int v = Integer.parseInt(x);
                if (v < 0 || v > 255) {
                    throw new IllegalArgumentException("CIDR inválido: " + cidr);
                }
                ip = (ip << 8) | v;
            }
            int pre = Integer.parseInt(p[1]);
            long mascara = pre == 0 ? 0 : (0xFFFFFFFFL << (32 - pre)) & 0xFFFFFFFFL;
            return new Bloque(ip & mascara, pre);
        }

        @Override
        public String toString() {
            return ((inicio >> 24) & 255) + "." + ((inicio >> 16) & 255) + "." + ((inicio >> 8) & 255) + "." + (inicio & 255) + "/" + prefijo;
        }
    }

    public Optional<String> proponer(String rangoPadre, int prefijo, List<String> ocupados) {
        Bloque padre = Bloque.de(rangoPadre);
        if (prefijo < padre.prefijo() || prefijo > 28) {
            throw new IllegalArgumentException("prefijo fuera de rango");
        }
        List<Bloque> usados = new ArrayList<>(ocupados.stream().map(Bloque::de).toList());
        long paso = 1L << (32 - prefijo);
        for (long ini = padre.inicio(); ini + paso - 1 <= padre.fin(); ini += paso) {
            Bloque candidato = new Bloque(ini, prefijo);
            if (usados.stream().noneMatch(candidato::solapa)) {
                return Optional.of(candidato.toString());
            }
        }
        return Optional.empty();
    }

    /** Pares solapados entre los rangos dados (para el verificador). */
    public List<String> solapes(List<String> cidrs) {
        var out = new ArrayList<String>();
        for (int i = 0; i < cidrs.size(); i++) {
            for (int j = i + 1; j < cidrs.size(); j++) {
                if (Bloque.de(cidrs.get(i)).solapa(Bloque.de(cidrs.get(j)))) {
                    out.add(cidrs.get(i) + " ∩ " + cidrs.get(j));
                }
            }
        }
        return out;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.requests.ListVcnsRequest;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.requests.ListCompartmentsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: todos los CIDR de VCN del tenancy (recorre compartimentos). */
public class RedesOci implements AutoCloseable {

    private final VirtualNetworkClient red;
    private final IdentityClient identidad;

    public RedesOci(VirtualNetworkClient red, IdentityClient identidad) {
        this.red = red;
        this.identidad = identidad;
    }

    public List<String> cidrsEnUso(String tenancyId) {
        var compartimentos = new ArrayList<String>(List.of(tenancyId));
        String pagina = null;
        do {
            var r = identidad.listCompartments(ListCompartmentsRequest.builder().compartmentId(tenancyId)
                .compartmentIdInSubtree(true).accessLevel(ListCompartmentsRequest.AccessLevel.Accessible).page(pagina).build());
            r.getItems().forEach(c -> compartimentos.add(c.getId()));
            pagina = r.getOpcNextPage();
        } while (pagina != null);
        var cidrs = new ArrayList<String>();
        for (String c : compartimentos) {
            String p = null;
            do {
                var r = red.listVcns(ListVcnsRequest.builder().compartmentId(c).page(p).build());
                r.getItems().forEach(v -> cidrs.addAll(v.getCidrBlocks()));
                p = r.getOpcNextPage();
            } while (p != null);
        }
        return cidrs;
    }

    @Override
    public void close() {
        red.close();
        identidad.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

public class ServicioDeLandingZone {

    public record Propuesta(String cidr, List<String> enUso) { }

    private final RedesOci redes;
    private final PlanificadorDeCidr planificador = new PlanificadorDeCidr();

    public ServicioDeLandingZone(RedesOci redes) {
        this.redes = redes;
    }

    /** redesLocales: rangos de oficinas o centros de datos conectados (no visibles como VCN). */
    public Propuesta proponer(String tenancyId, List<String> redesLocales) {
        var enUso = new ArrayList<>(redes.cidrsEnUso(tenancyId));
        enUso.addAll(redesLocales);
        String cidr = planificador.proponer("10.0.0.0/8", 16, enUso)
            .orElseThrow(() -> new IllegalStateException("no quedan /16 libres en 10.0.0.0/8"));
        return new Propuesta(cidr, enUso);
    }

    public List<String> verificarSolapes(String tenancyId) {
        return planificador.solapes(redes.cidrsEnUso(tenancyId));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class LandingZoneConfiguracion {

    @Bean(destroyMethod = "close")
    RedesOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        var r = Region.fromRegionId(region);
        return new RedesOci(VirtualNetworkClient.builder().region(r).build(auth), IdentityClient.builder().region(r).build(auth));
    }

    @Bean
    ServicioDeLandingZone servicio(RedesOci a) {
        return new ServicioDeLandingZone(a);
    }
}

@RestController
@RequestMapping("/casos/landing")
class LandingZoneControlador {

    private final ServicioDeLandingZone s;

    LandingZoneControlador(ServicioDeLandingZone s) {
        this.s = s;
    }

    @PostMapping("/cidr")
    ServicioDeLandingZone.Propuesta proponer(@RequestParam String tenancy, @RequestBody List<String> locales) {
        return s.proponer(tenancy, locales);
    }

    @GetMapping("/solapes")
    List<String> solapes(@RequestParam String tenancy) {
        return s.verificarSolapes(tenancy);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.identity.IdentityClient;
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
@RequestMapping("/reactivo/casos/landing")
class LandingZoneReactivoControlador {

    private final ServicioDeLandingZone s;

    LandingZoneReactivoControlador(ServicioDeLandingZone s) {
        this.s = s;
    }

    @PostMapping("/cidr")
    Mono<ServicioDeLandingZone.Propuesta> proponer(@RequestParam String tenancy, @RequestBody List<String> locales) {
        return Mono.fromCallable(() -> s.proponer(tenancy, locales)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/solapes")
    Mono<List<String>> solapes(@RequestParam String tenancy) {
        return Mono.fromCallable(() -> s.verificarSolapes(tenancy)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.identity.IdentityClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class LandingZoneProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    RedesOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        var r = Region.fromRegionId(region);
        return new RedesOci(VirtualNetworkClient.builder().region(r).build(auth), IdentityClient.builder().region(r).build(auth));
    }

    void cerrar(@Disposes RedesOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeLandingZone servicio(RedesOci a) {
        return new ServicioDeLandingZone(a);
    }
}

@Path("/casos/landing")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class LandingZoneRecurso {

    @Inject
    ServicioDeLandingZone s;

    @POST
    @Path("/cidr")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeLandingZone.Propuesta proponer(@QueryParam("tenancy") String tenancy, List<String> locales) {
        return s.proponer(tenancy, locales);
    }

    @GET
    @Path("/solapes")
    public List<String> solapes(@QueryParam("tenancy") String tenancy) {
        return s.verificarSolapes(tenancy);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.identity.IdentityClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/casos/landing")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class LandingZoneRecursoReactivo {

    @Inject
    ServicioDeLandingZone s;

    @POST
    @Path("/cidr")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeLandingZone.Propuesta> proponer(@QueryParam("tenancy") String tenancy, List<String> locales) {
        return Uni.createFrom().item(() -> s.proponer(tenancy, locales)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/solapes")
    public Uni<List<String>> solapes(@QueryParam("tenancy") String tenancy) {
        return Uni.createFrom().item(() -> s.verificarSolapes(tenancy)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Listar compartimentos | `Allow dynamic-group plataforma to inspect compartments in tenancy` |
| Listar VCN | `Allow dynamic-group plataforma to read virtual-network-family in tenancy` |

## 8. Qué NO hacer desde Java
- No olvides las redes locales conectadas por VPN/FastConnect: no aparecen como VCN.
- No uses solo la región actual si hay VCN en otras regiones conectadas: consulta cada región.
- No apliques la landing desde la app: la propuesta va al pipeline de Terraform.
