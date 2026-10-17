import genlib
POL = '''
/** Backoff por visibilidad: tras un fallo, el mensaje se oculta más tiempo en cada entrega. Puro. */
public class PoliticaDeReintento {

    public record Decision(boolean posponer, int segundos) { }

    private final int baseSegundos;
    private final int topeSegundos;

    public PoliticaDeReintento(int baseSegundos, int topeSegundos) {
        this.baseSegundos = baseSegundos;
        this.topeSegundos = topeSegundos;
    }

    /** deliveryCount empieza en 1. La DLQ la decide la cola (dead_letter_queue_delivery_count). */
    public Decision trasFallo(int deliveryCount) {
        int exp = Math.max(0, Math.min(deliveryCount - 1, 16));
        long s = (long) baseSegundos << exp;
        return new Decision(true, (int) Math.min(topeSegundos, s));
    }
}
'''
SDK = '''
import com.oracle.bmc.queue.QueueClient;
import com.oracle.bmc.queue.model.PutMessagesDetails;
import com.oracle.bmc.queue.model.PutMessagesDetailsEntry;
import com.oracle.bmc.queue.model.UpdateMessageDetails;
import com.oracle.bmc.queue.requests.DeleteMessageRequest;
import com.oracle.bmc.queue.requests.GetMessagesRequest;
import com.oracle.bmc.queue.requests.PutMessagesRequest;
import com.oracle.bmc.queue.requests.UpdateMessageRequest;
import java.util.List;

/** Adaptador del SDK: recibir con long polling, confirmar (borrar) y posponer (extender visibilidad). */
public class ColaOci implements AutoCloseable {

    public record Mensaje(String receipt, String contenido, int entregas) { }

    private final QueueClient cliente;
    private final String colaId;

    public ColaOci(QueueClient cliente, String colaId) {
        this.cliente = cliente;
        this.colaId = colaId;
    }

    public void enviar(String contenido) {
        cliente.putMessages(PutMessagesRequest.builder().queueId(colaId)
            .putMessagesDetails(PutMessagesDetails.builder()
                .messages(List.of(PutMessagesDetailsEntry.builder().content(contenido).build())).build())
            .build());
    }

    public List<Mensaje> recibir(int max) {
        return cliente.getMessages(GetMessagesRequest.builder().queueId(colaId)
                .limit(max).timeoutInSeconds(20).visibilityInSeconds(120).build())
            .getGetMessages().getMessages().stream()
            .map(m -> new Mensaje(m.getReceipt(), m.getContent(), m.getDeliveryCount()))
            .toList();
    }

    public void confirmar(String receipt) {
        cliente.deleteMessage(DeleteMessageRequest.builder().queueId(colaId).messageReceipt(receipt).build());
    }

    public void posponer(String receipt, int segundos) {
        cliente.updateMessage(UpdateMessageRequest.builder().queueId(colaId).messageReceipt(receipt)
            .updateMessageDetails(UpdateMessageDetails.builder().visibilityInSeconds(segundos).build()).build());
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDeFacturacion {

    public record Resumen(int recibidos, int procesados, int duplicados, int pospuestos) { }

    private final ColaOci cola;
    private final PoliticaDeReintento politica = new PoliticaDeReintento(15, 900);
    // idempotencia: en producción, tabla con clave única (id de pedido) en la base
    private final Set<String> facturados = ConcurrentHashMap.newKeySet();

    public ServicioDeFacturacion(ColaOci cola) {
        this.cola = cola;
    }

    public String encolar(String idPedido) {
        cola.enviar(idPedido);
        return "encolado " + idPedido;
    }

    /** Un ciclo del consumidor; en producción corre en un bucle o un @Scheduled. */
    public Resumen procesarLote() {
        int ok = 0, dup = 0, pos = 0;
        var lote = cola.recibir(10);
        for (var m : lote) {
            try {
                if (!m.contenido().matches("P-[0-9]{1,12}")) {
                    throw new IllegalArgumentException("pedido inválido");
                }
                if (facturados.add(m.contenido())) {
                    ok++;
                } else {
                    dup++;
                }
                cola.confirmar(m.receipt()); // borrar solo al terminar
            } catch (RuntimeException e) {
                cola.posponer(m.receipt(), politica.trasFallo(m.entregas()).segundos());
                pos++;
            }
        }
        return new Resumen(lote.size(), ok, dup, pos);
    }
}
'''
genlib.oci('oci/07-mensajeria/queue', 'Mensajería · Queue',
  'Un **consumidor correcto** de OCI Queue: recibe con *long polling*, procesa de forma idempotente, **borra solo al terminar** y, si falla, pospone el mensaje extendiendo su visibilidad con *backoff* exponencial (la DLQ la aplica la cola al superar las entregas).',
  [('cola.id', 'ocid1.queue.oc1.sa-saopaulo-1.aaaa'), ('cola.endpoint', 'https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com')],
  [('Política de reintento (lógica pura)', POL, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Facturacion', '/mensajeria/facturacion', 'ServicioDeFacturacion', 'ColaOci',
  ['import com.oracle.bmc.queue.QueueClient;'],
  'return new ColaOci(QueueClient.builder().endpoint(endpoint).build(auth), id);',
  [dict(n='encolar', v='POST', p='/{pedido}', args=[('String', 'pedido', 'p')], ret='String', call='s.encolar(pedido)'),
   dict(n='procesar', v='POST', p='/lote', args=[], ret='ServicioDeFacturacion.Resumen', call='s.procesarLote()')],
  [('Enviar, recibir, borrar y posponer', "`Allow dynamic-group consumidores-facturacion to use queues in compartment tienda-prod where target.queue.id = '<ocid>'`")],
  ['No borres el mensaje al recibirlo.',
   'No uses `region(...)` para `QueueClient`: necesita el `messages_endpoint` de la cola.',
   'No hagas `GetMessages` en bucle sin `timeoutInSeconds`.',
   'No llames al SDK bloqueante dentro del hilo de eventos en WebFlux/Mutiny.',
   'No reintentes infinitamente: deja que la DLQ actúe.'])
