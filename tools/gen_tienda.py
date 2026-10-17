import genlib
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
import com.oracle.bmc.queue.QueueClient;
import com.oracle.bmc.queue.model.PutMessagesDetails;
import com.oracle.bmc.queue.model.PutMessagesDetailsEntry;
import com.oracle.bmc.queue.requests.PutMessagesRequest;
import java.util.List;

/** Adaptador del SDK: publica el evento del outbox en la cola de facturación. */
public class PublicadorOci implements Outbox.Publicador, AutoCloseable {

    private final QueueClient cola;
    private final String colaId;

    public PublicadorOci(QueueClient cola, String colaId) {
        this.cola = cola;
        this.colaId = colaId;
    }

    @Override
    public void publicar(Outbox.Evento e) {
        // sobre mínimo: id para el inbox, tipo versionado y la carga
        String sobre = "{\\"id\\":\\"" + e.id() + "\\",\\"tipo\\":\\"" + e.tipo() + "\\",\\"clave\\":\\"" + e.clave()
            + "\\",\\"carga\\":" + e.carga() + "}";
        cola.putMessages(PutMessagesRequest.builder().queueId(colaId)
            .putMessagesDetails(PutMessagesDetails.builder()
                .messages(List.of(PutMessagesDetailsEntry.builder().content(sobre).build())).build())
            .build());
    }

    @Override
    public void close() {
        cola.close();
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

    private final PublicadorOci publicador;
    // Demo en memoria; en la app real es la tabla OUTBOX en la misma transacción que el pedido.
    private final Map<String, Outbox.Evento> outbox = new ConcurrentHashMap<>();
    private final Map<String, String> estados = new ConcurrentHashMap<>();

    public ServicioDePedidos(PublicadorOci publicador) {
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
genlib.oci('oci/11-casos-integrados/tienda-online', 'Caso integrado · Tienda online',
  'El corazón del caso: **outbox + relay + inbox**. El núcleo puro define el relay (publica lotes, marca enviados y aparta los fallidos definitivos sin detener el lote) y el inbox (procesa solo ids nuevos). El adaptador publica con `QueueClient`. El servicio de demostración guarda el outbox en memoria; en la app real es la tabla de [`ejemplos/sql/outbox.sql`](ejemplos/sql/outbox.sql) escrita en la misma transacción que el pedido (`JdbcTemplate`/`@Transactional` o Panache).',
  [('cola.id', 'ocid1.queue.oc1.sa-saopaulo-1.aaaa'), ('cola.endpoint', 'https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com')],
  [('Outbox, relay e inbox (lógica pura)', NUC, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Pedidos', '/tienda/pedidos', 'ServicioDePedidos', 'PublicadorOci',
  ['import com.oracle.bmc.queue.QueueClient;'],
  'return new PublicadorOci(QueueClient.builder().endpoint(endpoint).build(auth), id);',
  [dict(n='crear', v='POST', p='', args=[('ServicioDePedidos.Pedido', 'p', 'b')], ret='String', call='s.crear(p)', cpu=True),
   dict(n='relay', v='POST', p='/relay', args=[], ret='Outbox.Resultado', call='s.relay()')],
  [('Publicar en la cola (workload identity)', "Política con `request.principal.type = 'workload'`, namespace y service account (ver Terraform del caso)")],
  ['No publiques dentro de la transacción de base de datos (alarga bloqueos): escribe el outbox y publica después con el relay.',
   'No marques enviado antes de publicar.',
   'No proceses un evento sin pasar por el inbox.',
   'No pongas datos de tarjeta en eventos.',
   'No corras varios relays sin `SKIP LOCKED` (o un único relay con elección de líder).'])
