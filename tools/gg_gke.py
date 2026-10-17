import ggen
AUD = '''
import java.util.ArrayList;
import java.util.List;

/** Audita clústeres de GKE: canal, nodos privados, endpoint, Workload Identity y desfase de versión. Puro. */
public class AuditorDeClusteres {

    public record Cluster(String nombre, String ubicacion, String versionControl, List<String> versionesNodos, String canal,
                          boolean autopilot, boolean nodosPrivados, boolean endpointPrivado, boolean redesAutorizadas,
                          boolean workloadIdentity) { }

    public record Hallazgo(String cluster, String severidad, String mensaje) { }

    public List<Hallazgo> auditar(List<Cluster> clusteres) {
        var h = new ArrayList<Hallazgo>();
        for (Cluster c : clusteres) {
            if (c.canal() == null || c.canal().isBlank() || c.canal().equals("UNSPECIFIED")) {
                h.add(new Hallazgo(c.nombre(), "MEDIA", "sin canal de lanzamiento"));
            }
            if (!c.nodosPrivados()) {
                h.add(new Hallazgo(c.nombre(), "ALTA", "nodos con IP pública"));
            }
            if (!c.endpointPrivado() && !c.redesAutorizadas()) {
                h.add(new Hallazgo(c.nombre(), "ALTA", "plano de control accesible desde cualquier IP"));
            }
            if (!c.workloadIdentity()) {
                h.add(new Hallazgo(c.nombre(), "ALTA", "sin Workload Identity"));
            }
            for (String v : c.versionesNodos()) {
                int d = desfaseMenor(c.versionControl(), v);
                if (d >= 2) {
                    h.add(new Hallazgo(c.nombre(), "MEDIA", "node pool " + v + " va " + d + " versiones menores atrás"));
                }
            }
        }
        return h;
    }

    /** «1.31.4-gke.100» vs «1.29.8-gke.1» → 2. */
    static int desfaseMenor(String control, String nodo) {
        return menor(control) - menor(nodo);
    }

    private static int menor(String v) {
        String[] p = v.split("[.-]");
        return p.length > 1 ? Integer.parseInt(p[1]) : 0;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.container.v1.ClusterManagerClient;
import com.google.cloud.container.v1.ClusterManagerSettings;
import com.google.container.v1.NodePool;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador: clústeres de todas las ubicaciones del proyecto. */
public class ClusteresGcp implements AutoCloseable {

    private final ClusterManagerClient cliente;
    private final String proyecto;

    public ClusteresGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = ClusterManagerClient.create(ClusterManagerSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeClusteres.Cluster> todos() {
        return cliente.listClusters("projects/" + proyecto + "/locations/-").getClustersList().stream()
            .map(c -> new AuditorDeClusteres.Cluster(c.getName(), c.getLocation(), c.getCurrentMasterVersion(),
                c.getNodePoolsList().stream().map(NodePool::getVersion).toList(),
                c.hasReleaseChannel() ? c.getReleaseChannel().getChannel().name() : null,
                c.hasAutopilot() && c.getAutopilot().getEnabled(),
                c.getPrivateClusterConfig().getEnablePrivateNodes() || c.getNetworkConfig().getDefaultEnablePrivateNodes(),
                c.getPrivateClusterConfig().getEnablePrivateEndpoint(),
                c.getMasterAuthorizedNetworksConfig().getEnabled(),
                !c.getWorkloadIdentityConfig().getWorkloadPool().isBlank()))
            .toList();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeClusteres {

    private final ClusteresGcp gke;
    private final AuditorDeClusteres auditor = new AuditorDeClusteres();

    public ServicioDeClusteres(ClusteresGcp gke) {
        this.gke = gke;
    }

    public List<AuditorDeClusteres.Hallazgo> auditar() {
        return auditor.auditar(gke.todos());
    }
}
'''
ggen.gcp('gcp/04-compute/gke', 'Compute · GKE',
  'Un **auditor de clústeres**: lista todos los clústeres del proyecto (`ClusterManagerClient.listClusters` con ubicación `-`) y marca los que no tienen canal de lanzamiento, tienen nodos públicos o plano de control abierto, no tienen Workload Identity o tienen node pools dos o más versiones menores por detrás del plano de control.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Clusteres', '/compute/gke', 'ServicioDeClusteres', 'ClusteresGcp', ['import java.util.List;'],
  'return new ClusteresGcp(cred, proyecto);',
  [dict(n='auditar', v='GET', p='/auditoria', args=[], ret='List<AuditorDeClusteres.Hallazgo>', call='s.auditar()')],
  [('Listar clústeres', '`roles/container.clusterViewer`')],
  ['No uses la API de GKE para desplegar apps: eso es Kubernetes (manifiestos o GitOps).',
   'No guardes credenciales de kubeconfig en la app.',
   'No ignores el desfase de versiones: los nodos viejos quedan sin soporte.'])
