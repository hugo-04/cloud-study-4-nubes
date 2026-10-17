import genlib
NOM = '''
import java.time.Clock;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/** Reglas de nombre, tipo y tamaño de los comprobantes. Puro: reloj inyectado. */
public class NombradorDeComprobantes {

    private static final Map<String, String> EXTENSIONES = Map.of("application/pdf", "pdf", "image/png", "png", "image/jpeg", "jpg");
    private static final DateTimeFormatter RUTA = DateTimeFormatter.ofPattern("yyyy/MM/dd");

    private final Clock reloj;
    private final long maxBytes;

    public NombradorDeComprobantes(Clock reloj, long maxBytes) {
        this.reloj = reloj;
        this.maxBytes = maxBytes;
    }

    /** Mismo pedido y mismo día ⇒ mismo nombre: los reintentos no crean copias. */
    public String nombre(String idPedido, String tipo, long bytes) {
        if (idPedido == null || !idPedido.matches("P-[0-9]{1,12}")) {
            throw new IllegalArgumentException("idPedido inválido");
        }
        String ext = EXTENSIONES.get(tipo);
        if (ext == null) {
            throw new IllegalArgumentException("tipo no permitido: " + tipo);
        }
        if (bytes <= 0 || bytes > maxBytes) {
            throw new IllegalArgumentException("tamaño fuera de rango (máx. " + maxBytes + " bytes)");
        }
        return "pedidos/" + LocalDate.now(reloj).format(RUTA) + "/" + idPedido + "." + ext;
    }
}
'''
SDK = '''
import com.oracle.bmc.model.BmcException;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.PutObjectRequest;
import java.io.ByteArrayInputStream;
import java.util.Map;

/** Adaptador del SDK: escribe solo si el objeto no existe (If-None-Match: *). */
public class AlmacenOci implements AutoCloseable {

    public record Guardado(String nombre, boolean nuevo, String etag) { }

    private final ObjectStorageClient cliente;
    private final String bucket;
    private final String namespace;

    public AlmacenOci(ObjectStorageClient cliente, String bucket) {
        this.cliente = cliente;
        this.bucket = bucket;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public Guardado guardarSiNoExiste(String nombre, byte[] datos, String tipo, Map<String, String> meta) {
        try {
            var r = cliente.putObject(PutObjectRequest.builder()
                .namespaceName(namespace).bucketName(bucket).objectName(nombre)
                .contentType(tipo).contentLength((long) datos.length)
                .putObjectBody(new ByteArrayInputStream(datos))
                .opcMeta(meta)
                .ifNoneMatch("*")
                .build());
            return new Guardado(nombre, true, r.getETag());
        } catch (BmcException e) {
            if (e.getStatusCode() == 412) {
                return new Guardado(nombre, false, null); // ya existía: el reintento es inocuo
            }
            throw e;
        }
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Clock;
import java.util.Base64;
import java.util.Map;

public class ServicioDeComprobantes {

    public record Subida(String tipo, String contenidoBase64) { }

    private final AlmacenOci almacen;
    private final NombradorDeComprobantes nombrador = new NombradorDeComprobantes(Clock.systemUTC(), 5 * 1024 * 1024);

    public ServicioDeComprobantes(AlmacenOci almacen) {
        this.almacen = almacen;
    }

    public AlmacenOci.Guardado subir(String idPedido, Subida s) {
        byte[] datos = Base64.getDecoder().decode(s.contenidoBase64());
        String nombre = nombrador.nombre(idPedido, s.tipo(), datos.length);
        return almacen.guardarSiNoExiste(nombre, datos, s.tipo(), Map.of("pedido", idPedido));
    }
}
'''
genlib.oci('oci/06-storage/object-storage', 'Storage · Object Storage',
  'Un **guardado idempotente de comprobantes**: la lógica pura valida tipo y tamaño y arma un nombre determinista (`pedidos/AAAA/MM/DD/<id>.pdf`); el adaptador hace `putObject` con `If-None-Match: *`, así un reintento nunca pisa el comprobante ya enviado (un `412` significa «ya existía»).',
  [('almacen.bucket', 'comprobantes')],
  [('Nombres y validación (lógica pura)', NOM, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Comprobantes', '/storage/comprobantes', 'ServicioDeComprobantes', 'AlmacenOci',
  ['import com.oracle.bmc.objectstorage.ObjectStorageClient;'],
  'return new AlmacenOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);',
  [dict(n='subir', v='POST', p='/{id}', args=[('String', 'id', 'p'), ('ServicioDeComprobantes.Subida', 'sub', 'b')], ret='AlmacenOci.Guardado', call='s.subir(id, sub)')],
  [('Escribir objetos del bucket', "`Allow dynamic-group app-pedidos to manage objects in compartment tienda-prod where all {target.bucket.name = 'comprobantes', any {request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_INSPECT'}}`"),
   ('`getNamespace`', 'No requiere política adicional')],
  ['No cargues archivos de varios GB en memoria: usa `UploadManager` (multipart) con un `InputStream`.',
   'No crees un `ObjectStorageClient` por petición: es caro; uno por aplicación.',
   'No confíes en el `Content-Type` que envía el usuario sin validarlo.',
   'No registres el contenido ni los metadatos personales.',
   'No uses buckets públicos para servir archivos: PAR o un backend que valide.'])
