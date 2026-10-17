import sys; sys.path.insert(0, '/tmp/claude-0/-home-claude/91a1f301-d8cc-52b1-b5f2-6ef32b63def7/scratchpad')
import jdoc
REGLA = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Regla de coincidencia de un grupo dinámico: ALL { a = 'x', b != 'y' } o ANY { ... }. */
public final class ReglaDinamica {

    public record Condicion(String atributo, boolean igual, String valor) { }

    private final boolean todas;
    private final List<Condicion> condiciones;

    private ReglaDinamica(boolean todas, List<Condicion> condiciones) {
        this.todas = todas;
        this.condiciones = condiciones;
    }

    public static ReglaDinamica analizar(String texto) {
        String t = texto.strip();
        boolean todas;
        if (t.regionMatches(true, 0, "ALL", 0, 3)) {
            todas = true;
        } else if (t.regionMatches(true, 0, "ANY", 0, 3)) {
            todas = false;
        } else {
            throw new IllegalArgumentException("la regla debe empezar con ALL o ANY");
        }
        int abre = t.indexOf('{');
        int cierra = t.lastIndexOf('}');
        if (abre < 0 || cierra < abre) {
            throw new IllegalArgumentException("faltan las llaves { }");
        }
        var lista = new ArrayList<Condicion>();
        for (String trozo : separar(t.substring(abre + 1, cierra))) {
            lista.add(condicion(trozo.strip()));
        }
        if (lista.isEmpty()) {
            throw new IllegalArgumentException("la regla no tiene condiciones");
        }
        return new ReglaDinamica(todas, List.copyOf(lista));
    }

    /** Separa por comas que no estén dentro de comillas simples. */
    private static List<String> separar(String cuerpo) {
        var trozos = new ArrayList<String>();
        var actual = new StringBuilder();
        boolean dentro = false;
        for (char c : cuerpo.toCharArray()) {
            if (c == '\\'') {
                dentro = !dentro;
            }
            if (c == ',' && !dentro) {
                trozos.add(actual.toString());
                actual.setLength(0);
            } else {
                actual.append(c);
            }
        }
        if (!actual.toString().isBlank()) {
            trozos.add(actual.toString());
        }
        return trozos;
    }

    private static Condicion condicion(String c) {
        boolean igual = !c.contains("!=");
        String[] partes = c.split(igual ? "=" : "!=", 2);
        if (partes.length != 2) {
            throw new IllegalArgumentException("condición inválida: " + c);
        }
        String valor = partes[1].strip();
        if (valor.length() < 2 || !valor.startsWith("'") || !valor.endsWith("'")) {
            throw new IllegalArgumentException("el valor debe ir entre comillas simples: " + c);
        }
        return new Condicion(partes[0].strip(), igual, valor.substring(1, valor.length() - 1));
    }

    public List<Condicion> condiciones() {
        return condiciones;
    }

    public boolean esTodas() {
        return todas;
    }

    /** ¿Un recurso con estos atributos pertenece al grupo? */
    public boolean coincide(Map<String, String> atributos) {
        for (Condicion c : condiciones) {
            boolean cumple = c.igual() == c.valor().equals(atributos.get(c.atributo()));
            if (todas && !cumple) {
                return false;
            }
            if (!todas && cumple) {
                return true;
            }
        }
        return todas;
    }
}
'''
VAL = '''
import java.util.ArrayList;
import java.util.List;

/** Reglas de seguridad para reglas de grupos dinámicos. */
public final class ValidadorDeReglas {

    public List<String> advertencias(ReglaDinamica regla) {
        var salida = new ArrayList<String>();
        boolean acotaCompartimento = regla.condiciones().stream()
            .anyMatch(c -> c.igual() && (c.atributo().endsWith("compartment.id")));
        boolean soloNegaciones = regla.condiciones().stream().allMatch(c -> !c.igual());
        if (!regla.esTodas()) {
            salida.add("ANY: cada condición ensancha el grupo; ¿de verdad necesitas «o»?");
        }
        if (!acotaCompartimento) {
            salida.add("no acota por compartimento: puede incluir recursos de otros equipos");
        }
        if (soloNegaciones) {
            salida.add("solo tiene negaciones: incluye todo lo demás");
        }
        boolean usaEtiquetas = regla.condiciones().stream().anyMatch(c -> c.atributo().startsWith("tag."));
        if (usaEtiquetas) {
            salida.add("depende de etiquetas: restringe quién puede etiquetar recursos");
        }
        return salida;
    }
}
'''
SDK = '''
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.DynamicGroup;
import com.oracle.bmc.identity.requests.ListDynamicGroupsRequest;
import java.util.LinkedHashMap;
import java.util.Map;

/** Lee los grupos dinámicos del tenancy con paginación del SDK. */
public class GruposDinamicosOci {

    private final IdentityClient cliente;

    public GruposDinamicosOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public Map<String, String> reglasPorGrupo(String tenancyId) {
        var req = ListDynamicGroupsRequest.builder().compartmentId(tenancyId).build();
        var salida = new LinkedHashMap<String, String>();
        for (DynamicGroup g : cliente.getPaginators().listDynamicGroupsRecordIterator(req)) {
            salida.put(g.getName(), g.getMatchingRule());
        }
        return salida;
    }
}
'''
SERV = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class ServicioDeGrupos {

    private final GruposDinamicosOci grupos;
    private final ValidadorDeReglas validador = new ValidadorDeReglas();

    public ServicioDeGrupos(GruposDinamicosOci grupos) {
        this.grupos = grupos;
    }

    public record Revision(String grupo, List<String> advertencias) { }

    public List<Revision> auditar(String tenancyId) {
        var salida = new ArrayList<Revision>();
        for (Map.Entry<String, String> e : grupos.reglasPorGrupo(tenancyId).entrySet()) {
            try {
                var adv = validador.advertencias(ReglaDinamica.analizar(e.getValue()));
                if (!adv.isEmpty()) {
                    salida.add(new Revision(e.getKey(), adv));
                }
            } catch (IllegalArgumentException ex) {
                salida.add(new Revision(e.getKey(), List.of("regla ilegible: " + ex.getMessage())));
            }
        }
        return salida;
    }

    public List<String> revisarRegla(String regla) {
        return validador.advertencias(ReglaDinamica.analizar(regla));
    }

    public boolean pertenece(String regla, Map<String, String> atributos) {
        return ReglaDinamica.analizar(regla).coincide(atributos);
    }
}
'''
sec = dict(
  ns='Grupos', ruta='/iam/grupos-dinamicos', servicio='ServicioDeGrupos',
  spring_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.identity.IdentityClient;', 'import org.springframework.beans.factory.annotation.Value;', 'import java.util.List;', 'import java.util.Map;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    IdentityClient identidadCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDeGrupos servicioDeGrupos(IdentityClient cliente) {
        return new ServicioDeGrupos(new GruposDinamicosOci(cliente));
    }
''',
  q_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.identity.IdentityClient;', 'import java.util.List;', 'import java.util.Map;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region')],
  q_producer='''    ServicioDeGrupos servicioDeGrupos() {
        var cliente = IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDeGrupos(new GruposDinamicosOci(cliente));
    }''',
  endpoints=[
    dict(n='auditoria', v='GET', p='/auditoria', args=[('String', 'tenancy', 'q')], ret='List<ServicioDeGrupos.Revision>', call='s.auditar(tenancy)'),
    dict(n='revisar', v='GET', p='/revisar', args=[('String', 'regla', 'q')], ret='List<String>', call='s.revisarRegla(regla)', cpu=True),
  ])
jdoc.doc('/home/claude/cloud-study-4-nubes/oci/02-iam/dynamic-groups-principals/uso-en-java.md',
  'IAM · Grupos dinámicos y principales',
  'Tres piezas: un **analizador de reglas** (`ALL`/`ANY`, con prueba de pertenencia sin red), un **validador** que avisa de reglas peligrosas y un **auditor** que lee los grupos reales con el SDK. La autenticación de la propia aplicación (sección 2.1) es el uso de los principales.',
  'oci:\n  auth: instance   # config | instance | oke | resource\n  region: sa-saopaulo-1',
  'oci.auth=instance\noci.region=sa-saopaulo-1',
  [('Regla de coincidencia', REGLA, True), ('Validador de reglas', VAL, True), ('Lectura con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('`ListDynamicGroups`', '`Allow dynamic-group auditor-iam to inspect dynamic-groups in tenancy`'),
   ('Analizar y validar reglas', 'Ninguna: es lógica pura')],
  ['No uses `config` (archivo de usuario) en servidores: usa `instance`, `resource` u `oke`.',
   'No trates «pertenece» como prueba de permisos: además hace falta una política.',
   'No pongas OCID ni etiquetas de clientes en registros.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
