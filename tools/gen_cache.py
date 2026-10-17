import genlib
CA = '''
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
'''
SDK = '''
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
'''
SERV = '''
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
        return cacheAside.obtener(CacheAside.clave("catalogo", 3, sku), () -> "{\\"sku\\":\\"" + sku + "\\",\\"precio\\":39.90}");
    }
}
'''
genlib.oci('oci/08-datos/cache-redis', 'Datos · OCI Cache',
  '**Cache-aside bien hecho**: claves con servicio y versión (`catalogo:v3:POL-01`), TTL con *jitter*, un solo regenerador por clave para evitar estampidas y degradación a la fuente si la caché falla. El almacén es una interfaz que en la app real implementas sobre `StringRedisTemplate` (Spring Data Redis/Lettuce) o `RedisDataSource` (Quarkus); el adaptador del SDK descubre los endpoints `rediss://` con `RedisClusterClient`.',
  [],
  [('Cache-aside (lógica pura)', CA, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Catalogo', '/datos/catalogo', 'ServicioDeCatalogo', 'CacheOci',
  ['import com.oracle.bmc.redis.RedisClusterClient;'],
  'return new CacheOci(RedisClusterClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='endpoints', v='GET', p='/cache/{id}', args=[('String', 'id', 'p')], ret='CacheOci.Endpoints', call='s.endpoints(id)'),
   dict(n='ficha', v='GET', p='/{sku}', args=[('String', 'sku', 'p')], ret='String', call='s.ficha(sku)')],
  [('Descubrir endpoints', '`Allow dynamic-group app-tienda to read redis-clusters in compartment datos-prod`'),
   ('Contraseña del usuario de caché', "`Allow dynamic-group app-tienda to read secret-bundles in compartment datos-prod where target.secret.id = '<ocid>'`")],
  ['No uses la caché como fuente de verdad.',
   'No guardes claves sin TTL.',
   'No hagas que un *timeout* de la caché tumbe la petición.',
   'No uses `KEYS *`; usa `SCAN`.',
   'No llames a Lettuce bloqueante dentro del hilo de eventos: usa la API reactiva en WebFlux/Mutiny.'])
