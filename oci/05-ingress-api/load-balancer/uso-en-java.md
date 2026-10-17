# Oracle OCI · Ingress y API · Load Balancer · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **drenado seguro** para despliegues: antes de sacar una réplica, el servicio lee la salud real del backend set y se niega a drenar si quedarían menos réplicas sanas que el mínimo. Luego marca `drain=true` con `LoadBalancerClient.updateBackend`.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
lb:
  id: ocid1.loadbalancer.oc1.sa-saopaulo-1.aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
lb.id=ocid1.loadbalancer.oc1.sa-saopaulo-1.aaaa
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

### 2.2 Plan de drenado (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Decide si es seguro drenar un backend sin dejar el set por debajo del mínimo sano. Puro. */
public class PlanDeDrenado {

    public record Decision(boolean permitido, String motivo, int sanosRestantes) { }

    private final int minimoSanos;

    public PlanDeDrenado(int minimoSanos) {
        this.minimoSanos = minimoSanos;
    }

    /** total: nombres «ip:puerto» del set; noSanos: los que están en warning/critical/unknown; drenados: los que ya drenan. */
    public Decision evaluar(String objetivo, List<String> total, Set<String> noSanos, Set<String> drenados) {
        if (!total.contains(objetivo)) {
            return new Decision(false, "el backend no pertenece al set", 0);
        }
        var sanosActivos = new ArrayList<String>();
        for (String b : total) {
            if (!noSanos.contains(b) && !drenados.contains(b)) {
                sanosActivos.add(b);
            }
        }
        int restantes = sanosActivos.size() - (sanosActivos.contains(objetivo) ? 1 : 0);
        if (restantes < minimoSanos) {
            return new Decision(false, "quedarían " + restantes + " sanos; mínimo " + minimoSanos, restantes);
        }
        return new Decision(true, "ok", restantes);
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import com.oracle.bmc.loadbalancer.model.Backend;
import com.oracle.bmc.loadbalancer.model.UpdateBackendDetails;
import com.oracle.bmc.loadbalancer.requests.GetBackendSetHealthRequest;
import com.oracle.bmc.loadbalancer.requests.ListBackendsRequest;
import com.oracle.bmc.loadbalancer.requests.UpdateBackendRequest;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Adaptador del SDK: lee salud y backends, y aplica el drenado. */
public class BalanceadorOci implements AutoCloseable {

    public record Estado(List<String> total, Set<String> noSanos, Set<String> drenados) { }

    private final LoadBalancerClient cliente;
    private final String lbId;

    public BalanceadorOci(LoadBalancerClient cliente, String lbId) {
        this.cliente = cliente;
        this.lbId = lbId;
    }

    public Estado estado(String backendSet) {
        var salud = cliente.getBackendSetHealth(GetBackendSetHealthRequest.builder()
            .loadBalancerId(lbId).backendSetName(backendSet).build()).getBackendSetHealth();
        var noSanos = new HashSet<String>();
        noSanos.addAll(salud.getWarningStateBackendNames());
        noSanos.addAll(salud.getCriticalStateBackendNames());
        noSanos.addAll(salud.getUnknownStateBackendNames());
        List<Backend> backends = cliente.listBackends(ListBackendsRequest.builder()
            .loadBalancerId(lbId).backendSetName(backendSet).build()).getItems();
        var drenados = new HashSet<String>();
        backends.stream().filter(b -> Boolean.TRUE.equals(b.getDrain())).forEach(b -> drenados.add(b.getName()));
        return new Estado(backends.stream().map(Backend::getName).toList(), noSanos, drenados);
    }

    /** Devuelve el id de la work request (la operación es asíncrona). */
    public String drenar(String backendSet, String backend, boolean drenar) {
        var detalles = UpdateBackendDetails.builder().weight(1).backup(false).offline(false).drain(drenar).build();
        return cliente.updateBackend(UpdateBackendRequest.builder()
            .loadBalancerId(lbId).backendSetName(backendSet).backendName(backend)
            .updateBackendDetails(detalles).build()).getOpcWorkRequestId();
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
public class ServicioDeDrenado {

    public record Resultado(boolean aplicado, String motivo, String workRequest) { }

    private final BalanceadorOci lb;
    private final PlanDeDrenado plan = new PlanDeDrenado(1);

    public ServicioDeDrenado(BalanceadorOci lb) {
        this.lb = lb;
    }

    public Resultado drenar(String backendSet, String backend) {
        var e = lb.estado(backendSet);
        var d = plan.evaluar(backend, e.total(), e.noSanos(), e.drenados());
        if (!d.permitido()) {
            return new Resultado(false, d.motivo(), null);
        }
        return new Resultado(true, "quedan " + d.sanosRestantes() + " sanos", lb.drenar(backendSet, backend, true));
    }

    public Resultado reactivar(String backendSet, String backend) {
        return new Resultado(true, "reactivado", lb.drenar(backendSet, backend, false));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class DrenadoConfiguracion {

    @Bean(destroyMethod = "close")
    BalanceadorOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${lb.id}") String id) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        var cliente = LoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new BalanceadorOci(cliente, id);
    }

    @Bean
    ServicioDeDrenado servicio(BalanceadorOci a) {
        return new ServicioDeDrenado(a);
    }
}

@RestController
@RequestMapping("/ingress/drenado")
class DrenadoControlador {

    private final ServicioDeDrenado s;

    DrenadoControlador(ServicioDeDrenado s) {
        this.s = s;
    }

    @PostMapping("/{set}/{backend}/drenar")
    ServicioDeDrenado.Resultado drenar(@PathVariable String set, @PathVariable String backend) {
        return s.drenar(set, backend);
    }

    @PostMapping("/{set}/{backend}/reactivar")
    ServicioDeDrenado.Resultado reactivar(@PathVariable String set, @PathVariable String backend) {
        return s.reactivar(set, backend);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/drenado")
class DrenadoReactivoControlador {

    private final ServicioDeDrenado s;

    DrenadoReactivoControlador(ServicioDeDrenado s) {
        this.s = s;
    }

    @PostMapping("/{set}/{backend}/drenar")
    Mono<ServicioDeDrenado.Resultado> drenar(@PathVariable String set, @PathVariable String backend) {
        return Mono.fromCallable(() -> s.drenar(set, backend)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/{set}/{backend}/reactivar")
    Mono<ServicioDeDrenado.Resultado> reactivar(@PathVariable String set, @PathVariable String backend) {
        return Mono.fromCallable(() -> s.reactivar(set, backend)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class DrenadoProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "lb.id")
    String id;

    @jakarta.enterprise.inject.Produces
    @Singleton
    BalanceadorOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        var cliente = LoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new BalanceadorOci(cliente, id);
    }

    void cerrar(@Disposes BalanceadorOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeDrenado servicio(BalanceadorOci a) {
        return new ServicioDeDrenado(a);
    }
}

@Path("/ingress/drenado")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class DrenadoRecurso {

    @Inject
    ServicioDeDrenado s;

    @POST
    @Path("/{set}/{backend}/drenar")
    public ServicioDeDrenado.Resultado drenar(@PathParam("set") String set, @PathParam("backend") String backend) {
        return s.drenar(set, backend);
    }

    @POST
    @Path("/{set}/{backend}/reactivar")
    public ServicioDeDrenado.Resultado reactivar(@PathParam("set") String set, @PathParam("backend") String backend) {
        return s.reactivar(set, backend);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/ingress/drenado")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class DrenadoRecursoReactivo {

    @Inject
    ServicioDeDrenado s;

    @POST
    @Path("/{set}/{backend}/drenar")
    public Uni<ServicioDeDrenado.Resultado> drenar(@PathParam("set") String set, @PathParam("backend") String backend) {
        return Uni.createFrom().item(() -> s.drenar(set, backend)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/{set}/{backend}/reactivar")
    public Uni<ServicioDeDrenado.Resultado> reactivar(@PathParam("set") String set, @PathParam("backend") String backend) {
        return Uni.createFrom().item(() -> s.reactivar(set, backend)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer salud y backends | `Allow dynamic-group despliegues to read load-balancers in compartment red-prod` |
| Drenar / reactivar (`updateBackend`) | `Allow dynamic-group despliegues to use load-balancers in compartment red-prod` |

## 8. Qué NO hacer desde Java
- No drenes y detengas en el mismo instante: espera a que terminen las conexiones (o un tiempo fijo prudente).
- No ignores la work request: `updateBackend` es asíncrono.
- No confíes en `X-Forwarded-For` si la petición no viene del LB.
- No hagas que el chequeo de salud dependa de la base de datos.
- No uses `IP_HASH` para «resolver» sesiones en memoria: saca el estado de la réplica.
