# Oracle OCI · Datos · OCI Cache · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

**Cache-aside bien hecho**: claves con servicio y versión (`catalogo:v3:POL-01`), TTL con *jitter*, un solo regenerador por clave para evitar estampidas y degradación a la fuente si la caché falla. El almacén es una interfaz que en la app real implementas sobre `StringRedisTemplate` (Spring Data Redis/Lettuce) o `RedisDataSource` (Quarkus); el adaptador del SDK descubre los endpoints `rediss://` con `RedisClusterClient`.

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

### 2.2 Cache-aside (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.DoubleSupplier;
import java.util.function.Supplier;

/**
 * Cache-aside con TTL + jitter, un solo regenerador por clave (anti-estampida)
 * y degradación a la fuente si la caché falla. Puro: el almacén y el azar se inyectan.
 */
public class CacheAside {

    /** Lo implementa StringRedisTemplate (Spring) o RedisDataSource (Quarkus) en la app real. */
    public interface Almacen {
        Optional<String> leer(String clave);

        void escribir(String clave, String valor, Duration ttl);
    }

    private final Almacen almacen;
    private final Duration ttlBase;
    private final DoubleSupplier azar;
    private final ConcurrentHashMap<String, CompletableFuture<String>> enVuelo = new ConcurrentHashMap<>();

    public CacheAside(Almacen almacen, Duration ttlBase, DoubleSupplier azar) {
        this.almacen = almacen;
        this.ttlBase = ttlBase;
        this.azar = azar;
    }

    public static String clave(String servicio, int version, String id) {
        if (!servicio.matches("[a-z]{2,20}") || !id.matches("[A-Za-z0-9-]{1,64}")) {
            throw new IllegalArgumentException("clave inválida");
        }
        return servicio + ":v" + version + ":" + id;
    }

    /** TTL ±20 % para que las claves no expiren todas juntas. */
    public Duration ttlConJitter() {
        double factor = 0.8 + 0.4 * azar.getAsDouble();
        return Duration.ofMillis((long) (ttlBase.toMillis() * factor));
    }

    public String obtener(String clave, Supplier<String> fuente) {
        try {
            var v = almacen.leer(clave);
            if (v.isPresent()) {
                return v.get();
            }
        } catch (RuntimeException caidaDeCache) {
            return fuente.get(); // la caché acelera, no es requisito
        }
        var nuevo = new CompletableFuture<String>();
        var existente = enVuelo.putIfAbsent(clave, nuevo);
        if (existente != null) {
            return existente.join(); // otro hilo ya está regenerando
        }
        try {
            String valor = fuente.get();
            try {
                almacen.escribir(clave, valor, ttlConJitter());
            } catch (RuntimeException ignorada) {
                // si no se pudo guardar, igual respondemos
            }
            nuevo.complete(valor);
            return valor;
        } catch (RuntimeException e) {
            nuevo.completeExceptionally(e);
            throw e;
        } finally {
            enVuelo.remove(clave, nuevo);
        }
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.redis.RedisClusterClient;
import com.oracle.bmc.redis.requests.GetRedisClusterRequest;

/** Adaptador del SDK: descubre endpoints del clúster para configurar el cliente Redis al arrancar. */
public class CacheOci implements AutoCloseable {

    public record Endpoints(String estado, String uriPrimario, String uriReplicas, String modo) { }

    private final RedisClusterClient cliente;

    public CacheOci(RedisClusterClient cliente) {
        this.cliente = cliente;
    }

    public Endpoints endpoints(String clusterId) {
        var c = cliente.getRedisCluster(GetRedisClusterRequest.builder().redisClusterId(clusterId).build()).getRedisCluster();
        return new Endpoints(c.getLifecycleState().getValue(), "rediss://" + c.getPrimaryFqdn() + ":6379",
            "rediss://" + c.getReplicasFqdn() + ":6379", c.getClusterMode() == null ? "NONSHARDED" : c.getClusterMode().getValue());
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
import java.time.Duration;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;

public class ServicioDeCatalogo {

    private final CacheOci cache;
    // Demo: almacén en memoria. En la app real inyecta el adaptador sobre StringRedisTemplate o RedisDataSource.
    private final Map<String, String> memoria = new ConcurrentHashMap<>();
    private final CacheAside cacheAside = new CacheAside(new CacheAside.Almacen() {
        public Optional<String> leer(String clave) {
            return Optional.ofNullable(memoria.get(clave));
        }

        public void escribir(String clave, String valor, Duration ttl) {
            memoria.put(clave, valor);
        }
    }, Duration.ofMinutes(10), () -> ThreadLocalRandom.current().nextDouble());

    public ServicioDeCatalogo(CacheOci cache) {
        this.cache = cache;
    }

    public CacheOci.Endpoints endpoints(String clusterId) {
        return cache.endpoints(clusterId);
    }

    public String ficha(String sku) {
        return cacheAside.obtener(CacheAside.clave("catalogo", 3, sku), () -> "{\"sku\":\"" + sku + "\",\"precio\":39.90}");
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.redis.RedisClusterClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class CatalogoConfiguracion {

    @Bean(destroyMethod = "close")
    CacheOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CacheOci(RedisClusterClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeCatalogo servicio(CacheOci a) {
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

    @GetMapping("/cache/{id}")
    CacheOci.Endpoints endpoints(@PathVariable String id) {
        return s.endpoints(id);
    }

    @GetMapping("/{sku}")
    String ficha(@PathVariable String sku) {
        return s.ficha(sku);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.redis.RedisClusterClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
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

    @GetMapping("/cache/{id}")
    Mono<CacheOci.Endpoints> endpoints(@PathVariable String id) {
        return Mono.fromCallable(() -> s.endpoints(id)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/{sku}")
    Mono<String> ficha(@PathVariable String sku) {
        return Mono.fromCallable(() -> s.ficha(sku)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.redis.RedisClusterClient;
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
class CatalogoProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CacheOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CacheOci(RedisClusterClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes CacheOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCatalogo servicio(CacheOci a) {
        return new ServicioDeCatalogo(a);
    }
}

@Path("/datos/catalogo")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class CatalogoRecurso {

    @Inject
    ServicioDeCatalogo s;

    @GET
    @Path("/cache/{id}")
    public CacheOci.Endpoints endpoints(@PathParam("id") String id) {
        return s.endpoints(id);
    }

    @GET
    @Path("/{sku}")
    public String ficha(@PathParam("sku") String sku) {
        return s.ficha(sku);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.redis.RedisClusterClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/datos/catalogo")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class CatalogoRecursoReactivo {

    @Inject
    ServicioDeCatalogo s;

    @GET
    @Path("/cache/{id}")
    public Uni<CacheOci.Endpoints> endpoints(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> s.endpoints(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/{sku}")
    public Uni<String> ficha(@PathParam("sku") String sku) {
        return Uni.createFrom().item(() -> s.ficha(sku)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Descubrir endpoints | `Allow dynamic-group app-tienda to read redis-clusters in compartment datos-prod` |
| Contraseña del usuario de caché | `Allow dynamic-group app-tienda to read secret-bundles in compartment datos-prod where target.secret.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No uses la caché como fuente de verdad.
- No guardes claves sin TTL.
- No hagas que un *timeout* de la caché tumbe la petición.
- No uses `KEYS *`; usa `SCAN`.
- No llames a Lettuce bloqueante dentro del hilo de eventos: usa la API reactiva en WebFlux/Mutiny.
