import sys; sys.path.insert(0, '/tmp/claude-0/-home-claude/91a1f301-d8cc-52b1-b5f2-6ef32b63def7/scratchpad')
import jdoc
FUENTE = '''
/** De dónde sale el valor de un secreto (Vault en producción, un mapa en las pruebas). */
public interface FuenteDeSecretos {

    String leer(String secretId);
}
'''
CACHE = '''
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
'''
SDK = '''
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
'''
SERV = '''
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
'''
sec = dict(
  ns='Secretos', ruta='/secretos/vault', servicio='ServicioDeSecretos',
  spring_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import org.springframework.beans.factory.annotation.Value;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    SecretosOci secretosOci(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new SecretosOci(auth, region);
    }

    @Bean
    ServicioDeSecretos servicioDeSecretos(SecretosOci origen) {
        return new ServicioDeSecretos(origen);
    }
''',
  q_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import jakarta.enterprise.inject.Disposes;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region')],
  q_producer='''    SecretosOci secretosOci() {
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
    }''',
  endpoints=[
    dict(n='comprobar', v='GET', p='/comprobar', args=[('String', 'secretId', 'q')], ret='ServicioDeSecretos.Comprobacion', call='s.comprobar(secretId)'),
    dict(n='rotado', v='POST', p='/rotado', args=[('String', 'secretId', 'q')], ret='String', call='s.alRotar(secretId)'),
  ])

jdoc.doc('/home/claude/cloud-study-4-nubes/oci/03-secretos/vault-secrets/uso-en-java.md',
  'Secretos · Vault: secretos',
  'Una **caché con TTL y «stale-if-error»** (pura, con reloj inyectable) delante de `SecretsClient.getSecretBundle`: la aplicación lee el secreto una vez cada pocos minutos y sigue viva si Vault se pone lento.',
  'oci:\n  auth: instance\n  region: sa-saopaulo-1',
  'oci.auth=instance\noci.region=sa-saopaulo-1',
  [('Contrato de la fuente', FUENTE, True), ('Caché con TTL y gracia', CACHE, True), ('Lectura con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('`GetSecretBundle`', '`Allow dynamic-group app-pedidos-prod to read secret-bundles in compartment tienda-prod where target.secret.id = \'<ocid>\'`')],
  ['No devuelvas el valor del secreto por HTTP ni lo escribas en registros o excepciones.',
   'No leas el secreto en cada petición: cachea con TTL corto y gracia.',
   'Si el destino rechaza la credencial, invalida la caché y reintenta **una** vez (probable rotación).',
   'No pidas la etapa `PENDING` salvo en el proceso de rotación.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
