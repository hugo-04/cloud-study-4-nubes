# Google Cloud · Secretos · Secret Manager · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Una **caché de secretos con TTL y gracia ante fallos**: lee con `SecretManagerServiceClient.accessSecretVersion` (alias `latest`), verifica el **CRC32C** que devuelve el servicio, y si Secret Manager no responde sirve el último valor durante un periodo de gracia. El endpoint de ejemplo expone solo la longitud del valor, nunca el valor.

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

### 2.2 Caché con gracia (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.zip.CRC32C;

/** Caché de secretos con TTL y gracia ante fallos (stale-if-error). Puro: reloj y fuente inyectados. */
public class CacheDeSecretos {

    private record Entrada(byte[] valor, Instant leido) { }

    private final Function<String, byte[]> fuente;
    private final Clock reloj;
    private final Duration ttl;
    private final Duration gracia;
    private final Map<String, Entrada> cache = new ConcurrentHashMap<>();

    public CacheDeSecretos(Function<String, byte[]> fuente, Clock reloj, Duration ttl, Duration gracia) {
        this.fuente = fuente;
        this.reloj = reloj;
        this.ttl = ttl;
        this.gracia = gracia;
    }

    public byte[] obtener(String nombre) {
        Instant ahora = reloj.instant();
        Entrada e = cache.get(nombre);
        if (e != null && ahora.isBefore(e.leido().plus(ttl))) {
            return e.valor();
        }
        try {
            byte[] nuevo = fuente.apply(nombre);
            cache.put(nombre, new Entrada(nuevo, ahora));
            return nuevo;
        } catch (RuntimeException falla) {
            if (e != null && ahora.isBefore(e.leido().plus(ttl).plus(gracia))) {
                return e.valor(); // el servicio de secretos falló: se sirve el último valor dentro de la gracia
            }
            throw falla;
        }
    }

    public void invalidar(String nombre) {
        cache.remove(nombre);
    }

    /** Verifica el CRC32C que devuelve Secret Manager. */
    public static boolean integro(byte[] datos, long crcEsperado) {
        var c = new CRC32C();
        c.update(datos);
        return c.getValue() == crcEsperado;
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.secretmanager.v1.SecretManagerServiceClient;
import com.google.cloud.secretmanager.v1.SecretManagerServiceSettings;
import com.google.cloud.secretmanager.v1.SecretVersionName;
import java.io.IOException;
import java.io.UncheckedIOException;

/** Adaptador: lee la versión «latest» (o un alias) y verifica integridad. */
public class SecretosGcp implements AutoCloseable {

    private final SecretManagerServiceClient cliente;
    private final String proyecto;

    public SecretosGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = SecretManagerServiceClient.create(SecretManagerServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public byte[] leer(String secreto) {
        var payload = cliente.accessSecretVersion(SecretVersionName.of(proyecto, secreto, "latest")).getPayload();
        byte[] datos = payload.getData().toByteArray();
        if (payload.hasDataCrc32C() && !CacheDeSecretos.integro(datos, payload.getDataCrc32C())) {
            throw new IllegalStateException("el valor del secreto no pasó la verificación CRC32C");
        }
        return datos;
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
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;

public class ServicioDeSecretos {

    public record Estado(String secreto, int longitud) { }

    private final CacheDeSecretos cache;

    public ServicioDeSecretos(SecretosGcp secretos) {
        this.cache = new CacheDeSecretos(secretos::leer, Clock.systemUTC(), Duration.ofMinutes(5), Duration.ofMinutes(30));
    }

    /** Uso interno: por ejemplo, para construir el DataSource. Nunca devuelvas el valor por HTTP. */
    public String valor(String secreto) {
        return new String(cache.obtener(secreto), StandardCharsets.UTF_8);
    }

    public Estado estado(String secreto) {
        return new Estado(secreto, cache.obtener(secreto).length);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class SecretosConfiguracion {

    @Bean(destroyMethod = "close")
    SecretosGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SecretosGcp(cred, proyecto);
    }

    @Bean
    ServicioDeSecretos servicio(SecretosGcp a) {
        return new ServicioDeSecretos(a);
    }
}

@RestController
@RequestMapping("/secretos")
class SecretosControlador {

    private final ServicioDeSecretos s;

    SecretosControlador(ServicioDeSecretos s) {
        this.s = s;
    }

    @GetMapping("/{secreto}/estado")
    ServicioDeSecretos.Estado estado(@PathVariable String secreto) {
        return s.estado(secreto);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/secretos")
class SecretosReactivoControlador {

    private final ServicioDeSecretos s;

    SecretosReactivoControlador(ServicioDeSecretos s) {
        this.s = s;
    }

    @GetMapping("/{secreto}/estado")
    Mono<ServicioDeSecretos.Estado> estado(@PathVariable String secreto) {
        return Mono.fromCallable(() -> s.estado(secreto)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class SecretosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SecretosGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SecretosGcp(cred, proyecto);
    }

    void cerrar(@Disposes SecretosGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeSecretos servicio(SecretosGcp a) {
        return new ServicioDeSecretos(a);
    }
}

@Path("/secretos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class SecretosRecurso {

    @Inject
    ServicioDeSecretos s;

    @GET
    @Path("/{secreto}/estado")
    public ServicioDeSecretos.Estado estado(@PathParam("secreto") String secreto) {
        return s.estado(secreto);
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
import jakarta.ws.rs.PathParam;

@Path("/reactivo/secretos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class SecretosRecursoReactivo {

    @Inject
    ServicioDeSecretos s;

    @GET
    @Path("/{secreto}/estado")
    public Uni<ServicioDeSecretos.Estado> estado(@PathParam("secreto") String secreto) {
        return Uni.createFrom().item(() -> s.estado(secreto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer el valor | `roles/secretmanager.secretAccessor` **en ese secreto** |

## 8. Qué NO hacer desde Java
- No leas el secreto en cada petición.
- No expongas ni registres el valor.
- No fijes la gracia demasiado larga: tras una rotación forzada por incidente, invalida la caché.
- No uses `String` para secretos de larga vida si puedes manejarlos como `byte[]` y limpiarlos.
