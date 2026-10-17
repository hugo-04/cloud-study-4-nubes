import genlib
POL = '''
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;

/** Reglas de emisión de PAR: un objeto, una operación, poco tiempo y solo bajo prefijos permitidos. Puro. */
public class PoliticaDePar {

    public enum Operacion { LEER, ESCRIBIR }

    public record Plan(String nombrePar, String objeto, Operacion operacion, Instant vence) { }

    private final Clock reloj;
    private final List<String> prefijosPermitidos;

    public PoliticaDePar(Clock reloj, List<String> prefijosPermitidos) {
        this.reloj = reloj;
        this.prefijosPermitidos = List.copyOf(prefijosPermitidos);
    }

    public Plan planificar(String objeto, Operacion op, int minutos) {
        if (objeto == null || objeto.contains("..") || objeto.startsWith("/") || objeto.endsWith("/")) {
            throw new IllegalArgumentException("nombre de objeto inválido");
        }
        if (prefijosPermitidos.stream().noneMatch(objeto::startsWith)) {
            throw new IllegalArgumentException("prefijo no permitido para PAR");
        }
        int max = op == Operacion.LEER ? 15 : 30;
        if (minutos < 1 || minutos > max) {
            throw new IllegalArgumentException("vencimiento entre 1 y " + max + " minutos");
        }
        Instant ahora = reloj.instant();
        String nombre = (op == Operacion.LEER ? "lee-" : "escribe-") + Integer.toHexString(objeto.hashCode()) + "-" + ahora.getEpochSecond();
        return new Plan(nombre, objeto, op, ahora.plus(Duration.ofMinutes(minutos)));
    }
}
'''
SDK = '''
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.model.CreatePreauthenticatedRequestDetails;
import com.oracle.bmc.objectstorage.requests.CreatePreauthenticatedRequestRequest;
import com.oracle.bmc.objectstorage.requests.DeletePreauthenticatedRequestRequest;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import java.util.Date;

/** Adaptador del SDK: crea y revoca PAR. La URL solo existe en la respuesta de creación. */
public class ParOci implements AutoCloseable {

    public record Emitida(String id, String url, String vence) { }

    private final ObjectStorageClient cliente;
    private final String bucket;
    private final String namespace;

    public ParOci(ObjectStorageClient cliente, String bucket) {
        this.cliente = cliente;
        this.bucket = bucket;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public Emitida crear(PoliticaDePar.Plan p) {
        var tipo = p.operacion() == PoliticaDePar.Operacion.LEER
            ? CreatePreauthenticatedRequestDetails.AccessType.ObjectRead
            : CreatePreauthenticatedRequestDetails.AccessType.ObjectWrite;
        var par = cliente.createPreauthenticatedRequest(CreatePreauthenticatedRequestRequest.builder()
            .namespaceName(namespace).bucketName(bucket)
            .createPreauthenticatedRequestDetails(CreatePreauthenticatedRequestDetails.builder()
                .name(p.nombrePar()).objectName(p.objeto()).accessType(tipo)
                .timeExpires(Date.from(p.vence())).build())
            .build()).getPreauthenticatedRequest();
        return new Emitida(par.getId(), par.getFullPath(), p.vence().toString());
    }

    public void revocar(String parId) {
        cliente.deletePreauthenticatedRequest(DeletePreauthenticatedRequestRequest.builder()
            .namespaceName(namespace).bucketName(bucket).parId(parId).build());
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Clock;
import java.util.List;

public class ServicioDePar {

    public record Pedido(String objeto, PoliticaDePar.Operacion operacion, int minutos) { }

    private final ParOci par;
    private final PoliticaDePar politica = new PoliticaDePar(Clock.systemUTC(), List.of("pedidos/", "fotos/"));

    public ServicioDePar(ParOci par) {
        this.par = par;
    }

    public ParOci.Emitida emitir(Pedido p) {
        // aquí iría la regla de negocio: ¿este usuario es dueño del pedido?
        return par.crear(politica.planificar(p.objeto(), p.operacion(), p.minutos()));
    }

    public String revocar(String id) {
        par.revocar(id);
        return "revocada";
    }
}
'''
genlib.oci('oci/06-storage/par', 'Storage · PAR',
  'Un **emisor de PAR con reglas**: la lógica pura solo acepta un objeto concreto bajo prefijos permitidos, una operación (leer o escribir) y vencimientos cortos; el adaptador llama a `createPreauthenticatedRequest`, devuelve la URL **una sola vez** y permite revocar por id.',
  [('almacen.bucket', 'comprobantes')],
  [('Política de emisión (lógica pura)', POL, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Par', '/storage/par', 'ServicioDePar', 'ParOci',
  ['import com.oracle.bmc.objectstorage.ObjectStorageClient;'],
  'return new ParOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);',
  [dict(n='emitir', v='POST', p='', args=[('ServicioDePar.Pedido', 'p', 'b')], ret='ParOci.Emitida', call='s.emitir(p)'),
   dict(n='revocar', v='DELETE', p='/{id}', args=[('String', 'id', 'p')], ret='String', call='s.revocar(id)')],
  [('Crear y borrar PAR + delegar lectura/escritura', "`Allow dynamic-group app-pedidos to manage objects in compartment tienda-prod where all {target.bucket.name = 'comprobantes', any {request.permission = 'PAR_MANAGE', request.permission = 'OBJECT_READ', request.permission = 'OBJECT_CREATE'}}`")],
  ['No registres la URL (`fullPath`/`accessUri`): registra el id.',
   'No permitas que el cliente elija el nombre del objeto a escribir.',
   'No emitas PAR `Any*` desde la app: si hace falta, que sea infraestructura revisada.',
   'No cachees URLs de PAR para reutilizarlas: emite una nueva cuando se necesite.',
   'No te saltes la autorización de negocio: verifica que el usuario es dueño del objeto.'])
