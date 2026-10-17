import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdoc
VER = '''
/** Versión de Kubernetes: v1.31.1 → (1, 31, 1). */
public record VersionK8s(int mayor, int menor, int parche) implements Comparable<VersionK8s> {

    public static VersionK8s analizar(String texto) {
        String t = texto.strip();
        if (t.startsWith("v") || t.startsWith("V")) {
            t = t.substring(1);
        }
        String[] p = t.split("\\\\.");
        if (p.length < 2 || p.length > 3) {
            throw new IllegalArgumentException("versión no reconocida: " + texto);
        }
        return new VersionK8s(Integer.parseInt(p[0]), Integer.parseInt(p[1]), p.length == 3 ? Integer.parseInt(p[2]) : 0);
    }

    @Override
    public int compareTo(VersionK8s o) {
        int c = Integer.compare(mayor, o.mayor);
        if (c == 0) {
            c = Integer.compare(menor, o.menor);
        }
        return c == 0 ? Integer.compare(parche, o.parche) : c;
    }

    /** Distancia en versiones menores (positiva si esta es más nueva que la otra). */
    public int menoresSobre(VersionK8s otra) {
        return (mayor - otra.mayor) * 1000 + (menor - otra.menor);
    }

    @Override
    public String toString() {
        return "v" + mayor + "." + menor + "." + parche;
    }
}
'''
AUD = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Reglas de versiones entre el plano de control y sus node pools. Puro. */
public final class AuditorDeVersiones {

    public record Pool(String nombre, String version) { }

    public record Cluster(String nombre, String version, List<Pool> pools) { }

    public record Hallazgo(String cluster, String pool, String motivo) { }

    private final Set<VersionK8s> soportadas;
    private final int maxAtraso;

    /** soportadas: versiones menores vigentes (el parche no importa); maxAtraso: menores permitidos de diferencia. */
    public AuditorDeVersiones(Set<VersionK8s> soportadas, int maxAtraso) {
        this.soportadas = soportadas;
        this.maxAtraso = maxAtraso;
    }

    public List<Hallazgo> revisar(List<Cluster> clusters) {
        var salida = new ArrayList<Hallazgo>();
        for (Cluster c : clusters) {
            VersionK8s plano = VersionK8s.analizar(c.version());
            if (soportadas.stream().noneMatch(s -> s.mayor() == plano.mayor() && s.menor() == plano.menor())) {
                salida.add(new Hallazgo(c.nombre(), "(plano)", "versión " + plano + " fuera de las versiones soportadas"));
            }
            for (Pool p : c.pools()) {
                VersionK8s v = VersionK8s.analizar(p.version());
                int adelanto = v.menoresSobre(plano);
                if (adelanto > 0) {
                    salida.add(new Hallazgo(c.nombre(), p.nombre(), "el pool " + v + " es más nuevo que el plano " + plano));
                } else if (-adelanto > maxAtraso) {
                    salida.add(new Hallazgo(c.nombre(), p.nombre(), "el pool " + v + " va " + (-adelanto) + " versiones menores detrás del plano " + plano));
                }
            }
        }
        return salida;
    }
}
'''
SDK = '''
import com.oracle.bmc.containerengine.ContainerEngineClient;
import com.oracle.bmc.containerengine.model.ClusterSummary;
import com.oracle.bmc.containerengine.model.NodePoolSummary;
import com.oracle.bmc.containerengine.requests.ListClustersRequest;
import com.oracle.bmc.containerengine.requests.ListNodePoolsRequest;
import java.util.ArrayList;
import java.util.List;

/** Lee clústeres y node pools con paginación del SDK. */
public class ClustersOci {

    private final ContainerEngineClient cliente;

    public ClustersOci(ContainerEngineClient cliente) {
        this.cliente = cliente;
    }

    public List<AuditorDeVersiones.Cluster> todos(String compartimentoId) {
        var salida = new ArrayList<AuditorDeVersiones.Cluster>();
        var req = ListClustersRequest.builder().compartmentId(compartimentoId).build();
        for (ClusterSummary c : cliente.getPaginators().listClustersRecordIterator(req)) {
            var pools = new ArrayList<AuditorDeVersiones.Pool>();
            var rp = ListNodePoolsRequest.builder().compartmentId(compartimentoId).clusterId(c.getId()).build();
            for (NodePoolSummary p : cliente.getPaginators().listNodePoolsRecordIterator(rp)) {
                pools.add(new AuditorDeVersiones.Pool(p.getName(), p.getKubernetesVersion()));
            }
            salida.add(new AuditorDeVersiones.Cluster(c.getName(), c.getKubernetesVersion(), pools));
        }
        return salida;
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeClusters {

    private final ClustersOci clusters;
    private final AuditorDeVersiones auditor;

    public ServicioDeClusters(ClustersOci clusters, AuditorDeVersiones auditor) {
        this.clusters = clusters;
        this.auditor = auditor;
    }

    public List<AuditorDeVersiones.Hallazgo> auditar(String compartimentoId) {
        return auditor.revisar(clusters.todos(compartimentoId));
    }

    public List<AuditorDeVersiones.Hallazgo> auditarLista(List<AuditorDeVersiones.Cluster> lista) {
        return auditor.revisar(lista);
    }
}
'''
sec = dict(
  ns='Clusters', ruta='/compute/oke', servicio='ServicioDeClusters',
  spring_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.containerengine.ContainerEngineClient;', 'import org.springframework.beans.factory.annotation.Value;', 'import java.util.List;', 'import java.util.Set;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    ContainerEngineClient okeCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return ContainerEngineClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDeClusters servicioDeClusters(ContainerEngineClient cliente) {
        var soportadas = Set.of(VersionK8s.analizar("v1.31.0"), VersionK8s.analizar("v1.32.0"), VersionK8s.analizar("v1.33.0")); // verifica las vigentes
        return new ServicioDeClusters(new ClustersOci(cliente), new AuditorDeVersiones(soportadas, 2));
    }
''',
  q_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.containerengine.ContainerEngineClient;', 'import java.util.List;', 'import java.util.Set;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region')],
  q_producer='''    ServicioDeClusters servicioDeClusters() {
        var cliente = ContainerEngineClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        var soportadas = Set.of(VersionK8s.analizar("v1.31.0"), VersionK8s.analizar("v1.32.0"), VersionK8s.analizar("v1.33.0")); // verifica las vigentes
        return new ServicioDeClusters(new ClustersOci(cliente), new AuditorDeVersiones(soportadas, 2));
    }''',
  endpoints=[
    dict(n='auditoria', v='GET', p='/auditoria', args=[('String', 'compartimento', 'q')], ret='List<AuditorDeVersiones.Hallazgo>', call='s.auditar(compartimento)'),
    dict(n='revisar', v='POST', p='/revisar', args=[('List<AuditorDeVersiones.Cluster>', 'clusters', 'b')], ret='List<AuditorDeVersiones.Hallazgo>', call='s.auditarLista(clusters)', cpu=True),
  ])
jdoc.doc(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../oci/04-compute/oke/uso-en-java.md'),
  'Compute · OKE',
  'Un **auditor de versiones**: compara la versión de Kubernetes del plano de control con la de cada node pool (¿más nuevo que el plano? ¿demasiado atrás? ¿versión fuera de soporte?) leyendo los datos reales con `ContainerEngineClient`. La lógica es pura y se prueba sin red.',
  'oci:\n  auth: instance\n  region: sa-saopaulo-1',
  'oci.auth=instance\noci.region=sa-saopaulo-1',
  [('Versión de Kubernetes', VER, True), ('Auditor de versiones', AUD, True), ('Lectura con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('`ListClusters`, `ListNodePools`', '`Allow dynamic-group auditor-oke to inspect cluster-family in compartment tienda-prod`')],
  ['No codifiques la lista de versiones soportadas «para siempre»: léela de configuración y revísala cada trimestre.',
   'No uses este servicio para actualizar clústeres: solo informa; las actualizaciones van por Terraform y ventana de cambio.',
   'No expongas el listado de clústeres a Internet.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
