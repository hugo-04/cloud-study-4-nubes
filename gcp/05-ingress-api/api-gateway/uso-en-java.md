# Google Cloud · Ingress y API · API Gateway · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

En el backend: leer las **claims que reenvía el gateway** en `X-Apigateway-Api-Userinfo` (JSON en base64url), sin volver a validar la firma, y aplicar la **regla de negocio** que el gateway no conoce (solo el dueño ve su pedido). Además, un **inventario de gateways** con `ApiGatewayServiceClient.listGateways`. En el ejemplo la cabecera llega como parámetro para poder probarlo; en la app real se lee con `@RequestHeader`/`@HeaderParam`.

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

### 2.2 Claims del gateway (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;
import java.util.regex.Pattern;

/**
 * Lee las claims que API Gateway reenvía en X-Apigateway-Api-Userinfo (JSON en base64url) y aplica reglas de negocio.
 * Puro. La firma ya la validó el gateway: confía en la cabecera SOLO si el servicio es invocable únicamente por el gateway.
 */
public class ClaimsDelGateway {

    public record Usuario(String sub, String email, List<String> alcances) { }

    private static final Pattern CAMPO = Pattern.compile("\"(sub|email|scope)\"\\s*:\\s*\"([^\"]{0,512})\"");

    public static Optional<Usuario> leer(String cabecera) {
        if (cabecera == null || cabecera.isBlank() || cabecera.length() > 8192) {
            return Optional.empty();
        }
        String json;
        try {
            json = new String(Base64.getUrlDecoder().decode(cabecera.strip()), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
        Map<String, String> c = new TreeMap<>();
        var m = CAMPO.matcher(json);
        while (m.find()) {
            c.put(m.group(1), m.group(2));
        }
        if (!c.containsKey("sub")) {
            return Optional.empty();
        }
        var alcances = c.getOrDefault("scope", "").isBlank() ? List.<String>of() : List.of(c.get("scope").split(" "));
        return Optional.of(new Usuario(c.get("sub"), c.get("email"), alcances));
    }

    /** Regla de negocio que el gateway no conoce: solo el dueño (o soporte) ve el pedido. */
    public static boolean puedeVerPedido(Usuario u, String duenioDelPedido) {
        return u.sub().equals(duenioDelPedido) || u.alcances().contains("pedidos.soporte");
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.apigateway.v1.ApiGatewayServiceClient;
import com.google.cloud.apigateway.v1.ApiGatewayServiceSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: inventario de gateways (todas las ubicaciones) con su configuración activa. */
public class GatewaysGcp implements AutoCloseable {

    public record Gateway(String nombre, String config, String host, String estado) { }

    private final ApiGatewayServiceClient cliente;
    private final String proyecto;

    public GatewaysGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = ApiGatewayServiceClient.create(ApiGatewayServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Gateway> todos() {
        var out = new ArrayList<Gateway>();
        for (var g : cliente.listGateways("projects/" + proyecto + "/locations/-").iterateAll()) {
            out.add(new Gateway(g.getName(), g.getApiConfig(), g.getDefaultHostname(), g.getState().name()));
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

public class ServicioDePedidosApi {

    public record Respuesta(boolean permitido, String usuario) { }

    private final GatewaysGcp gateways;

    public ServicioDePedidosApi(GatewaysGcp gateways) {
        this.gateways = gateways;
    }

    public Respuesta verPedido(String userinfo, String duenio) {
        return ClaimsDelGateway.leer(userinfo)
            .map(u -> new Respuesta(ClaimsDelGateway.puedeVerPedido(u, duenio), u.sub()))
            .orElse(new Respuesta(false, null));
    }

    public List<GatewaysGcp.Gateway> inventario() {
        return gateways.todos();
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
class PedidosApiConfiguracion {

    @Bean(destroyMethod = "close")
    GatewaysGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new GatewaysGcp(cred, proyecto);
    }

    @Bean
    ServicioDePedidosApi servicio(GatewaysGcp a) {
        return new ServicioDePedidosApi(a);
    }
}

@RestController
@RequestMapping("/ingress/api")
class PedidosApiControlador {

    private final ServicioDePedidosApi s;

    PedidosApiControlador(ServicioDePedidosApi s) {
        this.s = s;
    }

    @GetMapping("/pedidos/permiso")
    ServicioDePedidosApi.Respuesta verPedido(@RequestParam String userinfo, @RequestParam String duenio) {
        return s.verPedido(userinfo, duenio);
    }

    @GetMapping("/gateways")
    List<GatewaysGcp.Gateway> inventario() {
        return s.inventario();
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
@RequestMapping("/reactivo/ingress/api")
class PedidosApiReactivoControlador {

    private final ServicioDePedidosApi s;

    PedidosApiReactivoControlador(ServicioDePedidosApi s) {
        this.s = s;
    }

    @GetMapping("/pedidos/permiso")
    Mono<ServicioDePedidosApi.Respuesta> verPedido(@RequestParam String userinfo, @RequestParam String duenio) {
        return Mono.fromCallable(() -> s.verPedido(userinfo, duenio));
    }

    @GetMapping("/gateways")
    Mono<List<GatewaysGcp.Gateway>> inventario() {
        return Mono.fromCallable(() -> s.inventario()).subscribeOn(Schedulers.boundedElastic());
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
class PedidosApiProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    GatewaysGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new GatewaysGcp(cred, proyecto);
    }

    void cerrar(@Disposes GatewaysGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePedidosApi servicio(GatewaysGcp a) {
        return new ServicioDePedidosApi(a);
    }
}

@Path("/ingress/api")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class PedidosApiRecurso {

    @Inject
    ServicioDePedidosApi s;

    @GET
    @Path("/pedidos/permiso")
    public ServicioDePedidosApi.Respuesta verPedido(@QueryParam("userinfo") String userinfo, @QueryParam("duenio") String duenio) {
        return s.verPedido(userinfo, duenio);
    }

    @GET
    @Path("/gateways")
    public List<GatewaysGcp.Gateway> inventario() {
        return s.inventario();
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

@Path("/reactivo/ingress/api")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class PedidosApiRecursoReactivo {

    @Inject
    ServicioDePedidosApi s;

    @GET
    @Path("/pedidos/permiso")
    public Uni<ServicioDePedidosApi.Respuesta> verPedido(@QueryParam("userinfo") String userinfo, @QueryParam("duenio") String duenio) {
        return Uni.createFrom().item(() -> s.verPedido(userinfo, duenio));
    }

    @GET
    @Path("/gateways")
    public Uni<List<GatewaysGcp.Gateway>> inventario() {
        return Uni.createFrom().item(() -> s.inventario()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar gateways | `roles/apigateway.viewer` |
| El gateway invoca el backend | `roles/run.invoker` a la cuenta del gateway sobre el servicio |

## 8. Qué NO hacer desde Java
- No confíes en `X-Apigateway-Api-Userinfo` si tu servicio es invocable por otros además del gateway.
- No reemplaces la autorización de negocio por la autenticación del gateway.
- No registres el JWT ni la cabecera completa.
