import genlib
TRI = '''
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/** Triaje de problemas: SLA por riesgo, vencidos primero. Puro: reloj inyectado. */
public class TriajeDeProblemas {

    public record Problema(String id, String riesgo, String regla, String recurso, Instant detectado) { }

    public record Prioridad(Problema problema, Instant vence, boolean vencido, long horasRestantes) { }

    private static final Map<String, Duration> SLA = Map.of(
        "CRITICAL", Duration.ofHours(24), "HIGH", Duration.ofDays(7),
        "MEDIUM", Duration.ofDays(30), "LOW", Duration.ofDays(90));
    private static final List<String> ORDEN = List.of("CRITICAL", "HIGH", "MEDIUM", "LOW", "MINOR");

    private final Clock reloj;

    public TriajeDeProblemas(Clock reloj) {
        this.reloj = reloj;
    }

    public List<Prioridad> priorizar(List<Problema> problemas) {
        Instant ahora = reloj.instant();
        return problemas.stream()
            .map(p -> {
                Instant vence = p.detectado().plus(SLA.getOrDefault(p.riesgo(), Duration.ofDays(180)));
                return new Prioridad(p, vence, vence.isBefore(ahora), Duration.between(ahora, vence).toHours());
            })
            .sorted(Comparator.comparing((Prioridad x) -> !x.vencido())
                .thenComparing(x -> rango(x.problema().riesgo()))
                .thenComparing(Prioridad::vence))
            .toList();
    }

    private static int rango(String riesgo) {
        int i = ORDEN.indexOf(riesgo);
        return i < 0 ? ORDEN.size() : i;
    }
}
'''
SDK = '''
import com.oracle.bmc.cloudguard.CloudGuardClient;
import com.oracle.bmc.cloudguard.model.ProblemLifecycleDetail;
import com.oracle.bmc.cloudguard.requests.ListProblemsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: problemas abiertos de todo el subárbol (paginando). */
public class CloudGuardOci implements AutoCloseable {

    private final CloudGuardClient cliente;

    public CloudGuardOci(CloudGuardClient cliente) {
        this.cliente = cliente;
    }

    public List<TriajeDeProblemas.Problema> abiertos(String compartimentoId) {
        var out = new ArrayList<TriajeDeProblemas.Problema>();
        String pagina = null;
        do {
            var r = cliente.listProblems(ListProblemsRequest.builder().compartmentId(compartimentoId)
                .compartmentIdInSubtree(true).accessLevel(ListProblemsRequest.AccessLevel.Accessible)
                .lifecycleDetail(ProblemLifecycleDetail.Open).page(pagina).build());
            r.getProblemCollection().getItems().forEach(p -> out.add(new TriajeDeProblemas.Problema(
                p.getId(), p.getRiskLevel().getValue(), p.getDetectorRuleId(), p.getResourceName(),
                p.getTimeFirstDetected().toInstant())));
            pagina = r.getOpcNextPage();
        } while (pagina != null);
        return out;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Clock;
import java.util.List;

public class ServicioDeTriaje {

    private final CloudGuardOci cloudGuard;
    private final TriajeDeProblemas triaje = new TriajeDeProblemas(Clock.systemUTC());

    public ServicioDeTriaje(CloudGuardOci cloudGuard) {
        this.cloudGuard = cloudGuard;
    }

    public List<TriajeDeProblemas.Prioridad> pendientes(String compartimentoId, int max) {
        return triaje.priorizar(cloudGuard.abiertos(compartimentoId)).stream().limit(max).toList();
    }
}
'''
genlib.oci('oci/09-gobierno/cloud-guard-security-zones', 'Gobierno · Cloud Guard y Security Zones',
  'Un **triaje de problemas con SLA**: trae los problemas abiertos de Cloud Guard de todo el subárbol (`CloudGuardClient.listProblems`, paginando) y los ordena: primero los que vencieron su SLA, luego por riesgo y fecha de vencimiento (CRITICAL 24 h, HIGH 7 días, MEDIUM 30, LOW 90). Ideal para el reporte diario del equipo de seguridad.',
  [],
  [('Triaje (lógica pura)', TRI, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Triaje', '/gobierno/cloud-guard', 'ServicioDeTriaje', 'CloudGuardOci',
  ['import com.oracle.bmc.cloudguard.CloudGuardClient;', 'import java.util.List;'],
  'return new CloudGuardOci(CloudGuardClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='pendientes', v='GET', p='/pendientes', args=[('String', 'compartimento', 'q'), ('int', 'max', 'q')], ret='List<TriajeDeProblemas.Prioridad>', call='s.pendientes(compartimento, max)')],
  [('Leer problemas', '`Allow dynamic-group seguridad-reportes to read cloud-guard-problems in tenancy`')],
  ['No uses la región local si los problemas se consolidan en la región de reporte: apunta el cliente allí.',
   'No descartes problemas desde código sin motivo ni dueño.',
   'No automatices correcciones destructivas desde un servicio de reporte.',
   'No olvides paginar.'])
