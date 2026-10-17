# Oracle OCI · Ingress y API · Ingress en OKE · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Lo que la app necesita detrás de un Ingress: un **resolutor de la IP real del cliente** que solo cree en `X-Forwarded-For` cuando la petición viene de la subred del LB, y un adaptador que **encuentra el LB creado por el Ingress** y reporta su IP y salud. En Spring Boot y Quarkus recuerda además el apagado ordenado (`server.shutdown=graceful` / `quarkus.shutdown.timeout`).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
entrada:
  compartimento: ocid1.compartment.oc1..aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
entrada.compartimento=ocid1.compartment.oc1..aaaa
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

### 2.2 Resolutor de IP (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.List;

/**
 * Obtiene la IP real del cliente detrás del LB/Ingress. Recorre X-Forwarded-For de derecha a izquierda
 * y se detiene en la primera IP que NO es un proxy de confianza. Puro (solo IPv4 en este ejemplo).
 */
public class ResolutorDeIpCliente {

    private record Rango(long red, long mascara) {
        boolean contiene(long ip) {
            return (ip & mascara) == red;
        }
    }

    private final List<Rango> confiables;

    public ResolutorDeIpCliente(List<String> cidrsConfiables) {
        this.confiables = cidrsConfiables.stream().map(ResolutorDeIpCliente::rango).toList();
    }

    public String resolver(String ipSocket, String xForwardedFor) {
        if (!esConfiable(ipSocket) || xForwardedFor == null || xForwardedFor.isBlank()) {
            return ipSocket; // la petición no vino por nuestro proxy: no se cree la cabecera
        }
        String[] saltos = xForwardedFor.split(",");
        for (int i = saltos.length - 1; i >= 0; i--) {
            String ip = saltos[i].strip();
            if (!ip.matches("\\d{1,3}(\\.\\d{1,3}){3}")) {
                return ipSocket; // cabecera manipulada
            }
            if (!esConfiable(ip)) {
                return ip;
            }
        }
        return saltos[0].strip();
    }

    private boolean esConfiable(String ip) {
        long v = aLong(ip);
        return confiables.stream().anyMatch(r -> r.contiene(v));
    }

    private static Rango rango(String cidr) {
        String[] p = cidr.split("/");
        int bits = Integer.parseInt(p[1]);
        long mascara = bits == 0 ? 0 : (0xFFFFFFFFL << (32 - bits)) & 0xFFFFFFFFL;
        return new Rango(aLong(p[0]) & mascara, mascara);
    }

    private static long aLong(String ip) {
        try {
            byte[] b = InetAddress.getByName(ip).getAddress();
            return ((b[0] & 0xFFL) << 24) | ((b[1] & 0xFFL) << 16) | ((b[2] & 0xFFL) << 8) | (b[3] & 0xFFL);
        } catch (UnknownHostException e) {
            throw new IllegalArgumentException("IP inválida: " + ip, e);
        }
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import com.oracle.bmc.loadbalancer.model.LoadBalancer;
import com.oracle.bmc.loadbalancer.requests.GetLoadBalancerHealthRequest;
import com.oracle.bmc.loadbalancer.requests.ListLoadBalancersRequest;
import java.util.Optional;

/** Adaptador del SDK: encuentra el LB que creó el Ingress (por nombre) y lee su IP y salud. */
public class IngressOci implements AutoCloseable {

    public record InfoLb(String nombre, String ip, String salud) { }

    private final LoadBalancerClient cliente;
    private final String compartimentoId;

    public IngressOci(LoadBalancerClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public Optional<InfoLb> buscar(String nombre) {
        return cliente.listLoadBalancers(ListLoadBalancersRequest.builder()
                .compartmentId(compartimentoId).displayName(nombre)
                .lifecycleState(LoadBalancer.LifecycleState.Active).build())
            .getItems().stream().findFirst()
            .map(lb -> new InfoLb(lb.getDisplayName(),
                lb.getIpAddresses().isEmpty() ? null : lb.getIpAddresses().get(0).getIpAddress(),
                cliente.getLoadBalancerHealth(GetLoadBalancerHealthRequest.builder().loadBalancerId(lb.getId()).build())
                    .getLoadBalancerHealth().getStatus().getValue()));
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

public class ServicioDeEntrada {

    private final IngressOci ingress;
    // Subred del LB del Ingress (los únicos proxies en los que se confía)
    private final ResolutorDeIpCliente resolutor = new ResolutorDeIpCliente(List.of("10.0.1.0/24"));

    public ServicioDeEntrada(IngressOci ingress) {
        this.ingress = ingress;
    }

    public String ipCliente(String ipSocket, String xff) {
        return resolutor.resolver(ipSocket, xff);
    }

    public IngressOci.InfoLb lb(String nombre) {
        return ingress.buscar(nombre).orElseThrow(() -> new IllegalArgumentException("no existe el LB " + nombre));
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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EntradaConfiguracion {

    @Bean(destroyMethod = "close")
    IngressOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${entrada.compartimento}") String compartimento) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new IngressOci(LoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    @Bean
    ServicioDeEntrada servicio(IngressOci a) {
        return new ServicioDeEntrada(a);
    }
}

@RestController
@RequestMapping("/ingress/entrada")
class EntradaControlador {

    private final ServicioDeEntrada s;

    EntradaControlador(ServicioDeEntrada s) {
        this.s = s;
    }

    @GetMapping("/ip")
    String ipCliente(@RequestParam String socket, @RequestParam String xff) {
        return s.ipCliente(socket, xff);
    }

    @GetMapping("/lb/{nombre}")
    IngressOci.InfoLb lb(@PathVariable String nombre) {
        return s.lb(nombre);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/entrada")
class EntradaReactivoControlador {

    private final ServicioDeEntrada s;

    EntradaReactivoControlador(ServicioDeEntrada s) {
        this.s = s;
    }

    @GetMapping("/ip")
    Mono<String> ipCliente(@RequestParam String socket, @RequestParam String xff) {
        return Mono.fromCallable(() -> s.ipCliente(socket, xff));
    }

    @GetMapping("/lb/{nombre}")
    Mono<IngressOci.InfoLb> lb(@PathVariable String nombre) {
        return Mono.fromCallable(() -> s.lb(nombre)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EntradaProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "entrada.compartimento")
    String compartimento;

    @jakarta.enterprise.inject.Produces
    @Singleton
    IngressOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new IngressOci(LoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    void cerrar(@Disposes IngressOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEntrada servicio(IngressOci a) {
        return new ServicioDeEntrada(a);
    }
}

@Path("/ingress/entrada")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EntradaRecurso {

    @Inject
    ServicioDeEntrada s;

    @GET
    @Path("/ip")
    public String ipCliente(@QueryParam("socket") String socket, @QueryParam("xff") String xff) {
        return s.ipCliente(socket, xff);
    }

    @GET
    @Path("/lb/{nombre}")
    public IngressOci.InfoLb lb(@PathParam("nombre") String nombre) {
        return s.lb(nombre);
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/ingress/entrada")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EntradaRecursoReactivo {

    @Inject
    ServicioDeEntrada s;

    @GET
    @Path("/ip")
    public Uni<String> ipCliente(@QueryParam("socket") String socket, @QueryParam("xff") String xff) {
        return Uni.createFrom().item(() -> s.ipCliente(socket, xff));
    }

    @GET
    @Path("/lb/{nombre}")
    public Uni<IngressOci.InfoLb> lb(@PathParam("nombre") String nombre) {
        return Uni.createFrom().item(() -> s.lb(nombre)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Buscar el LB y su salud | `Allow dynamic-group plataforma to read load-balancers in compartment red-prod` |
| El controlador crea el LB | `Allow any-user to manage load-balancers in compartment red-prod where request.principal.type = 'cluster'` *(o la identidad del controlador nativo; verifica)* |

## 8. Qué NO hacer desde Java
- No tomes el primer valor de `X-Forwarded-For` sin validar quién lo envió: el cliente puede falsificarlo.
- No ignores `SIGTERM`: activa el apagado ordenado del framework.
- No respondas *readiness* OK antes de que la app termine de calentar.
- No crees `Service LoadBalancer` desde el código de la app.
