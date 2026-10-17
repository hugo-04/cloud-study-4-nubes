import genlib
AUD = '''
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/** Revisa el bucket del estado y sus objetos: protección, convenciones, tamaños y bloqueos viejos. Puro. */
public class AuditorDeEstado {

    public record Bucket(String nombre, boolean versionado, boolean publico, boolean conLlavePropia) { }

    public record Objeto(String nombre, long bytes, Instant modificado) { }

    public record Hallazgo(String severidad, String objeto, String mensaje) { }

    private static final Pattern CLAVE = Pattern.compile("[a-z0-9-]+/(prod|no-prod)/[a-z0-9-]+\\\\.tfstate");

    private final Clock reloj;
    private final Duration bloqueoMaximo;
    private final long bytesMaximo;

    public AuditorDeEstado(Clock reloj, Duration bloqueoMaximo, long bytesMaximo) {
        this.reloj = reloj;
        this.bloqueoMaximo = bloqueoMaximo;
        this.bytesMaximo = bytesMaximo;
    }

    public List<Hallazgo> auditar(Bucket b, List<Objeto> objetos) {
        var h = new ArrayList<Hallazgo>();
        if (b.publico()) {
            h.add(new Hallazgo("CRITICA", b.nombre(), "bucket del estado con acceso público"));
        }
        if (!b.versionado()) {
            h.add(new Hallazgo("ALTA", b.nombre(), "sin versionado: un estado corrupto no se recupera"));
        }
        if (!b.conLlavePropia()) {
            h.add(new Hallazgo("MEDIA", b.nombre(), "sin llave propia (CMK)"));
        }
        Instant ahora = reloj.instant();
        for (Objeto o : objetos) {
            String n = o.nombre();
            if (n.endsWith(".lock") || n.endsWith(".tflock")) {
                if (o.modificado().isBefore(ahora.minus(bloqueoMaximo))) {
                    h.add(new Hallazgo("ALTA", n, "bloqueo con más de " + bloqueoMaximo.toMinutes() + " min: ¿runner muerto?"));
                }
            } else if (n.endsWith(".tfstate")) {
                if (!CLAVE.matcher(n).matches()) {
                    h.add(new Hallazgo("BAJA", n, "clave fuera de la convención unidad/entorno/componente.tfstate"));
                }
                if (o.bytes() > bytesMaximo) {
                    h.add(new Hallazgo("MEDIA", n, "estado muy grande (" + o.bytes() / 1024 + " KB): divide el componente"));
                }
            }
        }
        return h;
    }
}
'''
SDK = '''
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.model.BucketSummary;
import com.oracle.bmc.objectstorage.model.Bucket;
import com.oracle.bmc.objectstorage.requests.GetBucketRequest;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.ListObjectsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: lectura del bucket del estado (solo lectura). */
public class EstadoOci implements AutoCloseable {

    private final ObjectStorageClient cliente;
    private final String namespace;

    public EstadoOci(ObjectStorageClient cliente) {
        this.cliente = cliente;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public AuditorDeEstado.Bucket bucket(String nombre) {
        var b = cliente.getBucket(GetBucketRequest.builder().namespaceName(namespace).bucketName(nombre).build()).getBucket();
        return new AuditorDeEstado.Bucket(nombre, b.getVersioning() == Bucket.Versioning.Enabled,
            b.getPublicAccessType() != Bucket.PublicAccessType.NoPublicAccess, b.getKmsKeyId() != null);
    }

    public List<AuditorDeEstado.Objeto> objetos(String bucket) {
        var out = new ArrayList<AuditorDeEstado.Objeto>();
        String inicio = null;
        do {
            var r = cliente.listObjects(ListObjectsRequest.builder().namespaceName(namespace).bucketName(bucket)
                .fields("name,size,timeModified").start(inicio).build()).getListObjects();
            r.getObjects().forEach(o -> out.add(new AuditorDeEstado.Objeto(o.getName(),
                o.getSize() == null ? 0 : o.getSize(), o.getTimeModified().toInstant())));
            inicio = r.getNextStartWith();
        } while (inicio != null);
        return out;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Clock;
import java.time.Duration;
import java.util.List;

public class ServicioDeEstado {

    private final EstadoOci estado;
    private final AuditorDeEstado auditor = new AuditorDeEstado(Clock.systemUTC(), Duration.ofMinutes(60), 5L * 1024 * 1024);

    public ServicioDeEstado(EstadoOci estado) {
        this.estado = estado;
    }

    public List<AuditorDeEstado.Hallazgo> auditar(String bucket) {
        return auditor.auditar(estado.bucket(bucket), estado.objetos(bucket));
    }
}
'''
SDK = SDK.replace("import com.oracle.bmc.objectstorage.model.BucketSummary;\n", "")
genlib.oci('oci/10-terraform/estado-remoto', 'Terraform · Estado remoto',
  'Desde Java **no ejecutas `apply` ni editas el estado**: eso lo hacen los pipelines. Lo que sí construyes es un **auditor de solo lectura** del bucket del estado: ¿es privado, versionado y con llave propia? ¿Hay bloqueos viejos (runner muerto)? ¿Estados fuera de la convención o demasiado grandes? Usa `ObjectStorageClient.getBucket` y `listObjects` paginando con `nextStartWith`.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Estado', '/terraform/estado', 'ServicioDeEstado', 'EstadoOci',
  ['import com.oracle.bmc.objectstorage.ObjectStorageClient;', 'import java.util.List;'],
  'return new EstadoOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='auditar', v='GET', p='/{bucket}', args=[('String', 'bucket', 'p')], ret='List<AuditorDeEstado.Hallazgo>', call='s.auditar(bucket)')],
  [('Leer bucket y listar objetos (sin leer contenido)', "`Allow dynamic-group auditoria to read buckets in compartment plataforma where target.bucket.name = 'tfstate-modalima'` y `Allow dynamic-group auditoria to inspect objects in compartment plataforma where target.bucket.name = 'tfstate-modalima'`")],
  ['No leas el contenido del estado desde una app: contiene secretos.',
   'No borres bloqueos desde código: avisa y que una persona haga `force-unlock`.',
   'No le des a la app permisos de escritura sobre el bucket del estado.',
   'No olvides paginar `listObjects` con `nextStartWith`.'])
