import ggen
PRI = '''
import java.util.List;

/** Construye y valida principales de Workload Identity de GKE. Puro. */
public final class PrincipalesDeGke {

    private PrincipalesDeGke() { }

    private static final String NOMBRE_K8S = "[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?";

    public static String directo(long numeroProyecto, String proyecto, String namespace, String ksa) {
        validar(namespace, ksa);
        return "principal://iam.googleapis.com/projects/" + numeroProyecto + "/locations/global/workloadIdentityPools/"
            + proyecto + ".svc.id.goog/subject/ns/" + namespace + "/sa/" + ksa;
    }

    /** Todo un namespace (útil para lectura común; con cuidado). */
    public static String namespaceCompleto(long numeroProyecto, String proyecto, String namespace) {
        validar(namespace, "x");
        return "principalSet://iam.googleapis.com/projects/" + numeroProyecto + "/locations/global/workloadIdentityPools/"
            + proyecto + ".svc.id.goog/namespace/" + namespace;
    }

    /** Miembro para roles/iam.workloadIdentityUser en el modo suplantación. */
    public static String paraSuplantacion(String proyecto, String namespace, String ksa) {
        validar(namespace, ksa);
        return "serviceAccount:" + proyecto + ".svc.id.goog[" + namespace + "/" + ksa + "]";
    }

    public static boolean tieneRol(List<String> miembrosDelRol, String principal) {
        return miembrosDelRol.contains(principal);
    }

    private static void validar(String ns, String ksa) {
        if (!ns.matches(NOMBRE_K8S) || !ksa.matches(NOMBRE_K8S) || "default".equals(ksa)) {
            throw new IllegalArgumentException("namespace o KSA inválidos (y nunca la KSA default)");
        }
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.resourcemanager.v3.ProjectName;
import com.google.cloud.resourcemanager.v3.ProjectsClient;
import com.google.cloud.resourcemanager.v3.ProjectsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;

/** Adaptador: identidad vista por el pod (servidor de metadatos) y miembros de un rol en el proyecto. */
public class IdentidadGke implements AutoCloseable {

    private static final String METADATOS = "http://metadata.google.internal/computeMetadata/v1/";

    private final ProjectsClient proyectos;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();

    public IdentidadGke(GoogleCredentials cred) {
        try {
            this.proyectos = ProjectsClient.create(ProjectsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public String metadato(String ruta) {
        var req = HttpRequest.newBuilder(URI.create(METADATOS + ruta)).header("Metadata-Flavor", "Google")
            .timeout(Duration.ofSeconds(2)).build();
        try {
            return http.send(req, HttpResponse.BodyHandlers.ofString()).body().strip();
        } catch (IOException e) {
            throw new UncheckedIOException("sin servidor de metadatos (¿fuera de GKE?)", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    public List<String> miembros(String proyecto, String rol) {
        return proyectos.getIamPolicy(ProjectName.of(proyecto)).getBindingsList().stream()
            .filter(b -> b.getRole().equals(rol) && !b.hasCondition())
            .flatMap(b -> b.getMembersList().stream()).toList();
    }

    @Override
    public void close() {
        proyectos.close();
    }
}
'''
SERV = '''
public class ServicioDeIdentidad {

    public record Verificacion(String identidadDelPod, String principalEsperado, boolean tieneRol) { }

    private final IdentidadGke gke;

    public ServicioDeIdentidad(IdentidadGke gke) {
        this.gke = gke;
    }

    /** Prueba de humo al desplegar: ¿la KSA de este pod tiene el rol esperado en el proyecto? */
    public Verificacion verificar(String proyecto, long numero, String namespace, String ksa, String rol) {
        String vista = gke.metadato("instance/service-accounts/default/email");
        String esperado = PrincipalesDeGke.directo(numero, proyecto, namespace, ksa);
        return new Verificacion(vista, esperado, PrincipalesDeGke.tieneRol(gke.miembros(proyecto, rol), esperado));
    }
}
'''
ggen.gcp('gcp/02-iam/workload-identity-gke', 'IAM · Workload Identity en GKE',
  'En la app no hace falta código especial: **ADC** obtiene el token del servidor de metadatos de GKE. Lo que sí construyes es una **prueba de humo** para el despliegue: la lógica pura arma el principal directo de la KSA (o el miembro del modo suplantación) validando nombres y prohibiendo la KSA `default`; el adaptador lee la identidad vista por el pod en el servidor de metadatos y comprueba con `ProjectsClient.getIamPolicy` que ese principal tenga el rol esperado.',
  [],
  [('Principales (lógica pura)', PRI, True), ('Adaptador', SDK, True), ('Servicio', SERV, True)],
  'Identidad', '/iam/gke', 'ServicioDeIdentidad', 'IdentidadGke', [],
  'return new IdentidadGke(cred);',
  [dict(n='verificar', v='GET', p='/verificacion', args=[('String', 'proyecto', 'q'), ('long', 'numero', 'q'), ('String', 'ns', 'q'), ('String', 'ksa', 'q'), ('String', 'rol', 'q')], ret='ServicioDeIdentidad.Verificacion', call='s.verificar(proyecto, numero, ns, ksa, rol)')],
  [('Leer la política del proyecto (solo para la verificación)', '`roles/iam.securityReviewer`'),
   ('La app en sí', 'Los roles de datos otorgados a su principal de KSA')],
  ['No montes llaves JSON como secretos de Kubernetes.',
   'No uses la KSA `default` para nada con permisos.',
   'No uses el ID del proyecto donde va el **número** en `principal://`.',
   'No asumas que el metadata server responde en el primer milisegundo del arranque: reintenta.'])
