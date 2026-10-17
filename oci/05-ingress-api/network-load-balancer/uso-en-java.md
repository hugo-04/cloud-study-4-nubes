# Oracle OCI · Ingress y API · Network Load Balancer · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **semáforo de salud** para los backend sets de un NLB: lee `getBackendSetHealth` de cada set y lo traduce a VERDE/AMARILLO/ROJO con la disponibilidad real, listo para un tablero o una alarma.

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

### 2.2 Semáforo (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

/** Semáforo de salud de un backend set. Puro: recibe conteos, devuelve nivel y mensaje. */
public class SemaforoDeSalud {

    public enum Nivel { VERDE, AMARILLO, ROJO }

    public record Lectura(String set, int total, List<String> warning, List<String> critical, List<String> unknown) { }

    public record Veredicto(String set, Nivel nivel, double disponibilidad, String mensaje) { }

    private final double umbralAmarillo;

    public SemaforoDeSalud(double umbralAmarillo) {
        this.umbralAmarillo = umbralAmarillo;
    }

    public Veredicto evaluar(Lectura l) {
        if (l.total() == 0) {
            return new Veredicto(l.set(), Nivel.ROJO, 0, "set sin backends");
        }
        int malos = l.critical().size() + l.unknown().size();
        int sanos = l.total() - malos - l.warning().size();
        double disp = (double) sanos / l.total();
        Nivel nivel = sanos == 0 ? Nivel.ROJO : disp < umbralAmarillo || !l.warning().isEmpty() ? Nivel.AMARILLO : Nivel.VERDE;
        String msg = nivel == Nivel.VERDE ? "todo sano"
            : "sanos " + sanos + "/" + l.total() + (malos > 0 ? "; fallando: " + String.join(",", l.critical()) : "");
        return new Veredicto(l.set(), nivel, Math.round(disp * 1000) / 1000.0, msg);
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import com.oracle.bmc.networkloadbalancer.requests.GetBackendSetHealthRequest;
import com.oracle.bmc.networkloadbalancer.requests.GetNetworkLoadBalancerRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: lee la salud de todos los backend sets de un NLB. */
public class NlbOci implements AutoCloseable {

    private final NetworkLoadBalancerClient cliente;

    public NlbOci(NetworkLoadBalancerClient cliente) {
        this.cliente = cliente;
    }

    public List<SemaforoDeSalud.Lectura> lecturas(String nlbId) {
        var nlb = cliente.getNetworkLoadBalancer(GetNetworkLoadBalancerRequest.builder()
            .networkLoadBalancerId(nlbId).build()).getNetworkLoadBalancer();
        var out = new ArrayList<SemaforoDeSalud.Lectura>();
        for (String set : nlb.getBackendSets().keySet()) {
            var h = cliente.getBackendSetHealth(GetBackendSetHealthRequest.builder()
                .networkLoadBalancerId(nlbId).backendSetName(set).build()).getBackendSetHealth();
            out.add(new SemaforoDeSalud.Lectura(set, h.getTotalBackendCount(),
                h.getWarningStateBackendNames(), h.getCriticalStateBackendNames(), h.getUnknownStateBackendNames()));
        }
        return out;
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

public class ServicioDeSalud {

    private final NlbOci nlb;
    private final SemaforoDeSalud semaforo = new SemaforoDeSalud(0.67);

    public ServicioDeSalud(NlbOci nlb) {
        this.nlb = nlb;
    }

    public List<SemaforoDeSalud.Veredicto> revisar(String nlbId) {
        return nlb.lecturas(nlbId).stream().map(semaforo::evaluar).toList();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class NlbConfiguracion {

    @Bean(destroyMethod = "close")
    NlbOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new NlbOci(NetworkLoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeSalud servicio(NlbOci a) {
        return new ServicioDeSalud(a);
    }
}

@RestController
@RequestMapping("/ingress/nlb")
class NlbControlador {

    private final ServicioDeSalud s;

    NlbControlador(ServicioDeSalud s) {
        this.s = s;
    }

    @GetMapping("/{id}/salud")
    List<SemaforoDeSalud.Veredicto> revisar(@PathVariable String id) {
        return s.revisar(id);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/nlb")
class NlbReactivoControlador {

    private final ServicioDeSalud s;

    NlbReactivoControlador(ServicioDeSalud s) {
        this.s = s;
    }

    @GetMapping("/{id}/salud")
    Mono<List<SemaforoDeSalud.Veredicto>> revisar(@PathVariable String id) {
        return Mono.fromCallable(() -> s.revisar(id)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class NlbProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    NlbOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new NlbOci(NetworkLoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes NlbOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeSalud servicio(NlbOci a) {
        return new ServicioDeSalud(a);
    }
}

@Path("/ingress/nlb")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class NlbRecurso {

    @Inject
    ServicioDeSalud s;

    @GET
    @Path("/{id}/salud")
    public List<SemaforoDeSalud.Veredicto> revisar(@PathParam("id") String id) {
        return s.revisar(id);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.List;

@Path("/reactivo/ingress/nlb")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class NlbRecursoReactivo {

    @Inject
    ServicioDeSalud s;

    @GET
    @Path("/{id}/salud")
    public Uni<List<SemaforoDeSalud.Veredicto>> revisar(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> s.revisar(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer NLB y salud | `Allow dynamic-group monitoreo to read network-load-balancers in compartment red-prod` |

## 8. Qué NO hacer desde Java
- No consultes la salud en cada petición de usuario: hazlo periódicamente y cachea.
- No confundas `WARNING` con sano: algunos chequeos fallan.
- No uses el NLB para «ocultar» un backend sin TLS: cifra de extremo a extremo.
- No asumas que verás `X-Forwarded-For`: en capa 4 no existe; usa la preservación de origen.
