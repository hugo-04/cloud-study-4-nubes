import ggen
CACHE = '''
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
'''
SDK = '''
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
'''
SERV = '''
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
'''
ggen.gcp('gcp/03-secretos/secret-manager', 'Secretos · Secret Manager',
  'Una **caché de secretos con TTL y gracia ante fallos**: lee con `SecretManagerServiceClient.accessSecretVersion` (alias `latest`), verifica el **CRC32C** que devuelve el servicio, y si Secret Manager no responde sirve el último valor durante un periodo de gracia. El endpoint de ejemplo expone solo la longitud del valor, nunca el valor.',
  [],
  [('Caché con gracia (lógica pura)', CACHE, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Secretos', '/secretos', 'ServicioDeSecretos', 'SecretosGcp', [],
  'return new SecretosGcp(cred, proyecto);',
  [dict(n='estado', v='GET', p='/{secreto}/estado', args=[('String', 'secreto', 'p')], ret='ServicioDeSecretos.Estado', call='s.estado(secreto)')],
  [('Leer el valor', '`roles/secretmanager.secretAccessor` **en ese secreto**')],
  ['No leas el secreto en cada petición.',
   'No expongas ni registres el valor.',
   'No fijes la gracia demasiado larga: tras una rotación forzada por incidente, invalida la caché.',
   'No uses `String` para secretos de larga vida si puedes manejarlos como `byte[]` y limpiarlos.'])
