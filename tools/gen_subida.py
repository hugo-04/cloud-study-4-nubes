import genlib
NUC = '''
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/** Máquina de estados de una subida y validación por firma. Pura. */
public final class Subidas {

    private Subidas() { }

    public enum Estado { PENDIENTE, RECIBIDA, APROBADA, RECHAZADA, EXPIRADA, PROCESADA }

    private static final Map<Estado, Set<Estado>> PERMITIDAS = Map.of(
        Estado.PENDIENTE, Set.of(Estado.RECIBIDA, Estado.EXPIRADA),
        Estado.RECIBIDA, Set.of(Estado.APROBADA, Estado.RECHAZADA),
        Estado.APROBADA, Set.of(Estado.PROCESADA));

    /** Transición condicional: si el estado actual no es el esperado, no se hace nada (evento duplicado). */
    public static Optional<Estado> transicion(Estado actual, Estado esperado, Estado nuevo) {
        if (actual != esperado || !PERMITIDAS.getOrDefault(actual, Set.of()).contains(nuevo)) {
            return Optional.empty();
        }
        return Optional.of(nuevo);
    }

    public record Veredicto(boolean aprobado, String tipo, String motivo) { }

    /** Valida por los primeros bytes (firma), nunca por la extensión. */
    public static Veredicto validar(byte[] cabecera, long bytes, long maxBytes) {
        if (bytes <= 0 || bytes > maxBytes) {
            return new Veredicto(false, null, "tamaño fuera de rango");
        }
        if (empieza(cabecera, 0xFF, 0xD8, 0xFF)) {
            return new Veredicto(true, "image/jpeg", "ok");
        }
        if (empieza(cabecera, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) {
            return new Veredicto(true, "image/png", "ok");
        }
        if (empieza(cabecera, 0x25, 0x50, 0x44, 0x46, 0x2D)) {
            return new Veredicto(true, "application/pdf", "ok");
        }
        return new Veredicto(false, null, "tipo no permitido");
    }

    private static boolean empieza(byte[] b, int... firma) {
        if (b.length < firma.length) {
            return false;
        }
        for (int i = 0; i < firma.length; i++) {
            if ((b[i] & 0xFF) != firma[i]) {
                return false;
            }
        }
        return true;
    }

    public static String destino(String objetoEnCuarentena) {
        if (!objetoEnCuarentena.matches("cuarentena/S-[0-9]{1,20}\\\\.[a-z]{3,4}")) {
            throw new IllegalArgumentException("nombre fuera de la convención");
        }
        return "aprobados/" + objetoEnCuarentena.substring("cuarentena/".length());
    }
}
'''
SDK = '''
import com.oracle.bmc.model.Range;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.model.RenameObjectDetails;
import com.oracle.bmc.objectstorage.requests.DeleteObjectRequest;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.GetObjectRequest;
import com.oracle.bmc.objectstorage.requests.HeadObjectRequest;
import com.oracle.bmc.objectstorage.requests.RenameObjectRequest;
import java.io.IOException;
import java.io.UncheckedIOException;

/** Adaptador del SDK: leer la cabecera con un rango, mover condicionalmente y borrar rechazados. */
public class SubidasOci implements AutoCloseable {

    public record Info(long bytes, String etag) { }

    private final ObjectStorageClient cliente;
    private final String bucket;
    private final String namespace;

    public SubidasOci(ObjectStorageClient cliente, String bucket) {
        this.cliente = cliente;
        this.bucket = bucket;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public Info info(String objeto) {
        var h = cliente.headObject(HeadObjectRequest.builder().namespaceName(namespace).bucketName(bucket).objectName(objeto).build());
        return new Info(h.getContentLength(), h.getETag());
    }

    public byte[] cabecera(String objeto, int n) {
        var r = cliente.getObject(GetObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).range(new Range(0L, (long) n - 1)).build());
        try (var in = r.getInputStream()) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Mueve solo si el origen no cambió (ETag) y el destino no existe. */
    public void mover(String origen, String destino, String etag) {
        cliente.renameObject(RenameObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .renameObjectDetails(RenameObjectDetails.builder().sourceName(origen).newName(destino)
                .srcObjIfMatchETag(etag).newObjIfNoneMatchETag("*").build()).build());
    }

    public void borrar(String objeto, String etag) {
        cliente.deleteObject(DeleteObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).ifMatch(etag).build());
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDeSubidas {

    public record Resultado(String id, String estado, String detalle) { }

    private final SubidasOci objetos;
    // Demo: estados en memoria; en la app real, NoSQL o la base con actualización condicional.
    private final Map<String, Subidas.Estado> estados = new ConcurrentHashMap<>();

    public ServicioDeSubidas(SubidasOci objetos) {
        this.objetos = objetos;
    }

    /** Lo invoca el consumidor del evento createobject (función o endpoint). */
    public Resultado alLlegar(String objeto) {
        String id = objeto.substring(objeto.indexOf('/') + 1, objeto.lastIndexOf('.'));
        estados.putIfAbsent(id, Subidas.Estado.PENDIENTE);
        if (Subidas.transicion(estados.get(id), Subidas.Estado.PENDIENTE, Subidas.Estado.RECIBIDA).isEmpty()) {
            return new Resultado(id, estados.get(id).name(), "evento duplicado: ignorado");
        }
        estados.put(id, Subidas.Estado.RECIBIDA);
        var info = objetos.info(objeto);
        var v = Subidas.validar(objetos.cabecera(objeto, 16), info.bytes(), 25L * 1024 * 1024);
        if (!v.aprobado()) {
            objetos.borrar(objeto, info.etag());
            estados.put(id, Subidas.Estado.RECHAZADA);
            return new Resultado(id, "RECHAZADA", v.motivo());
        }
        objetos.mover(objeto, Subidas.destino(objeto), info.etag());
        estados.put(id, Subidas.Estado.APROBADA);
        return new Resultado(id, "APROBADA", v.tipo()); // aquí se envía el ticket a la cola
    }
}
'''
genlib.oci('oci/11-casos-integrados/subida-claim-check', 'Caso integrado · Subida con claim check',
  'El validador de la cuarentena: una **máquina de estados con transiciones condicionales** (un evento duplicado no hace nada), **validación por firma** de los primeros bytes (JPEG, PNG, PDF) y tamaño, y un adaptador que lee solo 16 bytes con un `Range`, mueve con `renameObject` condicionado por ETag (y destino inexistente) o borra el rechazado.',
  [('subidas.bucket', 'subidas')],
  [('Estados y validación (lógica pura)', NUC, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Subidas', '/casos/subidas', 'ServicioDeSubidas', 'SubidasOci',
  ['import com.oracle.bmc.objectstorage.ObjectStorageClient;'],
  'return new SubidasOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);',
  [dict(n='alLlegar', v='POST', p='/evento', args=[('String', 'objeto', 'q')], ret='ServicioDeSubidas.Resultado', call='s.alLlegar(objeto)')],
  [('Leer, mover y borrar en el bucket de subidas', "`Allow dynamic-group funciones-tienda to manage objects in compartment tienda-prod where target.bucket.name = 'subidas'`")],
  ['No descargues el archivo completo para validar el tipo: basta un rango.',
   'No muevas sin condición de ETag.',
   'No apruebes por extensión o `Content-Type`.',
   'No proceses archivos fuera de la convención de nombres.'])
