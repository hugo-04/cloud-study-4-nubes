# Google Cloud · Ingress y API · Entrada a GKE · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Lo que la app necesita detrás del Gateway: **la IP real del cliente** (el balanceador de Google agrega «cliente, balanceador» al final de `X-Forwarded-For`, así que el cliente es el **penúltimo** valor; lo anterior pudo inventarlo el cliente) y, para inventario, las **reglas de reenvío** que creó el controlador (`GlobalForwardingRulesClient`, nombres `gkegw…`).

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

### 2.2 IP del cliente (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Optional;

/**
 * IP real del cliente detrás del balanceador de aplicación de Google.
 * El balanceador AGREGA «<ip-cliente>, <ip-balanceador>» al final de X-Forwarded-For; lo anterior lo pudo escribir el cliente.
 * Con N proxies propios adicionales delante de la app (dentro de tu red), se saltan también. Puro.
 */
public final class IpDelCliente {

    private IpDelCliente() { }

    public static Optional<String> resolver(String xForwardedFor, int proxiesPropiosDetras) {
        if (xForwardedFor == null || xForwardedFor.isBlank()) {
            return Optional.empty();
        }
        List<String> saltos = List.of(xForwardedFor.split(",")).stream().map(String::strip).toList();
        int indice = saltos.size() - 2 - proxiesPropiosDetras; // último = balanceador; penúltimo = cliente
        if (indice < 0) {
            return Optional.empty();
        }
        String ip = saltos.get(indice);
        return ip.matches("[0-9a-fA-F:.]{3,45}") ? Optional.of(ip) : Optional.empty();
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.GlobalForwardingRulesClient;
import com.google.cloud.compute.v1.GlobalForwardingRulesSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: reglas de reenvío globales creadas por el controlador de Gateway (nombre «gkegw…»). */
public class GatewayGcp implements AutoCloseable {

    public record Regla(String nombre, String ip, String puertos, String esquema) { }

    private final GlobalForwardingRulesClient cliente;
    private final String proyecto;

    public GatewayGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = GlobalForwardingRulesClient.create(GlobalForwardingRulesSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Regla> deGateways(String filtroNombre) {
        var out = new ArrayList<Regla>();
        for (var f : cliente.list(proyecto).iterateAll()) {
            if (f.getName().startsWith("gkegw") && f.getName().contains(filtroNombre)) {
                out.add(new Regla(f.getName(), f.getIPAddress(), f.getPortRange(), f.getLoadBalancingScheme()));
            }
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

public class ServicioDeEntradaGke {

    private final GatewayGcp gateway;

    public ServicioDeEntradaGke(GatewayGcp gateway) {
        this.gateway = gateway;
    }

    public String ipCliente(String xff) {
        return IpDelCliente.resolver(xff, 0).orElse("desconocida");
    }

    public List<GatewayGcp.Regla> reglas(String filtro) {
        return gateway.deGateways(filtro);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EntradaGkeConfiguracion {

    @Bean(destroyMethod = "close")
    GatewayGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new GatewayGcp(cred, proyecto);
    }

    @Bean
    ServicioDeEntradaGke servicio(GatewayGcp a) {
        return new ServicioDeEntradaGke(a);
    }
}

@RestController
@RequestMapping("/ingress/gke")
class EntradaGkeControlador {

    private final ServicioDeEntradaGke s;

    EntradaGkeControlador(ServicioDeEntradaGke s) {
        this.s = s;
    }

    @GetMapping("/ip")
    String ipCliente(@RequestParam String xff) {
        return s.ipCliente(xff);
    }

    @GetMapping("/reglas")
    List<GatewayGcp.Regla> reglas(@RequestParam String filtro) {
        return s.reglas(filtro);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/gke")
class EntradaGkeReactivoControlador {

    private final ServicioDeEntradaGke s;

    EntradaGkeReactivoControlador(ServicioDeEntradaGke s) {
        this.s = s;
    }

    @GetMapping("/ip")
    Mono<String> ipCliente(@RequestParam String xff) {
        return Mono.fromCallable(() -> s.ipCliente(xff));
    }

    @GetMapping("/reglas")
    Mono<List<GatewayGcp.Regla>> reglas(@RequestParam String filtro) {
        return Mono.fromCallable(() -> s.reglas(filtro)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EntradaGkeProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    GatewayGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new GatewayGcp(cred, proyecto);
    }

    void cerrar(@Disposes GatewayGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEntradaGke servicio(GatewayGcp a) {
        return new ServicioDeEntradaGke(a);
    }
}

@Path("/ingress/gke")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EntradaGkeRecurso {

    @Inject
    ServicioDeEntradaGke s;

    @GET
    @Path("/ip")
    public String ipCliente(@QueryParam("xff") String xff) {
        return s.ipCliente(xff);
    }

    @GET
    @Path("/reglas")
    public List<GatewayGcp.Regla> reglas(@QueryParam("filtro") String filtro) {
        return s.reglas(filtro);
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
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/ingress/gke")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EntradaGkeRecursoReactivo {

    @Inject
    ServicioDeEntradaGke s;

    @GET
    @Path("/ip")
    public Uni<String> ipCliente(@QueryParam("xff") String xff) {
        return Uni.createFrom().item(() -> s.ipCliente(xff));
    }

    @GET
    @Path("/reglas")
    public Uni<List<GatewayGcp.Regla>> reglas(@QueryParam("filtro") String filtro) {
        return Uni.createFrom().item(() -> s.reglas(filtro)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar reglas de reenvío | `roles/compute.viewer` |

## 8. Qué NO hacer desde Java
- No tomes el primer valor de `X-Forwarded-For`.
- No asumas el formato si hay otros proxies (CDN externo, malla): ajusta `proxiesPropiosDetras`.
- No crees balanceadores desde la app: los crea el controlador a partir del Gateway.
