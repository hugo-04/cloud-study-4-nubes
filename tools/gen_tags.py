import genlib
VAL = '''
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Revisa etiquetas obligatorias y profundidad de la jerarquía. Puro. */
public class ValidadorDeGobierno {

    public record Compartimento(String id, String nombre, String padreId, Map<String, Map<String, Object>> etiquetas) { }

    public record Hallazgo(String compartimento, String regla, String detalle) { }

    private final Map<String, Set<String>> obligatorias; // "Gobierno.centro_costo" -> valores válidos
    private final int profundidadMaxima;

    public ValidadorDeGobierno(Map<String, Set<String>> obligatorias, int profundidadMaxima) {
        this.obligatorias = Map.copyOf(obligatorias);
        this.profundidadMaxima = profundidadMaxima;
    }

    public List<Hallazgo> revisar(String raizId, List<Compartimento> todos) {
        var porId = new HashMap<String, Compartimento>();
        todos.forEach(c -> porId.put(c.id(), c));
        var out = new ArrayList<Hallazgo>();
        for (var c : todos) {
            int nivel = 1;
            for (String p = c.padreId(); p != null && !p.equals(raizId) && porId.containsKey(p); p = porId.get(p).padreId()) {
                nivel++;
            }
            if (nivel > profundidadMaxima) {
                out.add(new Hallazgo(c.nombre(), "profundidad", "nivel " + nivel + " > " + profundidadMaxima));
            }
            for (var regla : obligatorias.entrySet()) {
                String[] p = regla.getKey().split("\\\\.", 2);
                Object valor = c.etiquetas().getOrDefault(p[0], Map.of()).get(p[1]);
                if (valor == null) {
                    out.add(new Hallazgo(c.nombre(), "etiqueta", "falta " + regla.getKey()));
                } else if (!regla.getValue().isEmpty() && !regla.getValue().contains(valor.toString())) {
                    out.add(new Hallazgo(c.nombre(), "etiqueta", regla.getKey() + "='" + valor + "' no es válido"));
                }
            }
        }
        return out;
    }
}
'''
SDK = '''
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.Compartment;
import com.oracle.bmc.identity.requests.ListCompartmentsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: todo el árbol de compartimentos activos con sus etiquetas definidas (paginando). */
public class CompartimentosOci implements AutoCloseable {

    private final IdentityClient cliente;

    public CompartimentosOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public List<ValidadorDeGobierno.Compartimento> arbol(String raizId) {
        var out = new ArrayList<ValidadorDeGobierno.Compartimento>();
        String pagina = null;
        do {
            var r = cliente.listCompartments(ListCompartmentsRequest.builder().compartmentId(raizId)
                .compartmentIdInSubtree(true).accessLevel(ListCompartmentsRequest.AccessLevel.Accessible)
                .lifecycleState(Compartment.LifecycleState.Active).page(pagina).build());
            r.getItems().forEach(c -> out.add(new ValidadorDeGobierno.Compartimento(
                c.getId(), c.getName(), c.getCompartmentId(), c.getDefinedTags())));
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
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ServicioDeGobierno {

    private final CompartimentosOci compartimentos;
    private final ValidadorDeGobierno validador = new ValidadorDeGobierno(Map.of(
        "Gobierno.centro_costo", Set.of("tienda", "pagos", "logistica", "plataforma"),
        "Gobierno.entorno", Set.of("prod", "no-prod")), 3);

    public ServicioDeGobierno(CompartimentosOci compartimentos) {
        this.compartimentos = compartimentos;
    }

    public List<ValidadorDeGobierno.Hallazgo> revisar(String raizId) {
        return validador.revisar(raizId, compartimentos.arbol(raizId));
    }
}
'''
genlib.oci('oci/09-gobierno/compartimentos-etiquetas', 'Gobierno · Compartimentos, etiquetas y cuotas',
  'Un **revisor de gobierno**: recorre todo el árbol de compartimentos con `IdentityClient.listCompartments` (subárbol, paginando) y marca los que superan la profundidad acordada o no tienen las etiquetas definidas obligatorias con valores válidos. Sirve como control nocturno o paso de un pipeline.',
  [],
  [('Validador (lógica pura)', VAL, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Gobierno', '/gobierno/compartimentos', 'ServicioDeGobierno', 'CompartimentosOci',
  ['import com.oracle.bmc.identity.IdentityClient;', 'import java.util.List;'],
  'return new CompartimentosOci(IdentityClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='revisar', v='GET', p='/revision', args=[('String', 'raiz', 'q')], ret='List<ValidadorDeGobierno.Hallazgo>', call='s.revisar(raiz)')],
  [('Listar compartimentos del árbol', '`Allow dynamic-group auditoria to inspect compartments in tenancy`'),
   ('Leer las etiquetas definidas', '`Allow dynamic-group auditoria to read tag-namespaces in tenancy`')],
  ['No olvides paginar: un árbol grande no cabe en una página.',
   'No uses etiquetas libres para reglas de gobierno: no se validan.',
   'No corras auditorías con una identidad que pueda modificar (solo `inspect`/`read`).',
   'No guardes datos sensibles en etiquetas.'])
