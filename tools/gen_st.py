import genlib
LOTE = '''
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Arma lotes para PutMessages respetando tamaño por mensaje y por lote. Puro. */
public class ArmadorDeLotes {

    public record Evento(String clave, String valor) { }

    private final int maxMensaje;
    private final int maxLote;
    private final int maxPorLote;

    public ArmadorDeLotes(int maxMensaje, int maxLote, int maxPorLote) {
        this.maxMensaje = maxMensaje;
        this.maxLote = maxLote;
        this.maxPorLote = maxPorLote;
    }

    public List<List<Evento>> armar(List<Evento> eventos) {
        var lotes = new ArrayList<List<Evento>>();
        var actual = new ArrayList<Evento>();
        int bytes = 0;
        for (Evento e : eventos) {
            if (e.clave() == null || e.clave().isBlank()) {
                throw new IllegalArgumentException("cada evento necesita clave (define partición y orden)");
            }
            int t = e.clave().getBytes(StandardCharsets.UTF_8).length + e.valor().getBytes(StandardCharsets.UTF_8).length;
            if (t > maxMensaje) {
                throw new IllegalArgumentException("evento de " + t + " bytes supera el máximo; usa claim check");
            }
            if (!actual.isEmpty() && (bytes + t > maxLote || actual.size() == maxPorLote)) {
                lotes.add(List.copyOf(actual));
                actual.clear();
                bytes = 0;
            }
            actual.add(e);
            bytes += t;
        }
        if (!actual.isEmpty()) {
            lotes.add(List.copyOf(actual));
        }
        return lotes;
    }
}
'''
SDK = '''
import com.oracle.bmc.streaming.StreamClient;
import com.oracle.bmc.streaming.model.PutMessagesDetails;
import com.oracle.bmc.streaming.model.PutMessagesDetailsEntry;
import com.oracle.bmc.streaming.requests.PutMessagesRequest;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: publica un lote y devuelve SOLO los eventos que fallaron, para reintentarlos. */
public class StreamOci implements AutoCloseable {

    private final StreamClient cliente;
    private final String streamId;

    public StreamOci(StreamClient cliente, String streamId) {
        this.cliente = cliente;
        this.streamId = streamId;
    }

    public List<ArmadorDeLotes.Evento> publicar(List<ArmadorDeLotes.Evento> lote) {
        var entradas = lote.stream().map(e -> PutMessagesDetailsEntry.builder()
            .key(e.clave().getBytes(StandardCharsets.UTF_8))
            .value(e.valor().getBytes(StandardCharsets.UTF_8)).build()).toList();
        var r = cliente.putMessages(PutMessagesRequest.builder().streamId(streamId)
            .putMessagesDetails(PutMessagesDetails.builder().messages(entradas).build()).build()).getPutMessagesResult();
        var fallidos = new ArrayList<ArmadorDeLotes.Evento>();
        if (r.getFailures() != null && r.getFailures() > 0) {
            for (int i = 0; i < r.getEntries().size(); i++) {
                if (r.getEntries().get(i).getError() != null) {
                    fallidos.add(lote.get(i)); // las respuestas vienen en el mismo orden
                }
            }
        }
        return fallidos;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeClickstream {

    public record Resultado(int enviados, int lotes, int fallidosFinales) { }

    private final StreamOci stream;
    private final ArmadorDeLotes armador = new ArmadorDeLotes(1_000_000, 1_000_000, 500);

    public ServicioDeClickstream(StreamOci stream) {
        this.stream = stream;
    }

    public Resultado publicar(List<ArmadorDeLotes.Evento> eventos) {
        var lotes = armador.armar(eventos);
        int fallidos = 0;
        for (var lote : lotes) {
            var pendientes = lote;
            for (int intento = 0; intento < 3 && !pendientes.isEmpty(); intento++) {
                if (intento > 0) {
                    dormir(200L << intento);
                }
                pendientes = stream.publicar(pendientes);
            }
            fallidos += pendientes.size(); // en producción: a una cola o archivo de rescate
        }
        return new Resultado(eventos.size() - fallidos, lotes.size(), fallidos);
    }

    private static void dormir(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }
}
'''
genlib.oci('oci/07-mensajeria/streaming', 'Mensajería · Streaming',
  'Un **productor de clickstream robusto** con la API nativa: la lógica pura arma lotes respetando el tamaño por mensaje y por lote y exige clave (la clave define partición y orden); el adaptador publica con `StreamClient.putMessages` y devuelve **solo las entradas fallidas** para reintentarlas, porque una respuesta 200 puede traer fallos parciales. Para clientes Kafka, ver `ejemplos/kafka/application.yml`.',
  [('stream.id', 'ocid1.stream.oc1.sa-saopaulo-1.aaaa'), ('stream.endpoint', 'https://cell-1.streaming.sa-saopaulo-1.oci.oraclecloud.com')],
  [('Armador de lotes (lógica pura)', LOTE, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Clickstream', '/mensajeria/clickstream', 'ServicioDeClickstream', 'StreamOci',
  ['import com.oracle.bmc.streaming.StreamClient;', 'import java.util.List;'],
  'return new StreamOci(StreamClient.builder().endpoint(endpoint).build(auth), id);',
  [dict(n='publicar', v='POST', p='', args=[('List<ArmadorDeLotes.Evento>', 'eventos', 'b')], ret='ServicioDeClickstream.Resultado', call='s.publicar(eventos)')],
  [('Publicar', "`Allow dynamic-group app-tienda to use stream-push in compartment tienda-prod where target.stream.id = '<ocid>'`"),
   ('Consumir (otro servicio)', "`Allow dynamic-group analitica to use stream-pull in compartment tienda-prod where target.stream.id = '<ocid>'`")],
  ['No ignores `failures` en la respuesta de `putMessages`.',
   'No uses una clave constante: saturas una partición.',
   'No publiques mensaje por mensaje en tráfico alto: agrupa.',
   'No guardes el *auth token* de Kafka en `application.yml`: va en Vault o en una variable inyectada.',
   'No hagas commit del offset antes de procesar.'])
