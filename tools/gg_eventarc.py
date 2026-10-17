import ggen
REC = '''
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Receptor de CloudEvents en modo binario: lee las cabeceras ce-*, valida, deduplica por (source, id)
 * y decide si el evento interesa. Puro: no depende del framework web.
 */
public class ReceptorDeEventos {

    public record Evento(String id, String source, String type, String subject, Instant time) { }

    public record Decision(String accion, Evento evento, List<String> motivos) { }

    private final Set<String> tiposAceptados;
    private final Map<String, Boolean> vistos = new ConcurrentHashMap<>();

    public ReceptorDeEventos(Set<String> tiposAceptados) {
        this.tiposAceptados = Set.copyOf(tiposAceptados);
    }

    public Decision recibir(Map<String, String> cabeceras) {
        var c = new LinkedHashMap<String, String>();
        cabeceras.forEach((k, v) -> c.put(k.toLowerCase(), v));
        var motivos = new ArrayList<String>();
        for (String obligatoria : List.of("ce-id", "ce-source", "ce-type", "ce-specversion")) {
            if (c.get(obligatoria) == null || c.get(obligatoria).isBlank()) {
                motivos.add("falta " + obligatoria);
            }
        }
        if (!motivos.isEmpty()) {
            return new Decision("descartar", null, motivos);   // 2xx igualmente: reintentar no lo arregla
        }
        Instant t = c.containsKey("ce-time") ? Instant.parse(c.get("ce-time")) : null;
        var e = new Evento(c.get("ce-id"), c.get("ce-source"), c.get("ce-type"), c.get("ce-subject"), t);
        if (!tiposAceptados.contains(e.type())) {
            return new Decision("ignorar", e, List.of("tipo no aceptado: " + e.type()));
        }
        if (vistos.putIfAbsent(e.source() + "|" + e.id(), Boolean.TRUE) != null) {
            return new Decision("duplicado", e, List.of("ya procesado"));
        }
        return new Decision("procesar", e, List.of());
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.eventarc.v1.EventarcClient;
import com.google.cloud.eventarc.v1.EventarcSettings;
import com.google.cloud.eventarc.v1.Trigger;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: audita los disparadores del proyecto (cuenta de servicio, filtros y destino). */
public class EventarcGcp implements AutoCloseable {

    public record Hallazgo(String disparador, String destino, List<String> filtros, List<String> problemas) { }

    private final EventarcClient cliente;
    private final String proyecto;

    public EventarcGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = EventarcClient.create(EventarcSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Hallazgo> auditar() {
        var out = new ArrayList<Hallazgo>();
        for (Trigger t : cliente.listTriggers("projects/" + proyecto + "/locations/-").iterateAll()) {
            var filtros = t.getEventFiltersList().stream().map(f -> f.getAttribute() + "=" + f.getValue()).toList();
            var problemas = new ArrayList<String>();
            if (t.getServiceAccount().isBlank() || t.getServiceAccount().contains("-compute@")) {
                problemas.add("usa la cuenta por defecto de Compute (o ninguna)");
            }
            boolean auditLogs = filtros.contains("type=google.cloud.audit.log.v1.written");
            if (auditLogs && filtros.stream().noneMatch(f -> f.startsWith("methodName="))) {
                problemas.add("Audit Logs sin filtro de methodName: mucho ruido");
            }
            var d = t.getDestination();
            String destino = d.hasCloudRun() ? "run:" + d.getCloudRun().getService() + d.getCloudRun().getPath()
                : d.hasWorkflow() ? "workflow:" + d.getWorkflow() : d.hasGke() ? "gke:" + d.getGke().getService() : "otro";
            out.add(new Hallazgo(t.getName().substring(t.getName().lastIndexOf('/') + 1), destino, filtros, problemas));
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
import java.util.Map;
import java.util.Set;

public class ServicioDeEventos {

    private final EventarcGcp gcp;
    private final ReceptorDeEventos receptor = new ReceptorDeEventos(Set.of("google.cloud.audit.log.v1.written"));

    public ServicioDeEventos(EventarcGcp gcp) {
        this.gcp = gcp;
    }

    /** Siempre se responde 2xx salvo error transitorio propio: así Eventarc no reintenta lo ya decidido. */
    public ReceptorDeEventos.Decision recibir(Map<String, String> cabeceras) {
        return receptor.recibir(cabeceras);
    }

    public List<EventarcGcp.Hallazgo> auditar() {
        return gcp.auditar();
    }
}
'''
ggen.gcp('gcp/07-mensajeria/eventarc', 'Mensajería · Eventarc',
  'Dos piezas: un **receptor de CloudEvents en modo binario** (lee `ce-id`, `ce-source`, `ce-type`, `ce-time`, valida, filtra por tipo y deduplica por `source|id`) y un adaptador que **audita los disparadores** con `EventarcClient.listTriggers` en todas las ubicaciones: cuenta de servicio por defecto, filtros de Audit Logs demasiado amplios y destino. En el ejemplo las cabeceras llegan como mapa para no atar la lógica al framework.',
  [],
  [('Receptor (lógica pura)', REC, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Eventos', '/mensajeria/eventos', 'ServicioDeEventos', 'EventarcGcp', [],
  'return new EventarcGcp(cred, proyecto);',
  [dict(n='recibir', v='POST', p='/iam', args=[('java.util.Map<String, String>', 'cabeceras', 'b')], ret='ReceptorDeEventos.Decision', call='s.recibir(cabeceras)', cpu=True),
   dict(n='auditar', v='GET', p='/disparadores', args=[], ret='java.util.List<EventarcGcp.Hallazgo>', call='s.auditar()')],
  [('Recibir eventos', 'La SA del disparador con `roles/run.invoker` sobre el destino'),
   ('Auditar disparadores', '`roles/eventarc.viewer` en el proyecto')],
  ['No dependas de entrega única: deduplica.',
   'No respondas 500 a eventos inválidos: los reintentos no los arreglan.',
   'No registres el cuerpo completo de Audit Logs (puede traer datos sensibles).',
   'En producción guarda los `vistos` en un almacén compartido con caducidad, no en memoria.'])
