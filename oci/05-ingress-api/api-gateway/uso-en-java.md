# Oracle OCI · Ingress y API · API Gateway · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Dos piezas: la **lógica de un autorizador propio** (`CUSTOM_AUTHENTICATION`) para llaves de socios —guarda solo el SHA-256, compara en tiempo constante y devuelve la respuesta con la forma que espera el gateway (`active`, `principal`, `scope`, `expiresAt`, `context`)— y un **inventario de APIs** con `DeploymentClient`. En producción el autorizador se empaqueta como función (ver [Functions](../../04-compute/functions/README.md)); aquí se expone también por HTTP para probarlo.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
apis:
  compartimento: ocid1.compartment.oc1..aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
apis.compartimento=ocid1.compartment.oc1..aaaa
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

### 2.2 Autorizador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

/**
 * Lógica del autorizador propio (CUSTOM_AUTHENTICATION) que corre en una función.
 * Guarda solo el SHA-256 de cada llave de socio; nunca la llave en claro. Puro: reloj inyectado.
 */
public class AutorizadorDeSocios {

    public record Socio(String nombre, List<String> alcances, boolean activo) { }

    /** Forma de la respuesta que espera API Gateway de un autorizador. */
    public record Respuesta(boolean active, String principal, List<String> scope, String expiresAt,
                            Map<String, String> context, String wwwAuthenticate) { }

    private final Map<String, Socio> porHash;
    private final Clock reloj;
    private final Duration validez;

    public AutorizadorDeSocios(Map<String, Socio> porHash, Clock reloj, Duration validez) {
        this.porHash = Map.copyOf(porHash);
        this.reloj = reloj;
        this.validez = validez;
    }

    public static String hash(String llave) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(llave.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(d);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public Respuesta autorizar(String cabecera) {
        if (cabecera == null || !cabecera.startsWith("ApiKey ") || cabecera.length() > 200) {
            return denegar("falta la llave");
        }
        String h = hash(cabecera.substring(7).strip());
        Socio s = null;
        for (var e : porHash.entrySet()) {
            // comparación en tiempo constante para no filtrar información por tiempos
            if (MessageDigest.isEqual(e.getKey().getBytes(StandardCharsets.UTF_8), h.getBytes(StandardCharsets.UTF_8))) {
                s = e.getValue();
            }
        }
        if (s == null || !s.activo()) {
            return denegar("llave inválida o revocada");
        }
        return new Respuesta(true, s.nombre(), s.alcances(), reloj.instant().plus(validez).toString(),
            Map.of("socio", s.nombre()), null);
    }

    private Respuesta denegar(String motivo) {
        return new Respuesta(false, null, List.of(), null, Map.of(), "ApiKey realm=\"socios\", error=\"" + motivo + "\"");
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.apigateway.DeploymentClient;
import com.oracle.bmc.apigateway.model.Deployment;
import com.oracle.bmc.apigateway.requests.ListDeploymentsRequest;
import java.util.List;

/** Adaptador del SDK: inventario de deployments activos (para un portal interno de APIs). */
public class ApisOci implements AutoCloseable {

    public record Api(String nombre, String prefijo, String endpoint) { }

    private final DeploymentClient cliente;
    private final String compartimentoId;

    public ApisOci(DeploymentClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public List<Api> activas() {
        return cliente.listDeployments(ListDeploymentsRequest.builder()
                .compartmentId(compartimentoId)
                .lifecycleState(Deployment.LifecycleState.Active)
                .build())
            .getDeploymentCollection().getItems().stream()
            .map(d -> new Api(d.getDisplayName(), d.getPathPrefix(), d.getEndpoint()))
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
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import java.util.Map;

public class ServicioDeApis {

    private final ApisOci apis;
    // En producción los hashes vienen de un secreto de Vault, no del código.
    private final AutorizadorDeSocios autorizador = new AutorizadorDeSocios(
        Map.of(AutorizadorDeSocios.hash("demo-cafe-andino"),
            new AutorizadorDeSocios.Socio("cafe-andino", List.of("catalogo.leer"), true)),
        Clock.systemUTC(), Duration.ofMinutes(15));

    public ServicioDeApis(ApisOci apis) {
        this.apis = apis;
    }

    public record Peticion(String type, String token) { }

    public AutorizadorDeSocios.Respuesta autorizar(Peticion p) {
        return autorizador.autorizar(p.token());
    }

    public List<ApisOci.Api> inventario() {
        return apis.activas();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.apigateway.DeploymentClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ApisConfiguracion {

    @Bean(destroyMethod = "close")
    ApisOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${apis.compartimento}") String compartimento) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ApisOci(DeploymentClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    @Bean
    ServicioDeApis servicio(ApisOci a) {
        return new ServicioDeApis(a);
    }
}

@RestController
@RequestMapping("/ingress/apis")
class ApisControlador {

    private final ServicioDeApis s;

    ApisControlador(ServicioDeApis s) {
        this.s = s;
    }

    @PostMapping("/autorizar")
    AutorizadorDeSocios.Respuesta autorizar(@RequestBody ServicioDeApis.Peticion p) {
        return s.autorizar(p);
    }

    @GetMapping("")
    List<ApisOci.Api> inventario() {
        return s.inventario();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.apigateway.DeploymentClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/apis")
class ApisReactivoControlador {

    private final ServicioDeApis s;

    ApisReactivoControlador(ServicioDeApis s) {
        this.s = s;
    }

    @PostMapping("/autorizar")
    Mono<AutorizadorDeSocios.Respuesta> autorizar(@RequestBody ServicioDeApis.Peticion p) {
        return Mono.fromCallable(() -> s.autorizar(p));
    }

    @GetMapping("")
    Mono<List<ApisOci.Api>> inventario() {
        return Mono.fromCallable(() -> s.inventario()).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.apigateway.DeploymentClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ApisProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "apis.compartimento")
    String compartimento;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ApisOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ApisOci(DeploymentClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    void cerrar(@Disposes ApisOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeApis servicio(ApisOci a) {
        return new ServicioDeApis(a);
    }
}

@Path("/ingress/apis")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ApisRecurso {

    @Inject
    ServicioDeApis s;

    @POST
    @Path("/autorizar")
    @Consumes(MediaType.APPLICATION_JSON)
    public AutorizadorDeSocios.Respuesta autorizar(ServicioDeApis.Peticion p) {
        return s.autorizar(p);
    }

    @GET
    @Path("")
    public List<ApisOci.Api> inventario() {
        return s.inventario();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.apigateway.DeploymentClient;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/ingress/apis")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ApisRecursoReactivo {

    @Inject
    ServicioDeApis s;

    @POST
    @Path("/autorizar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<AutorizadorDeSocios.Respuesta> autorizar(ServicioDeApis.Peticion p) {
        return Uni.createFrom().item(() -> s.autorizar(p));
    }

    @GET
    @Path("")
    public Uni<List<ApisOci.Api>> inventario() {
        return Uni.createFrom().item(() -> s.inventario()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Listar deployments | `Allow dynamic-group portal-apis to read api-deployments in compartment apis-prod` |
| El gateway invoca la función autorizadora | `Allow any-user to use functions-family in compartment apis-prod where ALL {request.principal.type = 'ApiGateway', request.resource.compartment.id = '<ocid>'}` |

## 8. Qué NO hacer desde Java
- No guardes llaves de socios en claro: solo su *hash* (y en Vault, no en el código).
- No compares llaves con `equals`: usa comparación en tiempo constante.
- No hagas que el autorizador consulte la base en cada petición: caché y `expiresAt`.
- No reenvíes el token completo al backend si basta con el principal.
- No dupliques en Java lo que el gateway ya valida (firma JWT), pero sí las reglas de negocio.
