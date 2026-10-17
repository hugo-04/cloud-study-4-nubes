import ggen
TRI = '''
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/**
 * Triaje: plazo de remediación por severidad, vencidos y orden de atención. Puro.
 */
public final class Triaje {

    public record Hallazgo(String categoria, String severidad, String recurso, Instant detectado) { }

    public record Priorizado(Hallazgo hallazgo, Instant vence, boolean vencido, long horasRestantes) { }

    private static final Map<String, Duration> SLA = Map.of(
        "CRITICAL", Duration.ofHours(24),
        "HIGH", Duration.ofDays(7),
        "MEDIUM", Duration.ofDays(30),
        "LOW", Duration.ofDays(90));

    private Triaje() {
    }

    public static List<Priorizado> priorizar(List<Hallazgo> hallazgos, Instant ahora) {
        return hallazgos.stream().map(h -> {
            var vence = h.detectado().plus(SLA.getOrDefault(h.severidad(), Duration.ofDays(90)));
            long horas = Duration.between(ahora, vence).toHours();
            return new Priorizado(h, vence, vence.isBefore(ahora), horas);
        }).sorted(Comparator.comparing(Priorizado::vence)).toList();
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.securitycenter.v2.ListFindingsRequest;
import com.google.cloud.securitycenter.v2.SecurityCenterClient;
import com.google.cloud.securitycenter.v2.SecurityCenterSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: hallazgos activos, no silenciados, de severidad alta o crítica en la organización. */
public class SccGcp implements AutoCloseable {

    private final SecurityCenterClient cliente;
    private final String organizacion;

    public SccGcp(GoogleCredentials cred, String organizacion) {
        try {
            this.cliente = SecurityCenterClient.create(SecurityCenterSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.organizacion = organizacion;
    }

    public List<Triaje.Hallazgo> activos(int maximo) {
        var req = ListFindingsRequest.newBuilder()
            .setParent("organizations/" + organizacion + "/sources/-/locations/global")
            .setFilter("state=\\"ACTIVE\\" AND mute!=\\"MUTED\\" AND (severity=\\"CRITICAL\\" OR severity=\\"HIGH\\")")
            .setPageSize(Math.min(maximo, 100))
            .build();
        var out = new ArrayList<Triaje.Hallazgo>();
        for (var r : cliente.listFindings(req).iterateAll()) {
            if (out.size() >= maximo) {
                break;
            }
            var f = r.getFinding();
            out.add(new Triaje.Hallazgo(f.getCategory(), f.getSeverity().name(), f.getResourceName(),
                Instant.ofEpochSecond(f.getEventTime().getSeconds())));
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
import java.time.Instant;
import java.util.List;

public class ServicioDeTriaje {

    private final SccGcp scc;

    public ServicioDeTriaje(SccGcp scc) {
        this.scc = scc;
    }

    public List<Triaje.Priorizado> pendientes() {
        return Triaje.priorizar(scc.activos(200), Instant.now());
    }
}
'''
ggen.gcp('gcp/09-gobierno/security-command-center', 'Gobierno · Security Command Center',
  'Dos piezas: un **triaje puro** que asigna un plazo de remediación por severidad (24 h críticos, 7 días altos…), marca vencidos y ordena por vencimiento; y un adaptador que trae los **hallazgos activos y no silenciados** de severidad crítica o alta de toda la organización con `v2.SecurityCenterClient.listFindings` (todas las fuentes con `sources/-`).',
  [('scc.organizacion', '123456789012')],
  [('Triaje (lógica pura)', TRI, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Triaje', '/gobierno/hallazgos', 'ServicioDeTriaje', 'SccGcp', [],
  'return new SccGcp(cred, organizacion);',
  [dict(n='pendientes', v='GET', p='', args=[], ret='java.util.List<Triaje.Priorizado>', call='s.pendientes()')],
  [('Leer hallazgos', '`roles/securitycenter.findingsViewer` en la organización'),
   ('Cambiar estado o mute', '`roles/securitycenter.findingsEditor` (no para este servicio)')],
  ['No muestres descripciones de amenazas a todo el mundo.',
   'No silencies desde la app: el mute es una decisión revisada.',
   'No traigas todas las severidades a la vez.',
   'No uses el triaje como sustituto de prevenir con Org Policy.'])
