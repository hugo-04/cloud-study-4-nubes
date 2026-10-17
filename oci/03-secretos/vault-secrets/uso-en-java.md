# Oracle OCI · Secretos · Vault: secretos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Una **caché con TTL y «stale-if-error»** (pura, con reloj inyectable) delante de `SecretsClient.getSecretBundle`: la aplicación lee el secreto una vez cada pocos minutos y sigue viva si Vault se pone lento.

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

### 2.2 Contrato de la fuente
```java
// (clase reutilizada en los bloques siguientes, ambos)
/** De dónde sale el valor de un secreto (Vault en producción, un mapa en las pruebas). */
public interface FuenteDeSecretos {

    String leer(String secretId);
}
```

### 2.3 Caché con TTL y gracia
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Caché con TTL y «stale-if-error»: si Vault falla, sirve el valor viejo durante un tiempo de gracia. */
public class CacheDeSecretos implements FuenteDeSecretos {

    private record Entrada(String valor, Instant leidoEn) { }

    private final FuenteDeSecretos origen;
    private final Clock reloj;
    private final Duration ttl;
    private final Duration gracia;
    private final Map<String, Entrada> entradas = new ConcurrentHashMap<>();

    public CacheDeSecretos(FuenteDeSecretos origen, Clock reloj, Duration ttl, Duration gracia) {
        this.origen = origen;
        this.reloj = reloj;
        this.ttl = ttl;
        this.gracia = gracia;
    }

    @Override
    public String leer(String secretId) {
        Instant ahora = reloj.instant();
        Entrada e = entradas.get(secretId);
        if (e != null && Duration.between(e.leidoEn(), ahora).compareTo(ttl) < 0) {
            return e.valor();
        }
        try {
            String nuevo = origen.leer(secretId);
            entradas.put(secretId, new Entrada(nuevo, ahora));
            return nuevo;
        } catch (RuntimeException fallo) {
            if (e != null && Duration.between(e.leidoEn(), ahora).compareTo(ttl.plus(gracia)) < 0) {
                return e.valor();
            }
            throw fallo;
        }
    }

    /** Úsalo si una credencial leída falla en el destino: probablemente se rotó. */
    public void invalidar(String secretId) {
        entradas.remove(secretId);
    }
}
```

### 2.4 Lectura con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.secrets.SecretsClient;
import com.oracle.bmc.secrets.model.Base64SecretBundleContentDetails;
import com.oracle.bmc.secrets.requests.GetSecretBundleRequest;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/** Lee la versión vigente (CURRENT) de un secreto con el endpoint de recuperación. */
public class SecretosOci implements FuenteDeSecretos, AutoCloseable {

    private final SecretsClient cliente;

    public SecretosOci(BasicAuthenticationDetailsProvider auth, String region) {
        this.cliente = SecretsClient.builder().region(Region.fromRegionId(region)).build(auth);
    }

    @Override
    public String leer(String secretId) {
        var req = GetSecretBundleRequest.builder().secretId(secretId).stage(GetSecretBundleRequest.Stage.Current).build();
        var contenido = cliente.getSecretBundle(req).getSecretBundle().getSecretBundleContent();
        String base64 = ((Base64SecretBundleContentDetails) contenido).getContent();
        return new String(Base64.getDecoder().decode(base64), StandardCharsets.UTF_8);
    }

    @Override
    public void close() {
        cliente.close();
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;

public class ServicioDeSecretos {

    private final CacheDeSecretos cache;

    public ServicioDeSecretos(FuenteDeSecretos origen) {
        this.cache = new CacheDeSecretos(origen, Clock.systemUTC(), Duration.ofMinutes(5), Duration.ofMinutes(30));
    }

    /** Nunca devuelvas el valor por HTTP: solo confirma que es legible. */
    public record Comprobacion(String secretId, boolean legible, int longitud) { }

    public Comprobacion comprobar(String secretId) {
        try {
            return new Comprobacion(secretId, true, cache.leer(secretId).length());
        } catch (RuntimeException e) {
            return new Comprobacion(secretId, false, 0);
        }
    }

    /** Para usar el valor dentro del proceso (por ejemplo, abrir un pool de conexiones). */
    public String valor(String secretId) {
        return cache.leer(secretId);
    }

    public String alRotar(String secretId) {
        cache.invalidar(secretId);
        return "caché invalidada";
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class SecretosConfiguracion {

    @Bean(destroyMethod = "close")
    SecretosOci secretosOci(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new SecretosOci(auth, region);
    }

    @Bean
    ServicioDeSecretos servicioDeSecretos(SecretosOci origen) {
        return new ServicioDeSecretos(origen);
    }
}

@RestController
@RequestMapping("/secretos/vault")
class SecretosControlador {

    private final ServicioDeSecretos s;

    SecretosControlador(ServicioDeSecretos s) {
        this.s = s;
    }

    @GetMapping("/comprobar")
    ServicioDeSecretos.Comprobacion comprobar(@RequestParam String secretId) {
        return s.comprobar(secretId);
    }

    @PostMapping("/rotado")
    String rotado(@RequestParam String secretId) {
        return s.alRotar(secretId);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/secretos/vault")
class SecretosReactivoControlador {

    private final ServicioDeSecretos s;

    SecretosReactivoControlador(ServicioDeSecretos s) {
        this.s = s;
    }

    @GetMapping("/comprobar")
    Mono<ServicioDeSecretos.Comprobacion> comprobar(@RequestParam String secretId) {
        return Mono.fromCallable(() -> s.comprobar(secretId)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/rotado")
    Mono<String> rotado(@RequestParam String secretId) {
        return Mono.fromCallable(() -> s.alRotar(secretId)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class SecretosProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SecretosOci secretosOci() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new SecretosOci(auth, region);
    }

    void cerrar(@Disposes SecretosOci s) {
        s.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeSecretos servicioDeSecretos(SecretosOci origen) {
        return new ServicioDeSecretos(origen);
    }
}

@Path("/secretos/vault")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class SecretosRecurso {

    @Inject
    ServicioDeSecretos s;

    @GET
    @Path("/comprobar")
    public ServicioDeSecretos.Comprobacion comprobar(@QueryParam("secretId") String secretId) {
        return s.comprobar(secretId);
    }

    @POST
    @Path("/rotado")
    public String rotado(@QueryParam("secretId") String secretId) {
        return s.alRotar(secretId);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/secretos/vault")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class SecretosRecursoReactivo {

    @Inject
    ServicioDeSecretos s;

    @GET
    @Path("/comprobar")
    public Uni<ServicioDeSecretos.Comprobacion> comprobar(@QueryParam("secretId") String secretId) {
        return Uni.createFrom().item(() -> s.comprobar(secretId)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/rotado")
    public Uni<String> rotado(@QueryParam("secretId") String secretId) {
        return Uni.createFrom().item(() -> s.alRotar(secretId)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `GetSecretBundle` | `Allow dynamic-group app-pedidos-prod to read secret-bundles in compartment tienda-prod where target.secret.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No devuelvas el valor del secreto por HTTP ni lo escribas en registros o excepciones.
- No leas el secreto en cada petición: cachea con TTL corto y gracia.
- Si el destino rechaza la credencial, invalida la caché y reintenta **una** vez (probable rotación).
- No pidas la etapa `PENDING` salvo en el proceso de rotación.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
