import ggen
EVA = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Réplica local (para pruebas) de la condición del proveedor: repositorio y rama permitidos por entorno.
 * Puro: recibe los claims ya decodificados del token externo.
 */
public class CondicionDeFederacion {

    public record Regla(String entorno, String repositorio, List<String> refsPermitidas) { }

    public record Resultado(boolean permitido, String entorno, List<String> motivos) { }

    private final List<Regla> reglas;
    private final String emisorEsperado;
    private final String audienciaEsperada;

    public CondicionDeFederacion(List<Regla> reglas, String emisorEsperado, String audienciaEsperada) {
        this.reglas = List.copyOf(reglas);
        this.emisorEsperado = emisorEsperado;
        this.audienciaEsperada = audienciaEsperada;
    }

    public Resultado evaluar(Map<String, String> claims, String entorno) {
        var motivos = new ArrayList<String>();
        if (!emisorEsperado.equals(claims.get("iss"))) {
            motivos.add("emisor distinto");
        }
        if (!audienciaEsperada.equals(claims.get("aud"))) {
            motivos.add("audiencia distinta");
        }
        var regla = reglas.stream().filter(r -> r.entorno().equals(entorno)).findFirst();
        if (regla.isEmpty()) {
            motivos.add("entorno sin regla: " + entorno);
        } else {
            if (!regla.get().repositorio().equals(claims.get("repository"))) {
                motivos.add("repositorio no permitido");
            }
            if (!regla.get().refsPermitidas().contains(claims.getOrDefault("ref", ""))) {
                motivos.add("rama/ref no permitida para " + entorno);
            }
        }
        return new Resultado(motivos.isEmpty(), entorno, motivos);
    }

    /** La misma regla escrita en CEL para el atributo attribute_condition del proveedor. */
    public static String comoCel(Regla r) {
        String refs = String.join(" || ", r.refsPermitidas().stream().map(x -> "assertion.ref == '" + x + "'").toList());
        return "assertion.repository == '" + r.repositorio() + "' && (" + refs + ")";
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.List;

/** Adaptador: credenciales federadas desde el archivo de configuración (tipo external_account). */
public class FederacionGcp implements AutoCloseable {

    public record Estado(String tipo, Instant vence) { }

    private final GoogleCredentials base;

    public FederacionGcp(GoogleCredentials base) {
        this.base = base;
    }

    /** En el pipeline, la ruta suele venir de GOOGLE_APPLICATION_CREDENTIALS (ADC lo resuelve solo). */
    public Estado probar(String rutaConfiguracion) {
        try (var in = new FileInputStream(rutaConfiguracion)) {
            var cred = GoogleCredentials.fromStream(in).createScoped(List.of("https://www.googleapis.com/auth/cloud-platform"));
            cred.refreshIfExpired();
            var token = cred.getAccessToken();
            return new Estado(cred.getClass().getSimpleName(), token.getExpirationTime() == null ? null : token.getExpirationTime().toInstant());
        } catch (IOException e) {
            throw new UncheckedIOException("no se pudo intercambiar el token externo", e);
        }
    }

    public GoogleCredentials base() {
        return base;
    }

    @Override
    public void close() {
        // sin recursos que cerrar
    }
}
'''
SERV = '''
import java.util.List;
import java.util.Map;

public class ServicioDeFederacion {

    private final FederacionGcp gcp;
    private final CondicionDeFederacion condicion = new CondicionDeFederacion(List.of(
            new CondicionDeFederacion.Regla("prod", "modalima/infra", List.of("refs/heads/main")),
            new CondicionDeFederacion.Regla("no-prod", "modalima/infra", List.of("refs/heads/main", "refs/heads/desarrollo"))),
        "https://ci.modalima.example", "https://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/ci-prod/providers/plataforma-ci");

    public ServicioDeFederacion(FederacionGcp gcp) {
        this.gcp = gcp;
    }

    public CondicionDeFederacion.Resultado simular(String entorno, Map<String, String> claims) {
        return condicion.evaluar(claims, entorno);
    }

    public FederacionGcp.Estado probar(String ruta) {
        return gcp.probar(ruta);
    }
}
'''
ggen.gcp('gcp/02-iam/workload-identity-federation', 'IAM · Workload Identity Federation',
  'Dos piezas: una **réplica local de la condición del proveedor** (emisor, audiencia, repositorio y rama permitidos por entorno, más su versión en CEL) para probar las reglas en el pipeline antes de aplicarlas, y un adaptador que carga el **archivo de configuración `external_account`** con `GoogleCredentials.fromStream` y hace el intercambio real para comprobar que funciona (sin exponer el token).',
  [],
  [('Condición (lógica pura)', EVA, True), ('Adaptador de google-auth-library', SDK, True), ('Servicio', SERV, True)],
  'Federacion', '/iam/federacion', 'ServicioDeFederacion', 'FederacionGcp', [],
  'return new FederacionGcp(cred);',
  [dict(n='simular', v='POST', p='/simulacion', args=[('String', 'entorno', 'q'), ('java.util.Map<String, String>', 'claims', 'b')], ret='CondicionDeFederacion.Resultado', call='s.simular(entorno, claims)', cpu=True),
   dict(n='probar', v='GET', p='/prueba', args=[('String', 'ruta', 'q')], ret='FederacionGcp.Estado', call='s.probar(ruta)')],
  [('Intercambio de tokens', 'Ninguno para el intercambio; los roles van al `principalSet` del repositorio'),
   ('Modo suplantación', '`roles/iam.workloadIdentityUser` del principalSet sobre la cuenta de servicio')],
  ['No confíes solo en tu réplica local: la condición real es la del proveedor (mantenlas sincronizadas con pruebas).',
   'No registres el token externo ni el federado.',
   'No guardes llaves JSON en el CI «como respaldo».',
   'No expongas el endpoint `/prueba` fuera del pipeline.'])
