import genlib
AGR = '''
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;
import java.util.regex.Pattern;

/** Ventanas fijas por hora del evento con marca de agua. Puro (no es seguro entre hilos: un agregador por partición). */
public class AgregadorDeVentanas {

    public record Click(String tipo, String sku, Instant ts) {
        private static final Pattern P = Pattern.compile("\\"(tipo|sku|ts)\\"\\\\s*:\\\\s*\\"([^\\"]{1,64})\\"");

        /** Lector mínimo del JSON del evento; descarta lo que no cumple. */
        public static Optional<Click> leer(String json) {
            Map<String, String> c = new TreeMap<>();
            var m = P.matcher(json);
            while (m.find()) {
                c.put(m.group(1), m.group(2));
            }
            try {
                return c.size() == 3 ? Optional.of(new Click(c.get("tipo"), c.get("sku"), Instant.parse(c.get("ts")))) : Optional.empty();
            } catch (RuntimeException e) {
                return Optional.empty();
            }
        }
    }

    public record Ventana(Instant inicio, Map<String, Integer> vistasPorSku) { }

    private final Duration tamano;
    private final Duration retraso;
    private final TreeMap<Instant, Map<String, Integer>> abiertas = new TreeMap<>();
    private Instant maxVisto = Instant.EPOCH;
    private long tardios;

    public AgregadorDeVentanas(Duration tamano, Duration retraso) {
        this.tamano = tamano;
        this.retraso = retraso;
    }

    public void registrar(Click c) {
        if (!"vista".equals(c.tipo())) {
            return;
        }
        Instant inicio = Instant.ofEpochMilli(c.ts().toEpochMilli() - Math.floorMod(c.ts().toEpochMilli(), tamano.toMillis()));
        if (inicio.plus(tamano).isBefore(marcaDeAgua())) {
            tardios++;
            return;
        }
        abiertas.computeIfAbsent(inicio, k -> new TreeMap<>()).merge(c.sku(), 1, Integer::sum);
        if (c.ts().isAfter(maxVisto)) {
            maxVisto = c.ts();
        }
    }

    public Instant marcaDeAgua() {
        return maxVisto.minus(retraso);
    }

    /** Devuelve y retira las ventanas cuyo fin quedó detrás de la marca de agua. */
    public List<Ventana> cerrar() {
        var out = new ArrayList<Ventana>();
        while (!abiertas.isEmpty() && !abiertas.firstKey().plus(tamano).isAfter(marcaDeAgua())) {
            var e = abiertas.pollFirstEntry();
            out.add(new Ventana(e.getKey(), Map.copyOf(e.getValue())));
        }
        return out;
    }

    public long tardios() {
        return tardios;
    }
}
'''
SDK = '''
import com.oracle.bmc.streaming.StreamClient;
import com.oracle.bmc.streaming.model.CreateGroupCursorDetails;
import com.oracle.bmc.streaming.requests.CreateGroupCursorRequest;
import com.oracle.bmc.streaming.requests.GetMessagesRequest;
import java.nio.charset.StandardCharsets;
import java.util.List;

/** Adaptador del SDK: lector de grupo de consumidores (sin commit automático). */
public class LectorDeGrupo implements AutoCloseable {

    private final StreamClient cliente;
    private final String streamId;
    private String cursor;

    public LectorDeGrupo(StreamClient cliente, String streamId, String grupo, String instancia) {
        this.cliente = cliente;
        this.streamId = streamId;
        this.cursor = cliente.createGroupCursor(CreateGroupCursorRequest.builder().streamId(streamId)
            .createGroupCursorDetails(CreateGroupCursorDetails.builder()
                .groupName(grupo).instanceName(instancia)
                .type(CreateGroupCursorDetails.Type.TrimHorizon).commitOnGet(false).build())
            .build()).getCursor().getValue();
    }

    /** Lee un lote y avanza el cursor; el commit se hace aparte, tras escribir el resultado. */
    public List<String> leer(int max) {
        var r = cliente.getMessages(GetMessagesRequest.builder().streamId(streamId).cursor(cursor).limit(max).build());
        cursor = r.getOpcNextCursor();
        return r.getItems().stream().map(m -> new String(m.getValue(), StandardCharsets.UTF_8)).toList();
    }

    public String cursorActual() {
        return cursor;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Duration;
import java.util.List;

public class ServicioDeClickstream {

    public record Ciclo(int leidos, List<AgregadorDeVentanas.Ventana> cerradas, long tardios) { }

    private final LectorDeGrupo lector;
    private final AgregadorDeVentanas agregador = new AgregadorDeVentanas(Duration.ofMinutes(1), Duration.ofSeconds(30));

    public ServicioDeClickstream(LectorDeGrupo lector) {
        this.lector = lector;
    }

    /** Un ciclo del consumidor del tablero; en producción corre en un bucle por instancia. */
    public synchronized Ciclo ciclo() {
        var mensajes = lector.leer(500);
        mensajes.forEach(json -> AgregadorDeVentanas.Click.leer(json).ifPresent(agregador::registrar));
        var cerradas = agregador.cerrar();
        // aquí: escribir el top por ventana en OCI Cache y luego hacer commit del cursor del grupo
        return new Ciclo(mensajes.size(), cerradas, agregador.tardios());
    }
}
'''
genlib.oci('oci/11-casos-integrados/clickstream', 'Caso integrado · Clickstream',
  'El consumidor del tablero: un **agregador por ventanas fijas de 1 minuto según la hora del evento** con **marca de agua** (máximo visto − 30 s) que cierra ventanas solo cuando ya no se esperan eventos y cuenta los tardíos; y un **lector de grupo** con `StreamClient.createGroupCursor` sin commit automático, para confirmar solo después de escribir el resultado.',
  [('stream.id', 'ocid1.stream.oc1.sa-saopaulo-1.aaaa'), ('stream.endpoint', 'https://cell-1.streaming.sa-saopaulo-1.oci.oraclecloud.com'), ('stream.instancia', 'tablero-1')],
  [('Agregador con marca de agua (lógica pura)', AGR, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Clickstream', '/casos/clickstream', 'ServicioDeClickstream', 'LectorDeGrupo',
  ['import com.oracle.bmc.streaming.StreamClient;'],
  'return new LectorDeGrupo(StreamClient.builder().endpoint(endpoint).build(auth), id, "tablero", instancia);',
  [dict(n='ciclo', v='POST', p='/ciclo', args=[], ret='ServicioDeClickstream.Ciclo', call='s.ciclo()')],
  [('Leer con grupo de consumidores', "`Allow dynamic-group analitica to use stream-pull in compartment tienda-prod where target.stream.id = '<ocid>'`")],
  ['No agregues por hora de llegada.',
   'No compartas un agregador entre hilos sin sincronizar (usa uno por partición o instancia).',
   'No hagas commit antes de escribir el resultado.',
   'No guardes identificadores personales en los eventos.'])
