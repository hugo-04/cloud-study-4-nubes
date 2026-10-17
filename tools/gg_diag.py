import ggen
SIM = '''
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

/** Simula reglas de firewall de VPC para un paquete de entrada. Puro (no evalúa políticas jerárquicas). */
public class SimuladorDeFirewall {

    public record Regla(String nombre, int prioridad, boolean permite, List<String> origenes, List<String> cuentasObjetivo,
                        List<String> etiquetasObjetivo, String protocolo, List<String> puertos, boolean deshabilitada) { }

    public record Paquete(String ipOrigen, String cuentaDestino, List<String> etiquetasDestino, String protocolo, int puerto) { }

    public record Veredicto(boolean permitido, String regla) { }

    public Veredicto evaluar(List<Regla> reglas, Paquete p) {
        Optional<Regla> primera = reglas.stream()
            .filter(r -> !r.deshabilitada() && aplica(r, p))
            // menor prioridad primero; a igual prioridad, deny gana
            .min(Comparator.comparingInt(Regla::prioridad).thenComparing(Regla::permite));
        return primera.map(r -> new Veredicto(r.permite(), r.nombre()))
            .orElse(new Veredicto(false, "implícita: entrada denegada"));
    }

    static boolean aplica(Regla r, Paquete p) {
        boolean objetivo = (r.cuentasObjetivo().isEmpty() && r.etiquetasObjetivo().isEmpty())
            || r.cuentasObjetivo().contains(p.cuentaDestino())
            || r.etiquetasObjetivo().stream().anyMatch(p.etiquetasDestino()::contains);
        boolean protocolo = "all".equals(r.protocolo()) || r.protocolo().equals(p.protocolo());
        boolean puerto = r.puertos().isEmpty() || r.puertos().stream().anyMatch(x -> enRango(x, p.puerto()));
        boolean origen = r.origenes().stream().anyMatch(c -> contiene(c, p.ipOrigen()));
        return objetivo && protocolo && puerto && origen;
    }

    static boolean enRango(String rango, int puerto) {
        String[] x = rango.split("-");
        int a = Integer.parseInt(x[0]);
        int b = x.length > 1 ? Integer.parseInt(x[1]) : a;
        return puerto >= a && puerto <= b;
    }

    static boolean contiene(String cidr, String ip) {
        String[] c = cidr.split("/");
        long red = aLong(c[0]);
        long tam = 1L << (32 - Integer.parseInt(c[1]));
        long ini = red & ~(tam - 1) & 0xFFFFFFFFL;
        long v = aLong(ip);
        return v >= ini && v < ini + tam;
    }

    static long aLong(String ip) {
        long v = 0;
        for (String o : ip.split("\\\\.")) {
            v = (v << 8) | Integer.parseInt(o);
        }
        return v;
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

/** Adaptador: reglas de entrada de una red convertidas al modelo del simulador (allow y deny). */
public class ReglasGcp implements AutoCloseable {

    private final FirewallsClient cliente;
    private final String proyecto;

    public ReglasGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = FirewallsClient.create(FirewallsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<SimuladorDeFirewall.Regla> deEntrada(String red) {
        var out = new ArrayList<SimuladorDeFirewall.Regla>();
        for (var f : cliente.list(proyecto).iterateAll()) {
            if (!"INGRESS".equals(f.getDirection()) || !f.getNetwork().endsWith("/" + red)) {
                continue;
            }
            List<String> origenes = f.getSourceRangesList().isEmpty() ? List.of("0.0.0.0/0") : List.copyOf(f.getSourceRangesList());
            f.getAllowedList().forEach(a -> out.add(new SimuladorDeFirewall.Regla(f.getName(), f.getPriority(), true, origenes,
                List.copyOf(f.getTargetServiceAccountsList()), List.copyOf(f.getTargetTagsList()), a.getIPProtocol(),
                List.copyOf(a.getPortsList()), f.getDisabled())));
            f.getDeniedList().forEach(d -> out.add(new SimuladorDeFirewall.Regla(f.getName(), f.getPriority(), false, origenes,
                List.copyOf(f.getTargetServiceAccountsList()), List.copyOf(f.getTargetTagsList()), d.getIPProtocol(),
                List.copyOf(d.getPortsList()), f.getDisabled())));
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
public class ServicioDeDiagnostico {

    private final ReglasGcp reglas;
    private final SimuladorDeFirewall simulador = new SimuladorDeFirewall();

    public ServicioDeDiagnostico(ReglasGcp reglas) {
        this.reglas = reglas;
    }

    public SimuladorDeFirewall.Veredicto simular(String red, SimuladorDeFirewall.Paquete p) {
        return simulador.evaluar(reglas.deEntrada(red), p);
    }
}
'''
ggen.gcp('gcp/01-red/diagnostico-conectividad', 'Red · Diagnóstico de conectividad',
  'Un **simulador de firewall** para pruebas automatizadas de configuración: lee las reglas de entrada de una red (allow y deny) con `FirewallsClient` y decide si un paquete concreto (IP de origen, cuenta de servicio/etiquetas del destino, protocolo, puerto) pasa, con la regla responsable o la denegación implícita. No reemplaza a Connectivity Tests (no ve políticas jerárquicas ni rutas), pero sirve en el pipeline.',
  [],
  [('Simulador (lógica pura)', SIM, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Diagnostico', '/red/diagnostico', 'ServicioDeDiagnostico', 'ReglasGcp', [],
  'return new ReglasGcp(cred, proyecto);',
  [dict(n='simular', v='POST', p='/simulacion', args=[('String', 'red', 'q'), ('SimuladorDeFirewall.Paquete', 'p', 'b')], ret='SimuladorDeFirewall.Veredicto', call='s.simular(red, p)')],
  [('Leer reglas', '`roles/compute.networkViewer`')],
  ['No confíes solo en esta simulación: confirma con Connectivity Tests (rutas, NAT, políticas jerárquicas).',
   'No abras reglas para «probar»: simula primero.',
   'No olvides que una regla sin `sourceRanges` ni orígenes por SA aplica a cualquier origen.'])
