import ggen
REV = '''
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Reglas del bucket del estado y de sus objetos (convención, tamaño, candados viejos). Puro.
 */
public final class RevisionDeEstado {

    public record Bucket(boolean versionado, boolean accesoUniforme, boolean sinAccesoPublico, String kms) { }

    public record Objeto(String nombre, long bytes, Instant creado) { }

    public record Informe(List<String> problemas, List<String> candadosViejos, List<String> estados) { }

    private static final Pattern CONVENCION = Pattern.compile("[a-z0-9-]+/[a-z0-9-]+\\\\.(tfstate|tflock)");

    private RevisionDeEstado() {
    }

    public static Informe revisar(Bucket b, List<Objeto> objetos, Instant ahora, Duration candadoMaximo, long bytesMaximo) {
        var p = new ArrayList<String>();
        if (!b.versionado()) {
            p.add("bucket sin versionado");
        }
        if (!b.accesoUniforme()) {
            p.add("acceso uniforme desactivado (ACL por objeto)");
        }
        if (!b.sinAccesoPublico()) {
            p.add("prevención de acceso público no forzada");
        }
        if (b.kms() == null || b.kms().isBlank()) {
            p.add("sin CMEK por defecto");
        }
        var viejos = new ArrayList<String>();
        var estados = new ArrayList<String>();
        for (var o : objetos) {
            if (!CONVENCION.matcher(o.nombre()).matches()) {
                p.add("objeto fuera de convención: " + o.nombre());
            }
            if (o.nombre().endsWith(".tflock") && Duration.between(o.creado(), ahora).compareTo(candadoMaximo) > 0) {
                viejos.add(o.nombre());
            }
            if (o.nombre().endsWith(".tfstate")) {
                estados.add(o.nombre());
                if (o.bytes() > bytesMaximo) {
                    p.add("estado grande (divídelo): " + o.nombre());
                }
            }
        }
        return new Informe(p, viejos, estados);
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;

/** Adaptador de solo lectura: metadatos del bucket y lista de objetos (nunca descarga el estado). */
public class EstadoGcp implements AutoCloseable {

    private final Storage storage;

    public EstadoGcp(GoogleCredentials cred, String proyecto) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
    }

    public RevisionDeEstado.Informe auditar(String bucket) {
        var b = storage.get(bucket);
        if (b == null) {
            throw new IllegalArgumentException("no existe el bucket " + bucket);
        }
        var iam = b.getIamConfiguration();
        var datos = new RevisionDeEstado.Bucket(Boolean.TRUE.equals(b.versioningEnabled()),
            iam != null && Boolean.TRUE.equals(iam.isUniformBucketLevelAccessEnabled()),
            iam != null && iam.getPublicAccessPrevention() == com.google.cloud.storage.BucketInfo.PublicAccessPrevention.ENFORCED,
            b.getDefaultKmsKeyName());
        var objetos = new ArrayList<RevisionDeEstado.Objeto>();
        for (var blob : storage.list(bucket).iterateAll()) {
            var creado = blob.getCreateTimeOffsetDateTime();
            objetos.add(new RevisionDeEstado.Objeto(blob.getName(), blob.getSize() == null ? 0 : blob.getSize(),
                creado == null ? Instant.EPOCH : creado.toInstant()));
        }
        return RevisionDeEstado.revisar(datos, objetos, Instant.now(), Duration.ofHours(2), 5_000_000);
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
'''
SERV = '''
public class ServicioDeEstado {

    private final EstadoGcp gcp;

    public ServicioDeEstado(EstadoGcp gcp) {
        this.gcp = gcp;
    }

    public RevisionDeEstado.Informe auditar(String bucket) {
        return gcp.auditar(bucket);
    }
}
'''
ggen.gcp('gcp/10-terraform/estado-remoto', 'Terraform · Estado remoto',
  'Desde Java **no ejecutas `apply` ni editas el estado**: eso lo hacen los pipelines. Lo que sí construyes es un **auditor de solo lectura** del bucket del estado: ¿versionado, acceso uniforme, sin acceso público y con CMEK? ¿Hay `.tflock` viejos (runner muerto)? ¿Objetos fuera de la convención `componente/workspace.tfstate` o estados demasiado grandes? Usa `Storage.get(bucket)` y `Storage.list`, **sin descargar** nunca el estado.',
  [],
  [('Reglas (lógica pura)', REV, True), ('Adaptador de Cloud Storage', SDK, True), ('Servicio', SERV, True)],
  'Estado', '/terraform/estado', 'ServicioDeEstado', 'EstadoGcp', [],
  'return new EstadoGcp(cred, proyecto);',
  [dict(n='auditar', v='GET', p='/{bucket}', args=[('String', 'bucket', 'p')], ret='RevisionDeEstado.Informe', call='s.auditar(bucket)')],
  [('Leer metadatos del bucket', '`roles/storage.legacyBucketReader` *(verifica)*'),
   ('Listar objetos', '`storage.objects.list` (sin `objects.get` para no poder leer el estado)')],
  ['No descargues el estado: contiene secretos.',
   'No borres candados desde la app: `force-unlock` es una decisión humana.',
   'No uses la SA del pipeline para auditar.',
   'No expongas el informe fuera de plataforma.'])
