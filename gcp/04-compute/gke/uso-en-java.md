# Google Cloud · Compute · GKE · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **auditor de clústeres**: lista todos los clústeres del proyecto (`ClusterManagerClient.listClusters` con ubicación `-`) y marca los que no tienen canal de lanzamiento, tienen nodos públicos o plano de control abierto, no tienen Workload Identity o tienen node pools dos o más versiones menores por detrás del plano de control.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
```

## 2. Núcleo común

### 2.1 Credenciales según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ImpersonatedCredentials;
import java.io.IOException;
import java.util.List;

public final class Credenciales {

    private static final List<String> ALCANCE = List.of("https://www.googleapis.com/auth/cloud-platform");

    private Credenciales() { }

    /**
     * ADC (Application Default Credentials): en la laptop, «gcloud auth application-default login»;
     * en GKE, Cloud Run, Functions o Compute Engine, la cuenta de servicio adjunta (sin llaves).
     * suplantar = correo de una cuenta de servicio para actuar como ella, o "ninguna".
     */
    public static GoogleCredentials crear(String suplantar) {
        try {
            var base = GoogleCredentials.getApplicationDefault().createScoped(ALCANCE);
            if (suplantar == null || suplantar.isBlank() || "ninguna".equals(suplantar)) {
                return base;
            }
            return ImpersonatedCredentials.create(base, suplantar, null, ALCANCE, 3600);
        } catch (IOException e) {
            throw new IllegalStateException("no hay credenciales ADC disponibles", e);
        }
    }
}
```

### 2.2 Auditor (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

/** Audita clústeres de GKE: canal, nodos privados, endpoint, Workload Identity y desfase de versión. Puro. */
public class AuditorDeClusteres {

    public record Cluster(String nombre, String ubicacion, String versionControl, List<String> versionesNodos, String canal,
                          boolean autopilot, boolean nodosPrivados, boolean endpointPrivado, boolean redesAutorizadas,
                          boolean workloadIdentity) { }

    public record Hallazgo(String cluster, String severidad, String mensaje) { }

    public List<Hallazgo> auditar(List<Cluster> clusteres) {
        var h = new ArrayList<Hallazgo>();
        for (Cluster c : clusteres) {
            if (c.canal() == null || c.canal().isBlank() || c.canal().equals("UNSPECIFIED")) {
                h.add(new Hallazgo(c.nombre(), "MEDIA", "sin canal de lanzamiento"));
            }
            if (!c.nodosPrivados()) {
                h.add(new Hallazgo(c.nombre(), "ALTA", "nodos con IP pública"));
            }
            if (!c.endpointPrivado() && !c.redesAutorizadas()) {
                h.add(new Hallazgo(c.nombre(), "ALTA", "plano de control accesible desde cualquier IP"));
            }
            if (!c.workloadIdentity()) {
                h.add(new Hallazgo(c.nombre(), "ALTA", "sin Workload Identity"));
            }
            for (String v : c.versionesNodos()) {
                int d = desfaseMenor(c.versionControl(), v);
                if (d >= 2) {
                    h.add(new Hallazgo(c.nombre(), "MEDIA", "node pool " + v + " va " + d + " versiones menores atrás"));
                }
            }
        }
        return h;
    }

    /** «1.31.4-gke.100» vs «1.29.8-gke.1» → 2. */
    static int desfaseMenor(String control, String nodo) {
        return menor(control) - menor(nodo);
    }

    private static int menor(String v) {
        String[] p = v.split("[.-]");
        return p.length > 1 ? Integer.parseInt(p[1]) : 0;
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.container.v1.ClusterManagerClient;
import com.google.cloud.container.v1.ClusterManagerSettings;
import com.google.container.v1.NodePool;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador: clústeres de todas las ubicaciones del proyecto. */
public class ClusteresGcp implements AutoCloseable {

    private final ClusterManagerClient cliente;
    private final String proyecto;

    public ClusteresGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = ClusterManagerClient.create(ClusterManagerSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeClusteres.Cluster> todos() {
        return cliente.listClusters("projects/" + proyecto + "/locations/-").getClustersList().stream()
            .map(c -> new AuditorDeClusteres.Cluster(c.getName(), c.getLocation(), c.getCurrentMasterVersion(),
                c.getNodePoolsList().stream().map(NodePool::getVersion).toList(),
                c.hasReleaseChannel() ? c.getReleaseChannel().getChannel().name() : null,
                c.hasAutopilot() && c.getAutopilot().getEnabled(),
                c.getPrivateClusterConfig().getEnablePrivateNodes() || c.getNetworkConfig().getDefaultEnablePrivateNodes(),
                c.getPrivateClusterConfig().getEnablePrivateEndpoint(),
                c.getMasterAuthorizedNetworksConfig().getEnabled(),
                !c.getWorkloadIdentityConfig().getWorkloadPool().isBlank()))
            .toList();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public class ServicioDeClusteres {

    private final ClusteresGcp gke;
    private final AuditorDeClusteres auditor = new AuditorDeClusteres();

    public ServicioDeClusteres(ClusteresGcp gke) {
        this.gke = gke;
    }

    public List<AuditorDeClusteres.Hallazgo> auditar() {
        return auditor.auditar(gke.todos());
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ClusteresConfiguracion {

    @Bean(destroyMethod = "close")
    ClusteresGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ClusteresGcp(cred, proyecto);
    }

    @Bean
    ServicioDeClusteres servicio(ClusteresGcp a) {
        return new ServicioDeClusteres(a);
    }
}

@RestController
@RequestMapping("/compute/gke")
class ClusteresControlador {

    private final ServicioDeClusteres s;

    ClusteresControlador(ServicioDeClusteres s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeClusteres.Hallazgo> auditar() {
        return s.auditar();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/compute/gke")
class ClusteresReactivoControlador {

    private final ServicioDeClusteres s;

    ClusteresReactivoControlador(ServicioDeClusteres s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeClusteres.Hallazgo>> auditar() {
        return Mono.fromCallable(() -> s.auditar()).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.google.auth.oauth2.GoogleCredentials;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ClusteresProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ClusteresGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ClusteresGcp(cred, proyecto);
    }

    void cerrar(@Disposes ClusteresGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeClusteres servicio(ClusteresGcp a) {
        return new ServicioDeClusteres(a);
    }
}

@Path("/compute/gke")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ClusteresRecurso {

    @Inject
    ServicioDeClusteres s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeClusteres.Hallazgo> auditar() {
        return s.auditar();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/compute/gke")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ClusteresRecursoReactivo {

    @Inject
    ServicioDeClusteres s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeClusteres.Hallazgo>> auditar() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar clústeres | `roles/container.clusterViewer` |

## 8. Qué NO hacer desde Java
- No uses la API de GKE para desplegar apps: eso es Kubernetes (manifiestos o GitOps).
- No guardes credenciales de kubeconfig en la app.
- No ignores el desfase de versiones: los nodos viejos quedan sin soporte.
