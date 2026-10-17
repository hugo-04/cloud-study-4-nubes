import ggen
SOBRE = '''
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;

/** Sobre híbrido: en línea si cabe, por referencia (objeto + generación + SHA-256) si no. Puro. */
public class SobreHibrido {

    public sealed interface Sobre permits EnLinea, Referencia { }

    public record EnLinea(byte[] carga) implements Sobre { }

    public record Referencia(String objeto, long generacion, String sha256, long bytes) implements Sobre { }

    private final int umbral;

    public SobreHibrido(int umbral) {
        this.umbral = umbral;
    }

    public boolean cabe(byte[] carga) {
        return (carga.length + 2) / 3 * 4 <= umbral; // tamaño en base64
    }

    public static String objetoPara(String idMensaje) {
        if (!idMensaje.matches("[A-Za-z0-9-]{1,64}")) {
            throw new IllegalArgumentException("id inválido");
        }
        return "cargas/" + idMensaje + ".bin";
    }

    /** Atributos del mensaje de Pub/Sub (el cuerpo va vacío en una referencia). */
    public Map<String, String> atributos(Sobre s) {
        return switch (s) {
            case EnLinea e -> Map.of("tipo", "INL");
            case Referencia r -> Map.of("tipo", "REF", "objeto", r.objeto(), "generacion", Long.toString(r.generacion()),
                "sha256", r.sha256(), "bytes", Long.toString(r.bytes()));
        };
    }

    public String cuerpo(Sobre s) {
        return s instanceof EnLinea e ? Base64.getEncoder().encodeToString(e.carga()) : "";
    }

    public Sobre leer(Map<String, String> atributos, String cuerpo) {
        return switch (atributos.getOrDefault("tipo", "")) {
            case "INL" -> new EnLinea(Base64.getDecoder().decode(cuerpo));
            case "REF" -> new Referencia(atributos.get("objeto"), Long.parseLong(atributos.get("generacion")),
                atributos.get("sha256"), Long.parseLong(atributos.get("bytes")));
            default -> throw new IllegalArgumentException("sobre desconocido");
        };
    }

    public static byte[] verificar(Referencia r, byte[] datos) {
        if (datos.length != r.bytes() || !MessageDigest.isEqual(sha256(datos).getBytes(StandardCharsets.US_ASCII),
                r.sha256().getBytes(StandardCharsets.US_ASCII))) {
            throw new IllegalStateException("la carga no coincide con el ticket");
        }
        return datos;
    }

    public static String sha256(byte[] d) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(d));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.TopicName;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;

/** Adaptador: guardarropa (Cloud Storage) + transporte del ticket (Pub/Sub). */
public class ClaimCheckGcp implements AutoCloseable {

    private final Storage storage;
    private final Publisher publicador;
    private final String bucket;

    public ClaimCheckGcp(GoogleCredentials cred, String proyecto, String bucket, String tema) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
        try {
            this.publicador = Publisher.newBuilder(TopicName.of(proyecto, tema))
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Devuelve la generación creada (o falla con 412 si ya existía). */
    public long guardar(String objeto, byte[] datos) {
        return storage.create(BlobInfo.newBuilder(BlobId.of(bucket, objeto)).build(), datos,
            Storage.BlobTargetOption.doesNotExist()).getGeneration();
    }

    public byte[] canjear(String objeto, long generacion) {
        return storage.readAllBytes(BlobId.of(bucket, objeto, generacion));
    }

    public String publicar(String cuerpo, Map<String, String> atributos) {
        var m = PubsubMessage.newBuilder().setData(ByteString.copyFromUtf8(cuerpo)).putAllAttributes(atributos).build();
        try {
            return publicador.publish(m).get(10, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (ExecutionException | java.util.concurrent.TimeoutException e) {
            throw new IllegalStateException("no se pudo publicar el ticket", e);
        }
    }

    @Override
    public void close() {
        try {
            publicador.shutdown();
            publicador.awaitTermination(10, TimeUnit.SECONDS);
            storage.close();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
'''
SERV = '''
import java.nio.charset.StandardCharsets;
import java.util.Map;

public class ServicioDeClaimCheck {

    public record Envio(String id, String carga) { }

    public record Recibido(Map<String, String> atributos, String cuerpo) { }

    private final ClaimCheckGcp gcp;
    private final SobreHibrido sobres = new SobreHibrido(64 * 1024);

    public ServicioDeClaimCheck(ClaimCheckGcp gcp) {
        this.gcp = gcp;
    }

    public String enviar(Envio e) {
        byte[] datos = e.carga().getBytes(StandardCharsets.UTF_8);
        SobreHibrido.Sobre s;
        if (sobres.cabe(datos)) {
            s = new SobreHibrido.EnLinea(datos);
        } else {
            String objeto = SobreHibrido.objetoPara(e.id());
            long gen = gcp.guardar(objeto, datos); // primero el objeto…
            s = new SobreHibrido.Referencia(objeto, gen, SobreHibrido.sha256(datos), datos.length);
        }
        return gcp.publicar(sobres.cuerpo(s), sobres.atributos(s)); // …después el ticket
    }

    public String canjear(Recibido r) {
        return switch (sobres.leer(r.atributos(), r.cuerpo())) {
            case SobreHibrido.EnLinea l -> new String(l.carga(), StandardCharsets.UTF_8);
            case SobreHibrido.Referencia ref ->
                new String(SobreHibrido.verificar(ref, gcp.canjear(ref.objeto(), ref.generacion())), StandardCharsets.UTF_8);
        };
    }
}
'''
ggen.gcp('gcp/06-storage/claim-check', 'Storage · Claim check',
  'El **sobre híbrido** completo: si la carga cabe bajo el umbral viaja en línea; si no, se guarda en Cloud Storage con `doesNotExist()` y el ticket lleva **objeto + generación + SHA-256 + tamaño** como atributos del mensaje de Pub/Sub (`Publisher.publish`). El consumidor canjea leyendo esa **generación exacta** y verifica la huella.',
  [('cc.bucket', 'modalima-tienda-prod-cargas'), ('cc.tema', 'pedidos-mayoristas')],
  [('Sobre híbrido (lógica pura)', SOBRE, True), ('Adaptador de las bibliotecas', SDK, True), ('Servicio', SERV, True)],
  'ClaimCheck', '/storage/claim-check', 'ServicioDeClaimCheck', 'ClaimCheckGcp', [],
  'return new ClaimCheckGcp(cred, proyecto, bucket, tema);',
  [dict(n='enviar', v='POST', p='/enviar', args=[('ServicioDeClaimCheck.Envio', 'e', 'b')], ret='String', call='s.enviar(e)'),
   dict(n='canjear', v='POST', p='/canjear', args=[('ServicioDeClaimCheck.Recibido', 'r', 'b')], ret='String', call='s.canjear(r)')],
  [('Productor', '`roles/storage.objectCreator` en el bucket + `roles/pubsub.publisher` en el tema'),
   ('Consumidor', '`roles/storage.objectViewer` en el bucket + `roles/pubsub.subscriber` en la suscripción')],
  ['No publiques el ticket antes de tener la generación del objeto.',
   'No borres la carga desde el consumidor.',
   'No crees un `Publisher` por mensaje: es caro; uno por aplicación y ciérralo al apagar.',
   'No leas cargas enormes en memoria si puedes procesarlas en *streaming* (`storage.reader`).'])
