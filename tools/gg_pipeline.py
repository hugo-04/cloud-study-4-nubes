import ggen
POL = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * Política sobre el plan (terraform show -json): bloquea destrucciones de recursos con datos,
 * recursos prohibidos y cambios de IAM amplios en prod. Puro.
 */
public final class PoliticaDePlan {

    public record Cambio(String direccion, String tipo, List<String> acciones) { }

    public record Veredicto(boolean permitido, List<String> bloqueos, List<String> avisos) { }

    private static final Set<String> CON_DATOS = Set.of("google_sql_database_instance", "google_storage_bucket",
        "google_spanner_database", "google_bigtable_instance", "google_firestore_database", "google_kms_crypto_key");
    private static final Set<String> PROHIBIDOS = Set.of("google_service_account_key");
    private static final Set<String> IAM_AMPLIO = Set.of("google_project_iam_binding", "google_project_iam_policy");

    private PoliticaDePlan() {
    }

    public static Veredicto evaluar(List<Cambio> cambios, String entorno) {
        var bloqueos = new ArrayList<String>();
        var avisos = new ArrayList<String>();
        for (var c : cambios) {
            boolean destruye = c.acciones().contains("delete");
            if (destruye && CON_DATOS.contains(c.tipo())) {
                (("prod".equals(entorno)) ? bloqueos : avisos).add("destruye recurso con datos: " + c.direccion()
                    + (c.acciones().contains("create") ? " (reemplazo: ¿falta un bloque moved?)" : ""));
            }
            if (PROHIBIDOS.contains(c.tipo()) && c.acciones().contains("create")) {
                bloqueos.add("recurso prohibido: " + c.direccion());
            }
            if (IAM_AMPLIO.contains(c.tipo()) && !c.acciones().equals(List.of("no-op"))) {
                avisos.add("IAM autoritativo (puede quitar accesos ajenos): " + c.direccion());
            }
        }
        return new Veredicto(bloqueos.isEmpty(), bloqueos, avisos);
    }
}
'''
SDK = '''
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee plan.json del bucket de artefactos del pipeline y extrae resource_changes. */
public class PlanGcp implements AutoCloseable {

    private final Storage storage;
    private final String bucket;
    private final ObjectMapper json = new ObjectMapper();

    public PlanGcp(GoogleCredentials cred, String proyecto, String bucket) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public List<PoliticaDePlan.Cambio> cambios(String objeto) {
        byte[] bytes = storage.readAllBytes(BlobId.of(bucket, objeto));
        try {
            return desdeJson(bytes);
        } catch (IOException e) {
            throw new UncheckedIOException("plan.json ilegible", e);
        }
    }

    List<PoliticaDePlan.Cambio> desdeJson(byte[] bytes) throws IOException {
        var out = new ArrayList<PoliticaDePlan.Cambio>();
        for (var rc : json.readTree(bytes).path("resource_changes")) {
            var acciones = new ArrayList<String>();
            rc.path("change").path("actions").forEach(a -> acciones.add(a.asText()));
            out.add(new PoliticaDePlan.Cambio(rc.path("address").asText(), rc.path("type").asText(), acciones));
        }
        return out;
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDePlanes {

    private final PlanGcp gcp;

    public ServicioDePlanes(PlanGcp gcp) {
        this.gcp = gcp;
    }

    public PoliticaDePlan.Veredicto evaluar(String objeto, String entorno) {
        return PoliticaDePlan.evaluar(gcp.cambios(objeto), entorno);
    }

    public PoliticaDePlan.Veredicto simular(String entorno, List<PoliticaDePlan.Cambio> cambios) {
        return PoliticaDePlan.evaluar(cambios, entorno);
    }
}
'''
ggen.gcp('gcp/10-terraform/autenticacion-y-pipelines', 'Terraform · Autenticación y pipelines',
  'La autenticación del pipeline no se programa (la resuelve ADC con el archivo `external_account` de la federación). Lo que sí aporta Java es la **política sobre el plan**: lee `plan.json` (`terraform show -json`) desde el bucket de artefactos y **bloquea en prod** la destrucción de recursos con datos (avisando si es un reemplazo que pide un bloque `moved`), prohíbe llaves de cuentas de servicio y avisa de IAM autoritativo. El mismo núcleo puro se empaqueta como CLI (`politica-plan.jar`) para el paso del pipeline.',
  [('planes.bucket', 'modalima-ci-artefactos')],
  [('Política (lógica pura)', POL, True), ('Adaptador (Cloud Storage + Jackson)', SDK, True), ('Servicio', SERV, True)],
  'Planes', '/terraform/planes', 'ServicioDePlanes', 'PlanGcp', [],
  'return new PlanGcp(cred, proyecto, bucket);',
  [dict(n='evaluar', v='GET', p='/evaluacion', args=[('String', 'objeto', 'q'), ('String', 'entorno', 'q')], ret='PoliticaDePlan.Veredicto', call='s.evaluar(objeto, entorno)'),
   dict(n='simular', v='POST', p='/simulacion', args=[('String', 'entorno', 'q'), ('java.util.List<PoliticaDePlan.Cambio>', 'cambios', 'b')], ret='PoliticaDePlan.Veredicto', call='s.simular(entorno, cambios)', cpu=True)],
  [('Leer plan.json', '`roles/storage.objectViewer` en el bucket de artefactos'),
   ('Plan/apply', 'Las SAs de plan y apply del pipeline (no este servicio)')],
  ['No registres el contenido de `plan.json`: puede tener secretos.',
   'No uses la política como única revisión: la humana sigue en prod.',
   'No le des a este servicio permisos de apply.',
   'No relajes bloqueos en prod con una variable de entorno.'])
