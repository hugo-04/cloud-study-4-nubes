# AWS · EKS · Uso desde Java

Dos usos: **(1)** tu aplicación **dentro de un pod** (JVM en contenedor, probes, apagado ordenado, saber con qué identidad AWS corre) y **(2)** **auditar el clúster desde Java** con el SDK (versión, grupos de nodos, add-ons). Para operar *dentro* de Kubernetes (crear Deployments, leer pods) se usa el cliente de Kubernetes del proyecto (fabric8 u oficial) o `kubectl`/GitOps; aquí cubrimos la API de **AWS** de EKS. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. La aplicación dentro del pod

```yaml
# Spring Boot (application.yml)
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 45s       # < terminationGracePeriodSeconds (60) menos el preStop (10)
management:
  endpoint:
    health:
      probes:
        enabled: true                     # se activa solo en Kubernetes; explícito es más claro
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
```
```properties
# Quarkus (application.properties)
quarkus.shutdown.timeout=45S
quarkus.kubernetes.readiness-probe.http-action-port=8080
```
Regla de tiempos: `preStop (10 s) + apagado de la app (45 s) ≤ terminationGracePeriodSeconds (60 s)`. Probes: **startup** para el arranque lento de Java, **readiness** para el tráfico, **liveness** solo para colgados reales.

## 2. Núcleo común: auditoría del clúster e identidad del pod

Reglas **puras** (se prueban sin AWS) + un lector del SDK. La identidad del pod se deduce de las variables de entorno que inyecta EKS.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.eks.EksClient;
import software.amazon.awssdk.services.eks.model.Addon;
import software.amazon.awssdk.services.eks.model.DescribeAddonRequest;
import software.amazon.awssdk.services.eks.model.DescribeClusterRequest;
import software.amazon.awssdk.services.eks.model.DescribeNodegroupRequest;
import software.amazon.awssdk.services.eks.model.ListAddonsRequest;
import software.amazon.awssdk.services.eks.model.ListNodegroupsRequest;
import software.amazon.awssdk.services.eks.model.Nodegroup;

record GrupoNodos(String nombre, String estado, String version, List<String> problemas) {}

record ComplementoEks(String nombre, String version, String estado, List<String> problemas) {}

record ResumenCluster(String nombre, String estado, String version, List<GrupoNodos> grupos,
                      List<ComplementoEks> complementos) {}

record Hallazgo(String severidad, String mensaje) {}

final class AuditoriaEks {
    private AuditoriaEks() {}

    /** "1.34" -> 34; formato inesperado -> -1 */
    static int menor(String version) {
        if (version == null) return -1;
        String[] p = version.split("\\.");
        if (p.length < 2) return -1;
        try {
            return Integer.parseInt(p[1].replaceAll("\\D.*$", ""));
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /** Reglas puras. versionMinimaSoportada: la menor versión menor que tu política acepta (p. ej. 32). */
    static List<Hallazgo> auditar(ResumenCluster c, int versionMinimaSoportada) {
        List<Hallazgo> r = new ArrayList<>();
        if (!"ACTIVE".equals(c.estado())) {
            r.add(new Hallazgo("ALTA", "El clúster está en estado " + c.estado()));
        }
        int vc = menor(c.version());
        if (vc >= 0 && vc < versionMinimaSoportada) {
            r.add(new Hallazgo("ALTA", "Versión " + c.version() + " por debajo de la mínima aceptada (1."
                    + versionMinimaSoportada + "): riesgo de soporte extendido o fin de soporte"));
        }
        for (GrupoNodos g : c.grupos()) {
            if (!"ACTIVE".equals(g.estado())) {
                r.add(new Hallazgo("ALTA", "Grupo de nodos " + g.nombre() + " en estado " + g.estado()));
            }
            int vg = menor(g.version());
            if (vc >= 0 && vg >= 0 && vc - vg > 0) {
                r.add(new Hallazgo(vc - vg >= 2 ? "ALTA" : "MEDIA", "Grupo " + g.nombre() + " va " + (vc - vg)
                        + " versión(es) menor(es) detrás del plano de control"));
            }
            g.problemas().forEach(p -> r.add(new Hallazgo("ALTA", "Grupo " + g.nombre() + ": " + p)));
        }
        for (ComplementoEks a : c.complementos()) {
            if (!"ACTIVE".equals(a.estado())) {
                r.add(new Hallazgo("MEDIA", "Add-on " + a.nombre() + " en estado " + a.estado()));
            }
            a.problemas().forEach(p -> r.add(new Hallazgo("MEDIA", "Add-on " + a.nombre() + ": " + p)));
        }
        return r;
    }

    /** ¿Con qué identidad AWS corre este pod? Sirve de pista rápida cuando hay AccessDenied. */
    static String identidadDelPod(Map<String, String> env) {
        if (env.containsKey("AWS_CONTAINER_CREDENTIALS_FULL_URI")) return "PodIdentity";
        if (env.containsKey("AWS_WEB_IDENTITY_TOKEN_FILE") && env.containsKey("AWS_ROLE_ARN")) return "IRSA";
        return "Rol del nodo u otra fuente (revisa: puede dar más permisos de los previstos)";
    }
}

final class LectorEks {
    private final EksClient eks;

    LectorEks(EksClient eks) {
        this.eks = eks;
    }

    ResumenCluster leer(String cluster) {
        var c = eks.describeCluster(DescribeClusterRequest.builder().name(cluster).build()).cluster();
        List<GrupoNodos> grupos = new ArrayList<>();
        for (String ng : eks.listNodegroupsPaginator(ListNodegroupsRequest.builder().clusterName(cluster).build())
                .nodegroups()) {
            Nodegroup n = eks.describeNodegroup(DescribeNodegroupRequest.builder()
                    .clusterName(cluster).nodegroupName(ng).build()).nodegroup();
            List<String> problemas = n.health() == null ? List.of() : n.health().issues().stream()
                    .map(i -> i.codeAsString() + ": " + i.message()).toList();
            grupos.add(new GrupoNodos(n.nodegroupName(), n.statusAsString(), n.version(), problemas));
        }
        List<ComplementoEks> complementos = new ArrayList<>();
        for (String nombre : eks.listAddonsPaginator(ListAddonsRequest.builder().clusterName(cluster).build())
                .addons()) {
            Addon a = eks.describeAddon(DescribeAddonRequest.builder()
                    .clusterName(cluster).addonName(nombre).build()).addon();
            List<String> problemas = a.health() == null ? List.of() : a.health().issues().stream()
                    .map(i -> i.codeAsString() + ": " + i.message()).toList();
            complementos.add(new ComplementoEks(a.addonName(), a.addonVersion(), a.statusAsString(), problemas));
        }
        return new ResumenCluster(c.name(), c.statusAsString(), c.version(), grupos, complementos);
    }
}
```

### Spring MVC (imperativo)
```java
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.eks.EksClient;

@Configuration
class EksConfig {
    @Bean(destroyMethod = "close")
    EksClient eks() {
        return EksClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    LectorEks lectorEks(EksClient eks) {
        return new LectorEks(eks);
    }
}

@RestController
class EksController {
    private final LectorEks lector;
    private final String cluster;
    private final int versionMinima;

    EksController(LectorEks lector, @Value("${eks.cluster:prod-tienda}") String cluster,
                  @Value("${eks.version-minima:32}") int versionMinima) {
        this.lector = lector;
        this.cluster = cluster;
        this.versionMinima = versionMinima;
    }

    @GetMapping("/interno/eks/auditoria")
    List<Hallazgo> auditoria() {
        return AuditoriaEks.auditar(lector.leer(cluster), versionMinima);
    }

    /** Útil para diagnosticar AccessDenied: ¿Pod Identity, IRSA o el rol del nodo? */
    @GetMapping("/interno/eks/identidad")
    Map<String, String> identidad() {
        return Map.of("fuente", AuditoriaEks.identidadDelPod(System.getenv()),
                "pod", System.getenv().getOrDefault("POD_NAME", "?"),
                "nodo", System.getenv().getOrDefault("NODE_NAME", "?"));
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class EksReactivoController {
    private final LectorEks lector;

    EksReactivoController(LectorEks lector) {
        this.lector = lector;
    }

    @GetMapping("/interno/eks/auditoria")
    Mono<List<Hallazgo>> auditoria() {
        return Mono.fromCallable(() -> AuditoriaEks.auditar(lector.leer("prod-tienda"), 32))
                .subscribeOn(Schedulers.boundedElastic());
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.eks.EksClient;

@Singleton
class EksProductores {
    @Produces
    @Singleton
    EksClient eks() {
        return EksClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    void cerrar(@Disposes EksClient eks) {
        eks.close();
    }

    @Produces
    @Singleton
    LectorEks lector(EksClient eks) {
        return new LectorEks(eks);
    }
}

@Path("/interno/eks")
class EksRecurso {
    @Inject
    LectorEks lector;

    @ConfigProperty(name = "eks.cluster", defaultValue = "prod-tienda")
    String cluster;

    @GET
    @Path("/auditoria")
    @jakarta.ws.rs.Produces("application/json")
    List<Hallazgo> auditoria() {
        return AuditoriaEks.auditar(lector.leer(cluster), 32);
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
import java.util.List;

@Path("/interno/eks-reactivo")
class EksReactivoRecurso {
    @Inject
    LectorEks lector;

    @GET
    @Path("/auditoria")
    @jakarta.ws.rs.Produces("application/json")
    Uni<List<Hallazgo>> auditoria() {
        return Uni.createFrom().item(() -> AuditoriaEks.auditar(lector.leer("prod-tienda"), 32))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 3. Permisos de este código
`eks:DescribeCluster`, `eks:ListNodegroups`, `eks:DescribeNodegroup`, `eks:ListAddons`, `eks:DescribeAddon`: **solo lectura**. Dálos al rol de la herramienta de auditoría (Pod Identity), no al rol del servicio de negocio.

## 4. Qué NO hacer desde Java
- ❌ Llamar a `describe*` por petición: cachea el resultado unos minutos (cuotas bajas).
- ❌ Dejar `/interno/**` sin autenticación ni `NetworkPolicy`.
- ❌ Usar el SDK para «gestionar» el clúster que ya gestionas con Terraform/GitOps (dos fuentes de verdad).
- ❌ Heredar credenciales del nodo: usa Pod Identity/IRSA y verifica con `/interno/eks/identidad`.
- ❌ Fijar `MaxRAMPercentage` al 100 %: deja espacio para metaspace, hilos y buffers.
