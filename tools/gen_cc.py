import genlib
SOBRE = '''
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.HexFormat;

/** Sobre híbrido del claim check: en línea si cabe, por referencia si no. Puro (sin SDK). */
public class SobreClaimCheck {

    public sealed interface Sobre permits EnLinea, Referencia { }

    public record EnLinea(byte[] carga) implements Sobre { }

    public record Referencia(String objeto, String sha256, long bytes) implements Sobre { }

    private final int umbralBytes;

    public SobreClaimCheck(int umbralBytes) {
        this.umbralBytes = umbralBytes;
    }

    /** Decide el sobre. El nombre del objeto es determinista por id de mensaje. */
    public Sobre armar(String idMensaje, byte[] carga) {
        if (!idMensaje.matches("[A-Za-z0-9-]{1,64}")) {
            throw new IllegalArgumentException("id de mensaje inválido");
        }
        // base64 crece ~4/3: se compara con el tamaño que realmente viajará
        if ((carga.length + 2) / 3 * 4 <= umbralBytes) {
            return new EnLinea(carga);
        }
        return new Referencia("cargas/" + idMensaje + ".bin", sha256(carga), carga.length);
    }

    public String serializar(Sobre s) {
        return switch (s) {
            case EnLinea e -> "v1|INL|" + Base64.getEncoder().encodeToString(e.carga());
            case Referencia r -> "v1|REF|" + r.objeto() + "|" + r.sha256() + "|" + r.bytes();
        };
    }

    public Sobre leer(String texto) {
        String[] p = texto.split("\\\\|");
        if (p.length < 3 || !p[0].equals("v1")) {
            throw new IllegalArgumentException("sobre desconocido");
        }
        return switch (p[1]) {
            case "INL" -> new EnLinea(Base64.getDecoder().decode(p[2]));
            case "REF" -> new Referencia(p[2], p[3], Long.parseLong(p[4]));
            default -> throw new IllegalArgumentException("tipo de sobre desconocido");
        };
    }

    /** Verifica que la carga canjeada es exactamente la enviada. */
    public byte[] verificar(Referencia r, byte[] canjeada) {
        if (canjeada.length != r.bytes() || !MessageDigest.isEqual(
                sha256(canjeada).getBytes(StandardCharsets.US_ASCII), r.sha256().getBytes(StandardCharsets.US_ASCII))) {
            throw new IllegalStateException("la carga no coincide con el ticket");
        }
        return canjeada;
    }

    static String sha256(byte[] datos) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(datos));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
'''
SDK = '''
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.GetObjectRequest;
import com.oracle.bmc.objectstorage.requests.PutObjectRequest;
import com.oracle.bmc.queue.QueueClient;
import com.oracle.bmc.queue.model.PutMessagesDetails;
import com.oracle.bmc.queue.model.PutMessagesDetailsEntry;
import com.oracle.bmc.queue.requests.PutMessagesRequest;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador del SDK: guardarropa (Object Storage) + transporte del ticket (OCI Queue). */
public class ClaimCheckOci implements AutoCloseable {

    private final ObjectStorageClient objetos;
    private final QueueClient cola;
    private final String bucket;
    private final String colaId;
    private final String namespace;

    public ClaimCheckOci(ObjectStorageClient objetos, QueueClient cola, String bucket, String colaId) {
        this.objetos = objetos;
        this.cola = cola;
        this.bucket = bucket;
        this.colaId = colaId;
        this.namespace = objetos.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public void guardar(String objeto, byte[] carga) {
        objetos.putObject(PutObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).contentLength((long) carga.length)
            .putObjectBody(new ByteArrayInputStream(carga)).build());
    }

    public byte[] canjear(String objeto) {
        var r = objetos.getObject(GetObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).build());
        try (var in = r.getInputStream()) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public void enviar(String ticket) {
        cola.putMessages(PutMessagesRequest.builder().queueId(colaId)
            .putMessagesDetails(PutMessagesDetails.builder()
                .messages(List.of(PutMessagesDetailsEntry.builder().content(ticket).build())).build())
            .build());
    }

    @Override
    public void close() {
        objetos.close();
        cola.close();
    }
}
'''
SERV = '''
import java.nio.charset.StandardCharsets;

public class ServicioDeClaimCheck {

    public record Envio(String id, String carga) { }

    private final ClaimCheckOci cc;
    private final SobreClaimCheck sobres = new SobreClaimCheck(64 * 1024);

    public ServicioDeClaimCheck(ClaimCheckOci cc) {
        this.cc = cc;
    }

    /** Productor: primero el objeto, luego el ticket. */
    public String enviar(Envio e) {
        var sobre = sobres.armar(e.id(), e.carga().getBytes(StandardCharsets.UTF_8));
        if (sobre instanceof SobreClaimCheck.Referencia r) {
            cc.guardar(r.objeto(), e.carga().getBytes(StandardCharsets.UTF_8));
        }
        String ticket = sobres.serializar(sobre);
        cc.enviar(ticket);
        return ticket.length() > 80 ? ticket.substring(0, 80) + "…" : ticket;
    }

    /** Consumidor: recibe el texto del mensaje y devuelve la carga verificada. */
    public String canjear(String ticket) {
        return switch (sobres.leer(ticket)) {
            case SobreClaimCheck.EnLinea l -> new String(l.carga(), StandardCharsets.UTF_8);
            case SobreClaimCheck.Referencia r -> new String(sobres.verificar(r, cc.canjear(r.objeto())), StandardCharsets.UTF_8);
        };
    }
}
'''
genlib.oci('oci/06-storage/claim-check', 'Storage · Claim check',
  'El **sobre híbrido** completo: la lógica pura decide si la carga va en línea o por referencia (calculando el crecimiento de base64), serializa el ticket con su huella SHA-256 y verifica al canjear; el adaptador escribe el objeto **antes** de enviar el ticket con `QueueClient.putMessages` y lo canjea con `getObject`.',
  [('cc.bucket', 'cargas'), ('cc.colaId', 'ocid1.queue.oc1.sa-saopaulo-1.aaaa'), ('cc.endpoint', 'https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com')],
  [('Sobre híbrido (lógica pura)', SOBRE, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'ClaimCheck', '/storage/claim-check', 'ServicioDeClaimCheck', 'ClaimCheckOci',
  ['import com.oracle.bmc.objectstorage.ObjectStorageClient;', 'import com.oracle.bmc.queue.QueueClient;'],
  'var objetos = ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth);\n// la cola usa su propio endpoint de mensajes (sale en Terraform: messages_endpoint)\nvar cola = QueueClient.builder().endpoint(endpoint).build(auth);\nreturn new ClaimCheckOci(objetos, cola, bucket, colaId);',
  [dict(n='enviar', v='POST', p='/enviar', args=[('ServicioDeClaimCheck.Envio', 'e', 'b')], ret='String', call='s.enviar(e)'),
   dict(n='canjear', v='POST', p='/canjear', args=[('String', 'ticket', 'b')], ret='String', call='s.canjear(ticket)')],
  [('Productor: crear objeto + enviar', "`Allow dynamic-group productores to manage objects in compartment tienda-prod where all {target.bucket.name = 'cargas', request.permission = 'OBJECT_CREATE'}` y `Allow dynamic-group productores to use queues in compartment tienda-prod`"),
   ('Consumidor: leer objeto', "`Allow dynamic-group consumidores to read objects in compartment tienda-prod where target.bucket.name = 'cargas'`")],
  ['No envíes el ticket antes de que `putObject` confirme.',
   'No borres la carga desde el consumidor: deja que el ciclo de vida lo haga.',
   'No pongas una PAR en el ticket.',
   'No leas cargas de varios MB en memoria si puedes procesarlas en *streaming*.'])
