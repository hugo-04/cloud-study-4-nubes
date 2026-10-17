import ggen
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
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.serialization.StringDeserializer;

/** Adaptador: consumidor del grupo sin commit automático (se confirma tras escribir el resultado). */
public class LectorDeGrupo implements AutoCloseable {

    private final KafkaConsumer<String, String> consumidor;

    public LectorDeGrupo(String bootstrap, String grupo, String tema) {
        Map<String, Object> p = new java.util.HashMap<>(Map.of(
            "bootstrap.servers", bootstrap,
            "security.protocol", "SASL_SSL",
            "sasl.mechanism", "OAUTHBEARER",
            "sasl.login.callback.handler.class", "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler",
            "sasl.jaas.config", "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;",
            "group.id", grupo,
            "enable.auto.commit", "false",
            "auto.offset.reset", "earliest",
            "max.poll.records", "500"));
        p.put("client.id", grupo + "-" + UUID.randomUUID());
        this.consumidor = new KafkaConsumer<>(p, new StringDeserializer(), new StringDeserializer());
        consumidor.subscribe(List.of(tema));
    }

    /** Devuelve todo el poll (el tope real es max.poll.records): descartar registros y luego confirmar los perdería. */
    public List<String> leer(int max) {
        var out = new ArrayList<String>();
        for (var r : consumidor.poll(Duration.ofMillis(500))) {
            out.add(r.value());
        }
        return out;
    }

    /** Confirma lo leído en el último poll (llamar solo después de escribir el resultado). */
    public void confirmar() {
        consumidor.commitSync();
    }

    @Override
    public void close() {
        consumidor.close();
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
        // aquí: escribir el top por ventana en Memorystore (reemplazo idempotente) y, después, confirmar
        lector.confirmar();
        return new Ciclo(mensajes.size(), cerradas, agregador.tardios());
    }
}
'''
ggen.gcp('gcp/11-casos-integrados/clickstream', 'Caso integrado · Clickstream',
  'El consumidor del tablero: un **agregador por ventanas fijas de 1 minuto según la hora del evento** con **marca de agua** (máximo visto − 30 s) que cierra ventanas solo cuando ya no se esperan eventos y cuenta los tardíos; y un **lector de grupo** de Managed Kafka con `KafkaConsumer` (OAUTHBEARER) **sin commit automático**, para confirmar con `commitSync` solo después de escribir el resultado. El tamaño del lote lo fija `max.poll.records`: `leer` nunca descarta registros, porque luego se confirmarían sin procesar.',
  [('kafka.bootstrap', 'bootstrap.eventos-modalima.southamerica-west1.managedkafka.modalima-prod.cloud.goog:9092')],
  [('Agregador por ventanas (lógica pura)', AGR, True), ('Adaptador con kafka-clients', SDK, True), ('Servicio', SERV, True)],
  'Clickstream', '/tienda/clickstream', 'ServicioDeClickstream', 'LectorDeGrupo', [],
  'return new LectorDeGrupo(bootstrap, "tablero", "clickstream");',
  [dict(n='ciclo', v='POST', p='/ciclo', args=[], ret='ServicioDeClickstream.Ciclo', call='s.ciclo()')],
  [('Consumir el tema', '`roles/managedkafka.client` para `gke-tablero` (Workload Identity)')],
  ['No actives el commit automático.',
   'No confirmes antes de escribir el resultado.',
   'No agrupes por hora de llegada.',
   'No expongas `/ciclo` como API pública: en producción es un bucle interno.'])
