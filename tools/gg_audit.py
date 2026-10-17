import ggen
FIL = '''
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Arma filtros del lenguaje de consultas de Logging para auditoría, escapando valores. Puro.
 */
public final class FiltroDeAuditoria {

    public enum Tipo { ACTIVIDAD, ACCESO_A_DATOS, SISTEMA, POLITICA }

    private FiltroDeAuditoria() {
    }

    public static String de(String proyecto, Tipo tipo, String metodo, String principal, Instant desde) {
        String log = switch (tipo) {
            case ACTIVIDAD -> "activity";
            case ACCESO_A_DATOS -> "data_access";
            case SISTEMA -> "system_event";
            case POLITICA -> "policy";
        };
        var partes = new ArrayList<String>(List.of(
            "logName=\\"projects/" + proyecto + "/logs/cloudaudit.googleapis.com%2F" + log + "\\""));
        if (metodo != null && !metodo.isBlank()) {
            partes.add("protoPayload.methodName:\\"" + escapar(metodo) + "\\"");
        }
        if (principal != null && !principal.isBlank()) {
            partes.add("protoPayload.authenticationInfo.principalEmail=\\"" + escapar(principal) + "\\"");
        }
        if (desde != null) {
            partes.add("timestamp>=\\"" + desde + "\\"");
        }
        return String.join(" AND ", partes);
    }

    static String escapar(String v) {
        return v.replace("\\\\", "\\\\\\\\").replace("\\"", "\\\\\\"");
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.audit.AuditLog;
import com.google.cloud.logging.Logging;
import com.google.cloud.logging.LoggingOptions;
import com.google.cloud.logging.Payload;
import com.google.protobuf.InvalidProtocolBufferException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee entradas de auditoría y extrae quién, qué y sobre qué recurso. */
public class AuditoriaGcp implements AutoCloseable {

    public record Evento(Instant momento, String principal, String servicio, String metodo, String recurso) { }

    private final Logging logging;
    private final String proyecto;

    public AuditoriaGcp(GoogleCredentials cred, String proyecto) {
        this.proyecto = proyecto;
        this.logging = LoggingOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
    }

    public List<Evento> buscar(String filtro, int maximo) {
        var out = new ArrayList<Evento>();
        var pagina = logging.listLogEntries(Logging.EntryListOption.filter(filtro),
            Logging.EntryListOption.sortOrder(Logging.SortingField.TIMESTAMP, Logging.SortingOrder.DESCENDING),
            Logging.EntryListOption.pageSize(Math.min(maximo, 100)));
        for (var e : pagina.iterateAll()) {
            if (out.size() >= maximo) {
                break;
            }
            if (e.getPayload() instanceof Payload.ProtoPayload p) {
                try {
                    var a = p.getData().unpack(AuditLog.class);
                    out.add(new Evento(Instant.ofEpochMilli(e.getTimestamp()), a.getAuthenticationInfo().getPrincipalEmail(),
                        a.getServiceName(), a.getMethodName(), a.getResourceName()));
                } catch (InvalidProtocolBufferException ex) {
                    // entrada que no es AuditLog: se omite
                }
            }
        }
        return out;
    }

    public String proyecto() {
        return proyecto;
    }

    @Override
    public void close() {
        try {
            logging.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
'''
SERV = '''
import java.time.Duration;
import java.time.Instant;
import java.util.List;

public class ServicioDeAuditoria {

    private final AuditoriaGcp gcp;
    private final String proyecto;

    public ServicioDeAuditoria(AuditoriaGcp gcp) {
        this.gcp = gcp;
        this.proyecto = gcp.proyecto();
    }

    /** Cambios de IAM de las últimas N horas. */
    public List<AuditoriaGcp.Evento> cambiosIam(int horas) {
        var f = FiltroDeAuditoria.de(proyecto, FiltroDeAuditoria.Tipo.ACTIVIDAD, "SetIamPolicy", null,
            Instant.now().minus(Duration.ofHours(horas)));
        return gcp.buscar(f, 50);
    }

    public String filtro(String metodo, String principal) {
        return FiltroDeAuditoria.de(proyecto, FiltroDeAuditoria.Tipo.ACCESO_A_DATOS, metodo, principal, null);
    }
}
'''
ggen.gcp('gcp/09-gobierno/audit-logs', 'Gobierno · Cloud Audit Logs',
  'Dos piezas: un **constructor puro de filtros** del lenguaje de Logging para los cuatro tipos de auditoría (con escape de valores, para no inyectar condiciones), y un adaptador que lee entradas con `Logging.listLogEntries` y **desempaqueta el `AuditLog`** del `protoPayload` para devolver quién, qué método y sobre qué recurso. Ideal para un panel de investigación interno.',
  [],
  [('Filtros (lógica pura)', FIL, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Auditoria', '/gobierno/auditoria', 'ServicioDeAuditoria', 'AuditoriaGcp', [],
  'return new AuditoriaGcp(cred, proyecto);',
  [dict(n='cambiosIam', v='GET', p='/iam', args=[('int', 'horas', 'q')], ret='java.util.List<AuditoriaGcp.Evento>', call='s.cambiosIam(horas)'),
   dict(n='filtro', v='GET', p='/filtro', args=[('String', 'metodo', 'q'), ('String', 'principal', 'q')], ret='String', call='s.filtro(metodo, principal)', cpu=True)],
  [('Leer Admin Activity', '`roles/logging.viewer`'),
   ('Leer Data Access', '`roles/logging.privateLogViewer`')],
  ['No concatenes valores del usuario en el filtro sin escapar.',
   'No expongas el panel fuera del equipo de seguridad.',
   'No pidas páginas enormes: acota por tiempo y método.',
   'No copies entradas de Data Access a sistemas sin control de acceso.'])
