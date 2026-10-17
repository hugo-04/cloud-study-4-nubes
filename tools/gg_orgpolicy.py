import ggen
LB = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Compara la política efectiva de cada restricción con la línea base esperada. Puro: recibe un resumen
 * por restricción (enforce / denyAll / valores permitidos) ya extraído del API.
 */
public final class LineaBase {

    public record Efectiva(boolean enforce, boolean denyAll, boolean allowAll, List<String> permitidos) { }

    public record Esperada(String tipo, List<String> permitidos) {
        public static Esperada aplicada() {
            return new Esperada("enforce", List.of());
        }

        public static Esperada denegarTodo() {
            return new Esperada("denyAll", List.of());
        }

        public static Esperada soloValores(List<String> v) {
            return new Esperada("valores", v);
        }
    }

    public record Brecha(String restriccion, String detalle) { }

    private LineaBase() {
    }

    public static List<Brecha> comparar(Map<String, Esperada> base, Map<String, Efectiva> efectivas) {
        var out = new ArrayList<Brecha>();
        base.forEach((c, esp) -> {
            var ef = efectivas.get(c);
            if (ef == null) {
                out.add(new Brecha(c, "sin política efectiva (valor por defecto de Google)"));
                return;
            }
            switch (esp.tipo()) {
                case "enforce" -> {
                    if (!ef.enforce()) {
                        out.add(new Brecha(c, "no está aplicada"));
                    }
                }
                case "denyAll" -> {
                    if (!ef.denyAll()) {
                        out.add(new Brecha(c, ef.allowAll() ? "permite todo" : "no deniega todo"));
                    }
                }
                default -> {
                    if (ef.allowAll()) {
                        out.add(new Brecha(c, "permite todo"));
                    } else {
                        var extra = ef.permitidos().stream().filter(v -> !esp.permitidos().contains(v)).toList();
                        if (!extra.isEmpty() || ef.permitidos().isEmpty()) {
                            out.add(new Brecha(c, "valores fuera de la base: " + extra));
                        }
                    }
                }
            }
        });
        return out;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.api.gax.rpc.NotFoundException;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.orgpolicy.v2.OrgPolicyClient;
import com.google.cloud.orgpolicy.v2.OrgPolicySettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/** Adaptador: lee la política efectiva de cada restricción en un proyecto y la resume. */
public class OrgPolicyGcp implements AutoCloseable {

    private final OrgPolicyClient cliente;

    public OrgPolicyGcp(GoogleCredentials cred) {
        try {
            this.cliente = OrgPolicyClient.create(OrgPolicySettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Map<String, LineaBase.Efectiva> efectivas(String proyecto, Set<String> restricciones) {
        var out = new HashMap<String, LineaBase.Efectiva>();
        for (String c : restricciones) {
            try {
                var pol = cliente.getEffectivePolicy("projects/" + proyecto + "/policies/" + c);
                boolean enforce = false;
                boolean deny = false;
                boolean allow = false;
                var permitidos = new ArrayList<String>();
                // Ojo: reglas con condición (tags) se resumen como si aplicaran siempre; revísalas aparte
                for (var r : pol.getSpec().getRulesList()) {
                    enforce |= r.getEnforce();
                    deny |= r.getDenyAll();
                    allow |= r.getAllowAll();
                    if (r.hasValues()) {
                        permitidos.addAll(r.getValues().getAllowedValuesList());
                    }
                }
                out.put(c, new LineaBase.Efectiva(enforce, deny, allow, permitidos));
            } catch (NotFoundException e) {
                // sin política: queda fuera del mapa
            }
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

public class ServicioDeLineaBase {

    private static final Map<String, LineaBase.Esperada> BASE = Map.of(
        "sql.restrictPublicIp", LineaBase.Esperada.aplicada(),
        "iam.disableServiceAccountKeyCreation", LineaBase.Esperada.aplicada(),
        "storage.publicAccessPrevention", LineaBase.Esperada.aplicada(),
        "compute.vmExternalIpAccess", LineaBase.Esperada.denegarTodo(),
        "gcp.resourceLocations", LineaBase.Esperada.soloValores(List.of("in:southamerica-locations")));

    private final OrgPolicyGcp gcp;

    public ServicioDeLineaBase(OrgPolicyGcp gcp) {
        this.gcp = gcp;
    }

    public List<LineaBase.Brecha> revisar(String proyecto) {
        return LineaBase.comparar(BASE, gcp.efectivas(proyecto, BASE.keySet()));
    }
}
'''
ggen.gcp('gcp/09-gobierno/org-policy', 'Gobierno · Organization Policy',
  'Dos piezas: una **comparación pura** entre la línea base que quieres (aplicada, denegar todo o solo ciertos valores) y lo que realmente aplica; y un adaptador que pide la **política efectiva** de cada restricción en un proyecto con `OrgPolicyClient.getEffectivePolicy` (ya resuelta la herencia) y la resume. Útil como control continuo o como paso del pipeline de alta de proyectos.',
  [],
  [('Línea base (lógica pura)', LB, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'LineaBase', '/gobierno/politicas', 'ServicioDeLineaBase', 'OrgPolicyGcp', [],
  'return new OrgPolicyGcp(cred);',
  [dict(n='revisar', v='GET', p='/{proyecto}', args=[('String', 'proyecto', 'p')], ret='java.util.List<LineaBase.Brecha>', call='s.revisar(proyecto)')],
  [('Leer políticas efectivas', '`roles/orgpolicy.policyViewer` (en la organización o carpeta)')],
  ['No uses esta revisión como sustituto de aplicar las políticas: solo detecta brechas.',
   'No des `policyAdmin` a la cuenta de auditoría.',
   'No ignores las reglas con condición: revísalas por separado.',
   'No apliques cambios de política desde la app: hazlo por código revisado.'])
