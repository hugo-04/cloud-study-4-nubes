import ggen
POL = '''
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Reglas para emitir tokens suplantados: quién puede pedir qué cuenta, qué alcances y cuánto dura. Puro. */
public class PoliticaDeSuplantacion {

    public record Pedido(String solicitante, String cuenta, List<String> alcances, Duration vida) { }

    public record Decision(boolean permitido, String motivo) { }

    private final Map<String, Set<String>> permitidas; // solicitante -> cuentas que puede suplantar
    private final Set<String> alcancesPermitidos;
    private final Duration vidaMaxima;

    public PoliticaDeSuplantacion(Map<String, Set<String>> permitidas, Set<String> alcancesPermitidos, Duration vidaMaxima) {
        this.permitidas = Map.copyOf(permitidas);
        this.alcancesPermitidos = Set.copyOf(alcancesPermitidos);
        this.vidaMaxima = vidaMaxima;
    }

    public Decision evaluar(Pedido p) {
        if (!p.cuenta().matches("[a-z][a-z0-9-]{4,29}@[a-z][a-z0-9-]{4,28}[a-z0-9]\\\\.iam\\\\.gserviceaccount\\\\.com")) {
            return new Decision(false, "cuenta de servicio inválida");
        }
        if (!permitidas.getOrDefault(p.solicitante(), Set.of()).contains(p.cuenta())) {
            return new Decision(false, p.solicitante() + " no puede suplantar a " + p.cuenta());
        }
        if (p.alcances().isEmpty() || !alcancesPermitidos.containsAll(p.alcances())) {
            return new Decision(false, "alcances no permitidos");
        }
        if (p.vida().isNegative() || p.vida().isZero() || p.vida().compareTo(vidaMaxima) > 0) {
            return new Decision(false, "vida del token fuera de rango (máx. " + vidaMaxima.toMinutes() + " min)");
        }
        return new Decision(true, "ok");
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.iam.credentials.v1.IamCredentialsClient;
import com.google.cloud.iam.credentials.v1.IamCredentialsSettings;
import com.google.cloud.iam.credentials.v1.ServiceAccountName;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.List;

/** Adaptador: genera tokens de acceso de vida corta como otra cuenta (IAM Credentials). */
public class SuplantacionGcp implements AutoCloseable {

    public record Token(String cuenta, Instant vence, String huella) { }

    private final IamCredentialsClient cliente;

    public SuplantacionGcp(GoogleCredentials cred) {
        try {
            this.cliente = IamCredentialsClient.create(IamCredentialsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Token emitir(String cuenta, List<String> alcances, java.time.Duration vida) {
        var r = cliente.generateAccessToken(ServiceAccountName.of("-", cuenta), List.of(), alcances,
            com.google.protobuf.Duration.newBuilder().setSeconds(vida.toSeconds()).build());
        // nunca devolvemos el token a un cliente HTTP en este ejemplo: solo su huella para auditoría
        String huella = Integer.toHexString(r.getAccessToken().hashCode());
        return new Token(cuenta, Instant.ofEpochSecond(r.getExpireTime().getSeconds()), huella);
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ServicioDeSuplantacion {

    public record Solicitud(String solicitante, String cuenta, List<String> alcances, int minutos) { }

    public record Resultado(boolean emitido, String motivo, SuplantacionGcp.Token token) { }

    private final SuplantacionGcp gcp;
    // En producción estas reglas viven en configuración versionada y revisada.
    private final PoliticaDeSuplantacion politica = new PoliticaDeSuplantacion(
        Map.of("tarea-reportes", Set.of("lector-ventas@modalima-datos-prod.iam.gserviceaccount.com")),
        Set.of("https://www.googleapis.com/auth/cloud-platform.read-only", "https://www.googleapis.com/auth/devstorage.read_only"),
        Duration.ofMinutes(60));

    public ServicioDeSuplantacion(SuplantacionGcp gcp) {
        this.gcp = gcp;
    }

    public Resultado emitir(Solicitud s) {
        var d = politica.evaluar(new PoliticaDeSuplantacion.Pedido(s.solicitante(), s.cuenta(), s.alcances(), Duration.ofMinutes(s.minutos())));
        if (!d.permitido()) {
            return new Resultado(false, d.motivo(), null);
        }
        return new Resultado(true, "ok", gcp.emitir(s.cuenta(), s.alcances(), Duration.ofMinutes(s.minutos())));
    }
}
'''
ggen.gcp('gcp/02-iam/cuentas-de-servicio', 'IAM · Cuentas de servicio y suplantación',
  'Un **emisor de tokens suplantados con reglas**: la lógica pura decide quién puede suplantar qué cuenta, con qué alcances y por cuánto tiempo (máx. 60 min); el adaptador llama a `IamCredentialsClient.generateAccessToken`. El ejemplo devuelve solo la huella y el vencimiento (los tokens no se exponen por HTTP). Para el caso simple de «mi código actúa como otra cuenta», basta `ImpersonatedCredentials` (ver `Credenciales` en 2.1).',
  [],
  [('Política de suplantación (lógica pura)', POL, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Suplantacion', '/iam/suplantacion', 'ServicioDeSuplantacion', 'SuplantacionGcp', [],
  'return new SuplantacionGcp(cred);',
  [dict(n='emitir', v='POST', p='', args=[('ServicioDeSuplantacion.Solicitud', 'sol', 'b')], ret='ServicioDeSuplantacion.Resultado', call='s.emitir(sol)')],
  [('Generar tokens como la cuenta destino', '`roles/iam.serviceAccountTokenCreator` **sobre esa cuenta** (no en el proyecto)'),
   ('API', 'Habilitar `iamcredentials.googleapis.com`')],
  ['No descargues ni uses llaves JSON.',
   'No devuelvas tokens por endpoints HTTP ni los registres.',
   'No pidas `cloud-platform` si basta un alcance de solo lectura (los roles IAM igual mandan).',
   'No encadenes suplantaciones sin necesidad (`delegates`).'])
