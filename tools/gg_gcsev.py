import ggen
PRO = '''
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** Decide qué hacer con una notificación de Cloud Storage recibida por Pub/Sub push. Puro. */
public class ProcesadorDeNotificaciones {

    /** Cuerpo del push de Pub/Sub. */
    public record Push(Mensaje message, String subscription) { }

    public record Mensaje(String messageId, Map<String, String> attributes) { }

    public enum Accion { PROCESAR, DUPLICADO, IGNORAR }

    public record Decision(Accion accion, String bucket, String objeto, Long generacion, String motivo) { }

    private final String prefijo;
    private final Set<String> extensiones;
    private final Set<String> vistos;

    public ProcesadorDeNotificaciones(String prefijo, Set<String> extensiones, int memoria) {
        this.prefijo = prefijo;
        this.extensiones = Set.copyOf(extensiones);
        this.vistos = Collections.synchronizedSet(Collections.newSetFromMap(new LinkedHashMap<String, Boolean>(16, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, Boolean> e) {
                return size() > memoria;
            }
        }));
    }

    public Decision decidir(Push p) {
        if (p == null || p.message() == null || p.message().attributes() == null) {
            return new Decision(Accion.IGNORAR, null, null, null, "mensaje incompleto");
        }
        var a = p.message().attributes();
        String bucket = a.get("bucketId");
        String objeto = a.get("objectId");
        String gen = a.get("objectGeneration");
        if (!"OBJECT_FINALIZE".equals(a.get("eventType")) || bucket == null || objeto == null || gen == null) {
            return new Decision(Accion.IGNORAR, bucket, objeto, null, "evento no relevante");
        }
        if (!objeto.startsWith(prefijo) || objeto.contains("..")) {
            return new Decision(Accion.IGNORAR, bucket, objeto, null, "fuera del prefijo");
        }
        String ext = objeto.substring(objeto.lastIndexOf('.') + 1).toLowerCase(java.util.Locale.ROOT);
        if (!extensiones.contains(ext)) {
            return new Decision(Accion.IGNORAR, bucket, objeto, null, "extensión no admitida");
        }
        long generacion = Long.parseLong(gen);
        // la generación identifica la versión exacta: dedupe por bucket/objeto#generación
        if (!vistos.add(bucket + "/" + objeto + "#" + generacion)) {
            return new Decision(Accion.DUPLICADO, bucket, objeto, generacion, "ya procesado");
        }
        return new Decision(Accion.PROCESAR, bucket, objeto, generacion, "ok");
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.util.Optional;

/** Adaptador: comprueba que la generación del evento sigue existiendo. */
public class ObjetosGcs implements AutoCloseable {

    public record Info(long bytes, String tipo) { }

    private final Storage storage;

    public ObjetosGcs(GoogleCredentials cred, String proyecto) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
    }

    public Optional<Info> generacion(String bucket, String objeto, long generacion) {
        var b = storage.get(BlobId.of(bucket, objeto, generacion));
        return b == null ? Optional.empty() : Optional.of(new Info(b.getSize(), b.getContentType()));
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
'''
SERV = '''
import java.util.Set;

public class ServicioDeNotificaciones {

    public record Resultado(String accion, String detalle) { }

    private final ObjetosGcs objetos;
    private final ProcesadorDeNotificaciones procesador = new ProcesadorDeNotificaciones("fotos/", Set.of("jpg", "png"), 10_000);

    public ServicioDeNotificaciones(ObjetosGcs objetos) {
        this.objetos = objetos;
    }

    /** Responde 2xx siempre que el mensaje se haya decidido (procesado, duplicado o ignorado): así no se reintenta. */
    public Resultado recibir(ProcesadorDeNotificaciones.Push p) {
        var d = procesador.decidir(p);
        if (d.accion() != ProcesadorDeNotificaciones.Accion.PROCESAR) {
            return new Resultado(d.accion().name(), d.motivo());
        }
        return objetos.generacion(d.bucket(), d.objeto(), d.generacion())
            .map(i -> new Resultado("PROCESAR", d.objeto() + " (" + i.bytes() + " bytes)"))
            .orElse(new Resultado("IGNORAR", "la generación ya no existe"));
    }
}
'''
ggen.gcp('gcp/06-storage/eventos-cloud-storage', 'Storage · Eventos de Cloud Storage',
  'Un **consumidor push** de las notificaciones del bucket: la lógica pura lee los atributos (`bucketId`, `objectId`, `objectGeneration`, `eventType`), filtra por prefijo y extensión y **deduplica por `bucket/objeto#generación`**; el adaptador comprueba con `Storage.get(BlobId.of(bucket, objeto, generación))` que esa versión exacta siga existiendo antes de procesarla.',
  [],
  [('Procesador (lógica pura)', PRO, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Notificaciones', '/storage/eventos', 'ServicioDeNotificaciones', 'ObjetosGcs', [],
  'return new ObjetosGcs(cred, proyecto);',
  [dict(n='recibir', v='POST', p='/push', args=[('ProcesadorDeNotificaciones.Push', 'p', 'b')], ret='ServicioDeNotificaciones.Resultado', call='s.recibir(p)')],
  [('Leer la generación en el bucket de origen', '`roles/storage.objectViewer` en el bucket'),
   ('Recibir el push', 'Cloud Run privado: `roles/run.invoker` para la cuenta OIDC de la suscripción')],
  ['No respondas error a un duplicado: Pub/Sub lo reintentaría.',
   'No leas «el objeto actual»: lee la generación del evento.',
   'No uses la deduplicación en memoria con varias réplicas: compártela.',
   'No escribas el resultado donde dispara la notificación.'])
