import genlib
TRI = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/** Triage por capas: evalúa en orden y señala la primera que falla; «no se pudo comprobar» también cuenta. Puro. */
public class TriageDeCapas {

    public enum Resultado { OK, FALLA, DESCONOCIDO }

    public record Chequeo(String capa, Supplier<Boolean> prueba) { }

    public record Paso(String capa, Resultado resultado, String detalle) { }

    public record Informe(List<Paso> pasos, String primeraCapaConProblema, String runbook) { }

    private static final Map<String, String> RUNBOOK = Map.of(
        "load-balancer", "502/504: salud de backends → readiness → último despliegue",
        "pods", "reinicios/OOM → revertir despliegue → escalar",
        "dependencias", "sesiones de ATP, latencia de caché, DLQ → pools → consultas top",
        "cambios", "revertir el último cambio de infraestructura o aplicación");

    public Informe evaluar(List<Chequeo> chequeos) {
        var pasos = new ArrayList<Paso>();
        String primera = null;
        for (Chequeo c : chequeos) {
            Resultado r;
            String detalle;
            try {
                r = c.prueba().get() ? Resultado.OK : Resultado.FALLA;
                detalle = r == Resultado.OK ? "ok" : "falla";
            } catch (RuntimeException e) {
                r = Resultado.DESCONOCIDO;
                detalle = "no se pudo comprobar: " + e.getClass().getSimpleName();
            }
            pasos.add(new Paso(c.capa(), r, detalle));
            if (primera == null && r != Resultado.OK) {
                primera = c.capa();
            }
        }
        return new Informe(pasos, primera, primera == null ? "sin hallazgos en las capas" : RUNBOOK.getOrDefault(primera, "revisar la capa"));
    }

    /** Tasa de error a partir de conteos (protege la división). */
    public static double tasaDeError(double errores, double total) {
        return total <= 0 ? 0 : errores / total;
    }
}
'''
SDK = '''
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import com.oracle.bmc.loadbalancer.model.LoadBalancerHealth;
import com.oracle.bmc.loadbalancer.requests.GetLoadBalancerHealthRequest;
import com.oracle.bmc.monitoring.MonitoringClient;
import com.oracle.bmc.monitoring.model.SummarizeMetricsDataDetails;
import com.oracle.bmc.monitoring.requests.SummarizeMetricsDataRequest;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;

/** Adaptador del SDK: métricas del LB (MQL) y salud general. */
public class SenalesOci implements AutoCloseable {

    private final MonitoringClient monitoreo;
    private final LoadBalancerClient lb;
    private final String compartimentoId;

    public SenalesOci(MonitoringClient monitoreo, LoadBalancerClient lb, String compartimentoId) {
        this.monitoreo = monitoreo;
        this.lb = lb;
        this.compartimentoId = compartimentoId;
    }

    /** Suma de una métrica del LB en la ventana (por ejemplo HttpResponses5xx o HttpRequests; verifica nombres). */
    public double sumaLb(String metrica, String lbId, Duration ventana) {
        Instant fin = Instant.now();
        var det = SummarizeMetricsDataDetails.builder().namespace("oci_lbaas")
            .query(metrica + "[1m]{resourceId = \\"" + lbId + "\\"}.sum()")
            .startTime(Date.from(fin.minus(ventana))).endTime(Date.from(fin)).build();
        return monitoreo.summarizeMetricsData(SummarizeMetricsDataRequest.builder()
                .compartmentId(compartimentoId).summarizeMetricsDataDetails(det).build())
            .getItems().stream().flatMap(m -> m.getAggregatedDatapoints().stream())
            .mapToDouble(p -> p.getValue()).sum();
    }

    public boolean lbSano(String lbId) {
        return lb.getLoadBalancerHealth(GetLoadBalancerHealthRequest.builder().loadBalancerId(lbId).build())
            .getLoadBalancerHealth().getStatus() == LoadBalancerHealth.Status.Ok;
    }

    @Override
    public void close() {
        monitoreo.close();
        lb.close();
    }
}
'''
SERV = '''
import java.time.Duration;
import java.util.List;

public class ServicioDeTriage {

    private final SenalesOci senales;
    private final TriageDeCapas triage = new TriageDeCapas();

    public ServicioDeTriage(SenalesOci senales) {
        this.senales = senales;
    }

    public TriageDeCapas.Informe evaluar(String lbId, double umbralError) {
        var ventana = Duration.ofMinutes(5);
        return triage.evaluar(List.of(
            new TriageDeCapas.Chequeo("load-balancer", () -> senales.lbSano(lbId)),
            new TriageDeCapas.Chequeo("errores-5xx", () -> TriageDeCapas.tasaDeError(
                senales.sumaLb("HttpResponses5xx", lbId, ventana), senales.sumaLb("HttpRequests", lbId, ventana)) < umbralError)
            // + pods, dependencias y cambios recientes con sus propios adaptadores
        ));
    }
}
'''
genlib.oci('oci/11-casos-integrados/runbook-diagnostico', 'Caso integrado · Runbook de diagnóstico',
  'Un **triage automático por capas**: recorre chequeos en orden (salud del LB, tasa de 5xx de los últimos 5 minutos con `MonitoringClient.summarizeMetricsData` en MQL), marca la **primera capa con problema** y sugiere el runbook; si un chequeo no puede ejecutarse (permisos, red), lo reporta como DESCONOCIDO, que también es un hallazgo.',
  [('triage.compartimento', 'ocid1.compartment.oc1..aaaa')],
  [('Triage por capas (lógica pura)', TRI, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Triage', '/casos/triage', 'ServicioDeTriage', 'SenalesOci',
  ['import com.oracle.bmc.loadbalancer.LoadBalancerClient;', 'import com.oracle.bmc.monitoring.MonitoringClient;'],
  'var r = Region.fromRegionId(region);\nreturn new SenalesOci(MonitoringClient.builder().region(r).build(auth), LoadBalancerClient.builder().region(r).build(auth), compartimento);',
  [dict(n='evaluar', v='GET', p='/{lb}', args=[('String', 'lb', 'p'), ('double', 'umbral', 'q')], ret='TriageDeCapas.Informe', call='s.evaluar(lb, umbral)')],
  [('Leer métricas', '`Allow dynamic-group guardia-triage to read metrics in compartment tienda-prod`'),
   ('Leer salud del LB', '`Allow dynamic-group guardia-triage to read load-balancers in compartment red-prod`')],
  ['No hagas mitigaciones automáticas desde el triage: propone; las personas deciden.',
   'No trates un error de lectura como OK.',
   'No consultes ventanas largas con resolución de 1 minuto en cada llamada.',
   'No dependas del sistema que diagnosticas: corre el triage fuera del clúster afectado.'])
