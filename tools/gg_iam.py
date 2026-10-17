import ggen
AUD = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Audita los bindings de una política de permisos. Puro. */
public class AuditorDePolitica {

    public record Binding(String rol, List<String> miembros, String condicion) { }

    public record Hallazgo(String severidad, String rol, String miembro, String mensaje) { }

    private static final Set<String> BASICOS = Set.of("roles/owner", "roles/editor", "roles/viewer");
    private static final Set<String> PELIGROSOS = Set.of(
        "roles/iam.serviceAccountTokenCreator", "roles/iam.serviceAccountKeyAdmin", "roles/resourcemanager.projectIamAdmin");

    public List<Hallazgo> auditar(List<Binding> bindings) {
        var h = new ArrayList<Hallazgo>();
        for (Binding b : bindings) {
            for (String m : b.miembros()) {
                if (m.equals("allUsers") || m.equals("allAuthenticatedUsers")) {
                    h.add(new Hallazgo("CRITICA", b.rol(), m, "acceso público"));
                }
                if (BASICOS.contains(b.rol())) {
                    h.add(new Hallazgo(b.rol().equals("roles/viewer") ? "MEDIA" : "ALTA", b.rol(), m, "rol básico: usa predefinidos"));
                }
                if (m.startsWith("user:") && !b.rol().startsWith("roles/viewer")) {
                    h.add(new Hallazgo("BAJA", b.rol(), m, "usuario individual: usa un grupo"));
                }
                if (PELIGROSOS.contains(b.rol()) && b.condicion() == null) {
                    h.add(new Hallazgo("ALTA", b.rol(), m, "rol de escalada sin condición a nivel de proyecto"));
                }
                if (m.startsWith("deleted:")) {
                    h.add(new Hallazgo("BAJA", b.rol(), m, "principal eliminado: limpiar"));
                }
            }
        }
        return h;
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
import java.util.List;

/** Adaptador: política de permisos de un proyecto. */
public class PoliticasGcp implements AutoCloseable {

    private final ProjectsClient cliente;

    public PoliticasGcp(GoogleCredentials cred) {
        try {
            this.cliente = ProjectsClient.create(ProjectsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<AuditorDePolitica.Binding> bindings(String proyecto) {
        var politica = cliente.getIamPolicy(ProjectName.of(proyecto));
        return politica.getBindingsList().stream()
            .map(b -> new AuditorDePolitica.Binding(b.getRole(), List.copyOf(b.getMembersList()),
                b.hasCondition() ? b.getCondition().getExpression() : null))
            .toList();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.Comparator;
import java.util.List;

public class ServicioDeIam {

    private final PoliticasGcp politicas;
    private final AuditorDePolitica auditor = new AuditorDePolitica();

    public ServicioDeIam(PoliticasGcp politicas) {
        this.politicas = politicas;
    }

    public List<AuditorDePolitica.Hallazgo> auditar(String proyecto) {
        return auditor.auditar(politicas.bindings(proyecto)).stream()
            .sorted(Comparator.comparing(AuditorDePolitica.Hallazgo::severidad)).toList();
    }
}
'''
ggen.gcp('gcp/02-iam/iam-roles-politicas', 'IAM · Roles y políticas de permisos',
  'Un **auditor de la política de permisos** de un proyecto: la lee con `ProjectsClient.getIamPolicy` y marca acceso público (`allUsers`, `allAuthenticatedUsers`), roles básicos, usuarios individuales en vez de grupos, roles que permiten escalar (crear tokens o llaves de cuentas de servicio, administrar IAM) sin condición, y principales eliminados.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Iam', '/iam/politicas', 'ServicioDeIam', 'PoliticasGcp', ['import java.util.List;'],
  'return new PoliticasGcp(cred);',
  [dict(n='auditar', v='GET', p='/{proyecto}', args=[('String', 'proyecto', 'p')], ret='List<AuditorDePolitica.Hallazgo>', call='s.auditar(proyecto)')],
  [('Leer la política del proyecto', '`roles/iam.securityReviewer` (o `roles/resourcemanager.projectIamAdmin` solo para modificar)')],
  ['No modifiques políticas sin el ETag (lectura-modificación-escritura).',
   'No uses `setIamPolicy` desde apps: reemplaza la política entera.',
   'No audites solo el proyecto: la herencia de carpetas y organización también cuenta (Policy Analyzer).'])
