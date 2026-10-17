import genlib
AUD = '''
import java.util.ArrayList;
import java.util.List;

/** Revisa las export options de NFS. Puro: recibe opciones simplificadas. */
public class AuditorDeExports {

    public record Opcion(String origen, boolean lecturaEscritura, String squash, boolean puertoPrivilegiado, boolean anonimo) { }

    public record Hallazgo(String ruta, String origen, String severidad, String mensaje) { }

    public List<Hallazgo> auditar(String ruta, List<Opcion> opciones) {
        var h = new ArrayList<Hallazgo>();
        for (Opcion o : opciones) {
            int prefijo = Integer.parseInt(o.origen().substring(o.origen().indexOf('/') + 1));
            if (prefijo == 0) {
                h.add(new Hallazgo(ruta, o.origen(), "ALTA", "abierto a cualquier origen"));
            } else if (prefijo < 16) {
                h.add(new Hallazgo(ruta, o.origen(), "MEDIA", "rango de origen muy amplio (/" + prefijo + ")"));
            }
            if (o.lecturaEscritura() && "NONE".equals(o.squash())) {
                h.add(new Hallazgo(ruta, o.origen(), "ALTA", "lectura-escritura sin root squash"));
            }
            if (!o.puertoPrivilegiado()) {
                h.add(new Hallazgo(ruta, o.origen(), "BAJA", "no exige puerto privilegiado"));
            }
            if (o.anonimo()) {
                h.add(new Hallazgo(ruta, o.origen(), "MEDIA", "permite acceso anónimo"));
            }
        }
        return h;
    }
}
'''
SDK = '''
import com.oracle.bmc.filestorage.FileStorageClient;
import com.oracle.bmc.filestorage.model.ClientOptions;
import com.oracle.bmc.filestorage.model.ExportSummary;
import com.oracle.bmc.filestorage.requests.GetExportRequest;
import com.oracle.bmc.filestorage.requests.ListExportsRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Adaptador del SDK: lee todos los exports del compartimento con sus opciones. */
public class ExportsOci implements AutoCloseable {

    private final FileStorageClient cliente;

    public ExportsOci(FileStorageClient cliente) {
        this.cliente = cliente;
    }

    public List<Map.Entry<String, List<AuditorDeExports.Opcion>>> exports(String compartimentoId) {
        var out = new ArrayList<Map.Entry<String, List<AuditorDeExports.Opcion>>>();
        String pagina = null;
        do {
            var r = cliente.listExports(ListExportsRequest.builder().compartmentId(compartimentoId)
                .lifecycleState(ListExportsRequest.LifecycleState.Active).page(pagina).build());
            for (ExportSummary s : r.getItems()) {
                var e = cliente.getExport(GetExportRequest.builder().exportId(s.getId()).build()).getExport();
                out.add(Map.entry(e.getPath(), e.getExportOptions().stream().map(ExportsOci::aOpcion).toList()));
            }
            pagina = r.getOpcNextPage();
        } while (pagina != null);
        return out;
    }

    private static AuditorDeExports.Opcion aOpcion(ClientOptions c) {
        return new AuditorDeExports.Opcion(c.getSource(), c.getAccess() == ClientOptions.Access.ReadWrite,
            c.getIdentitySquash().getValue(), Boolean.TRUE.equals(c.getRequirePrivilegedSourcePort()),
            Boolean.TRUE.equals(c.getIsAnonymousAccessAllowed()));
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeAuditoriaNfs {

    private final ExportsOci exports;
    private final AuditorDeExports auditor = new AuditorDeExports();

    public ServicioDeAuditoriaNfs(ExportsOci exports) {
        this.exports = exports;
    }

    public List<AuditorDeExports.Hallazgo> auditar(String compartimentoId) {
        return exports.exports(compartimentoId).stream()
            .flatMap(e -> auditor.auditar(e.getKey(), e.getValue()).stream())
            .toList();
    }
}
'''
genlib.oci('oci/06-storage/file-storage', 'Storage · File Storage',
  'Un **auditor de exports NFS**: recorre todos los exports del compartimento con `FileStorageClient` (paginando) y marca orígenes abiertos o demasiado amplios, lectura-escritura sin *root squash*, falta de puerto privilegiado y acceso anónimo. En NFS esas opciones **son** la política de acceso a los datos.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Nfs', '/storage/nfs', 'ServicioDeAuditoriaNfs', 'ExportsOci',
  ['import com.oracle.bmc.filestorage.FileStorageClient;', 'import java.util.List;'],
  'return new ExportsOci(FileStorageClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='auditar', v='GET', p='/auditoria', args=[('String', 'compartimento', 'q')], ret='List<AuditorDeExports.Hallazgo>', call='s.auditar(compartimento)')],
  [('Listar y leer exports', '`Allow dynamic-group auditoria to read file-family in compartment tienda-prod`')],
  ['No uses la API de OCI para leer o escribir archivos: el plano de datos es NFS (monta y usa `java.nio.file`).',
   'No escribas el mismo archivo desde varias réplicas sin coordinación: usa nombres únicos y renombrado atómico.',
   'No hagas `Files.walk` sobre millones de archivos en cada petición.',
   'No corras el contenedor como root para «arreglar» permisos.'])
