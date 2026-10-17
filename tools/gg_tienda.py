import ggen
NUC = '''
import java.util.List;
import java.util.function.Function;

/** Relay del outbox e inbox idempotente. Puro: los repositorios y el publicador son interfaces. */
public final class Outbox {

    private Outbox() { }

    public record Evento(String id, String tipo, String clave, String carga, int intentos) { }

    public interface Repositorio {
        /** En SQL: SELECT … WHERE estado='PENDIENTE' … FOR UPDATE SKIP LOCKED. */
        List<Evento> pendientes(int max);

        void marcarEnviado(String id);

        void registrarFallo(String id, boolean definitivo);
    }

    public interface Publicador {
        void publicar(Evento e);
    }

    public record Resultado(int enviados, int reintentables, int fallidos) { }

    public static final class Relay {
        private final Repositorio repo;
        private final Publicador publicador;
        private final int maxIntentos;

        public Relay(Repositorio repo, Publicador publicador, int maxIntentos) {
            this.repo = repo;
            this.publicador = publicador;
            this.maxIntentos = maxIntentos;
        }

        /** Un evento que falla no detiene al resto del lote. */
        public Resultado ejecutar(int lote) {
            int ok = 0, reint = 0, mal = 0;
            for (Evento e : repo.pendientes(lote)) {
                try {
                    publicador.publicar(e);
                    repo.marcarEnviado(e.id());
                    ok++;
                } catch (RuntimeException ex) {
                    boolean definitivo = e.intentos() + 1 >= maxIntentos;
                    repo.registrarFallo(e.id(), definitivo);
                    if (definitivo) {
                        mal++;
                    } else {
                        reint++;
                    }
                }
            }
            return new Resultado(ok, reint, mal);
        }
    }

    /** Inbox: procesa solo si el id es nuevo (en SQL, INSERT con clave única). */
    public static final class Inbox {
        private final Function<String, Boolean> registrarSiNuevo;

        public Inbox(Function<String, Boolean> registrarSiNuevo) {
            this.registrarSiNuevo = registrarSiNuevo;
        }

        public boolean procesar(String idEvento, Runnable efecto) {
            if (!registrarSiNuevo.apply(idEvento)) {
                return false; // duplicado: se ignora sin error
            }
            efecto.run();
            return true;
        }
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.TopicName;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;

/** Adaptador: publica el evento del outbox en Pub/Sub con clave de orden = pedido. */
public class PublicadorGcp implements Outbox.Publicador, AutoCloseable {

    private final Publisher publisher;

    public PublicadorGcp(GoogleCredentials cred, String proyecto, String tema, String endpointRegional) {
        try {
            this.publisher = Publisher.newBuilder(TopicName.of(proyecto, tema))
                .setCredentialsProvider(FixedCredentialsProvider.create(cred))
                .setEnableMessageOrdering(true)
                .setEndpoint(endpointRegional)        // el orden exige endpoint regional
                .build();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @Override
    public void publicar(Outbox.Evento e) {
        var msg = PubsubMessage.newBuilder()
            .setData(ByteString.copyFromUtf8(e.carga()))
            .putAttributes("id", e.id())             // para el inbox del consumidor
            .putAttributes("tipo", e.tipo())
            .setOrderingKey(e.clave())
            .build();
        try {
            publisher.publish(msg).get(10, TimeUnit.SECONDS);   // confirmar antes de marcar enviado
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(ex);
        } catch (ExecutionException | java.util.concurrent.TimeoutException ex) {
            publisher.resumePublish(e.clave());     // tras un fallo, la clave queda pausada
            throw new IllegalStateException("no se publicó " + e.id(), ex);
        }
    }

    @Override
    public void close() {
        publisher.shutdown();
        try {
            publisher.awaitTermination(10, TimeUnit.SECONDS);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
        }
    }
}
'''
SERV = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDePedidos {

    public record Pedido(String idPedido, String total) { }

    private final PublicadorGcp publicador;
    // Demo en memoria; en la app real es la tabla OUTBOX en la misma transacción que el pedido.
    private final Map<String, Outbox.Evento> outbox = new ConcurrentHashMap<>();
    private final Map<String, String> estados = new ConcurrentHashMap<>();

    public ServicioDePedidos(PublicadorGcp publicador) {
        this.publicador = publicador;
    }

    public String crear(Pedido p) {
        if (!p.idPedido().matches("P-[0-9]{1,12}") || !p.total().matches("[0-9]{1,7}(\\\\.[0-9]{2})?")) {
            throw new IllegalArgumentException("pedido inválido");
        }
        String id = UUID.randomUUID().toString();
        // INSERT pedido + INSERT outbox en una sola transacción
        outbox.put(id, new Outbox.Evento(id, "PedidoPagado.v1", p.idPedido(), "{\\"total\\":" + p.total() + "}", 0));
        estados.put(id, "PENDIENTE");
        return id;
    }

    public Outbox.Resultado relay() {
        var repo = new Outbox.Repositorio() {
            public List<Outbox.Evento> pendientes(int max) {
                return new ArrayList<>(outbox.values()).stream().filter(e -> "PENDIENTE".equals(estados.get(e.id()))).limit(max).toList();
            }

            public void marcarEnviado(String id) {
                estados.put(id, "ENVIADO");
            }

            public void registrarFallo(String id, boolean definitivo) {
                outbox.computeIfPresent(id, (k, e) -> new Outbox.Evento(e.id(), e.tipo(), e.clave(), e.carga(), e.intentos() + 1));
                if (definitivo) {
                    estados.put(id, "FALLIDO");
                }
            }
        };
        return new Outbox.Relay(repo, publicador, 5).ejecutar(50);
    }
}
'''
ggen.gcp('gcp/11-casos-integrados/tienda-online', 'Caso integrado · Tienda online',
  'El corazón del caso: **outbox + relay + inbox**. El núcleo puro define el relay (publica lotes, marca enviados y aparta los fallidos definitivos sin detener el lote) y el inbox (procesa solo ids nuevos). El adaptador publica con `Publisher` de Pub/Sub, **espera la confirmación** antes de que el relay marque enviado, usa la clave de orden del pedido y reanuda la clave tras un fallo. El servicio de demostración guarda el outbox en memoria; en la app real es la tabla de [`ejemplos/sql/outbox.sql`](ejemplos/sql/outbox.sql) escrita en la misma transacción que el pedido (`@Transactional` o Panache).',
  [('pubsub.tema', 'pedido-pagado'), ('pubsub.endpoint', 'southamerica-west1-pubsub.googleapis.com:443')],
  [('Outbox, relay e inbox (lógica pura)', NUC, True), ('Adaptador de Pub/Sub', SDK, True), ('Servicio', SERV, True)],
  'Pedidos', '/tienda/pedidos', 'ServicioDePedidos', 'PublicadorGcp', [],
  'return new PublicadorGcp(cred, proyecto, tema, endpoint);',
  [dict(n='crear', v='POST', p='', args=[('ServicioDePedidos.Pedido', 'p', 'b')], ret='String', call='s.crear(p)', cpu=True),
   dict(n='relay', v='POST', p='/relay', args=[], ret='Outbox.Resultado', call='s.relay()')],
  [('Publicar en el tema', '`roles/pubsub.publisher` en `pedido-pagado` para `run-pedidos`'),
   ('Consumir (push)', '`roles/run.invoker` para `pubsub-push` en facturación')],
  ['No publiques dentro de la transacción de base de datos: escribe el outbox y publica después con el relay.',
   'No marques enviado antes de la confirmación de Pub/Sub.',
   'No proceses un evento sin pasar por el inbox.',
   'No pongas datos de tarjeta en eventos.',
   'No corras varios relays sin `SKIP LOCKED`.'])
