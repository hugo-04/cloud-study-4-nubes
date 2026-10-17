import genlib
CON = '''
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/** Construye la condición JSON de una regla de Events y la valida antes de enviarla. Puro. */
public class CondicionDeRegla {

    private static final Pattern TIPO = Pattern.compile("com\\\\.oraclecloud\\\\.[a-z0-9]+\\\\.[a-z0-9.]+");
    private static final Pattern VALOR = Pattern.compile("[A-Za-z0-9_.*-]{1,100}");

    private final List<String> tipos = new ArrayList<>();
    private final Map<String, List<String>> data = new LinkedHashMap<>();

    public CondicionDeRegla tipo(String t) {
        if (!TIPO.matcher(t).matches()) {
            throw new IllegalArgumentException("tipo de evento inválido: " + t);
        }
        tipos.add(t);
        return this;
    }

    /** Filtro sobre data (por ejemplo compartmentName o resourceName). Valores de la lista = O. */
    public CondicionDeRegla dato(String campo, List<String> valores) {
        if (!campo.matches("[a-zA-Z]{1,40}") || valores.isEmpty() || valores.stream().anyMatch(v -> !VALOR.matcher(v).matches())) {
            throw new IllegalArgumentException("filtro inválido: " + campo);
        }
        data.put(campo, List.copyOf(valores));
        return this;
    }

    public String json() {
        if (tipos.isEmpty()) {
            throw new IllegalStateException("una regla sin tipos de evento recibiría demasiado");
        }
        var sb = new StringBuilder("{\\"eventType\\":").append(lista(tipos));
        if (!data.isEmpty()) {
            sb.append(",\\"data\\":{");
            int i = 0;
            for (var e : data.entrySet()) {
                sb.append(i++ > 0 ? "," : "").append('"').append(e.getKey()).append("\\":").append(lista(e.getValue()));
            }
            sb.append('}');
        }
        return sb.append('}').toString();
    }

    private static String lista(List<String> v) {
        return v.stream().map(s -> "\\"" + s + "\\"").reduce((a, b) -> a + "," + b).map(s -> "[" + s + "]").orElse("[]");
    }
}
'''
SDK = '''
import com.oracle.bmc.events.EventsClient;
import com.oracle.bmc.events.model.ActionDetailsList;
import com.oracle.bmc.events.model.CreateNotificationServiceActionDetails;
import com.oracle.bmc.events.model.CreateRuleDetails;
import com.oracle.bmc.events.requests.CreateRuleRequest;
import com.oracle.bmc.events.requests.ListRulesRequest;
import java.util.List;
import java.util.UUID;

/** Adaptador del SDK: crea reglas con acción a un tema y lista las existentes. */
public class ReglasOci implements AutoCloseable {

    public record Regla(String id, String nombre, boolean activa, String condicion) { }

    private final EventsClient cliente;
    private final String compartimentoId;

    public ReglasOci(EventsClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public String crear(String nombre, String condicionJson, String temaId) {
        var detalles = CreateRuleDetails.builder()
            .compartmentId(compartimentoId).displayName(nombre).isEnabled(true).condition(condicionJson)
            .actions(ActionDetailsList.builder().actions(List.of(
                CreateNotificationServiceActionDetails.builder().topicId(temaId).isEnabled(true).build())).build())
            .build();
        return cliente.createRule(CreateRuleRequest.builder().createRuleDetails(detalles)
            .opcRetryToken(UUID.nameUUIDFromBytes(nombre.getBytes()).toString()).build()).getRule().getId();
    }

    public List<Regla> listar() {
        return cliente.listRules(ListRulesRequest.builder().compartmentId(compartimentoId).build()).getItems().stream()
            .map(r -> new Regla(r.getId(), r.getDisplayName(), Boolean.TRUE.equals(r.getIsEnabled()), r.getCondition()))
            .toList();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeReglas {

    public record Pedido(String nombre, List<String> tipos, List<String> compartimentos, String temaId) { }

    private final ReglasOci reglas;

    public ServicioDeReglas(ReglasOci reglas) {
        this.reglas = reglas;
    }

    public String crear(Pedido p) {
        var c = new CondicionDeRegla();
        p.tipos().forEach(c::tipo);
        if (p.compartimentos() != null && !p.compartimentos().isEmpty()) {
            c.dato("compartmentName", p.compartimentos());
        }
        return reglas.crear(p.nombre(), c.json(), p.temaId());
    }

    public List<ReglasOci.Regla> listar() {
        return reglas.listar();
    }
}
'''
genlib.oci('oci/07-mensajeria/events', 'Mensajería · Events',
  'Un **constructor de reglas seguro**: la lógica pura arma la condición JSON (tipos validados con el patrón `com.oraclecloud.<servicio>.<acción>`, filtros de `data` sin caracteres raros, prohibido «sin tipos») y el adaptador crea la regla con acción a un tema usando `EventsClient` con `opcRetryToken` derivado del nombre.',
  [('reglas.compartimento', 'ocid1.compartment.oc1..aaaa')],
  [('Condición (lógica pura)', CON, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Reglas', '/mensajeria/reglas', 'ServicioDeReglas', 'ReglasOci',
  ['import com.oracle.bmc.events.EventsClient;', 'import java.util.List;'],
  'return new ReglasOci(EventsClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);',
  [dict(n='crear', v='POST', p='', args=[('ServicioDeReglas.Pedido', 'p', 'b')], ret='String', call='s.crear(p)'),
   dict(n='listar', v='GET', p='', args=[], ret='List<ReglasOci.Regla>', call='s.listar()')],
  [('Crear y listar reglas', '`Allow group plataforma to manage cloudevents-rules in compartment prod`'),
   ('Events publica en el tema', '`Allow service cloudEvents to use ons-topics in compartment prod` *(verifica el nombre del principal de servicio)*')],
  ['No construyas la condición concatenando texto del usuario sin validar.',
   'No crees reglas desde la app en tiempo de ejecución si pueden vivir en Terraform: este ejemplo es para un portal de plataforma.',
   'No hagas acciones destructivas automáticas sin comprobar el evento contra la API.',
   'No olvides que la regla ve solo su compartimento y descendientes.'])
