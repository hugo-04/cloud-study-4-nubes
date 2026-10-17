import ggen
AUD = '''
import java.util.ArrayList;
import java.util.List;

/** Audita opciones de exportación NFS de instancias de Filestore. Puro. */
public class AuditorDeExportaciones {

    public record Opcion(List<String> rangos, String acceso, String squash) { }

    public record Compartido(String instancia, String nombre, List<Opcion> opciones) { }

    public record Hallazgo(String compartido, String severidad, String mensaje) { }

    public List<Hallazgo> auditar(List<Compartido> compartidos) {
        var h = new ArrayList<Hallazgo>();
        for (Compartido c : compartidos) {
            String id = c.instancia() + ":" + c.nombre();
            if (c.opciones().isEmpty()) {
                h.add(new Hallazgo(id, "ALTA", "sin opciones de exportación: cualquier cliente de la red monta en RW"));
            }
            for (Opcion o : c.opciones()) {
                for (String r : o.rangos()) {
                    int pre = r.contains("/") ? Integer.parseInt(r.substring(r.indexOf('/') + 1)) : 32;
                    if (pre < 16) {
                        h.add(new Hallazgo(id, "MEDIA", "rango muy amplio " + r));
                    }
                }
                if ("READ_WRITE".equals(o.acceso()) && "NO_ROOT_SQUASH".equals(o.squash())) {
                    h.add(new Hallazgo(id, "ALTA", "lectura-escritura sin root squash para " + o.rangos()));
                }
            }
        }
        return h;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.asset.v1.AssetServiceClient;
import com.google.cloud.asset.v1.AssetServiceSettings;
import com.google.cloud.asset.v1.ContentType;
import com.google.cloud.asset.v1.ListAssetsRequest;
import com.google.protobuf.Struct;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee instancias de Filestore desde Cloud Asset Inventory (contenido RESOURCE). */
public class FilestoreGcp implements AutoCloseable {

    private final AssetServiceClient cliente;
    private final String proyecto;

    public FilestoreGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = AssetServiceClient.create(AssetServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeExportaciones.Compartido> compartidos() {
        var req = ListAssetsRequest.newBuilder().setParent("projects/" + proyecto)
            .addAssetTypes("file.googleapis.com/Instance").setContentType(ContentType.RESOURCE).build();
        var out = new ArrayList<AuditorDeExportaciones.Compartido>();
        for (var a : cliente.listAssets(req).iterateAll()) {
            Struct data = a.getResource().getData();
            String instancia = a.getName().substring(a.getName().lastIndexOf('/') + 1);
            for (com.google.protobuf.Value fs : lista(data, "fileShares")) {
                var s = fs.getStructValue();
                var opciones = lista(s, "nfsExportOptions").stream().map(v -> {
                    var o = v.getStructValue();
                    return new AuditorDeExportaciones.Opcion(lista(o, "ipRanges").stream().map(com.google.protobuf.Value::getStringValue).toList(),
                        texto(o, "accessMode"), texto(o, "squashMode"));
                }).toList();
                out.add(new AuditorDeExportaciones.Compartido(instancia, texto(s, "name"), opciones));
            }
        }
        return out;
    }

    private static List<com.google.protobuf.Value> lista(Struct s, String campo) {
        var v = s.getFieldsMap().get(campo);
        return v == null ? List.of() : v.getListValue().getValuesList();
    }

    private static String texto(Struct s, String campo) {
        var v = s.getFieldsMap().get(campo);
        return v == null ? "" : v.getStringValue();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeFilestore {

    private final FilestoreGcp filestore;
    private final AuditorDeExportaciones auditor = new AuditorDeExportaciones();

    public ServicioDeFilestore(FilestoreGcp filestore) {
        this.filestore = filestore;
    }

    public List<AuditorDeExportaciones.Hallazgo> auditar() {
        return auditor.auditar(filestore.compartidos());
    }
}
'''
ggen.gcp('gcp/06-storage/filestore', 'Storage · Filestore',
  'Un **auditor de opciones de exportación NFS**: como el BOM no incluye una biblioteca de Filestore, lee las instancias desde **Cloud Asset Inventory** (`AssetServiceClient.listAssets` con tipo `file.googleapis.com/Instance` y contenido `RESOURCE`), recorre la estructura (`fileShares[].nfsExportOptions[]`) y marca compartidos sin opciones, rangos demasiado amplios y lectura-escritura sin *root squash*. El acceso a los datos en sí se hace montando NFS y usando `java.nio.file`.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador (Cloud Asset Inventory)', SDK, True), ('Servicio', SERV, True)],
  'Filestore', '/storage/filestore', 'ServicioDeFilestore', 'FilestoreGcp', ['import java.util.List;'],
  'return new FilestoreGcp(cred, proyecto);',
  [dict(n='auditar', v='GET', p='/auditoria', args=[], ret='List<AuditorDeExportaciones.Hallazgo>', call='s.auditar()')],
  [('Leer el inventario de recursos', '`roles/cloudasset.viewer` en el proyecto')],
  ['No uses la API para leer archivos: monta NFS.',
   'No escribas el mismo archivo desde varias réplicas sin coordinación (renombrado atómico, nombres únicos).',
   'No corras contenedores como root para «arreglar» permisos.'])
