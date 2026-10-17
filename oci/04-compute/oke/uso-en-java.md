# Oracle OCI · Compute · OKE · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **auditor de versiones**: compara la versión de Kubernetes del plano de control con la de cada node pool (¿más nuevo que el plano? ¿demasiado atrás? ¿versión fuera de soporte?) leyendo los datos reales con `ContainerEngineClient`. La lógica es pura y se prueba sin red.

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

### 2.2 Versión de Kubernetes
```java
// (clase reutilizada en los bloques siguientes, ambos)
/** Versión de Kubernetes: v1.31.1 → (1, 31, 1). */
public record VersionK8s(int mayor, int menor, int parche) implements Comparable<VersionK8s> {

    public static VersionK8s analizar(String texto) {
        String t = texto.strip();
        if (t.startsWith("v") || t.startsWith("V")) {
            t = t.substring(1);
        }
        String[] p = t.split("\\.");
        if (p.length < 2 || p.length > 3) {
            throw new IllegalArgumentException("versión no reconocida: " + texto);
        }
        return new VersionK8s(Integer.parseInt(p[0]), Integer.parseInt(p[1]), p.length == 3 ? Integer.parseInt(p[2]) : 0);
    }

    @Override
    public int compareTo(VersionK8s o) {
        int c = Integer.compare(mayor, o.mayor);
        if (c == 0) {
            c = Integer.compare(menor, o.menor);
        }
        return c == 0 ? Integer.compare(parche, o.parche) : c;
    }

    /** Distancia en versiones menores (positiva si esta es más nueva que la otra). */
    public int menoresSobre(VersionK8s otra) {
        return (mayor - otra.mayor) * 1000 + (menor - otra.menor);
    }

    @Override
    public String toString() {
        return "v" + mayor + "." + menor + "." + parche;
    }
}
```

### 2.3 Auditor de versiones
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Reglas de versiones entre el plano de control y sus node pools. Puro. */
public final class AuditorDeVersiones {

    public record Pool(String nombre, String version) { }

    public record Cluster(String nombre, String version, List<Pool> pools) { }

    public record Hallazgo(String cluster, String pool, String motivo) { }

    private final Set<VersionK8s> soportadas;
    private final int maxAtraso;

    /** soportadas: versiones menores vigentes (el parche no importa); maxAtraso: menores permitidos de diferencia. */
    public AuditorDeVersiones(Set<VersionK8s> soportadas, int maxAtraso) {
        this.soportadas = soportadas;
        this.maxAtraso = maxAtraso;
    }

    public List<Hallazgo> revisar(List<Cluster> clusters) {
        var salida = new ArrayList<Hallazgo>();
        for (Cluster c : clusters) {
            VersionK8s plano = VersionK8s.analizar(c.version());
            if (soportadas.stream().noneMatch(s -> s.mayor() == plano.mayor() && s.menor() == plano.menor())) {
                salida.add(new Hallazgo(c.nombre(), "(plano)", "versión " + plano + " fuera de las versiones soportadas"));
            }
            for (Pool p : c.pools()) {
                VersionK8s v = VersionK8s.analizar(p.version());
                int adelanto = v.menoresSobre(plano);
                if (adelanto > 0) {
                    salida.add(new Hallazgo(c.nombre(), p.nombre(), "el pool " + v + " es más nuevo que el plano " + plano));
                } else if (-adelanto > maxAtraso) {
                    salida.add(new Hallazgo(c.nombre(), p.nombre(), "el pool " + v + " va " + (-adelanto) + " versiones menores detrás del plano " + plano));
                }
            }
        }
        return salida;
    }
}
```

### 2.4 Lectura con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.containerengine.ContainerEngineClient;
import com.oracle.bmc.containerengine.model.ClusterSummary;
import com.oracle.bmc.containerengine.model.NodePoolSummary;
import com.oracle.bmc.containerengine.requests.ListClustersRequest;
import com.oracle.bmc.containerengine.requests.ListNodePoolsRequest;
import java.util.ArrayList;
import java.util.List;

/** Lee clústeres y node pools con paginación del SDK. */
public class ClustersOci {

    private final ContainerEngineClient cliente;

    public ClustersOci(ContainerEngineClient cliente) {
        this.cliente = cliente;
    }

    public List<AuditorDeVersiones.Cluster> todos(String compartimentoId) {
        var salida = new ArrayList<AuditorDeVersiones.Cluster>();
        var req = ListClustersRequest.builder().compartmentId(compartimentoId).build();
        for (ClusterSummary c : cliente.getPaginators().listClustersRecordIterator(req)) {
            var pools = new ArrayList<AuditorDeVersiones.Pool>();
            var rp = ListNodePoolsRequest.builder().compartmentId(compartimentoId).clusterId(c.getId()).build();
            for (NodePoolSummary p : cliente.getPaginators().listNodePoolsRecordIterator(rp)) {
                pools.add(new AuditorDeVersiones.Pool(p.getName(), p.getKubernetesVersion()));
            }
            salida.add(new AuditorDeVersiones.Cluster(c.getName(), c.getKubernetesVersion(), pools));
        }
        return salida;
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public class ServicioDeClusters {

    private final ClustersOci clusters;
    private final AuditorDeVersiones auditor;

    public ServicioDeClusters(ClustersOci clusters, AuditorDeVersiones auditor) {
        this.clusters = clusters;
        this.auditor = auditor;
    }

    public List<AuditorDeVersiones.Hallazgo> auditar(String compartimentoId) {
        return auditor.revisar(clusters.todos(compartimentoId));
    }

    public List<AuditorDeVersiones.Hallazgo> auditarLista(List<AuditorDeVersiones.Cluster> lista) {
        return auditor.revisar(lista);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.containerengine.ContainerEngineClient;
import java.util.List;
import java.util.Set;
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
class ClustersConfiguracion {

    @Bean(destroyMethod = "close")
    ContainerEngineClient okeCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return ContainerEngineClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDeClusters servicioDeClusters(ContainerEngineClient cliente) {
        var soportadas = Set.of(VersionK8s.analizar("v1.31.0"), VersionK8s.analizar("v1.32.0"), VersionK8s.analizar("v1.33.0")); // verifica las vigentes
        return new ServicioDeClusters(new ClustersOci(cliente), new AuditorDeVersiones(soportadas, 2));
    }
}

@RestController
@RequestMapping("/compute/oke")
class ClustersControlador {

    private final ServicioDeClusters s;

    ClustersControlador(ServicioDeClusters s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeVersiones.Hallazgo> auditoria(@RequestParam String compartimento) {
        return s.auditar(compartimento);
    }

    @PostMapping("/revisar")
    List<AuditorDeVersiones.Hallazgo> revisar(@RequestBody List<AuditorDeVersiones.Cluster> clusters) {
        return s.auditarLista(clusters);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.containerengine.ContainerEngineClient;
import java.util.List;
import java.util.Set;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/compute/oke")
class ClustersReactivoControlador {

    private final ServicioDeClusters s;

    ClustersReactivoControlador(ServicioDeClusters s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeVersiones.Hallazgo>> auditoria(@RequestParam String compartimento) {
        return Mono.fromCallable(() -> s.auditar(compartimento)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/revisar")
    Mono<List<AuditorDeVersiones.Hallazgo>> revisar(@RequestBody List<AuditorDeVersiones.Cluster> clusters) {
        return Mono.fromCallable(() -> s.auditarLista(clusters));
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.containerengine.ContainerEngineClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.Set;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ClustersProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeClusters servicioDeClusters() {
        var cliente = ContainerEngineClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        var soportadas = Set.of(VersionK8s.analizar("v1.31.0"), VersionK8s.analizar("v1.32.0"), VersionK8s.analizar("v1.33.0")); // verifica las vigentes
        return new ServicioDeClusters(new ClustersOci(cliente), new AuditorDeVersiones(soportadas, 2));
    }
}

@Path("/compute/oke")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ClustersRecurso {

    @Inject
    ServicioDeClusters s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeVersiones.Hallazgo> auditoria(@QueryParam("compartimento") String compartimento) {
        return s.auditar(compartimento);
    }

    @POST
    @Path("/revisar")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<AuditorDeVersiones.Hallazgo> revisar(List<AuditorDeVersiones.Cluster> clusters) {
        return s.auditarLista(clusters);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.containerengine.ContainerEngineClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import java.util.Set;

@Path("/reactivo/compute/oke")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ClustersRecursoReactivo {

    @Inject
    ServicioDeClusters s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeVersiones.Hallazgo>> auditoria(@QueryParam("compartimento") String compartimento) {
        return Uni.createFrom().item(() -> s.auditar(compartimento)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/revisar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<AuditorDeVersiones.Hallazgo>> revisar(List<AuditorDeVersiones.Cluster> clusters) {
        return Uni.createFrom().item(() -> s.auditarLista(clusters));
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `ListClusters`, `ListNodePools` | `Allow dynamic-group auditor-oke to inspect cluster-family in compartment tienda-prod` |

## 8. Qué NO hacer desde Java
- No codifiques la lista de versiones soportadas «para siempre»: léela de configuración y revísala cada trimestre.
- No uses este servicio para actualizar clústeres: solo informa; las actualizaciones van por Terraform y ventana de cambio.
- No expongas el listado de clústeres a Internet.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
