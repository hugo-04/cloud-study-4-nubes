# AWS · ElastiCache · Uso desde Java

Con una caché, lo importante no es el comando `GET`: es **qué haces cuando falla, cuando vence y cuando todos preguntan a la vez**. Por eso el núcleo común son seis piezas pequeñas y probadas: **claves y slots**, **TTL con azar**, **cache-aside** (con una sola recarga por clave y caché negativa), **limitador por ventana**, **candado con token** y los **scripts Lua**. Versiones: Java 21, Spring Boot 4.1 (Spring Data Redis + Lettuce), Quarkus 3.40 (cliente Redis), Valkey/Redis OSS en ElastiCache con TLS.

## 1. Configuración
```yaml
# Spring Boot (application.yml) — TLS y usuario ACL; la contraseña viene de Secrets Manager (variable de entorno)
spring:
  data:
    redis:
      host: ${REDIS_HOST}                 # endpoint primario (modo clúster deshabilitado)
      port: 6379
      username: app
      password: ${REDIS_PASSWORD}
      timeout: 300ms                      # tiempo máximo por comando: corto, la caché es opcional
      connect-timeout: 1s
      ssl:
        enabled: true                     # el grupo tiene cifrado en tránsito
      # Modo clúster habilitado: usa el endpoint de configuración
      # cluster:
      #   nodes: ${REDIS_HOST}:6379
app:
  entorno: prod
```
```properties
# Quarkus (application.properties)
quarkus.redis.hosts=rediss://${REDIS_HOST}:6379
quarkus.redis.user=app
quarkus.redis.password=${REDIS_PASSWORD}
quarkus.redis.timeout=300ms
quarkus.redis.max-pool-size=16
quarkus.redis.max-pool-waiting=64
# Modo clúster habilitado: quarkus.redis.client-type=cluster y el endpoint de configuración
app.entorno=prod
```
**DNS y failover:** tras un failover el nombre del endpoint apunta a otro nodo. Limita el caché de DNS de la JVM (`-Dnetworkaddress.cache.ttl=10`, o `networkaddress.cache.ttl` en `java.security`) para seguirlo rápido.

## 2. Núcleo común

### 2.1 Claves y slots
Nombres con **prefijo de aplicación y entorno** (nunca choques entre ambientes) y, en modo clúster, **etiquetas de hash** para que claves relacionadas caigan en el mismo slot. `slot(...)` replica el cálculo del servidor (CRC16 módulo 16 384) para que puedas comprobar tus diseños sin conectarte.
```java
// (clase reutilizada en los bloques siguientes, ambos)
public final class ClavesRedis {
    private ClavesRedis() {}

    private static String parte(String valor) {
        if (valor == null || valor.isBlank() || valor.indexOf(' ') >= 0 || valor.indexOf(':') >= 0) {
            throw new IllegalArgumentException("parte de clave inválida: " + valor);
        }
        return valor;
    }

    /** app:prod:producto:A1 */
    public static String clave(String entorno, String tipo, String id) {
        return "app:" + parte(entorno) + ":" + parte(tipo) + ":" + parte(id);
    }

    /** app:prod:{cliente-42}:carrito  → todas las claves con la misma etiqueta comparten slot */
    public static String conEtiqueta(String entorno, String etiqueta, String tipo) {
        return "app:" + parte(entorno) + ":{" + parte(etiqueta) + "}:" + parte(tipo);
    }

    /** CRC16 (XMODEM) % 16384, usando solo el contenido de la primera {etiqueta} no vacía, como el servidor. */
    public static int slot(String clave) {
        String hash = clave;
        int abre = clave.indexOf('{');
        if (abre >= 0) {
            int cierra = clave.indexOf('}', abre + 1);
            if (cierra > abre + 1) {
                hash = clave.substring(abre + 1, cierra);
            }
        }
        int crc = 0;
        for (byte b : hash.getBytes(java.nio.charset.StandardCharsets.UTF_8)) {
            crc ^= (b & 0xFF) << 8;
            for (int i = 0; i < 8; i++) {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
                crc &= 0xFFFF;
            }
        }
        return crc % 16_384;
    }
}
```

### 2.2 TTL con azar
Sin azar, miles de claves creadas juntas **vencen juntas** (avalancha). Con ±20 % se reparten en el tiempo.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.function.DoubleSupplier;

public final class TtlConAzar {
    private TtlConAzar() {}

    /** base × (1 ± fraccion). fraccion en [0, 0.5]. */
    public static Duration con(Duration base, double fraccion, DoubleSupplier azar) {
        if (fraccion < 0 || fraccion > 0.5) {
            throw new IllegalArgumentException("fraccion debe estar entre 0 y 0.5");
        }
        double factor = 1 + fraccion * (2 * azar.getAsDouble() - 1);
        return Duration.ofMillis(Math.max(1, Math.round(base.toMillis() * factor)));
    }
}
```

### 2.3 Comandos mínimos y scripts
Una interfaz pequeña separa la **lógica** (cache-aside, limitador, candado) del **cliente** (Spring o Quarkus): se prueba sin servidor y se cambia de cliente sin tocar la lógica. Los scripts hacen atómico lo que son dos pasos.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.Optional;

public interface Comandos {
    Optional<String> leer(String clave);

    void guardar(String clave, String valor, Duration ttl);

    void borrar(String clave);

    /** SET NX PX: true solo si la clave no existía. */
    boolean guardarSiNoExiste(String clave, String valor, Duration ttl);

    /** Borra solo si el valor coincide (script): true si borró. */
    boolean borrarSiIgual(String clave, String valor);

    /** INCR y, si es el primero, EXPIRE (script): devuelve el contador. */
    long incrementarConVentana(String clave, Duration ventana);
}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
public final class ScriptsRedis {
    private ScriptsRedis() {}

    /** Mismo contenido que ejemplos/lua/limitador.lua */
    public static final String CONTADOR = """
            local c = redis.call('INCR', KEYS[1])
            if c == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
            return c
            """;

    /** Mismo contenido que ejemplos/lua/liberar-candado.lua */
    public static final String BORRAR_SI_IGUAL = """
            if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end
            return 0
            """;
}
```

### 2.4 Cache-aside robusto
Cuatro defensas en una pieza: **(1)** la caché es opcional (si falla, se va al origen); **(2)** **una sola recarga por clave** dentro del proceso (los demás esperan); **(3)** **caché negativa** corta («no existe»); **(4)** TTL con azar.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.DoubleSupplier;
import java.util.function.Supplier;

public final class CacheAside {
    private static final String NEGATIVO = "\u0000no-existe";

    private final Comandos redis;
    private final Duration ttl;
    private final Duration ttlNegativo;
    private final DoubleSupplier azar;
    private final ConcurrentHashMap<String, CompletableFuture<Optional<String>>> enVuelo = new ConcurrentHashMap<>();
    private final AtomicLong aciertos = new AtomicLong();
    private final AtomicLong fallos = new AtomicLong();
    private final AtomicLong errores = new AtomicLong();

    public CacheAside(Comandos redis, Duration ttl, Duration ttlNegativo, DoubleSupplier azar) {
        this.redis = redis;
        this.ttl = ttl;
        this.ttlNegativo = ttlNegativo;
        this.azar = azar;
    }

    public Optional<String> obtener(String clave, Supplier<Optional<String>> origen) {
        try {
            Optional<String> guardado = redis.leer(clave);
            if (guardado.isPresent()) {
                aciertos.incrementAndGet();
                return NEGATIVO.equals(guardado.get()) ? Optional.empty() : guardado;
            }
        } catch (RuntimeException e) {
            errores.incrementAndGet();   // la caché es opcional: se sigue al origen
        }
        fallos.incrementAndGet();

        CompletableFuture<Optional<String>> mio = new CompletableFuture<>();
        CompletableFuture<Optional<String>> lider = enVuelo.putIfAbsent(clave, mio);
        if (lider != null) {
            try {
                return lider.join();
            } catch (CompletionException e) {
                if (e.getCause() instanceof RuntimeException causa) {
                    throw causa;
                }
                throw e;
            }
        }
        try {
            Optional<String> valor = origen.get();
            guardar(clave, valor);
            mio.complete(valor);
            return valor;
        } catch (RuntimeException e) {
            mio.completeExceptionally(e);
            throw e;
        } finally {
            enVuelo.remove(clave, mio);
        }
    }

    private void guardar(String clave, Optional<String> valor) {
        try {
            if (valor.isPresent()) {
                redis.guardar(clave, valor.get(), TtlConAzar.con(ttl, 0.2, azar));
            } else {
                redis.guardar(clave, NEGATIVO, ttlNegativo);
            }
        } catch (RuntimeException e) {
            errores.incrementAndGet();
        }
    }

    /** Tras modificar el origen: borra la clave (el siguiente lector la recarga). */
    public void invalidar(String clave) {
        try {
            redis.borrar(clave);
        } catch (RuntimeException e) {
            errores.incrementAndGet();
        }
    }

    public long aciertos() { return aciertos.get(); }
    public long fallos() { return fallos.get(); }
    public long errores() { return errores.get(); }
}
```

### 2.5 Limitador por ventana y candado
El limitador cuenta por **tramos de tiempo** (el tramo forma parte de la clave, así que cada tramo se reinicia solo). Es simple y barato; permite ráfagas en el cambio de tramo. El candado usa **ficha propia** y se libera **solo si la ficha coincide**.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;

public final class LimitadorVentana {
    public record Decision(boolean permitido, long usadas, long restantes, long reintentarEnSegundos) {}

    private final Comandos redis;
    private final int limite;
    private final Duration ventana;
    private final Clock reloj;
    private final boolean permitirSiFalla;

    /** @param permitirSiFalla true = si la caché cae, no bloquear a nadie (suele ser lo correcto para proteger la experiencia) */
    public LimitadorVentana(Comandos redis, int limite, Duration ventana, Clock reloj, boolean permitirSiFalla) {
        this.redis = redis;
        this.limite = limite;
        this.ventana = ventana;
        this.reloj = reloj;
        this.permitirSiFalla = permitirSiFalla;
    }

    public Decision intentar(String sujeto) {
        long segundos = ventana.toSeconds();
        long ahora = reloj.instant().getEpochSecond();
        String clave = "rl:" + sujeto + ":" + (ahora / segundos);
        long usadas;
        try {
            usadas = redis.incrementarConVentana(clave, ventana);
        } catch (RuntimeException e) {
            return new Decision(permitirSiFalla, 0, limite, 0);
        }
        boolean permitido = usadas <= limite;
        return new Decision(permitido, usadas, Math.max(0, limite - usadas), permitido ? 0 : segundos - (ahora % segundos));
    }
}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.Optional;
import java.util.function.Supplier;

/**
 * Exclusión mutua "de buena fe": sirve para no duplicar trabajo. Si la acción dura más que el
 * vencimiento, habrá dos dueños; la acción debe ser idempotente o la corrección debe garantizarse en la base.
 */
public final class Candado {
    private final Comandos redis;
    private final Supplier<String> fichas;

    public Candado(Comandos redis, Supplier<String> fichas) {
        this.redis = redis;
        this.fichas = fichas;
    }

    public Optional<String> adquirir(String recurso, Duration ttl) {
        String ficha = fichas.get();
        return redis.guardarSiNoExiste("lock:" + recurso, ficha, ttl) ? Optional.of(ficha) : Optional.empty();
    }

    public boolean liberar(String recurso, String ficha) {
        return redis.borrarSiIgual("lock:" + recurso, ficha);
    }

    /** Vacío si otro tiene el candado; si no, ejecuta y libera (aunque falle). */
    public <T> Optional<T> conCandado(String recurso, Duration ttl, Supplier<T> accion) {
        Optional<String> ficha = adquirir(recurso, ttl);
        if (ficha.isEmpty()) {
            return Optional.empty();
        }
        try {
            return Optional.ofNullable(accion.get());
        } finally {
            liberar(recurso, ficha.get());
        }
    }
}
```

### 2.6 Modelo y repositorio de ejemplo
El producto y el repositorio **de origen** (el que de verdad guarda: [DynamoDB](../dynamodb/README.md), [Aurora](../rds-aurora/README.md)); la caché solo lo acelera.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.util.Optional;

public record Producto(String sku, String nombre, BigDecimal precio) {}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Optional;

public interface CatalogoRepo {
    Optional<Producto> buscar(String sku);

    Producto guardar(Producto producto);
}
```

## 3. Spring MVC (imperativo)
```java
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.data.redis.autoconfigure.LettuceClientConfigurationBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import io.lettuce.core.ClientOptions;
import tools.jackson.databind.json.JsonMapper;

class ComandosSpring implements Comandos {
    private static final RedisScript<Long> BORRAR = RedisScript.of(ScriptsRedis.BORRAR_SI_IGUAL, Long.class);
    private static final RedisScript<Long> CONTADOR = RedisScript.of(ScriptsRedis.CONTADOR, Long.class);

    private final StringRedisTemplate redis;

    ComandosSpring(StringRedisTemplate redis) {
        this.redis = redis;
    }

    @Override
    public Optional<String> leer(String clave) {
        return Optional.ofNullable(redis.opsForValue().get(clave));
    }

    @Override
    public void guardar(String clave, String valor, Duration ttl) {
        redis.opsForValue().set(clave, valor, ttl);
    }

    @Override
    public void borrar(String clave) {
        redis.delete(clave);
    }

    @Override
    public boolean guardarSiNoExiste(String clave, String valor, Duration ttl) {
        return Boolean.TRUE.equals(redis.opsForValue().setIfAbsent(clave, valor, ttl));
    }

    @Override
    public boolean borrarSiIgual(String clave, String valor) {
        Long r = redis.execute(BORRAR, List.of(clave), valor);
        return r != null && r == 1L;
    }

    @Override
    public long incrementarConVentana(String clave, Duration ventana) {
        Long r = redis.execute(CONTADOR, List.of(clave), Long.toString(ventana.toSeconds()));
        if (r == null) {
            throw new IllegalStateException("el script del contador no devolvió valor");
        }
        return r;
    }
}

@Configuration
class RedisConfig {
    /** Falla rápido mientras reconecta (por defecto el cliente acumula comandos hasta que vuelve). */
    @Bean
    LettuceClientConfigurationBuilderCustomizer lettuceRapido() {
        return b -> b.clientOptions(ClientOptions.builder()
                .autoReconnect(true)
                .disconnectedBehavior(ClientOptions.DisconnectedBehavior.REJECT_COMMANDS)
                .build());
    }

    @Bean
    Comandos comandos(StringRedisTemplate redis) {
        return new ComandosSpring(redis);
    }

    @Bean
    CacheAside cacheAside(Comandos comandos) {
        return new CacheAside(comandos, Duration.ofMinutes(10), Duration.ofSeconds(30), Math::random);
    }

    @Bean
    LimitadorVentana limitador(Comandos comandos) {
        return new LimitadorVentana(comandos, 100, Duration.ofMinutes(1), Clock.systemUTC(), true);
    }

    @Bean
    Candado candado(Comandos comandos) {
        return new Candado(comandos, () -> UUID.randomUUID().toString());
    }
}

@RestController
class CatalogoController {
    private final CacheAside cache;
    private final CatalogoRepo repo;
    private final JsonMapper json;
    private final LimitadorVentana limitador;
    private final Candado candado;
    private final String entorno;

    CatalogoController(CacheAside cache, CatalogoRepo repo, JsonMapper json, LimitadorVentana limitador,
                       Candado candado, @Value("${app.entorno}") String entorno) {
        this.cache = cache;
        this.repo = repo;
        this.json = json;
        this.limitador = limitador;
        this.candado = candado;
        this.entorno = entorno;
    }

    @GetMapping("/catalogo/{sku}")
    ResponseEntity<Producto> buscar(@PathVariable String sku) {
        LimitadorVentana.Decision d = limitador.intentar("catalogo:" + sku);
        if (!d.permitido()) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .header("Retry-After", Long.toString(d.reintentarEnSegundos())).build();
        }
        String clave = ClavesRedis.clave(entorno, "producto", sku);
        Optional<String> texto = cache.obtener(clave, () -> repo.buscar(sku).map(json::writeValueAsString));
        return texto.map(t -> ResponseEntity.ok(json.readValue(t, Producto.class)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PutMapping("/catalogo/{sku}")
    ResponseEntity<Producto> actualizar(@PathVariable String sku, @RequestBody Producto nuevo) {
        Producto guardado = repo.guardar(new Producto(sku, nuevo.nombre(), nuevo.precio()));
        cache.invalidar(ClavesRedis.clave(entorno, "producto", sku));   // primero el origen, después la caché
        return ResponseEntity.ok(guardado);
    }

    /** Un solo generador a la vez: los demás reciben 409 y no repiten el trabajo. */
    @PostMapping("/informes/{id}/generar")
    ResponseEntity<String> generar(@PathVariable String id) {
        return candado.conCandado("informe:" + id, Duration.ofMinutes(10), () -> "generado")
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.status(HttpStatus.CONFLICT).body("ya se está generando"));
    }
}
```

## 4. Spring WebFlux (reactivo)
Aquí el cache-aside se escribe con operadores: el fallo de la caché se convierte en «vacío» (`onErrorResume`) y `switchIfEmpty` va al origen.
```java
import java.time.Duration;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import tools.jackson.databind.json.JsonMapper;

/** Tu repositorio reactivo (R2DBC, cliente asíncrono de DynamoDB…). */
interface CatalogoRepoReactivo {
    Mono<Producto> buscar(String sku);
}

@RestController
class CatalogoReactivoController {
    private static final RedisScript<Long> CONTADOR = RedisScript.of(ScriptsRedis.CONTADOR, Long.class);

    private final ReactiveStringRedisTemplate redis;
    private final CatalogoRepoReactivo repo;
    private final JsonMapper json;
    private final String entorno;

    CatalogoReactivoController(ReactiveStringRedisTemplate redis, CatalogoRepoReactivo repo, JsonMapper json,
                               @Value("${app.entorno}") String entorno) {
        this.redis = redis;
        this.repo = repo;
        this.json = json;
        this.entorno = entorno;
    }

    @GetMapping("/r/catalogo/{sku}")
    Mono<ResponseEntity<Producto>> buscar(@PathVariable String sku) {
        String clave = ClavesRedis.clave(entorno, "producto", sku);
        return limitar("catalogo:" + sku).flatMap(permitido -> {
            if (!permitido) {
                return Mono.just(ResponseEntity.<Producto>status(HttpStatus.TOO_MANY_REQUESTS).build());
            }
            return redis.opsForValue().get(clave)
                    .map(texto -> json.readValue(texto, Producto.class))
                    .onErrorResume(e -> Mono.empty())            // caché caída o ilegible = fallo de caché
                    .switchIfEmpty(Mono.defer(() -> repo.buscar(sku).flatMap(p -> guardar(clave, p))))
                    .map(ResponseEntity::ok)
                    .defaultIfEmpty(ResponseEntity.notFound().build());
        });
    }

    private Mono<Producto> guardar(String clave, Producto p) {
        Duration ttl = TtlConAzar.con(Duration.ofMinutes(10), 0.2, Math::random);
        return redis.opsForValue().set(clave, json.writeValueAsString(p), ttl)
                .onErrorReturn(false)                            // no fallar la respuesta por no poder guardar
                .thenReturn(p);
    }

    /** true si cabe en el límite (100 por minuto); si Redis falla, deja pasar. */
    private Mono<Boolean> limitar(String sujeto) {
        long tramo = System.currentTimeMillis() / 60_000L;
        return redis.execute(CONTADOR, List.of("rl:" + sujeto + ":" + tramo), List.of("60"))
                .next()
                .map(usadas -> usadas <= 100)
                .onErrorReturn(true);
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.quarkus.redis.datasource.RedisDataSource;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.time.Clock;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

class ComandosQuarkus implements Comandos {
    private final RedisDataSource redis;

    ComandosQuarkus(RedisDataSource redis) {
        this.redis = redis;
    }

    @Override
    public Optional<String> leer(String clave) {
        var r = redis.execute("GET", clave);
        return r == null ? Optional.empty() : Optional.of(r.toString());
    }

    @Override
    public void guardar(String clave, String valor, Duration ttl) {
        redis.execute("SET", clave, valor, "PX", Long.toString(ttl.toMillis()));
    }

    @Override
    public void borrar(String clave) {
        redis.execute("DEL", clave);
    }

    @Override
    public boolean guardarSiNoExiste(String clave, String valor, Duration ttl) {
        return redis.execute("SET", clave, valor, "NX", "PX", Long.toString(ttl.toMillis())) != null;
    }

    @Override
    public boolean borrarSiIgual(String clave, String valor) {
        return redis.execute("EVAL", ScriptsRedis.BORRAR_SI_IGUAL, "1", clave, valor).toLong() == 1L;
    }

    @Override
    public long incrementarConVentana(String clave, Duration ventana) {
        return redis.execute("EVAL", ScriptsRedis.CONTADOR, "1", clave, Long.toString(ventana.toSeconds())).toLong();
    }
}

@ApplicationScoped
class RedisProductores {
    @Produces
    @Singleton
    Comandos comandos(RedisDataSource redis) {
        return new ComandosQuarkus(redis);
    }

    @Produces
    @Singleton
    CacheAside cacheAside(Comandos comandos) {
        return new CacheAside(comandos, Duration.ofMinutes(10), Duration.ofSeconds(30), Math::random);
    }

    @Produces
    @Singleton
    LimitadorVentana limitador(Comandos comandos) {
        return new LimitadorVentana(comandos, 100, Duration.ofMinutes(1), Clock.systemUTC(), true);
    }

    @Produces
    @Singleton
    Candado candado(Comandos comandos) {
        return new Candado(comandos, () -> UUID.randomUUID().toString());
    }
}
```
```java
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Duration;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@Path("/catalogo")
@Produces(MediaType.APPLICATION_JSON)
class CatalogoRecurso {
    @Inject
    CacheAside cache;

    @Inject
    CatalogoRepo repo;

    @Inject
    ObjectMapper json;

    @Inject
    LimitadorVentana limitador;

    @Inject
    Candado candado;

    @ConfigProperty(name = "app.entorno")
    String entorno;

    private String aTexto(Producto p) {
        try {
            return json.writeValueAsString(p);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private Producto deTexto(String t) {
        try {
            return json.readValue(t, Producto.class);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @GET
    @Path("/{sku}")
    public Response buscar(@PathParam("sku") String sku) {
        LimitadorVentana.Decision d = limitador.intentar("catalogo:" + sku);
        if (!d.permitido()) {
            return Response.status(429).header("Retry-After", d.reintentarEnSegundos()).build();
        }
        return cache.obtener(ClavesRedis.clave(entorno, "producto", sku), () -> repo.buscar(sku).map(this::aTexto))
                .map(t -> Response.ok(deTexto(t)).build())
                .orElseGet(() -> Response.status(Response.Status.NOT_FOUND).build());
    }

    @PUT
    @Path("/{sku}")
    public Response actualizar(@PathParam("sku") String sku, Producto nuevo) {
        Producto guardado = repo.guardar(new Producto(sku, nuevo.nombre(), nuevo.precio()));
        cache.invalidar(ClavesRedis.clave(entorno, "producto", sku));
        return Response.ok(guardado).build();
    }

    @POST
    @Path("/informes/{id}/generar")
    public Response generar(@PathParam("id") String id) {
        return candado.conCandado("informe:" + id, Duration.ofMinutes(10), () -> "generado")
                .map(r -> Response.ok(r).build())
                .orElseGet(() -> Response.status(Response.Status.CONFLICT).entity("ya se está generando").build());
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.quarkus.redis.datasource.ReactiveRedisDataSource;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Duration;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Tu repositorio reactivo: devuelve el JSON del producto, o un Uni vacío (null) si no existe. */
interface CatalogoRepoMutiny {
    Uni<String> buscarJson(String sku);
}

@Path("/m/catalogo")
class CatalogoMutinyRecurso {
    @Inject
    ReactiveRedisDataSource redis;

    @Inject
    CatalogoRepoMutiny repo;

    @ConfigProperty(name = "app.entorno")
    String entorno;

    @GET
    @Path("/{sku}")
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Response> buscar(@PathParam("sku") String sku) {
        String clave = ClavesRedis.clave(entorno, "producto", sku);
        return redis.execute("GET", clave)
                .onFailure().recoverWithNull()                           // caché caída = fallo de caché
                .map(r -> r == null ? null : r.toString())
                .onItem().ifNull().switchTo(() -> repo.buscarJson(sku)
                        .onItem().ifNotNull().call(json -> {
                            long ms = TtlConAzar.con(Duration.ofMinutes(10), 0.2, Math::random).toMillis();
                            return redis.execute("SET", clave, json, "PX", Long.toString(ms))
                                    .onFailure().recoverWithNull();      // no fallar la respuesta por no poder guardar
                        }))
                .map(json -> json == null
                        ? Response.status(Response.Status.NOT_FOUND).build()
                        : Response.ok(json).build());
    }
}
```

## 7. Permisos
La aplicación **no usa permisos IAM para los datos**: se autentica con su usuario ACL (cadena de acceso en [`ejemplos/acl/acceso.txt`](ejemplos/acl/acceso.txt)) y contraseña desde Secrets Manager, sobre TLS. IAM interviene en el **plano de control** (operación, failover de prueba, copias): [`ejemplos/json/politica-operacion.json`](ejemplos/json/politica-operacion.json), en una identidad distinta de la de la aplicación. La red lo decide el grupo de seguridad ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)).

## 8. Qué NO hacer desde Java
- **No** dejes claves sin TTL ni todos los TTL iguales (§2.2).
- **No** hagas que la aplicación dependa de la caché: ante error, ve al origen (§2.4).
- **No** uses `KEYS *`; recorre con `SCAN`.
- **No** hagas `INCR` y `EXPIRE` por separado: usa el script (§2.3).
- **No** liberes un candado sin comprobar la ficha, ni lo uses como única garantía de exclusión (§2.5).
- **No** guardes objetos con serialización nativa de Java entre versiones distintas: usa JSON controlado (como arriba) y versiona el formato.
- **No** dejes el cliente acumulando comandos mientras reconecta: rechaza y reintenta con espera (§3, `REJECT_COMMANDS`).
- **No** abras un cliente por petición: uno por proceso.
- **No** uses operaciones multi-clave en modo clúster sin etiquetas de hash (§2.1).
