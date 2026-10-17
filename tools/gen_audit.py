import genlib
DET = '''
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Señala eventos sensibles fuera de horario, desde IP no habitual o fallidos repetidos. Puro. */
public class DetectorDeActividad {

    public record Evento(String nombre, String principal, String ip, String recurso, Instant cuando, int estado) { }

    public record Alerta(Evento evento, List<String> motivos) { }

    private final Set<String> sensibles;
    private final Set<String> prefijosIpConocidos;
    private final ZoneId zona;

    public DetectorDeActividad(Set<String> sensibles, Set<String> prefijosIpConocidos, ZoneId zona) {
        this.sensibles = Set.copyOf(sensibles);
        this.prefijosIpConocidos = Set.copyOf(prefijosIpConocidos);
        this.zona = zona;
    }

    public List<Alerta> analizar(List<Evento> eventos) {
        var out = new ArrayList<Alerta>();
        for (Evento e : eventos) {
            boolean sensible = sensibles.stream().anyMatch(s -> e.nombre().startsWith(s));
            if (!sensible) {
                continue;
            }
            var motivos = new ArrayList<String>();
            var local = e.cuando().atZone(zona);
            LocalTime hora = local.toLocalTime();
            boolean finDeSemana = local.getDayOfWeek() == DayOfWeek.SATURDAY || local.getDayOfWeek() == DayOfWeek.SUNDAY;
            if (finDeSemana || hora.isBefore(LocalTime.of(7, 0)) || hora.isAfter(LocalTime.of(21, 0))) {
                motivos.add("fuera de horario (" + local.getDayOfWeek() + " " + hora.withNano(0) + ")");
            }
            if (e.ip() != null && prefijosIpConocidos.stream().noneMatch(e.ip()::startsWith)) {
                motivos.add("IP no habitual " + e.ip());
            }
            if (e.estado() == 401 || e.estado() == 403 || e.estado() == 404) {
                motivos.add("intento denegado (" + e.estado() + ")");
            }
            if (!motivos.isEmpty()) {
                out.add(new Alerta(e, motivos));
            }
        }
        return out;
    }
}
'''
SDK = '''
import com.oracle.bmc.audit.AuditClient;
import com.oracle.bmc.audit.requests.ListEventsRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/** Adaptador del SDK: eventos de auditoría de una ventana (paginando). */
public class AuditOci implements AutoCloseable {

    private final AuditClient cliente;

    public AuditOci(AuditClient cliente) {
        this.cliente = cliente;
    }

    public List<DetectorDeActividad.Evento> eventos(String compartimentoId, Instant desde, Instant hasta) {
        var out = new ArrayList<DetectorDeActividad.Evento>();
        String pagina = null;
        do {
            var r = cliente.listEvents(ListEventsRequest.builder().compartmentId(compartimentoId)
                .startTime(Date.from(desde)).endTime(Date.from(hasta)).page(pagina).build());
            for (var e : r.getItems()) {
                var d = e.getData();
                int estado = d.getResponse() == null || d.getResponse().getStatus() == null ? 0 : Integer.parseInt(d.getResponse().getStatus());
                out.add(new DetectorDeActividad.Evento(d.getEventName(),
                    d.getIdentity() == null ? null : d.getIdentity().getPrincipalName(),
                    d.getIdentity() == null ? null : d.getIdentity().getIpAddress(),
                    d.getResourceName(), e.getEventTime().toInstant(), estado));
            }
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
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;

public class ServicioDeAuditoria {

    private final AuditOci audit;
    private final DetectorDeActividad detector = new DetectorDeActividad(
        Set.of("CreatePolicy", "UpdatePolicy", "DeletePolicy", "UpdateSecurityList", "Delete", "UpdateBucket", "CreateApiKey"),
        Set.of("10.", "200.48."), ZoneId.of("America/Lima"));

    public ServicioDeAuditoria(AuditOci audit) {
        this.audit = audit;
    }

    public List<DetectorDeActividad.Alerta> revisar(String compartimentoId, int horas) {
        if (horas < 1 || horas > 72) {
            throw new IllegalArgumentException("ventana de 1 a 72 horas");
        }
        Instant hasta = Instant.now();
        return detector.analizar(audit.eventos(compartimentoId, hasta.minus(Duration.ofHours(horas)), hasta));
    }
}
'''
genlib.oci('oci/09-gobierno/audit', 'Gobierno · Audit',
  'Un **detector de actividad sensible**: trae los eventos de Audit de una ventana acotada (`AuditClient.listEvents`, paginando) y marca operaciones sensibles (políticas, borrados, llaves de API, buckets) hechas fuera de horario en la zona horaria del negocio, desde IP no habitual o denegadas. Útil como tarea cada hora que publica en un tema de seguridad.',
  [],
  [('Detector (lógica pura)', DET, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Auditoria', '/gobierno/audit', 'ServicioDeAuditoria', 'AuditOci',
  ['import com.oracle.bmc.audit.AuditClient;', 'import java.util.List;'],
  'return new AuditOci(AuditClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='revisar', v='GET', p='/revision', args=[('String', 'compartimento', 'q'), ('int', 'horas', 'q')], ret='List<DetectorDeActividad.Alerta>', call='s.revisar(compartimento, horas)')],
  [('Leer eventos de auditoría', '`Allow dynamic-group seguridad-reportes to read audit-events in tenancy`')],
  ['No pidas ventanas enormes: acota por horas y compartimento.',
   'No olvides la región *home* para eventos de IAM.',
   'No expongas IPs y nombres de Audit en endpoints públicos.',
   'No compares horas sin zona horaria: los eventos vienen en UTC.'])
