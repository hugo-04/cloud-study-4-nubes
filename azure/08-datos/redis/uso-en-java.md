# Azure · Redis · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1 (Spring Framework 7, Spring Data Redis 4.1, Lettuce 7.5, Jackson 3), `redis-authx-entraid` 0.2.0, Azure SDK BOM 1.3, Quarkus 3.40**. Verifica las vigentes.

Principios: **una conexión compartida** (Lettuce multiplexa comandos sobre pocas conexiones), **Entra ID con renovación automática del token**, **TTL en todo lo que sea caché** (con *jitter*), **serialización JSON controlada** (nunca la serialización nativa de Java), **scripts Lua** para operaciones atómicas, **reconexión y degradación** si Redis no responde, y **claves con prefijo y versión**.

```xml
<!-- Spring Boot -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis-reactive</artifactId></dependency> <!-- WebFlux -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-cache</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>redis.clients.authentication</groupId><artifactId>redis-authx-entraid</artifactId><version>0.2.0</version></dependency>
<!-- Quarkus (Lettuce directo: quarkus-redis-client no renueva tokens de Entra) -->
<dependency><groupId>io.lettuce</groupId><artifactId>lettuce-core</artifactId><version>7.5.2.RELEASE</version></dependency>
<dependency><groupId>redis.clients.authentication</groupId><artifactId>redis-authx-entraid</artifactId><version>0.2.0</version></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-rest-jackson</artifactId></dependency>
```
Permisos: la identidad de la aplicación debe estar **asignada en la política de acceso** de la instancia (ver [Terraform](ejemplos/terraform/main.tf)). Los scripts Lua de [ejemplos/lua](ejemplos/lua/) se copian a `src/main/resources/scripts/`.

Dato de ejemplo que se cachea en todo el documento (un producto del catálogo, con el precio en céntimos):

```java
// (clase reutilizada en los bloques siguientes, ambos)
record Producto(String sku, String nombre, long precioCentimos) { }
```

## 1. Entra ID: credenciales con token que se renueva solo

La conexión usa `AUTH <object id> <token>`. El token **caduca**, y Redis **corta** la conexión si no se vuelve a autenticar a tiempo. La biblioteca oficial `redis-authx-entraid` pide el token con `DefaultAzureCredential`, **lo renueva antes de que expire** y avisa a Lettuce, que **reautentica** las conexiones abiertas (`ReauthenticateBehavior.ON_NEW_CREDENTIALS`). El usuario (el *object id*) lo extrae de la identidad del token.

Dos formas de conectar según la **política de clúster** elegida al crear la instancia:
- **OSSCluster** → cliente de clúster (`RedisClusterConfiguration`): el primer contacto es el puerto 10000; el cliente descubre los shards (rango 85XX, **no los fijes**) y refresca la topología.
- **EnterpriseCluster / NoCluster** → un único endpoint: configuración *standalone* normal.

```yaml
# application.yml
app:
  redis:
    host: amr-modalima-abc123.eastus2.redis.azure.net   # cópialo de la página Overview
    puerto: 10000
    politica-cluster: OSS                               # OSS | ENTERPRISE
spring:
  cache:
    type: redis
```

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.identity.DefaultAzureCredentialBuilder;
import io.lettuce.authx.TokenBasedRedisCredentialsProvider;
import io.lettuce.core.ClientOptions;
import io.lettuce.core.RedisCredentialsProvider;
import io.lettuce.core.SocketOptions;
import io.lettuce.core.TimeoutOptions;
import io.lettuce.core.cluster.ClusterClientOptions;
import io.lettuce.core.cluster.ClusterTopologyRefreshOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisClusterConfiguration;
import org.springframework.data.redis.connection.RedisConfiguration;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceClientConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.connection.lettuce.RedisCredentialsProviderFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import redis.clients.authentication.core.TokenAuthConfig;
import redis.clients.authentication.entraid.AzureTokenAuthConfigBuilder;

import java.time.Duration;
import java.util.Set;

@Configuration
class RedisConfig {

    /** Un solo proveedor para toda la aplicación: pide y renueva el token de Entra ID. */
    @Bean(destroyMethod = "close")
    TokenBasedRedisCredentialsProvider credencialesEntra() {
        TokenAuthConfig config = AzureTokenAuthConfigBuilder.builder()
                // En Azure: identidad administrada / Workload Identity. En tu máquina: az login.
                .defaultAzureCredential(new DefaultAzureCredentialBuilder().build())
                .scopes(Set.of("https://redis.azure.com/.default"))
                .tokenRequestExecTimeoutInMs(2000)
                .build();
        return TokenBasedRedisCredentialsProvider.create(config);
    }

    @Bean
    LettuceConnectionFactory redisConnectionFactory(
            TokenBasedRedisCredentialsProvider credenciales,
            @Value("${app.redis.host}") String host,
            @Value("${app.redis.puerto:10000}") int puerto,
            @Value("${app.redis.politica-cluster:OSS}") String politica) {

        RedisCredentialsProviderFactory fabrica = new RedisCredentialsProviderFactory() {
            @Override
            public RedisCredentialsProvider createCredentialsProvider(RedisConfiguration configuracion) {
                return credenciales;
            }
        };

        SocketOptions socket = SocketOptions.builder()
                .connectTimeout(Duration.ofSeconds(5))
                .keepAlive(true)
                .build();
        TimeoutOptions tiempos = TimeoutOptions.enabled(Duration.ofSeconds(2));

        if ("OSS".equalsIgnoreCase(politica)) {
            RedisClusterConfiguration cluster = new RedisClusterConfiguration();
            cluster.clusterNode(host, puerto);

            ClusterClientOptions opciones = ClusterClientOptions.builder()
                    .topologyRefreshOptions(ClusterTopologyRefreshOptions.builder()
                            .enableAllAdaptiveRefreshTriggers()           // refresca al detectar MOVED/reconexiones
                            .enablePeriodicRefresh(Duration.ofMinutes(1))
                            .build())
                    .socketOptions(socket)
                    .timeoutOptions(tiempos)
                    .reauthenticateBehavior(ClientOptions.ReauthenticateBehavior.ON_NEW_CREDENTIALS)
                    .build();

            return new LettuceConnectionFactory(cluster, LettuceClientConfiguration.builder()
                    .clientOptions(opciones)
                    .commandTimeout(Duration.ofSeconds(2))
                    .redisCredentialsProviderFactory(fabrica)
                    .useSsl().and()
                    .build());
        }

        RedisStandaloneConfiguration unico = new RedisStandaloneConfiguration(host, puerto);
        ClientOptions opciones = ClientOptions.builder()
                .socketOptions(socket)
                .timeoutOptions(tiempos)
                .reauthenticateBehavior(ClientOptions.ReauthenticateBehavior.ON_NEW_CREDENTIALS)
                .build();

        return new LettuceConnectionFactory(unico, LettuceClientConfiguration.builder()
                .clientOptions(opciones)
                .commandTimeout(Duration.ofSeconds(2))
                .redisCredentialsProviderFactory(fabrica)
                .useSsl().and()
                .build());
    }

    @Bean
    StringRedisTemplate stringRedisTemplate(LettuceConnectionFactory fabrica) {
        return new StringRedisTemplate(fabrica);
    }
}
```
Puntos clave:
- **Un solo `LettuceConnectionFactory`** (una conexión compartida y multiplexada): no abras una por solicitud.
- El proveedor de credenciales es **singleton** y se cierra al apagar (`destroyMethod = "close"`).
- Tiempos de espera **cortos** (2 s): si Redis tarda, es mejor degradar que acumular hilos.
- Para pruebas locales sin Entra (Redis en contenedor), crea otro perfil con `RedisStandaloneConfiguration` sin TLS ni proveedor de credenciales.

## 2. Spring Cache: `@Cacheable` con TTL por caché, *jitter* y JSON tipado

La abstracción de caché de Spring permite cachear con una anotación. Reglas: **TTL distinto por caché**, **vencimiento con *jitter*** (para no expirar todo a la vez), **JSON tipado** (`JacksonJsonRedisSerializer<T>`, sin tipos incrustados ni serialización de Java), **no cachear `null`** y **prefijo con versión** en las claves.

```java
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.cache.RedisCacheWriter;
import org.springframework.data.redis.serializer.JacksonJsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

@Configuration
@EnableCaching
class CacheConfig {

    /** TTL base ± hasta 20 %: las claves no vencen todas en el mismo segundo. */
    private static RedisCacheWriter.TtlFunction conJitter(Duration base) {
        long maximoExtra = Math.max(1, base.toSeconds() / 5);
        return (clave, valor) -> base.plusSeconds(ThreadLocalRandom.current().nextLong(maximoExtra));
    }

    private static RedisCacheConfiguration configuracion(Duration ttl, Class<?> tipo) {
        return RedisCacheConfiguration.defaultCacheConfig()
                .entryTtl(conJitter(ttl))
                .disableCachingNullValues()
                .prefixCacheNameWith("modalima:v1:")                      // servicio + versión del formato
                .serializeValuesWith(RedisSerializationContext.SerializationPair
                        .fromSerializer(new JacksonJsonRedisSerializer<>(tipo)));
    }

    @Bean
    CacheManager cacheManager(LettuceConnectionFactory fabrica) {
        return RedisCacheManager.builder(fabrica)
                .withInitialCacheConfigurations(Map.of(
                        "producto", configuracion(Duration.ofMinutes(10), Producto.class)))
                .build();                       // solo las cachés declaradas: no se crean otras al vuelo
    }
}

interface ProductoRepositorio {
    Producto buscar(String sku);

    void guardar(Producto producto);
}

@Service
class CatalogoServicio {

    private final ProductoRepositorio repositorio;

    CatalogoServicio(ProductoRepositorio repositorio) {
        this.repositorio = repositorio;
    }

    /** Primera vez: va a la base y guarda en Redis; las siguientes salen de Redis hasta que venza el TTL. */
    @Cacheable(cacheNames = "producto", key = "#sku", unless = "#result == null")
    public Producto porSku(String sku) {
        return repositorio.buscar(sku);
    }

    /** Al cambiar el dato, invalida la clave para que la próxima lectura recargue. */
    @CacheEvict(cacheNames = "producto", key = "#producto.sku()")
    public void actualizar(Producto producto) {
        repositorio.guardar(producto);
    }
}
```
Limitaciones de `@Cacheable`: no evita la **estampida** (varias instancias recargan a la vez al expirar), no hace **caché negativa** y la invalidación depende de que la modificación pase por tu código. Para esos casos usa el patrón manual de la sección 4.

## 3. Bloqueo distribuido con token y liberación atómica

Un bloqueo en Redis es `SET clave token NX PX ttl`: solo lo toma quien lo ve libre, y **vence solo** (si el dueño muere, no queda bloqueado para siempre). Para liberarlo, hay que comprobar que **sigue siendo nuestro** (que no venció y lo tomó otro): eso exige comparar y borrar en **una sola operación atómica** → script Lua [`liberar-bloqueo.lua`](ejemplos/lua/liberar-bloqueo.lua).

> **Cuidado con las garantías:** es un bloqueo de *eficiencia* (evitar trabajo duplicado), no de *exactitud*. Si el dueño se pausa más que el TTL, otro puede tomarlo y los dos trabajan a la vez. Para exactitud estricta, protege además el recurso final (restricción única en la base de datos, `ETag`, *fencing token*).

```java
// (clase reutilizada en los bloques siguientes)
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Component
class BloqueoRedis {

    private final StringRedisTemplate redis;
    private final RedisScript<Long> scriptLiberar =
            RedisScript.of(new ClassPathResource("scripts/liberar-bloqueo.lua"), Long.class);

    BloqueoRedis(StringRedisTemplate redis) {
        this.redis = redis;
    }

    /** @return el token del dueño si se tomó el bloqueo; vacío si ya lo tiene otro */
    Optional<String> tomar(String clave, Duration ttl) {
        String token = UUID.randomUUID().toString();
        Boolean tomado = redis.opsForValue().setIfAbsent(clave, token, ttl);
        return Boolean.TRUE.equals(tomado) ? Optional.of(token) : Optional.empty();
    }

    /** Libera solo si el bloqueo sigue siendo del que lo tomó. */
    boolean liberar(String clave, String token) {
        Long resultado = redis.execute(scriptLiberar, List.of(clave), token);
        return resultado != null && resultado == 1L;
    }
}

@Component
class CierreDiario {

    private final BloqueoRedis bloqueo;

    CierreDiario(BloqueoRedis bloqueo) {
        this.bloqueo = bloqueo;
    }

    /** Solo una réplica ejecuta el cierre; las demás lo omiten sin esperar. */
    void ejecutarSiLibre(Runnable cierre) {
        Optional<String> token = bloqueo.tomar("bloqueo:v1:cierre-diario", Duration.ofMinutes(10));
        if (token.isEmpty()) {
            return;
        }
        try {
            cierre.run();
        } finally {
            bloqueo.liberar("bloqueo:v1:cierre-diario", token.get());
        }
    }
}
```

## 4. Cache-aside manual: anti-estampida, caché negativa y *jitter*

Lo que `@Cacheable` no resuelve:
- **Estampida:** al vencer una clave popular, cientos de solicitudes la recargan a la vez. Solución: solo **una** carga (bloqueo corto); las demás esperan unos milisegundos el resultado.
- **Caché negativa:** si "no existe" se consulta mil veces, cada una golpea la base. Se guarda una marca con TTL corto.
- **Jitter** en el TTL.
- **Degradación:** si Redis falla, se consulta la base directamente (con el límite de tu base) y se registra el error.

```java
import org.springframework.data.redis.RedisSystemException;
import tools.jackson.databind.json.JsonMapper;

import java.util.function.Supplier;
import java.util.concurrent.ThreadLocalRandom;

@Component
class CacheAside {

    private static final String NO_EXISTE = "∅";                 // marca de caché negativa
    private static final Duration TTL_NEGATIVO = Duration.ofSeconds(30);

    private final StringRedisTemplate redis;
    private final BloqueoRedis bloqueo;
    private final JsonMapper json;

    CacheAside(StringRedisTemplate redis, BloqueoRedis bloqueo, JsonMapper json) {
        this.redis = redis;
        this.bloqueo = bloqueo;
        this.json = json;
    }

    <T> T obtener(String clave, Class<T> tipo, Duration ttl, Supplier<T> cargador) {
        try {
            String guardado = redis.opsForValue().get(clave);
            if (guardado != null) {
                return NO_EXISTE.equals(guardado) ? null : json.readValue(guardado, tipo);
            }

            String claveBloqueo = "lock:" + clave;
            Optional<String> token = bloqueo.tomar(claveBloqueo, Duration.ofSeconds(5));
            if (token.isPresent()) {
                try {
                    T cargado = cargador.get();                       // UNA sola carga
                    guardar(clave, cargado, ttl);
                    return cargado;
                } finally {
                    bloqueo.liberar(claveBloqueo, token.get());
                }
            }

            // Otra réplica está cargando: espera hasta ~1 s a que aparezca el valor
            for (int intento = 0; intento < 10; intento++) {
                Thread.sleep(100);
                guardado = redis.opsForValue().get(clave);
                if (guardado != null) {
                    return NO_EXISTE.equals(guardado) ? null : json.readValue(guardado, tipo);
                }
            }
            return cargador.get();                                     // plan B: sin caché
        } catch (RedisSystemException e) {
            return cargador.get();                                     // Redis caído: degradar a la base
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return cargador.get();
        }
    }

    private <T> void guardar(String clave, T valor, Duration ttl) {
        if (valor == null) {
            redis.opsForValue().set(clave, NO_EXISTE, TTL_NEGATIVO);
            return;
        }
        long extra = ThreadLocalRandom.current().nextLong(Math.max(1, ttl.toSeconds() / 5));
        redis.opsForValue().set(clave, json.writeValueAsString(valor), ttl.plusSeconds(extra));
    }

    void invalidar(String clave) {
        redis.delete(clave);
    }
}
```
Uso: `cacheAside.obtener("catalogo:v1:" + sku, Producto.class, Duration.ofMinutes(10), () -> repositorio.buscar(sku))`.

## 5. Idempotencia, limitador de tasa y reserva atómica de stock (Lua)

Cada operación compuesta que debe ser **atómica** se resuelve con un script: Redis ejecuta el script completo sin intercalar otros comandos. Los scripts están en [ejemplos/lua](ejemplos/lua/) (probados contra Redis).

| Operación | Cómo | Clave |
|---|---|---|
| Idempotencia ("solo la primera vez") | `SET clave valor NX EX` | `idem:v1:pedido:<Idempotency-Key>` |
| Limitador por ventana fija | [`limitador-ventana-fija.lua`](ejemplos/lua/limitador-ventana-fija.lua) | `limite:v1:api:<cliente>` |
| Reserva de stock sin pasar de cero | [`reservar-stock.lua`](ejemplos/lua/reservar-stock.lua) | `stock:v1:<sku>` (hash con `disponible`) |

En **clúster**, cada script debe tocar **claves del mismo slot** (aquí cada script usa una sola clave).

```java
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.List;

@Component
class ControlesRedis {

    private final StringRedisTemplate redis;

    @SuppressWarnings({"rawtypes", "unchecked"})
    private final RedisScript<List> scriptLimitador =
            RedisScript.of(new ClassPathResource("scripts/limitador-ventana-fija.lua"), List.class);
    private final RedisScript<Long> scriptStock =
            RedisScript.of(new ClassPathResource("scripts/reservar-stock.lua"), Long.class);

    ControlesRedis(StringRedisTemplate redis) {
        this.redis = redis;
    }

    /** @return true si es la primera vez que se ve esta clave en las últimas 24 h */
    boolean primeraVez(String claveIdempotencia) {
        return Boolean.TRUE.equals(redis.opsForValue()
                .setIfAbsent("idem:v1:pedido:" + claveIdempotencia, "1", Duration.ofHours(24)));
    }

    record Limite(boolean permitido, long usadas, long segundosRestantes) { }

    Limite limitar(String cliente, int maximo, Duration ventana) {
        List<?> r = redis.execute(scriptLimitador, List.of("limite:v1:api:" + cliente),
                String.valueOf(maximo), String.valueOf(ventana.toSeconds()));
        if (r == null || r.size() < 3) {
            return new Limite(true, 0, 0);                  // si Redis no responde: no bloquear a los clientes
        }
        return new Limite(((Number) r.get(0)).longValue() == 1L, ((Number) r.get(1)).longValue(),
                ((Number) r.get(2)).longValue());
    }

    /** @return stock restante, -1 si no alcanza, -2 si el producto no existe */
    long reservarStock(String sku, int cantidad) {
        Long restante = redis.execute(scriptStock, List.of("stock:v1:" + sku), String.valueOf(cantidad));
        return restante == null ? -2 : restante;
    }
}
```
Decisiones de diseño: el **stock oficial** vive en la base de datos; Redis sirve para **frenar picos** (reserva rápida), con una conciliación posterior. Si Redis se reinicia sin persistencia, se **reconstruye** el stock desde la base.

## 6. Redis Streams: cola ligera con grupos y reintento de pendientes

Un *Stream* guarda mensajes en orden; un **grupo de consumidores** reparte los mensajes entre instancias, y cada mensaje se **confirma** (`XACK`) al terminar. Los no confirmados quedan **pendientes** y se pueden reclamar si un consumidor muere. Es útil para **volúmenes moderados y tareas internas**; **no sustituye** a un broker durable (Service Bus / Event Hubs): la retención y la durabilidad dependen de la memoria y la persistencia. Limita el tamaño con `XADD ... MAXLEN`/recorte.

```java
import org.springframework.data.domain.Range;
import org.springframework.data.redis.connection.stream.Consumer;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.connection.stream.PendingMessage;
import org.springframework.data.redis.connection.stream.PendingMessages;
import org.springframework.data.redis.connection.stream.ReadOffset;
import org.springframework.data.redis.connection.stream.RecordId;
import org.springframework.data.redis.connection.stream.StreamOffset;
import org.springframework.data.redis.connection.stream.StreamReadOptions;
import org.springframework.data.redis.connection.stream.StreamRecords;
import org.springframework.scheduling.annotation.Scheduled;

import java.util.Map;

@Component
class EventosPedidos {

    private static final String STREAM = "pedidos:v1:eventos";
    private static final String GRUPO = "facturacion";

    private final StringRedisTemplate redis;
    private final String consumidor = System.getenv().getOrDefault("HOSTNAME", UUID.randomUUID().toString());

    EventosPedidos(StringRedisTemplate redis) {
        this.redis = redis;
        crearGrupo();
    }

    private void crearGrupo() {
        try {
            redis.opsForStream().createGroup(STREAM, ReadOffset.from("0"), GRUPO);   // crea también el stream si no existe
        } catch (RuntimeException e) {
            // BUSYGROUP: el grupo ya existe → correcto
        }
    }

    RecordId publicar(String tipo, String pedidoId) {
        return redis.opsForStream().add(StreamRecords.string(Map.of("tipo", tipo, "pedidoId", pedidoId))
                .withStreamKey(STREAM));
    }

    /** Lee mensajes nuevos asignados a este consumidor y los procesa; confirma solo los exitosos. */
    @Scheduled(fixedDelay = 500)
    void procesarNuevos() {
        List<MapRecord<String, Object, Object>> lote = redis.opsForStream().read(
                Consumer.from(GRUPO, consumidor),
                StreamReadOptions.empty().count(20).block(Duration.ofSeconds(2)),
                StreamOffset.create(STREAM, ReadOffset.lastConsumed()));
        if (lote == null) {
            return;
        }
        for (MapRecord<String, Object, Object> registro : lote) {
            try {
                facturar(registro.getValue().get("pedidoId").toString());   // debe ser idempotente
                redis.opsForStream().acknowledge(STREAM, GRUPO, registro.getId());
            } catch (RuntimeException e) {
                // sin ACK → queda pendiente y se reintentará (ver reclamarPendientes)
            }
        }
    }

    /** Reclama mensajes pendientes de consumidores caídos (más de 60 s sin confirmar). */
    @Scheduled(fixedDelay = 30_000)
    void reclamarPendientes() {
        PendingMessages pendientes = redis.opsForStream().pending(STREAM, GRUPO, Range.unbounded(), 50);
        for (PendingMessage pendiente : pendientes) {
            if (pendiente.getElapsedTimeSinceLastDelivery().compareTo(Duration.ofSeconds(60)) > 0) {
                List<MapRecord<String, Object, Object>> reclamados = redis.opsForStream().claim(
                        STREAM, GRUPO, consumidor, Duration.ofSeconds(60), pendiente.getId());
                for (MapRecord<String, Object, Object> r : reclamados) {
                    facturar(r.getValue().get("pedidoId").toString());
                    redis.opsForStream().acknowledge(STREAM, GRUPO, r.getId());
                }
            }
        }
    }

    private void facturar(String pedidoId) {
        // lógica idempotente: si ya se facturó este pedido, no hacer nada
    }
}
```
Para mensajería con garantías fuertes, retención larga o reproducción, usa [Service Bus](../../07-mensajeria/service-bus/README.md) o [Event Hubs](../../07-mensajeria/event-hubs-kafka/README.md).

## 7. Pub/Sub: invalidar cachés locales en todas las instancias

Pub/Sub es **efímero**: quien no esté escuchando en ese instante pierde el mensaje. Sirve para **avisos** (no para trabajo): por ejemplo, cuando una instancia cambia el catálogo, todas las demás **borran su caché local (L1)**; si se pierde un aviso, el TTL corto de la L1 lo corrige.

```java
import org.springframework.data.redis.connection.Message;
import org.springframework.data.redis.listener.ChannelTopic;
import org.springframework.data.redis.listener.RedisMessageListenerContainer;

import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

@Component
class CatalogoLocal {

    private final ConcurrentHashMap<String, Producto> l1 = new ConcurrentHashMap<>();

    Producto obtener(String sku, Supplier<Producto> cargador) {
        return l1.computeIfAbsent(sku, k -> cargador.get());
    }

    void invalidar(String sku) {
        l1.remove(sku);
    }
}

@Configuration
class InvalidacionConfig {

    static final String CANAL = "canal:v1:catalogo-invalidado";

    @Bean
    RedisMessageListenerContainer contenedorDeMensajes(LettuceConnectionFactory fabrica, CatalogoLocal local) {
        RedisMessageListenerContainer contenedor = new RedisMessageListenerContainer();
        contenedor.setConnectionFactory(fabrica);
        contenedor.addMessageListener((Message mensaje, byte[] patron) ->
                local.invalidar(new String(mensaje.getBody())), new ChannelTopic(CANAL));
        return contenedor;
    }
}

@Component
class PublicadorInvalidacion {

    private final StringRedisTemplate redis;

    PublicadorInvalidacion(StringRedisTemplate redis) {
        this.redis = redis;
    }

    void avisar(String sku) {
        redis.convertAndSend(InvalidacionConfig.CANAL, sku);
    }
}
```

## 8. Spring WebFlux (reactivo): `ReactiveStringRedisTemplate`

`LettuceConnectionFactory` ya sirve la API reactiva (Lettuce es reactivo por dentro). El patrón reactivo añade un truco útil: **una sola carga por clave dentro del pod** (`ConcurrentHashMap<String, Mono<T>>`), para que cientos de solicitudes simultáneas por el mismo producto compartan la misma consulta a la base.

```java
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.ScanOptions;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import tools.jackson.databind.json.JsonMapper;

import java.util.concurrent.ConcurrentHashMap;

interface ProductoRepositorioReactivo {
    Mono<Producto> buscar(String sku);
}

@Configuration
class RedisReactivoConfig {

    @Bean
    ReactiveStringRedisTemplate reactiveStringRedisTemplate(LettuceConnectionFactory fabrica) {
        return new ReactiveStringRedisTemplate(fabrica);
    }
}

@Component
class CatalogoReactivo {

    private final ReactiveStringRedisTemplate redis;
    private final ProductoRepositorioReactivo repositorio;
    private final JsonMapper json;
    private final ConcurrentHashMap<String, Mono<Producto>> cargasEnCurso = new ConcurrentHashMap<>();

    CatalogoReactivo(ReactiveStringRedisTemplate redis, ProductoRepositorioReactivo repositorio, JsonMapper json) {
        this.redis = redis;
        this.repositorio = repositorio;
        this.json = json;
    }

    Mono<Producto> porSku(String sku) {
        String clave = "catalogo:v1:" + sku;
        return redis.opsForValue().get(clave)
                .map(texto -> json.readValue(texto, Producto.class))
                .onErrorResume(e -> Mono.empty())                         // Redis falla → tratar como fallo de caché
                .switchIfEmpty(Mono.defer(() -> cargarUnaVez(clave, sku)));
    }

    private Mono<Producto> cargarUnaVez(String clave, String sku) {
        return cargasEnCurso.computeIfAbsent(clave, k ->
                repositorio.buscar(sku)
                        .flatMap(producto -> redis.opsForValue()
                                .set(clave, json.writeValueAsString(producto), Duration.ofMinutes(10))
                                .onErrorReturn(false)                      // no fallar la respuesta por no poder cachear
                                .thenReturn(producto))
                        .doFinally(senal -> cargasEnCurso.remove(clave))
                        .cache());                                         // todos los suscriptores comparten el resultado
    }

    /** Reserva atómica de stock con Lua en modo reactivo. */
    Mono<Long> reservarStock(String sku, int cantidad) {
        RedisScript<Long> script = RedisScript.of(new ClassPathResource("scripts/reservar-stock.lua"), Long.class);
        return redis.execute(script, List.of("stock:v1:" + sku), List.of(String.valueOf(cantidad))).next();
    }

    Flux<String> clavesDeCatalogo() {
        // SCAN en lugar de KEYS: recorre por lotes sin bloquear el servidor
        return redis.scan(ScanOptions.scanOptions()
                .match("catalogo:v1:*").count(100).build());
    }
}
```
Reglas en reactivo: **no bloquees** el hilo de eventos (`block()`, `Thread.sleep`); trata los fallos de Redis como *fallo de caché* y sigue con la base; y limita la concurrencia hacia la base.

## 9. Quarkus · imperativo (Lettuce con renovación de token)

`quarkus-redis-client` (basado en Vert.x) acepta una **contraseña estática**: sirve con claves de acceso o con un token que se vuelve a configurar antes de caducar, pero **no renueva solo el token de Entra ID** sobre conexiones abiertas. Para producción sin claves, la opción práctica es usar **Lettuce con `redis-authx-entraid`** mediante productores CDI. *Verifica si una versión más nueva de la extensión añade proveedores de credenciales dinámicos.*

```properties
# application.properties
app.redis.host=amr-modalima-abc123.eastus2.redis.azure.net
app.redis.puerto=10000

# Desarrollo local o pruebas con claves de acceso (NO producción): extensión oficial de Quarkus
# quarkus.redis.hosts=rediss://amr-modalima-abc123.eastus2.redis.azure.net:10000
# quarkus.redis.password=${REDIS_ACCESS_KEY}
```

```java
import io.lettuce.authx.TokenBasedRedisCredentialsProvider;
import io.lettuce.core.ClientOptions;
import io.lettuce.core.RedisURI;
import io.lettuce.core.cluster.ClusterClientOptions;
import io.lettuce.core.cluster.ClusterTopologyRefreshOptions;
import io.lettuce.core.cluster.RedisClusterClient;
import io.lettuce.core.cluster.api.StatefulRedisClusterConnection;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import redis.clients.authentication.core.TokenAuthConfig;
import redis.clients.authentication.entraid.AzureTokenAuthConfigBuilder;
import com.azure.identity.DefaultAzureCredentialBuilder;

import java.time.Duration;
import java.util.Set;

@ApplicationScoped
class LettuceProductor {

    @ConfigProperty(name = "app.redis.host")
    String host;

    @ConfigProperty(name = "app.redis.puerto", defaultValue = "10000")
    int puerto;

    @Produces
    @Singleton
    TokenBasedRedisCredentialsProvider credencialesEntra() {
        TokenAuthConfig config = AzureTokenAuthConfigBuilder.builder()
                .defaultAzureCredential(new DefaultAzureCredentialBuilder().build())
                .scopes(Set.of("https://redis.azure.com/.default"))
                .tokenRequestExecTimeoutInMs(2000)
                .build();
        return TokenBasedRedisCredentialsProvider.create(config);
    }

    void cerrarCredenciales(@Disposes TokenBasedRedisCredentialsProvider credenciales) {
        credenciales.close();
    }

    /** Política OSSCluster. Con EnterpriseCluster usa RedisClient/StatefulRedisConnection. */
    @Produces
    @Singleton
    RedisClusterClient clienteRedis(TokenBasedRedisCredentialsProvider credenciales) {
        RedisURI uri = RedisURI.builder()
                .withHost(host)
                .withPort(puerto)
                .withSsl(true)
                .withAuthentication(credenciales)
                .withTimeout(Duration.ofSeconds(2))
                .build();
        RedisClusterClient cliente = RedisClusterClient.create(uri);
        cliente.setOptions(ClusterClientOptions.builder()
                .topologyRefreshOptions(ClusterTopologyRefreshOptions.builder()
                        .enableAllAdaptiveRefreshTriggers()
                        .enablePeriodicRefresh(Duration.ofMinutes(1))
                        .build())
                .reauthenticateBehavior(ClientOptions.ReauthenticateBehavior.ON_NEW_CREDENTIALS)
                .build());
        return cliente;
    }

    void cerrarCliente(@Disposes RedisClusterClient cliente) {
        cliente.shutdown();
    }

    @Produces
    @Singleton
    StatefulRedisClusterConnection<String, String> conexion(RedisClusterClient cliente) {
        return cliente.connect();                      // una conexión multiplexada para toda la aplicación
    }

    void cerrarConexion(@Disposes StatefulRedisClusterConnection<String, String> conexion) {
        conexion.close();
    }
}
```

```java
import com.fasterxml.jackson.databind.ObjectMapper;
import io.lettuce.core.cluster.api.StatefulRedisClusterConnection;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.time.Duration;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Supplier;

@ApplicationScoped
class CatalogoCache {

    @Inject
    StatefulRedisClusterConnection<String, String> conexion;

    @Inject
    ObjectMapper json;

    Producto obtener(String sku, Supplier<Producto> cargador) {
        String clave = "catalogo:v1:" + sku;
        try {
            String guardado = conexion.sync().get(clave);
            if (guardado != null) {
                return json.readValue(guardado, Producto.class);
            }
            Producto cargado = cargador.get();
            if (cargado != null) {
                long ttl = 600 + ThreadLocalRandom.current().nextLong(120);     // 10 min + jitter
                conexion.sync().setex(clave, ttl, json.writeValueAsString(cargado));
            }
            return cargado;
        } catch (io.lettuce.core.RedisException | com.fasterxml.jackson.core.JsonProcessingException e) {
            return cargador.get();                                                // degradar a la base
        }
    }
}

@Path("/catalogo")
@Produces(MediaType.APPLICATION_JSON)
class CatalogoRecurso {

    @Inject
    CatalogoCache cache;

    @GET
    @Path("/{sku}")
    Response porSku(@PathParam("sku") String sku) {
        Producto p = cache.obtener(sku, () -> new Producto(sku, "Polo básico", 8990));   // aquí iría la base
        return p == null ? Response.status(Response.Status.NOT_FOUND).build() : Response.ok(p).build();
    }
}
```

## 10. Quarkus · reactivo (Mutiny sobre la API reactiva de Lettuce)

La conexión de Lettuce expone `reactive()` (Reactor). Se convierte a Mutiny con `JdkFlowAdapter`, igual que con otros SDK de Azure.

```java
import com.fasterxml.jackson.databind.ObjectMapper;
import io.lettuce.core.cluster.api.StatefulRedisClusterConnection;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import reactor.adapter.JdkFlowAdapter;
import reactor.core.publisher.Mono;

import java.util.function.Supplier;

@ApplicationScoped
class CatalogoCacheReactivo {

    @Inject
    StatefulRedisClusterConnection<String, String> conexion;

    @Inject
    ObjectMapper json;

    private static <T> Uni<T> aUni(Mono<T> mono) {
        return Uni.createFrom().publisher(JdkFlowAdapter.publisherToFlowPublisher(mono));
    }

    Uni<Producto> obtener(String sku, Supplier<Uni<Producto>> cargador) {
        String clave = "catalogo:v1:" + sku;
        Uni<String> guardado = aUni(conexion.reactive().get(clave));     // Mono vacío → item nulo
        return guardado
                .onFailure().recoverWithNull()                           // Redis falla → tratar como fallo de caché
                .flatMap(texto -> {
                    if (texto != null) {
                        try {
                            return Uni.createFrom().item(json.readValue(texto, Producto.class));
                        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
                            return cargador.get();
                        }
                    }
                    return cargador.get().flatMap(p -> {
                        if (p == null) {
                            return Uni.createFrom().nullItem();
                        }
                        try {
                            return aUni(conexion.reactive().setex(clave, 600, json.writeValueAsString(p)))
                                    .onFailure().recoverWithNull()
                                    .replaceWith(p);
                        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
                            return Uni.createFrom().item(p);
                        }
                    });
                });
    }
}

@Path("/reactivo/catalogo")
@Produces(MediaType.APPLICATION_JSON)
class CatalogoRecursoReactivo {

    @Inject
    CatalogoCacheReactivo cache;

    @GET
    @Path("/{sku}")
    Uni<Producto> porSku(@PathParam("sku") String sku) {
        return cache.obtener(sku, () -> Uni.createFrom().item(new Producto(sku, "Polo básico", 8990)));
    }
}
```

## 11. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| Unitarias | La lógica de caché detrás de una interfaz; dobles en memoria | Sin red |
| Integración local | **Redis en contenedor** (Testcontainers `redis:7`) con configuración *standalone* sin TLS ni Entra | Verifica TTL, scripts Lua, Streams, claves; no prueba Entra ni clúster |
| Integración de clúster | Contenedor de Redis Cluster o la instancia de desarrollo con política igual a producción | Detecta `CROSSSLOT` y redirecciones antes de producción |
| Resiliencia | Detén Redis, expira el token (reduce el TTL en pruebas), simula latencia | La aplicación debe degradar y recuperarse |
| Entra ID | Instancia de desarrollo con tu identidad (`az login`) | La renovación del token se comprueba con el cliente corriendo > 1 hora |

```java
// nocheck — requiere Testcontainers (org.testcontainers:testcontainers) y Docker
@Testcontainers
class ControlesRedisIT {

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7.4").withExposedPorts(6379);

    @Test
    void reservaNuncaPasaDeCero() {
        LettuceConnectionFactory fabrica = new LettuceConnectionFactory(redis.getHost(), redis.getMappedPort(6379));
        fabrica.afterPropertiesSet();
        StringRedisTemplate plantilla = new StringRedisTemplate(fabrica);
        plantilla.opsForHash().put("stock:v1:POL", "disponible", "10");
        // ejecuta reservarStock(…) concurrentemente y afirma que el total reservado ≤ 10
    }
}
```

## 12. Resumen de buenas prácticas en código

- **Una conexión compartida** (Lettuce), cliente de **clúster** si la política es OSS, tiempos de espera cortos, reconexión automática.
- **Entra ID con `redis-authx-entraid`:** el token se renueva solo; sin claves en la configuración.
- **TTL con *jitter*** en toda la caché; **caché negativa** corta; **una sola carga** por clave (estampida).
- **JSON tipado**; claves `servicio:vN:entidad:id`; versión nueva al cambiar el formato.
- **Lua** para lo compuesto y atómico; **bloqueos con token** y TTL; protege además el recurso final.
- **`SCAN`**, nunca `KEYS`; evita claves y colecciones gigantes.
- **Degradar** si Redis falla (ir a la base con límites); no hacer que la caché sea un punto único de fallo.
- Streams/Pub/Sub para casos ligeros; **brokers** (Service Bus/Event Hubs) para garantías fuertes.
- En reactivo: sin bloqueos y con carga única por clave dentro del pod.
- Probar: Redis local para la lógica, instancia de desarrollo para Entra, clúster para `CROSSSLOT` y pruebas de resiliencia.
