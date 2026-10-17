import ggen
CLA = '''
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/** Procesa un mensaje y decide ack/nack según el tipo de falla. Puro (el efecto de negocio se inyecta). */
public class ProcesadorDeMensajes {

    public enum Respuesta { ACK, NACK }

    /** Falla que vale la pena reintentar (base caída, timeout). */
    public static class Transitoria extends RuntimeException {
        public Transitoria(String m) {
            super(m);
        }
    }

    public interface Efecto {
        void aplicar(String clave, String datos, Map<String, String> atributos);
    }

    private final Efecto efecto;
    private final Set<String> hechos = ConcurrentHashMap.newKeySet(); // en producción: tabla con clave única
    private final AtomicLong rechazados = new AtomicLong();

    public ProcesadorDeMensajes(Efecto efecto) {
        this.efecto = efecto;
    }

    public Respuesta procesar(String idMensaje, String datos, Map<String, String> atributos) {
        String clave = atributos.getOrDefault("idEvento", idMensaje); // id de negocio si existe
        if (hechos.contains(clave)) {
            return Respuesta.ACK; // duplicado: confirmar sin repetir el efecto
        }
        try {
            efecto.aplicar(clave, datos, atributos);
            hechos.add(clave);
            return Respuesta.ACK;
        } catch (Transitoria t) {
            return Respuesta.NACK; // se reentrega con backoff de la suscripción
        } catch (RuntimeException permanente) {
            rechazados.incrementAndGet(); // registrar para revisión; reintentar no lo arreglará
            return Respuesta.ACK;
        }
    }

    public long rechazados() {
        return rechazados.get();
    }
}
'''
SDK = '''
import com.google.api.gax.batching.FlowControlSettings;
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.pubsub.v1.MessageReceiver;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.cloud.pubsub.v1.Subscriber;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.ProjectSubscriptionName;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.TopicName;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/** Adaptador: publicador con clave de orden y suscriptor con flow control que delega al procesador puro. */
public class PubSubGcp implements AutoCloseable {

    private final Publisher publicador;
    private final Subscriber suscriptor;

    public PubSubGcp(GoogleCredentials cred, String proyecto, String tema, String suscripcion, ProcesadorDeMensajes procesador) {
        var cp = FixedCredentialsProvider.create(cred);
        try {
            this.publicador = Publisher.newBuilder(TopicName.of(proyecto, tema)).setCredentialsProvider(cp)
                .setEnableMessageOrdering(true).build();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.suscriptor = Subscriber.newBuilder(ProjectSubscriptionName.of(proyecto, suscripcion), (MessageReceiver) (m, consumidor) -> {
                var r = procesador.procesar(m.getMessageId(), m.getData().toStringUtf8(), m.getAttributesMap());
                if (r == ProcesadorDeMensajes.Respuesta.ACK) {
                    consumidor.ack(); // solo después de procesar
                } else {
                    consumidor.nack();
                }
            })
            .setCredentialsProvider(cp)
            .setFlowControlSettings(FlowControlSettings.newBuilder()
                .setMaxOutstandingElementCount(100L).setMaxOutstandingRequestBytes(50L * 1024 * 1024).build())
            .build();
        this.suscriptor.startAsync().awaitRunning();
    }

    public String publicar(String datos, String claveOrden, Map<String, String> atributos) {
        var m = PubsubMessage.newBuilder().setData(ByteString.copyFromUtf8(datos)).setOrderingKey(claveOrden)
            .putAllAttributes(atributos).build();
        try {
            return publicador.publish(m).get(10, TimeUnit.SECONDS);
        } catch (Exception e) {
            publicador.resumePublish(claveOrden); // tras un error, la clave queda pausada
            throw new IllegalStateException("no se pudo publicar", e);
        }
    }

    @Override
    public void close() {
        try {
            suscriptor.stopAsync().awaitTerminated(30, TimeUnit.SECONDS);
            publicador.shutdown();
            publicador.awaitTermination(10, TimeUnit.SECONDS);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
'''
SERV = '''
import java.util.Map;

public class ServicioDeEventos {

    public record Evento(String idEvento, String idCliente, String datos) { }

    private final PubSubGcp pubsub;

    public ServicioDeEventos(PubSubGcp pubsub) {
        this.pubsub = pubsub;
    }

    /** Clave de orden por cliente: sus eventos llegan en orden, los de distintos clientes en paralelo. */
    public String publicar(Evento e) {
        return pubsub.publicar(e.datos(), e.idCliente(), Map.of("idEvento", e.idEvento(), "tipo", "PedidoPagado.v1"));
    }
}
'''
ggen.gcp('gcp/07-mensajeria/pubsub', 'Mensajería · Pub/Sub',
  'Publicador y suscriptor bien hechos: el **procesador puro** deduplica por id de negocio y decide **ack** (procesado, duplicado o error permanente registrado) o **nack** (error transitorio, que reentrega la suscripción con backoff). El adaptador publica con **clave de orden** (`setEnableMessageOrdering`, `resumePublish` tras error) y suscribe con **flow control**, confirmando solo después de procesar.',
  [('pubsub.tema', 'pedidos-pagados'), ('pubsub.suscripcion', 'facturacion')],
  [('Procesador (lógica pura)', CLA, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Eventos', '/mensajeria/eventos', 'ServicioDeEventos', 'PubSubGcp', [],
  'var procesador = new ProcesadorDeMensajes((clave, datos, atributos) -> { /* facturar de forma idempotente */ });\nreturn new PubSubGcp(cred, proyecto, tema, suscripcion, procesador);',
  [dict(n='publicar', v='POST', p='', args=[('ServicioDeEventos.Evento', 'e', 'b')], ret='String', call='s.publicar(e)')],
  [('Publicar', '`roles/pubsub.publisher` en el tema'), ('Consumir', '`roles/pubsub.subscriber` en la suscripción')],
  ['No hagas ack antes de procesar.',
   'No hagas nack de errores permanentes: los reentregarás para siempre.',
   'No crees un `Publisher` por mensaje.',
   'No olvides `resumePublish` tras un error con clave de orden.',
   'No bloquees el hilo de eventos de WebFlux/Mutiny esperando `publish().get()`.'])
