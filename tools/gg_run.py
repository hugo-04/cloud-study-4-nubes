import ggen
POL = '''
import java.time.Duration;
import java.util.Set;

/** Política de llamada servicio-a-servicio: plazo total, reintentos solo seguros, backoff. Pura. */
public class PoliticaDeLlamada {

    public record Decision(boolean reintentar, Duration espera) { }

    private static final Set<String> IDEMPOTENTES = Set.of("GET", "HEAD", "PUT", "DELETE", "OPTIONS");
    private static final Set<Integer> TRANSITORIOS = Set.of(429, 502, 503, 504);

    private final int maxIntentos;
    private final Duration base;

    public PoliticaDeLlamada(int maxIntentos, Duration base) {
        this.maxIntentos = maxIntentos;
        this.base = base;
    }

    /** POST solo se reintenta si lleva Idempotency-Key. Respeta el plazo restante del llamador. */
    public Decision tras(String metodo, boolean conClaveIdempotencia, int estado, int intento, Duration restante) {
        boolean seguro = IDEMPOTENTES.contains(metodo) || conClaveIdempotencia;
        Duration espera = base.multipliedBy(1L << Math.min(intento, 10));
        boolean hayTiempo = restante.compareTo(espera.plusMillis(200)) > 0;
        return new Decision(seguro && TRANSITORIOS.contains(estado) && intento + 1 < maxIntentos && hayTiempo, espera);
    }

    /** La audiencia del ID token es la URL base del servicio (sin ruta). */
    public static String audiencia(String url) {
        var u = java.net.URI.create(url);
        if (!"https".equals(u.getScheme()) || u.getHost() == null) {
            throw new IllegalArgumentException("URL de servicio inválida");
        }
        return "https://" + u.getHost();
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.IdTokenCredentials;
import com.google.auth.oauth2.IdTokenProvider;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;

/** Adaptador: llama a un servicio privado de Cloud Run con ID token y aplica la política. */
public class LlamadorRun implements AutoCloseable {

    public record Respuesta(int estado, String cuerpo, int intentos) { }

    private final GoogleCredentials cred;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
    private final PoliticaDeLlamada politica = new PoliticaDeLlamada(3, Duration.ofMillis(200));

    public LlamadorRun(GoogleCredentials cred) {
        this.cred = cred;
    }

    private String idToken(String audiencia) throws IOException {
        if (!(cred instanceof IdTokenProvider proveedor)) {
            throw new IllegalStateException("estas credenciales no emiten ID tokens (en local usa suplantación de una SA)");
        }
        var t = IdTokenCredentials.newBuilder().setIdTokenProvider(proveedor).setTargetAudience(audiencia).build();
        t.refreshIfExpired();
        return t.getIdToken().getTokenValue();
    }

    public Respuesta get(String url, Duration plazo) {
        Instant limite = Instant.now().plus(plazo);
        try {
            String token = idToken(PoliticaDeLlamada.audiencia(url));
            for (int intento = 0; ; intento++) {
                Duration restante = Duration.between(Instant.now(), limite);
                var req = HttpRequest.newBuilder(URI.create(url)).timeout(restante).GET()
                    .header("Authorization", "Bearer " + token).build();
                var r = http.send(req, HttpResponse.BodyHandlers.ofString());
                var d = politica.tras("GET", false, r.statusCode(), intento, Duration.between(Instant.now(), limite));
                if (!d.reintentar()) {
                    return new Respuesta(r.statusCode(), r.body(), intento + 1);
                }
                Thread.sleep(d.espera().toMillis());
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    @Override
    public void close() {
        // HttpClient no requiere cierre explícito en Java 21 para este uso
    }
}
'''
SERV = '''
import java.time.Duration;

public class ServicioDePrecios {

    private final LlamadorRun run;
    private final String urlPrecios = "https://precios-abc123-tl.a.run.app";

    public ServicioDePrecios(LlamadorRun run) {
        this.run = run;
    }

    public LlamadorRun.Respuesta precio(String sku) {
        if (!sku.matches("[A-Z]{3}-[0-9]{2,6}")) {
            throw new IllegalArgumentException("sku inválido");
        }
        return run.get(urlPrecios + "/precios/" + sku, Duration.ofSeconds(2));
    }
}
'''
ggen.gcp('gcp/04-compute/cloud-run', 'Compute · Cloud Run',
  'Una **llamada servicio-a-servicio** correcta hacia un Cloud Run privado: obtiene un **ID token** con `IdTokenCredentials` (audiencia = URL base del servicio) desde las credenciales ADC, respeta un **plazo total** y reintenta solo métodos seguros (o con clave de idempotencia) ante 429/5xx transitorios. Dentro de Cloud Run, ADC ya entrega credenciales capaces de emitir ID tokens.',
  [],
  [('Política de llamada (lógica pura)', POL, True), ('Adaptador (google-auth-library + HttpClient)', SDK, True), ('Servicio', SERV, True)],
  'Precios', '/compute/precios', 'ServicioDePrecios', 'LlamadorRun', [],
  'return new LlamadorRun(cred);',
  [dict(n='precio', v='GET', p='/{sku}', args=[('String', 'sku', 'p')], ret='LlamadorRun.Respuesta', call='s.precio(sku)')],
  [('Invocar el servicio destino', '`roles/run.invoker` sobre **ese** servicio para la SA del llamador')],
  ['No hagas público un servicio interno para «evitar el token».',
   'No reintentes POST sin clave de idempotencia.',
   'No uses timeouts mayores que el plazo del llamador.',
   'No arranques hilos de fondo con CPU solo en peticiones.',
   'No pidas el ID token en cada llamada si puedes reutilizarlo hasta que venza (la biblioteca lo cachea).'])
