# AWS · Parameter Store · Uso desde Java

Tres maneras de leer la configuración, de la más simple a la más controlada: **(A)** `spring.config.import` (Spring Cloud AWS), **(B)** cliente SSM + **caché tipada con refresco** (este documento, funciona igual en Spring y Quarkus) y **(C)** una `ConfigSource` propia en Quarkus. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56), Spring Cloud AWS 4.2.

## 1. Núcleo común: leer la rama, tipar, cachear

Tres piezas separadas: quien **lee** (`LectorSsm`), quien **interpreta** (`Configuracion`, pura: se prueba sin AWS) y quien **cachea** (`CacheConfiguracion`, con TTL y «última buena» si SSM falla).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParametersByPathRequest;
import software.amazon.awssdk.services.ssm.model.Parameter;
import software.amazon.awssdk.services.ssm.model.ParameterType;

/** Un parámetro leído. El toString NUNCA imprime el valor de un SecureString. */
record Parametro(String nombre, String valor, ParameterType tipo, long version) {
    boolean seguro() {
        return tipo == ParameterType.SECURE_STRING;
    }

    @Override
    public String toString() {
        return "Parametro[" + nombre + ", " + tipo + ", v" + version + ", valor=" + (seguro() ? "***" : valor) + "]";
    }
}

interface LectorParametros {
    List<Parametro> leerRama(String ruta);
}

final class LectorSsm implements LectorParametros {
    private final SsmClient ssm;

    LectorSsm(SsmClient ssm) {
        this.ssm = ssm;
    }

    @Override
    public List<Parametro> leerRama(String ruta) {
        var req = GetParametersByPathRequest.builder().path(ruta).recursive(true).withDecryption(true).build();
        List<Parametro> resultado = new ArrayList<>();
        // El paginator sigue el NextToken solo (cada página trae hasta 10 parámetros)
        for (var pagina : ssm.getParametersByPathPaginator(req)) {
            for (Parameter p : pagina.parameters()) {
                resultado.add(new Parametro(p.name(), p.value(), p.type(), p.version()));
            }
        }
        return resultado;
    }
}

/** Foto de la configuración con lecturas tipadas, límites y valores por defecto. Lógica pura. */
final class Configuracion {
    private final String base;
    private final Map<String, Parametro> porClave = new TreeMap<>();   // clave relativa: "db/pool-max"
    private final Set<String> avisos = ConcurrentHashMap.newKeySet();

    Configuracion(String base, List<Parametro> parametros) {
        this.base = base.endsWith("/") ? base.substring(0, base.length() - 1) : base;
        for (Parametro p : parametros) {
            porClave.put(claveRelativa(this.base, p.nombre()), p);
        }
    }

    /** "/prod/pedidos" + "/prod/pedidos/db/pool-max" -> "db/pool-max" */
    static String claveRelativa(String base, String nombre) {
        String r = nombre.startsWith(base) ? nombre.substring(base.length()) : nombre;
        return r.startsWith("/") ? r.substring(1) : r;
    }

    /** "db/pool-max" -> "db.pool-max" (nombre de propiedad al estilo Spring/MicroProfile) */
    static String aPropiedad(String claveRelativa) {
        return claveRelativa.replace('/', '.');
    }

    String texto(String clave, String defecto) {
        Parametro p = porClave.get(clave);
        if (p == null) {
            avisos.add("falta " + clave + " (uso el valor por defecto)");
            return defecto;
        }
        return p.valor();
    }

    int entero(String clave, int defecto, int min, int max) {
        Parametro p = porClave.get(clave);
        if (p == null) {
            avisos.add("falta " + clave + " (uso " + defecto + ")");
            return defecto;
        }
        try {
            int v = Integer.parseInt(p.valor().trim());
            if (v < min || v > max) {
                avisos.add(clave + "=" + v + " fuera de [" + min + "," + max + "] (uso " + defecto + ")");
                return defecto;
            }
            return v;
        } catch (NumberFormatException e) {
            avisos.add(clave + " no es un entero (uso " + defecto + ")");
            return defecto;
        }
    }

    /** Solo acepta true/false: "ture" no se interpreta como false en silencio. */
    boolean booleano(String clave, boolean defecto) {
        Parametro p = porClave.get(clave);
        if (p == null) {
            avisos.add("falta " + clave + " (uso " + defecto + ")");
            return defecto;
        }
        String v = p.valor().trim();
        if (v.equalsIgnoreCase("true")) return true;
        if (v.equalsIgnoreCase("false")) return false;
        avisos.add(clave + " no es true/false (uso " + defecto + ")");
        return defecto;
    }

    /** Para parámetros StringList: "a, b,c" -> [a, b, c] */
    List<String> lista(String clave) {
        Parametro p = porClave.get(clave);
        if (p == null || p.valor().isBlank()) return List.of();
        return Arrays.stream(p.valor().split(",")).map(String::trim).filter(s -> !s.isEmpty()).toList();
    }

    /** Qué hay y en qué versión, sin ningún valor: seguro para exponer en un endpoint interno. */
    Map<String, String> estado() {
        Map<String, String> r = new TreeMap<>();
        porClave.forEach((k, p) -> r.put(k, p.tipo() + " v" + p.version()));
        return r;
    }

    List<String> avisos() {
        return avisos.stream().sorted().toList();
    }

    /** Propiedades al estilo MicroProfile/Spring para una ConfigSource. */
    Map<String, String> comoPropiedades() {
        Map<String, String> r = new TreeMap<>();
        porClave.forEach((k, p) -> r.put(aPropiedad(k), p.valor()));
        return r;
    }
}

/** Caché con TTL. Si SSM falla y hay una versión anterior, la conserva y reintenta pronto. */
final class CacheConfiguracion {
    private static final Duration REINTENTO = Duration.ofSeconds(30);

    private final LectorParametros lector;
    private final String base;
    private final Duration ttl;
    private final Clock reloj;
    private volatile Configuracion actual;
    private volatile Instant venceEn = Instant.EPOCH;
    private volatile int fallosSeguidos;

    CacheConfiguracion(LectorParametros lector, String base, Duration ttl, Clock reloj) {
        this.lector = lector;
        this.base = base;
        this.ttl = ttl;
        this.reloj = reloj;
    }

    Configuracion obtener() {
        Configuracion a = actual;
        if (a != null && reloj.instant().isBefore(venceEn)) return a;
        return refrescar(false);
    }

    /** Fuerza la recarga (para el refresco en segundo plano). */
    void refrescarAhora() {
        refrescar(true);
    }

    int fallosSeguidos() {
        return fallosSeguidos;
    }

    private synchronized Configuracion refrescar(boolean forzar) {
        Instant ahora = reloj.instant();
        if (!forzar && actual != null && ahora.isBefore(venceEn)) return actual;   // otro hilo ya lo hizo
        try {
            actual = new Configuracion(base, lector.leerRama(base));
            venceEn = ahora.plus(ttl);
            fallosSeguidos = 0;
            return actual;
        } catch (RuntimeException e) {
            fallosSeguidos++;
            if (actual == null) throw e;          // arranque sin configuración: que falle ruidosamente
            venceEn = ahora.plus(REINTENTO);      // sigo con la última buena y reintento pronto
            return actual;
        }
    }
}
```

## 2. Spring MVC (imperativo)
Se carga **al arrancar** (si falla, la aplicación no sube: mejor que servir con valores a medias) y luego se refresca por TTL.
```java
import java.time.Clock;
import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ssm.SsmClient;

@Configuration
class ParametrosConfig {
    @Bean(destroyMethod = "close")
    SsmClient ssm() {
        return SsmClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    CacheConfiguracion cacheConfiguracion(SsmClient ssm,
                                          @Value("${config.ruta:/prod/pedidos}") String ruta,
                                          @Value("${config.ttl:PT5M}") Duration ttl) {
        return new CacheConfiguracion(new LectorSsm(ssm), ruta, ttl, Clock.systemUTC());
    }

    @Bean
    ApplicationRunner precargaDeConfiguracion(CacheConfiguracion cache) {
        return args -> cache.obtener();      // falla el arranque si no se puede leer la rama
    }
}

@Component
class LimitesDePedido {
    private final CacheConfiguracion cache;

    LimitesDePedido(CacheConfiguracion cache) {
        this.cache = cache;
    }

    int maxItems() {
        return cache.obtener().entero("pedidos/max-items", 50, 1, 500);
    }

    boolean nuevaUi() {
        return cache.obtener().booleano("features/nueva-ui", false);
    }
}

@RestController
class ConfigController {
    private final CacheConfiguracion cache;

    ConfigController(CacheConfiguracion cache) {
        this.cache = cache;
    }

    /** Solo nombres y versiones; JAMÁS valores. Protégelo como endpoint interno. */
    @GetMapping("/interno/config/estado")
    Map<String, Object> estado() {
        Configuracion c = cache.obtener();
        return Map.of("parametros", c.estado(), "avisos", c.avisos(), "fallosSeguidos", cache.fallosSeguidos());
    }
}

@Component
class ConfigHealth implements HealthIndicator {
    private final CacheConfiguracion cache;

    ConfigHealth(CacheConfiguracion cache) {
        this.cache = cache;
    }

    @Override
    public Health health() {
        // Con la última buena en memoria el servicio sigue sirviendo: UP, pero con el detalle visible
        return Health.up().withDetail("fallosSeguidos", cache.fallosSeguidos()).build();
    }
}
```

## 3. Spring WebFlux (reactivo)
El SDK síncrono bloquea; si la caché expiró, la recarga no puede ocurrir en un hilo de Netty. Se aísla en `boundedElastic` y se refresca en segundo plano para que las peticiones casi nunca la paguen.
```java
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.util.Map;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.Disposable;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class ConfigReactivoController {
    private final CacheConfiguracion cache;

    ConfigReactivoController(CacheConfiguracion cache) {
        this.cache = cache;
    }

    @GetMapping("/interno/config/estado")
    Mono<Map<String, Object>> estado() {
        return Mono.fromCallable(() -> {
            Configuracion c = cache.obtener();
            return Map.<String, Object>of("parametros", c.estado(), "avisos", c.avisos(),
                    "fallosSeguidos", cache.fallosSeguidos());
        }).subscribeOn(Schedulers.boundedElastic());
    }
}

@Component
class RefrescoEnSegundoPlano {
    private final Disposable tarea;

    RefrescoEnSegundoPlano(CacheConfiguracion cache) {
        this.tarea = Flux.interval(Duration.ofMinutes(4))
                .concatMap(t -> Mono.fromRunnable(cache::refrescarAhora)
                        .subscribeOn(Schedulers.boundedElastic())
                        .onErrorResume(e -> Mono.empty()))      // un fallo no mata el refresco
                .subscribe();
    }

    @PreDestroy
    void parar() {
        tarea.dispose();
    }
}
```

## 4. Quarkus (imperativo)
Con la extensión `quarkus-amazon-ssm` el `SsmClient` ya existe como bean (`quarkus.ssm.aws.region=us-east-1`); solo falta el productor de la caché. Se usa `@Singleton` porque las clases del núcleo son `final` (sin proxy).
```java
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.time.Clock;
import java.time.Duration;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.ssm.SsmClient;

@Singleton
class ParametrosProductores {
    @Produces
    @Singleton
    CacheConfiguracion cache(SsmClient ssm,
                             @ConfigProperty(name = "config.ruta", defaultValue = "/prod/pedidos") String ruta,
                             @ConfigProperty(name = "config.ttl", defaultValue = "PT5M") Duration ttl) {
        return new CacheConfiguracion(new LectorSsm(ssm), ruta, ttl, Clock.systemUTC());
    }

    /** Falla el arranque si la rama no se puede leer. */
    void alArrancar(@Observes StartupEvent evento, CacheConfiguracion cache) {
        cache.obtener();
    }
}

@Path("/interno/config")
class ConfigRecurso {
    @Inject
    CacheConfiguracion cache;

    @GET
    @Path("/estado")
    @jakarta.ws.rs.Produces("application/json")
    Map<String, Object> estado() {
        Configuracion c = cache.obtener();
        return Map.of("parametros", c.estado(), "avisos", c.avisos(), "fallosSeguidos", cache.fallosSeguidos());
    }
}
```

### Quarkus: una `ConfigSource` propia (los parámetros como `@ConfigProperty`)
Así `@ConfigProperty(name = "db.pool-max")` lee de Parameter Store sin cambiar el resto del código. Se registra en `META-INF/services/org.eclipse.microprofile.config.spi.ConfigSourceProvider`. El cliente se crea **a mano** porque la configuración se resuelve antes de que exista CDI. Ordinal 270: gana a `application.properties` (250) y pierde frente a variables de entorno (300).
```java
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.eclipse.microprofile.config.spi.ConfigSource;
import org.eclipse.microprofile.config.spi.ConfigSourceProvider;
import software.amazon.awssdk.services.ssm.SsmClient;

public class SsmConfigSourceProvider implements ConfigSourceProvider {
    @Override
    public Iterable<ConfigSource> getConfigSources(ClassLoader cl) {
        String ruta = System.getenv("CONFIG_SSM_RUTA");
        if (ruta == null || ruta.isBlank()) {
            return List.of();       // sin ruta (build, tests, desarrollo): no hace nada
        }
        try (SsmClient ssm = SsmClient.create()) {
            Configuracion cfg = new Configuracion(ruta, new LectorSsm(ssm).leerRama(ruta));
            return List.of(new MapaConfigSource("ssm:" + ruta, cfg.comoPropiedades()));
        }
    }
}

final class MapaConfigSource implements ConfigSource {
    private final String nombre;
    private final Map<String, String> valores;

    MapaConfigSource(String nombre, Map<String, String> valores) {
        this.nombre = nombre;
        this.valores = Map.copyOf(valores);
    }

    @Override
    public Set<String> getPropertyNames() {
        return valores.keySet();
    }

    @Override
    public String getValue(String propertyName) {
        return valores.get(propertyName);
    }

    @Override
    public String getName() {
        return nombre;
    }

    @Override
    public int getOrdinal() {
        return 270;
    }
}
```
Se lee **una vez al arrancar**: para cambiar un valor hay que reiniciar el pod (un *rollout* barato). Si necesitas cambios en caliente, usa la caché del apartado anterior.

## 5. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.util.Map;

@Path("/interno/config-reactivo")
class ConfigReactivoRecurso {
    @Inject
    CacheConfiguracion cache;

    @GET
    @Path("/estado")
    @jakarta.ws.rs.Produces("application/json")
    Uni<Map<String, Object>> estado() {
        return Uni.createFrom().item(() -> {
            Configuracion c = cache.obtener();
            return Map.<String, Object>of("parametros", c.estado(), "avisos", c.avisos(),
                    "fallosSeguidos", cache.fallosSeguidos());
        }).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 6. El atajo sin código: Spring Cloud AWS
Para la mayoría de los servicios Spring Boot basta con esto: la rama completa se convierte en propiedades (`/prod/pedidos/db/pool-max` → `db.pool-max`). Dependencia: `io.awspring.cloud:spring-cloud-aws-starter-parameter-store`.
```yaml
# application.yml
spring:
  config:
    import: "optional:aws-parameterstore:/prod/pedidos/"
  cloud:
    aws:
      region:
        static: us-east-1
      parameterstore:
        reload:
          strategy: refresh     # recarga periódica de los beans @ConfigurationProperties (verifica opciones en la doc)
          period: PT5M
```
```java
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "db")
record DbProps(String url, int poolMax) {}
```
`optional:` hace que la aplicación **arranque aunque no exista la rama** (útil en local y en pruebas); en producción quita `optional:` para que falle rápido.

## 7. Rendimiento y costo
- **Una llamada por rama**, no por valor: `GetParametersByPath` devuelve páginas de hasta 10; una rama de 40 parámetros son 4 llamadas, cada 5 minutos, por instancia.
- Con muchas réplicas, el TTL se multiplica por pods: 200 pods × 12 lecturas/hora × 4 páginas = ~9 600 llamadas/hora. Si te acercas a la cuota, **alarga el TTL** o activa el rendimiento alto (con costo, *verifica*).
- El `SsmClient` es **thread-safe** y caro de crear: uno por aplicación.
- Los `SecureString` suman una llamada a KMS por valor descifrado (con costo y cuota propios).

## 8. Qué NO hacer desde Java
- ❌ `GetParameter` en cada petición.
- ❌ Loguear valores o imprimir `Parametro` sin redacción (aquí el `toString` ya lo enmascara).
- ❌ Interpretar `"ture"` como `false` en silencio: valida y avisa.
- ❌ Arrancar con configuración a medias: falla rápido si falta lo imprescindible, usa valores por defecto solo para lo opcional.
- ❌ Bloquear hilos de Netty/event-loop con el SDK síncrono: `boundedElastic` / pool de trabajadores.
- ❌ Exponer valores en un endpoint de depuración (solo nombres y versiones).
