import genlib
SEM = '''
import java.util.List;

/** Semáforo de salud de un backend set. Puro: recibe conteos, devuelve nivel y mensaje. */
public class SemaforoDeSalud {

    public enum Nivel { VERDE, AMARILLO, ROJO }

    public record Lectura(String set, int total, List<String> warning, List<String> critical, List<String> unknown) { }

    public record Veredicto(String set, Nivel nivel, double disponibilidad, String mensaje) { }

    private final double umbralAmarillo;

    public SemaforoDeSalud(double umbralAmarillo) {
        this.umbralAmarillo = umbralAmarillo;
    }

    public Veredicto evaluar(Lectura l) {
        if (l.total() == 0) {
            return new Veredicto(l.set(), Nivel.ROJO, 0, "set sin backends");
        }
        int malos = l.critical().size() + l.unknown().size();
        int sanos = l.total() - malos - l.warning().size();
        double disp = (double) sanos / l.total();
        Nivel nivel = sanos == 0 ? Nivel.ROJO : disp < umbralAmarillo || !l.warning().isEmpty() ? Nivel.AMARILLO : Nivel.VERDE;
        String msg = nivel == Nivel.VERDE ? "todo sano"
            : "sanos " + sanos + "/" + l.total() + (malos > 0 ? "; fallando: " + String.join(",", l.critical()) : "");
        return new Veredicto(l.set(), nivel, Math.round(disp * 1000) / 1000.0, msg);
    }
}
'''
SDK = '''
import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;
import com.oracle.bmc.networkloadbalancer.requests.GetBackendSetHealthRequest;
import com.oracle.bmc.networkloadbalancer.requests.GetNetworkLoadBalancerRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: lee la salud de todos los backend sets de un NLB. */
public class NlbOci implements AutoCloseable {

    private final NetworkLoadBalancerClient cliente;

    public NlbOci(NetworkLoadBalancerClient cliente) {
        this.cliente = cliente;
    }

    public List<SemaforoDeSalud.Lectura> lecturas(String nlbId) {
        var nlb = cliente.getNetworkLoadBalancer(GetNetworkLoadBalancerRequest.builder()
            .networkLoadBalancerId(nlbId).build()).getNetworkLoadBalancer();
        var out = new ArrayList<SemaforoDeSalud.Lectura>();
        for (String set : nlb.getBackendSets().keySet()) {
            var h = cliente.getBackendSetHealth(GetBackendSetHealthRequest.builder()
                .networkLoadBalancerId(nlbId).backendSetName(set).build()).getBackendSetHealth();
            out.add(new SemaforoDeSalud.Lectura(set, h.getTotalBackendCount(),
                h.getWarningStateBackendNames(), h.getCriticalStateBackendNames(), h.getUnknownStateBackendNames()));
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
import java.util.List;

public class ServicioDeSalud {

    private final NlbOci nlb;
    private final SemaforoDeSalud semaforo = new SemaforoDeSalud(0.67);

    public ServicioDeSalud(NlbOci nlb) {
        this.nlb = nlb;
    }

    public List<SemaforoDeSalud.Veredicto> revisar(String nlbId) {
        return nlb.lecturas(nlbId).stream().map(semaforo::evaluar).toList();
    }
}
'''
genlib.oci('oci/05-ingress-api/network-load-balancer', 'Ingress y API · Network Load Balancer',
  'Un **semáforo de salud** para los backend sets de un NLB: lee `getBackendSetHealth` de cada set y lo traduce a VERDE/AMARILLO/ROJO con la disponibilidad real, listo para un tablero o una alarma.',
  [],
  [('Semáforo (lógica pura)', SEM, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Nlb', '/ingress/nlb', 'ServicioDeSalud', 'NlbOci',
  ['import com.oracle.bmc.networkloadbalancer.NetworkLoadBalancerClient;', 'import java.util.List;'],
  'return new NlbOci(NetworkLoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='revisar', v='GET', p='/{id}/salud', args=[('String', 'id', 'p')], ret='List<SemaforoDeSalud.Veredicto>', call='s.revisar(id)')],
  [('Leer NLB y salud', '`Allow dynamic-group monitoreo to read network-load-balancers in compartment red-prod`')],
  ['No consultes la salud en cada petición de usuario: hazlo periódicamente y cachea.',
   'No confundas `WARNING` con sano: algunos chequeos fallan.',
   'No uses el NLB para «ocultar» un backend sin TLS: cifra de extremo a extremo.',
   'No asumas que verás `X-Forwarded-For`: en capa 4 no existe; usa la preservación de origen.'])
