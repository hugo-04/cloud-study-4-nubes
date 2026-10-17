import ggen
NOM = '''
import java.time.Clock;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/** Nombre determinista, tipo y tamaño de los comprobantes. Puro: reloj inyectado. */
public class ReglasDeComprobantes {

    private static final Map<String, String> EXTENSIONES = Map.of("application/pdf", "pdf", "image/png", "png", "image/jpeg", "jpg");
    private static final DateTimeFormatter RUTA = DateTimeFormatter.ofPattern("yyyy/MM/dd");

    private final Clock reloj;
    private final long maxBytes;

    public ReglasDeComprobantes(Clock reloj, long maxBytes) {
        this.reloj = reloj;
        this.maxBytes = maxBytes;
    }

    public String nombre(String idPedido, String tipo, long bytes) {
        if (idPedido == null || !idPedido.matches("P-[0-9]{1,12}")) {
            throw new IllegalArgumentException("idPedido inválido");
        }
        String ext = EXTENSIONES.get(tipo);
        if (ext == null) {
            throw new IllegalArgumentException("tipo no permitido: " + tipo);
        }
        if (bytes <= 0 || bytes > maxBytes) {
            throw new IllegalArgumentException("tamaño fuera de rango");
        }
        return "pedidos/" + LocalDate.now(reloj).format(RUTA) + "/" + idPedido + "." + ext;
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageException;
import com.google.cloud.storage.StorageOptions;
import java.util.Map;

/** Adaptador: escribe solo si el objeto no existe (ifGenerationMatch=0). */
public class AlmacenGcs implements AutoCloseable {

    public record Guardado(String objeto, boolean nuevo, Long generacion) { }

    private final Storage storage;
    private final String bucket;

    public AlmacenGcs(GoogleCredentials cred, String proyecto, String bucket) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public Guardado guardarSiNoExiste(String objeto, byte[] datos, String tipo, Map<String, String> meta) {
        var info = BlobInfo.newBuilder(BlobId.of(bucket, objeto)).setContentType(tipo).setMetadata(meta).build();
        try {
            var b = storage.create(info, datos, Storage.BlobTargetOption.doesNotExist());
            return new Guardado(objeto, true, b.getGeneration());
        } catch (StorageException e) {
            if (e.getCode() == 412) {
                return new Guardado(objeto, false, null); // ya existía: el reintento es inocuo
            }
            throw e;
        }
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            throw new IllegalStateException("error al cerrar Storage", e);
        }
    }
}
'''
SERV = '''
import java.time.Clock;
import java.util.Base64;
import java.util.Map;

public class ServicioDeComprobantes {

    public record Subida(String tipo, String contenidoBase64) { }

    private final AlmacenGcs almacen;
    private final ReglasDeComprobantes reglas = new ReglasDeComprobantes(Clock.systemUTC(), 5 * 1024 * 1024);

    public ServicioDeComprobantes(AlmacenGcs almacen) {
        this.almacen = almacen;
    }

    public AlmacenGcs.Guardado subir(String idPedido, Subida s) {
        byte[] datos = Base64.getDecoder().decode(s.contenidoBase64());
        return almacen.guardarSiNoExiste(reglas.nombre(idPedido, s.tipo(), datos.length), datos, s.tipo(), Map.of("pedido", idPedido));
    }
}
'''
ggen.gcp('gcp/06-storage/cloud-storage', 'Storage · Cloud Storage',
  'Un **guardado idempotente de comprobantes**: la lógica pura valida tipo y tamaño y arma un nombre determinista; el adaptador escribe con `Storage.create(..., BlobTargetOption.doesNotExist())` (equivale a `ifGenerationMatch=0`), así un reintento nunca pisa el comprobante ya enviado: un `412` significa «ya existía».',
  [('almacen.bucket', 'modalima-tienda-prod-comprobantes')],
  [('Reglas de nombre (lógica pura)', NOM, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Comprobantes', '/storage/comprobantes', 'ServicioDeComprobantes', 'AlmacenGcs', [],
  'return new AlmacenGcs(cred, proyecto, bucket);',
  [dict(n='subir', v='POST', p='/{id}', args=[('String', 'id', 'p'), ('ServicioDeComprobantes.Subida', 'sub', 'b')], ret='AlmacenGcs.Guardado', call='s.subir(id, sub)')],
  [('Crear objetos (sin leer ni borrar)', '`roles/storage.objectCreator` en el bucket')],
  ['No cargues archivos grandes en memoria: usa `storage.writer(...)` (subida reanudable) con un `InputStream`.',
   'No crees un cliente `Storage` por petición.',
   'No confíes en el `Content-Type` que envía el usuario.',
   'No uses ACL por objeto: acceso uniforme e IAM.'])
