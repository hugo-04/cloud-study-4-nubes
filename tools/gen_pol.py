import sys; sys.path.insert(0, '/tmp/claude-0/-home-claude/91a1f301-d8cc-52b1-b5f2-6ef32b63def7/scratchpad')
import jdoc
HALL = '''
import java.util.List;

public record Hallazgo(String severidad, String frase, String motivo) {

    public static final String ALTA = "ALTA";
    public static final String MEDIA = "MEDIA";
    public static final String ERROR = "ERROR";

    public static List<String> orden() {
        return List.of(ERROR, ALTA, MEDIA);
    }
}
'''
LINTER = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

/** Revisa frases de políticas OCI sin llamar a la red. */
public final class LinterDePoliticas {

    private static final Pattern FRASE = Pattern.compile(
        "^allow\\\\s+(any-user|(?:group|dynamic-group|service)\\\\s+.+?)\\\\s+to\\\\s+(inspect|read|use|manage)\\\\s+(\\\\S+)\\\\s+in\\\\s+(tenancy|compartment\\\\s+(?:id\\\\s+)?\\\\S+)(?:\\\\s+where\\\\s+(.+))?$",
        Pattern.CASE_INSENSITIVE);

    public List<Hallazgo> revisar(List<String> frases) {
        var salida = new ArrayList<Hallazgo>();
        for (String frase : frases) {
            String f = frase == null ? "" : frase.strip();
            var m = FRASE.matcher(f);
            if (!m.matches()) {
                salida.add(new Hallazgo(Hallazgo.ERROR, f, "no sigue la forma «Allow <quién> to <verbo> <recurso> in <dónde>»"));
                continue;
            }
            String quien = m.group(1).toLowerCase(Locale.ROOT);
            String verbo = m.group(2).toLowerCase(Locale.ROOT);
            String recurso = m.group(3).toLowerCase(Locale.ROOT);
            boolean tenancy = m.group(4).equalsIgnoreCase("tenancy");
            boolean condicion = m.group(5) != null && !m.group(5).isBlank();
            boolean manage = verbo.equals("manage");
            boolean todo = recurso.equals("all-resources");
            if (quien.equals("any-user") && !condicion) {
                salida.add(new Hallazgo(Hallazgo.ALTA, f, "any-user sin condición abre el recurso a cualquier principal"));
            }
            if (manage && todo && tenancy) {
                salida.add(new Hallazgo(Hallazgo.ALTA, f, "manage all-resources en todo el tenancy es el poder del administrador"));
            } else if (manage && todo) {
                salida.add(new Hallazgo(Hallazgo.MEDIA, f, "manage all-resources: ¿basta con una familia de recursos o con use/read?"));
            } else if (manage && tenancy) {
                salida.add(new Hallazgo(Hallazgo.MEDIA, f, "manage en todo el tenancy: acota a un compartimento"));
            }
        }
        return salida;
    }
}
'''
SDK = '''
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.Policy;
import com.oracle.bmc.identity.requests.ListPoliciesRequest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Lee las políticas de un compartimento con paginación del SDK. */
public class PoliticasOci {

    private final IdentityClient cliente;

    public PoliticasOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public Map<String, List<String>> frasesPorPolitica(String compartimentoId) {
        var req = ListPoliciesRequest.builder().compartmentId(compartimentoId).build();
        var salida = new LinkedHashMap<String, List<String>>();
        for (Policy p : cliente.getPaginators().listPoliciesRecordIterator(req)) {
            salida.put(p.getName(), new ArrayList<>(p.getStatements()));
        }
        return salida;
    }
}
'''
SERV = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class ServicioDePoliticas {

    private final LinterDePoliticas linter;
    private final PoliticasOci politicas;

    public ServicioDePoliticas(LinterDePoliticas linter, PoliticasOci politicas) {
        this.linter = linter;
        this.politicas = politicas;
    }

    public record HallazgoDePolitica(String politica, Hallazgo hallazgo) { }

    public List<HallazgoDePolitica> auditar(String compartimentoId) {
        var salida = new ArrayList<HallazgoDePolitica>();
        for (Map.Entry<String, List<String>> e : politicas.frasesPorPolitica(compartimentoId).entrySet()) {
            for (Hallazgo h : linter.revisar(e.getValue())) {
                salida.add(new HallazgoDePolitica(e.getKey(), h));
            }
        }
        return salida;
    }

    public List<Hallazgo> revisar(List<String> frases) {
        return linter.revisar(frases);
    }
}
'''
sec = dict(
  ns='Politicas', ruta='/iam/politicas', servicio='ServicioDePoliticas',
  spring_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.identity.IdentityClient;', 'import org.springframework.beans.factory.annotation.Value;', 'import java.util.List;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    IdentityClient identidadCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDePoliticas servicioDePoliticas(IdentityClient cliente) {
        return new ServicioDePoliticas(new LinterDePoliticas(), new PoliticasOci(cliente));
    }
''',
  q_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.identity.IdentityClient;', 'import java.util.List;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region')],
  q_producer='''    ServicioDePoliticas servicioDePoliticas() {
        var cliente = IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDePoliticas(new LinterDePoliticas(), new PoliticasOci(cliente));
    }''',
  endpoints=[
    dict(n='auditoria', v='GET', p='/auditoria', args=[('String', 'compartimento', 'q')], ret='List<ServicioDePoliticas.HallazgoDePolitica>', call='s.auditar(compartimento)'),
    dict(n='revisar', v='POST', p='/revisar', args=[('List<String>', 'frases', 'b')], ret='List<Hallazgo>', call='s.revisar(frases)', cpu=True),
  ])
jdoc.doc('/home/claude/cloud-study-4-nubes/oci/02-iam/politicas-compartimentos/uso-en-java.md',
  'IAM · Compartimentos, grupos y políticas',
  'Dos herramientas: un **linter de frases** (puro, sin red: detecta `any-user` sin condición y `manage all-resources`) y un **auditor** que lee las políticas reales de un compartimento con el SDK y las pasa por el linter.',
  'oci:\n  auth: instance\n  region: sa-saopaulo-1',
  'oci.auth=instance\noci.region=sa-saopaulo-1',
  [('Hallazgo', HALL, True), ('El linter de frases', LINTER, True), ('Lectura de políticas con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('`ListPolicies`', '`Allow dynamic-group auditor-iam to inspect policies in tenancy` *(verifica si necesitas `read policies` para ver las frases)*'),
   ('El linter', 'Ninguna: no llama a la red')],
  ['No apliques políticas desde la aplicación: el auditor **lee y avisa**; los cambios van por Terraform y revisión.',
   'No trates el linter como prueba de seguridad: detecta patrones conocidos, no entiende tu negocio.',
   'No registres frases con datos de clientes en etiquetas ni condiciones.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
