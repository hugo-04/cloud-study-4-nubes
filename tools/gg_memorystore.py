import ggen
POL = '''
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
'''
SDK = '''
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
'''
SERV = '''
import java.time.Duration;

public class ServicioDeCatalogo {

    private final CacheGcp cache;

    public ServicioDeCatalogo(CacheGcp cache) {
        this.cache = cache;
    }

    public String producto(String id) {
        return cache.obtener(PoliticaDeCache.clave("producto", 1, id), Duration.ofMinutes(10),
            () -> "{\\"id\\":\\"" + id + "\\",\\"origen\\":\\"base\\"}");   // en la app real: el repositorio
    }

    public long ttl(long baseSegundos) {
        return PoliticaDeCache.ttl(Duration.ofSeconds(baseSegundos), 0.1, java.util.random.RandomGenerator.getDefault()).toSeconds();
    }
}
'''
ggen.gcp('gcp/08-datos/memorystore', 'Datos · Memorystore',
  'Con Memorystore el código es el de cualquier Redis/Valkey; lo propio de Google es la **conexión privada con TLS** y la **autenticación IAM**: la contraseña es un token de acceso de la cuenta de servicio, que aquí se entrega con un `RedisCredentialsProvider` para que Lettuce lo pida de nuevo al reconectar. La lógica pura da claves versionadas y TTL con *jitter*; el adaptador hace cache-aside y **degrada a la fuente** si la caché falla. En Spring viene con `spring-boot-starter-data-redis`; en Quarkus agrega `io.lettuce:lettuce-core` (o usa `quarkus-redis-client` con la misma idea).',
  [('cache.host', '10.20.0.5'), ('cache.puerto', '6379')],
  [('Política (lógica pura)', POL, True), ('Adaptador con Lettuce', SDK, True), ('Servicio', SERV, True)],
  'Catalogo', '/datos/catalogo', 'ServicioDeCatalogo', 'CacheGcp', [],
  'return new CacheGcp(cred, host, Integer.parseInt(puerto));',
  [dict(n='producto', v='GET', p='/{id}', args=[('String', 'id', 'p')], ret='String', call='s.producto(id)'),
   dict(n='ttl', v='GET', p='/ttl', args=[('long', 'base', 'q')], ret='Long', call='s.ttl(base)', cpu=True)],
  [('Conectar con IAM', '`roles/memorystore.dbConnectionUser` *(verifica)*'),
   ('Administrar instancias', '`roles/memorystore.admin`')],
  ['No guardes claves sin TTL.',
   'No dejes que un fallo de la caché tumbe la petición.',
   'No uses `KEYS *`.',
   'No pongas la cadena AUTH en la configuración: Secret Manager o IAM.'])
