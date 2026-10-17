# Google Cloud · Datos · Memorystore · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Con Memorystore el código es el de cualquier Redis/Valkey; lo propio de Google es la **conexión privada con TLS** y la **autenticación IAM**: la contraseña es un token de acceso de la cuenta de servicio, que aquí se entrega con un `RedisCredentialsProvider` para que Lettuce lo pida de nuevo al reconectar. La lógica pura da claves versionadas y TTL con *jitter*; el adaptador hace cache-aside y **degrada a la fuente** si la caché falla. En Spring viene con `spring-boot-starter-data-redis`; en Quarkus agrega `io.lettuce:lettuce-core` (o usa `quarkus-redis-client` con la misma idea).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
cache:
  host: 10.20.0.5
  puerto: 6379
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
cache.host=10.20.0.5
cache.puerto=6379
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

### 2.2 Política (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.random.RandomGenerator;

/**
 * Política de cache-aside: nombre de clave con prefijo y versión, y TTL con jitter
 * para que las claves no venzan todas a la vez. Puro.
 */
public final class PoliticaDeCache {

    private PoliticaDeCache() {
    }

    public static String clave(String dominio, int version, String id) {
        if (id.isBlank() || id.contains(" ")) {
            throw new IllegalArgumentException("id inválido");
        }
        return dominio + ":v" + version + ":" + id;
    }

    /** base ± fraccion (p. ej. 600 s ± 10 %). */
    public static Duration ttl(Duration base, double fraccion, RandomGenerator azar) {
        long seg = base.toSeconds();
        long delta = Math.round(seg * fraccion);
        long valor = seg - delta + (delta == 0 ? 0 : azar.nextLong(2 * delta + 1));
        return Duration.ofSeconds(Math.max(1, valor));
    }
}
```

### 2.3 Adaptador con Lettuce
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import io.lettuce.core.RedisClient;
import io.lettuce.core.RedisCredentials;
import io.lettuce.core.RedisCredentialsProvider;
import io.lettuce.core.RedisURI;
import io.lettuce.core.api.StatefulRedisConnection;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.function.Supplier;
import java.util.random.RandomGenerator;

/**
 * Adaptador: cache-aside con Lettuce sobre TLS y autenticación IAM (token de acceso como contraseña,
 * renovado en cada reconexión). Si la caché falla, se degrada a la fuente.
 */
public class CacheGcp implements AutoCloseable {

    private final RedisClient cliente;
    private final StatefulRedisConnection<String, String> conexion;
    private final RandomGenerator azar = RandomGenerator.getDefault();

    public CacheGcp(GoogleCredentials cred, String host, int puerto) {
        var scoped = cred.createScoped(List.of("https://www.googleapis.com/auth/cloud-platform"));
        RedisCredentialsProvider tokens = RedisCredentialsProvider.from(() -> RedisCredentials.just("default", token(scoped)));
        var uri = RedisURI.builder().withHost(host).withPort(puerto).withSsl(true)
            .withAuthentication(tokens).withTimeout(Duration.ofMillis(300)).build();
        this.cliente = RedisClient.create(uri);
        this.conexion = cliente.connect();
    }

    private static String token(GoogleCredentials c) {
        try {
            c.refreshIfExpired();
            return c.getAccessToken().getTokenValue();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public String obtener(String clave, Duration ttlBase, Supplier<String> fuente) {
        Optional<String> enCache;
        try {
            enCache = Optional.ofNullable(conexion.sync().get(clave));
        } catch (RuntimeException e) {
            return fuente.get();                       // caché caída: degradar
        }
        if (enCache.isPresent()) {
            return enCache.get();
        }
        String valor = fuente.get();
        try {
            conexion.sync().setex(clave, PoliticaDeCache.ttl(ttlBase, 0.1, azar).toSeconds(), valor);
        } catch (RuntimeException e) {
            // no guardar no es un error de negocio
        }
        return valor;
    }

    @Override
    public void close() {
        conexion.close();
        cliente.shutdown();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;

public class ServicioDeCatalogo {

    private final CacheGcp cache;

    public ServicioDeCatalogo(CacheGcp cache) {
        this.cache = cache;
    }

    public String producto(String id) {
        return cache.obtener(PoliticaDeCache.clave("producto", 1, id), Duration.ofMinutes(10),
            () -> "{\"id\":\"" + id + "\",\"origen\":\"base\"}");   // en la app real: el repositorio
    }

    public long ttl(long baseSegundos) {
        return PoliticaDeCache.ttl(Duration.ofSeconds(baseSegundos), 0.1, java.util.random.RandomGenerator.getDefault()).toSeconds();
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class CatalogoConfiguracion {

    @Bean(destroyMethod = "close")
    CacheGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${cache.host}") String host, @Value("${cache.puerto}") String puerto) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new CacheGcp(cred, host, Integer.parseInt(puerto));
    }

    @Bean
    ServicioDeCatalogo servicio(CacheGcp a) {
        return new ServicioDeCatalogo(a);
    }
}

@RestController
@RequestMapping("/datos/catalogo")
class CatalogoControlador {

    private final ServicioDeCatalogo s;

    CatalogoControlador(ServicioDeCatalogo s) {
        this.s = s;
    }

    @GetMapping("/{id}")
    String producto(@PathVariable String id) {
        return s.producto(id);
    }

    @GetMapping("/ttl")
    Long ttl(@RequestParam long base) {
        return s.ttl(base);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/catalogo")
class CatalogoReactivoControlador {

    private final ServicioDeCatalogo s;

    CatalogoReactivoControlador(ServicioDeCatalogo s) {
        this.s = s;
    }

    @GetMapping("/{id}")
    Mono<String> producto(@PathVariable String id) {
        return Mono.fromCallable(() -> s.producto(id)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/ttl")
    Mono<Long> ttl(@RequestParam long base) {
        return Mono.fromCallable(() -> s.ttl(base));
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class CatalogoProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "cache.host")
    String host;

    @ConfigProperty(name = "cache.puerto")
    String puerto;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CacheGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new CacheGcp(cred, host, Integer.parseInt(puerto));
    }

    void cerrar(@Disposes CacheGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCatalogo servicio(CacheGcp a) {
        return new ServicioDeCatalogo(a);
    }
}

@Path("/datos/catalogo")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class CatalogoRecurso {

    @Inject
    ServicioDeCatalogo s;

    @GET
    @Path("/{id}")
    public String producto(@PathParam("id") String id) {
        return s.producto(id);
    }

    @GET
    @Path("/ttl")
    public Long ttl(@QueryParam("base") long base) {
        return s.ttl(base);
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
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/datos/catalogo")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class CatalogoRecursoReactivo {

    @Inject
    ServicioDeCatalogo s;

    @GET
    @Path("/{id}")
    public Uni<String> producto(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> s.producto(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/ttl")
    public Uni<Long> ttl(@QueryParam("base") long base) {
        return Uni.createFrom().item(() -> s.ttl(base));
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Conectar con IAM | `roles/memorystore.dbConnectionUser` *(verifica)* |
| Administrar instancias | `roles/memorystore.admin` |

## 8. Qué NO hacer desde Java
- No guardes claves sin TTL.
- No dejes que un fallo de la caché tumbe la petición.
- No uses `KEYS *`.
- No pongas la cadena AUTH en la configuración: Secret Manager o IAM.
