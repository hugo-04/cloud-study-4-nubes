import genlib
PROC = '''
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** Decide qué hacer con un evento de Object Storage: filtra, deduplica por eventID. Puro. */
public class ProcesadorDeEventos {

    /** Forma del evento (CloudEvents de OCI); el framework lo deserializa desde JSON. */
    public record Evento(String eventType, String eventID, String eventTime, Datos data) { }

    public record Datos(String resourceName, Detalles additionalDetails) { }

    public record Detalles(String bucketName, String namespace, String eTag) { }

    public enum Accion { PROCESAR, DUPLICADO, IGNORAR }

    public record Decision(Accion accion, String motivo) { }

    private final String bucketEsperado;
    private final String prefijo;
    private final Set<String> extensiones;
    private final Set<String> vistos;

    public ProcesadorDeEventos(String bucketEsperado, String prefijo, Set<String> extensiones, int memoria) {
        this.bucketEsperado = bucketEsperado;
        this.prefijo = prefijo;
        this.extensiones = Set.copyOf(extensiones);
        // conjunto acotado (LRU): en producción usa una tabla con expiración compartida entre réplicas
        this.vistos = Collections.synchronizedSet(Collections.newSetFromMap(new LinkedHashMap<String, Boolean>(16, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, Boolean> e) {
                return size() > memoria;
            }
        }));
    }

    public Decision decidir(Evento e) {
        if (e == null || e.data() == null || e.data().additionalDetails() == null || e.eventID() == null) {
            return new Decision(Accion.IGNORAR, "evento incompleto");
        }
        if (!e.eventType().endsWith(".createobject") && !e.eventType().endsWith(".updateobject")) {
            return new Decision(Accion.IGNORAR, "tipo no relevante");
        }
        if (!bucketEsperado.equals(e.data().additionalDetails().bucketName())) {
            return new Decision(Accion.IGNORAR, "otro bucket");
        }
        String nombre = e.data().resourceName();
        if (nombre == null || !nombre.startsWith(prefijo) || nombre.contains("..")) {
            return new Decision(Accion.IGNORAR, "fuera del prefijo");
        }
        String ext = nombre.substring(nombre.lastIndexOf('.') + 1).toLowerCase(java.util.Locale.ROOT);
        if (!extensiones.contains(ext)) {
            return new Decision(Accion.IGNORAR, "extensión no admitida");
        }
        if (!vistos.add(e.eventID())) {
            return new Decision(Accion.DUPLICADO, "eventID ya procesado");
        }
        return new Decision(Accion.PROCESAR, nombre);
    }
}
'''
SDK = '''
import com.oracle.bmc.model.BmcException;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.HeadObjectRequest;
import java.util.Optional;

/** Adaptador del SDK: comprueba que el objeto sigue existiendo y con el mismo ETag. */
public class ObjetosOci implements AutoCloseable {

    public record Info(long bytes, String tipo, String etag) { }

    private final ObjectStorageClient cliente;

    public ObjetosOci(ObjectStorageClient cliente) {
        this.cliente = cliente;
    }

    public Optional<Info> head(String namespace, String bucket, String nombre) {
        try {
            var r = cliente.headObject(HeadObjectRequest.builder()
                .namespaceName(namespace).bucketName(bucket).objectName(nombre).build());
            return Optional.of(new Info(r.getContentLength(), r.getContentType(), r.getETag()));
        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                return Optional.empty();
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
import java.util.Set;

public class ServicioDeEventos {

    public record Resultado(String accion, String detalle) { }

    private final ObjetosOci objetos;
    private final ProcesadorDeEventos procesador = new ProcesadorDeEventos("fotos-productos", "fotos/", Set.of("jpg", "png"), 10_000);

    public ServicioDeEventos(ObjetosOci objetos) {
        this.objetos = objetos;
    }

    public Resultado recibir(ProcesadorDeEventos.Evento e) {
        var d = procesador.decidir(e);
        if (d.accion() != ProcesadorDeEventos.Accion.PROCESAR) {
            return new Resultado(d.accion().name(), d.motivo());
        }
        var det = e.data().additionalDetails();
        return objetos.head(det.namespace(), det.bucketName(), e.data().resourceName())
            .filter(i -> det.eTag() == null || det.eTag().equals(i.etag()))
            .map(i -> new Resultado("PROCESAR", e.data().resourceName() + " (" + i.bytes() + " bytes)"))
            .orElse(new Resultado("IGNORAR", "el objeto ya no existe o cambió"));
    }
}
'''
genlib.oci('oci/06-storage/eventos-object-storage', 'Storage · Eventos de Object Storage',
  'Un **consumidor de eventos** de Object Storage (la misma lógica sirve dentro de una función o detrás de un endpoint HTTP de Notifications): el núcleo puro filtra por tipo, bucket, prefijo y extensión y **deduplica por `eventID`**; el adaptador hace `headObject` para confirmar que el objeto sigue ahí con el mismo ETag antes de procesarlo.',
  [],
  [('Procesador de eventos (lógica pura)', PROC, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Eventos', '/storage/eventos', 'ServicioDeEventos', 'ObjetosOci',
  ['import com.oracle.bmc.objectstorage.ObjectStorageClient;'],
  'return new ObjetosOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='recibir', v='POST', p='', args=[('ProcesadorDeEventos.Evento', 'e', 'b')], ret='ServicioDeEventos.Resultado', call='s.recibir(e)')],
  [('`headObject` en el bucket de origen', "`Allow dynamic-group consumidores to read objects in compartment tienda-prod where target.bucket.name = 'fotos-productos'`"),
   ('Escribir el resultado', "`Allow dynamic-group consumidores to manage objects in compartment tienda-prod where target.bucket.name = 'miniaturas'`")],
  ['No supongas que cada evento llega una sola vez ni en orden.',
   'No escribas el resultado en el bucket/prefijo que dispara la regla.',
   'No uses la deduplicación en memoria con varias réplicas: compártela (tabla con expiración o caché distribuida).',
   'No descargues el objeto antes de filtrar: decide primero con los metadatos del evento.'])
