import ggen
AUD = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Señala reglas de firewall peligrosas o difíciles de gobernar. Puro. */
public class AuditorDeFirewall {

    public record Permiso(String protocolo, List<String> puertos) { }

    public record Regla(String nombre, String direccion, int prioridad, List<String> origenes, List<Permiso> permitidos,
                        List<String> cuentasObjetivo, List<String> etiquetasObjetivo, boolean deshabilitada, boolean conLogs) { }

    public record Hallazgo(String regla, String severidad, String mensaje) { }

    private static final Set<Integer> SENSIBLES = Set.of(22, 3389, 3306, 5432, 6379, 9200, 27017);

    public List<Hallazgo> auditar(List<Regla> reglas) {
        var h = new ArrayList<Hallazgo>();
        for (Regla r : reglas) {
            if (r.deshabilitada() || !"INGRESS".equals(r.direccion()) || r.permitidos().isEmpty()) {
                continue;
            }
            boolean desdeInternet = r.origenes().contains("0.0.0.0/0");
            boolean sinObjetivo = r.cuentasObjetivo().isEmpty() && r.etiquetasObjetivo().isEmpty();
            for (Permiso p : r.permitidos()) {
                boolean todos = "all".equals(p.protocolo()) || p.puertos().isEmpty();
                if (desdeInternet && (todos || p.puertos().stream().anyMatch(AuditorDeFirewall::esSensible))) {
                    h.add(new Hallazgo(r.nombre(), "ALTA", "abre " + (todos ? "todos los puertos" : p.puertos()) + " a Internet"));
                }
            }
            if (sinObjetivo) {
                h.add(new Hallazgo(r.nombre(), "MEDIA", "aplica a todas las instancias de la red"));
            } else if (r.cuentasObjetivo().isEmpty()) {
                h.add(new Hallazgo(r.nombre(), "BAJA", "usa etiquetas de red en lugar de cuentas de servicio"));
            }
            if (desdeInternet && !r.conLogs()) {
                h.add(new Hallazgo(r.nombre(), "BAJA", "regla abierta a Internet sin logs"));
            }
        }
        return h;
    }

    static boolean esSensible(String puertos) {
        String[] p = puertos.split("-");
        int desde = Integer.parseInt(p[0]);
        int hasta = p.length > 1 ? Integer.parseInt(p[1]) : desde;
        return SENSIBLES.stream().anyMatch(s -> s >= desde && s <= hasta);
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.FirewallsClient;
import com.google.cloud.compute.v1.FirewallsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: reglas de firewall de VPC del proyecto. */
public class FirewallGcp implements AutoCloseable {

    private final FirewallsClient cliente;
    private final String proyecto;

    public FirewallGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = FirewallsClient.create(FirewallsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeFirewall.Regla> reglas() {
        var out = new ArrayList<AuditorDeFirewall.Regla>();
        for (var f : cliente.list(proyecto).iterateAll()) {
            var permitidos = f.getAllowedList().stream()
                .map(a -> new AuditorDeFirewall.Permiso(a.getIPProtocol(), List.copyOf(a.getPortsList()))).toList();
            out.add(new AuditorDeFirewall.Regla(f.getName(), f.getDirection(), f.getPriority(), List.copyOf(f.getSourceRangesList()),
                permitidos, List.copyOf(f.getTargetServiceAccountsList()), List.copyOf(f.getTargetTagsList()),
                f.getDisabled(), f.hasLogConfig() && f.getLogConfig().getEnable()));
        }
        return out;
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

public class ServicioDeFirewall {

    private final FirewallGcp firewall;
    private final AuditorDeFirewall auditor = new AuditorDeFirewall();

    public ServicioDeFirewall(FirewallGcp firewall) {
        this.firewall = firewall;
    }

    public List<AuditorDeFirewall.Hallazgo> auditar() {
        return auditor.auditar(firewall.reglas()).stream()
            .sorted(Comparator.comparing(AuditorDeFirewall.Hallazgo::severidad))
            .toList();
    }
}
'''
ggen.gcp('gcp/01-red/firewall-rutas-nat', 'Red · Firewall, rutas y Cloud NAT',
  'Un **auditor de reglas de firewall**: lee las reglas de VPC con `FirewallsClient.list` y marca las de entrada que abren puertos sensibles o todos los puertos a `0.0.0.0/0`, las que aplican a todas las instancias, las que usan etiquetas en vez de cuentas de servicio y las abiertas a Internet sin logs.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Firewall', '/red/firewall', 'ServicioDeFirewall', 'FirewallGcp', ['import java.util.List;'],
  'return new FirewallGcp(cred, proyecto);',
  [dict(n='auditar', v='GET', p='/auditoria', args=[], ret='List<AuditorDeFirewall.Hallazgo>', call='s.auditar()')],
  [('Listar reglas', '`roles/compute.networkViewer` (o `roles/compute.securityAdmin` solo si además corrige)')],
  ['No corrijas reglas desde la app: reporta y corrige en Terraform.',
   'No olvides las políticas jerárquicas: este auditor solo ve reglas de VPC (léelas aparte con `FirewallPoliciesClient`).',
   'No asumas que una regla deshabilitada es inofensiva: alguien puede habilitarla.'])
