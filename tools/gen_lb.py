import genlib
PLAN = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Decide si es seguro drenar un backend sin dejar el set por debajo del mínimo sano. Puro. */
public class PlanDeDrenado {

    public record Decision(boolean permitido, String motivo, int sanosRestantes) { }

    private final int minimoSanos;

    public PlanDeDrenado(int minimoSanos) {
        this.minimoSanos = minimoSanos;
    }

    /** total: nombres «ip:puerto» del set; noSanos: los que están en warning/critical/unknown; drenados: los que ya drenan. */
    public Decision evaluar(String objetivo, List<String> total, Set<String> noSanos, Set<String> drenados) {
        if (!total.contains(objetivo)) {
            return new Decision(false, "el backend no pertenece al set", 0);
        }
        var sanosActivos = new ArrayList<String>();
        for (String b : total) {
            if (!noSanos.contains(b) && !drenados.contains(b)) {
                sanosActivos.add(b);
            }
        }
        int restantes = sanosActivos.size() - (sanosActivos.contains(objetivo) ? 1 : 0);
        if (restantes < minimoSanos) {
            return new Decision(false, "quedarían " + restantes + " sanos; mínimo " + minimoSanos, restantes);
        }
        return new Decision(true, "ok", restantes);
    }
}
'''
SDK = '''
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import com.oracle.bmc.loadbalancer.model.Backend;
import com.oracle.bmc.loadbalancer.model.UpdateBackendDetails;
import com.oracle.bmc.loadbalancer.requests.GetBackendSetHealthRequest;
import com.oracle.bmc.loadbalancer.requests.ListBackendsRequest;
import com.oracle.bmc.loadbalancer.requests.UpdateBackendRequest;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Adaptador del SDK: lee salud y backends, y aplica el drenado. */
public class BalanceadorOci implements AutoCloseable {

    public record Estado(List<String> total, Set<String> noSanos, Set<String> drenados) { }

    private final LoadBalancerClient cliente;
    private final String lbId;

    public BalanceadorOci(LoadBalancerClient cliente, String lbId) {
        this.cliente = cliente;
        this.lbId = lbId;
    }

    public Estado estado(String backendSet) {
        var salud = cliente.getBackendSetHealth(GetBackendSetHealthRequest.builder()
            .loadBalancerId(lbId).backendSetName(backendSet).build()).getBackendSetHealth();
        var noSanos = new HashSet<String>();
        noSanos.addAll(salud.getWarningStateBackendNames());
        noSanos.addAll(salud.getCriticalStateBackendNames());
        noSanos.addAll(salud.getUnknownStateBackendNames());
        List<Backend> backends = cliente.listBackends(ListBackendsRequest.builder()
            .loadBalancerId(lbId).backendSetName(backendSet).build()).getItems();
        var drenados = new HashSet<String>();
        backends.stream().filter(b -> Boolean.TRUE.equals(b.getDrain())).forEach(b -> drenados.add(b.getName()));
        return new Estado(backends.stream().map(Backend::getName).toList(), noSanos, drenados);
    }

    /** Devuelve el id de la work request (la operación es asíncrona). */
    public String drenar(String backendSet, String backend, boolean drenar) {
        var detalles = UpdateBackendDetails.builder().weight(1).backup(false).offline(false).drain(drenar).build();
        return cliente.updateBackend(UpdateBackendRequest.builder()
            .loadBalancerId(lbId).backendSetName(backendSet).backendName(backend)
            .updateBackendDetails(detalles).build()).getOpcWorkRequestId();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
public class ServicioDeDrenado {

    public record Resultado(boolean aplicado, String motivo, String workRequest) { }

    private final BalanceadorOci lb;
    private final PlanDeDrenado plan = new PlanDeDrenado(1);

    public ServicioDeDrenado(BalanceadorOci lb) {
        this.lb = lb;
    }

    public Resultado drenar(String backendSet, String backend) {
        var e = lb.estado(backendSet);
        var d = plan.evaluar(backend, e.total(), e.noSanos(), e.drenados());
        if (!d.permitido()) {
            return new Resultado(false, d.motivo(), null);
        }
        return new Resultado(true, "quedan " + d.sanosRestantes() + " sanos", lb.drenar(backendSet, backend, true));
    }

    public Resultado reactivar(String backendSet, String backend) {
        return new Resultado(true, "reactivado", lb.drenar(backendSet, backend, false));
    }
}
'''
genlib.oci('oci/05-ingress-api/load-balancer', 'Ingress y API · Load Balancer',
  'Un **drenado seguro** para despliegues: antes de sacar una réplica, el servicio lee la salud real del backend set y se niega a drenar si quedarían menos réplicas sanas que el mínimo. Luego marca `drain=true` con `LoadBalancerClient.updateBackend`.',
  [('lb.id', 'ocid1.loadbalancer.oc1.sa-saopaulo-1.aaaa')],
  [('Plan de drenado (lógica pura)', PLAN, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Drenado', '/ingress/drenado', 'ServicioDeDrenado', 'BalanceadorOci',
  ['import com.oracle.bmc.loadbalancer.LoadBalancerClient;'],
  'var cliente = LoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth);\nreturn new BalanceadorOci(cliente, id);',
  [dict(n='drenar', v='POST', p='/{set}/{backend}/drenar', args=[('String', 'set', 'p'), ('String', 'backend', 'p')], ret='ServicioDeDrenado.Resultado', call='s.drenar(set, backend)'),
   dict(n='reactivar', v='POST', p='/{set}/{backend}/reactivar', args=[('String', 'set', 'p'), ('String', 'backend', 'p')], ret='ServicioDeDrenado.Resultado', call='s.reactivar(set, backend)')],
  [('Leer salud y backends', '`Allow dynamic-group despliegues to read load-balancers in compartment red-prod`'),
   ('Drenar / reactivar (`updateBackend`)', '`Allow dynamic-group despliegues to use load-balancers in compartment red-prod`')],
  ['No drenes y detengas en el mismo instante: espera a que terminen las conexiones (o un tiempo fijo prudente).',
   'No ignores la work request: `updateBackend` es asíncrono.',
   'No confíes en `X-Forwarded-For` si la petición no viene del LB.',
   'No hagas que el chequeo de salud dependa de la base de datos.',
   'No uses `IP_HASH` para «resolver» sesiones en memoria: saca el estado de la réplica.'])
