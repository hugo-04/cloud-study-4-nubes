import ggen
POL = '''
import java.util.Map;
import java.util.Set;

/** Reglas para emitir URLs firmadas: prefijo, método, vencimiento y tipo fijados por el backend. Puro. */
public class PoliticaDeFirma {

    public enum Metodo { GET, PUT }

    public record Plan(String objeto, Metodo metodo, int minutos, Map<String, String> cabeceras) { }

    private final Set<String> prefijos;
    private final Set<String> tipos;

    public PoliticaDeFirma(Set<String> prefijos, Set<String> tipos) {
        this.prefijos = Set.copyOf(prefijos);
        this.tipos = Set.copyOf(tipos);
    }

    public Plan descarga(String objeto, int minutos) {
        validarObjeto(objeto);
        if (minutos < 1 || minutos > 15) {
            throw new IllegalArgumentException("descargas: 1 a 15 minutos");
        }
        return new Plan(objeto, Metodo.GET, minutos, Map.of());
    }

    /** La subida exige el tipo exacto y que el objeto no exista (precondición firmada). */
    public Plan subida(String objeto, String tipo, int minutos) {
        validarObjeto(objeto);
        if (!tipos.contains(tipo)) {
            throw new IllegalArgumentException("tipo no permitido");
        }
        if (minutos < 1 || minutos > 30) {
            throw new IllegalArgumentException("subidas: 1 a 30 minutos");
        }
        return new Plan(objeto, Metodo.PUT, minutos, Map.of("Content-Type", tipo, "x-goog-if-generation-match", "0"));
    }

    private void validarObjeto(String objeto) {
        if (objeto == null || objeto.contains("..") || objeto.startsWith("/") || prefijos.stream().noneMatch(objeto::startsWith)) {
            throw new IllegalArgumentException("objeto fuera de los prefijos permitidos");
        }
    }
}
'''
SDK = '''
import com.google.auth.ServiceAccountSigner;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.HttpMethod;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.util.concurrent.TimeUnit;

/** Adaptador: firma V4 sin llaves (las credenciales adjuntas firman vía IAM signBlob). */
public class FirmadorGcs implements AutoCloseable {

    private final Storage storage;
    private final ServiceAccountSigner firmante;
    private final String bucket;

    public FirmadorGcs(GoogleCredentials cred, String proyecto, String bucket) {
        if (!(cred instanceof ServiceAccountSigner s)) {
            throw new IllegalStateException("estas credenciales no pueden firmar: usa la SA adjunta o suplanta una SA (gcp.suplantar)");
        }
        this.firmante = s;
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public String firmar(PoliticaDeFirma.Plan p) {
        var info = BlobInfo.newBuilder(BlobId.of(bucket, p.objeto())).build();
        var metodo = p.metodo() == PoliticaDeFirma.Metodo.GET ? HttpMethod.GET : HttpMethod.PUT;
        return storage.signUrl(info, p.minutos(), TimeUnit.MINUTES,
            Storage.SignUrlOption.withV4Signature(),
            Storage.SignUrlOption.httpMethod(metodo),
            Storage.SignUrlOption.withExtHeaders(p.cabeceras()),
            Storage.SignUrlOption.signWith(firmante)).toString();
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

public class ServicioDeUrls {

    public record Emitida(String url, String metodo, int minutos, java.util.Map<String, String> cabecerasObligatorias) { }

    private final FirmadorGcs firmador;
    private final PoliticaDeFirma politica = new PoliticaDeFirma(Set.of("fotos/", "pedidos/"), Set.of("image/jpeg", "image/png", "application/pdf"));

    public ServicioDeUrls(FirmadorGcs firmador) {
        this.firmador = firmador;
    }

    public Emitida descarga(String objeto) {
        // aquí va la autorización de negocio: ¿este usuario puede ver este objeto?
        var p = politica.descarga(objeto, 10);
        return new Emitida(firmador.firmar(p), "GET", p.minutos(), p.cabeceras());
    }

    public Emitida subida(String idFoto, String tipo) {
        String ext = tipo.equals("image/png") ? "png" : "jpg";
        var p = politica.subida("fotos/" + idFoto + "." + ext, tipo, 10);
        return new Emitida(firmador.firmar(p), "PUT", p.minutos(), p.cabeceras());
    }
}
'''
ggen.gcp('gcp/06-storage/urls-firmadas', 'Storage · URLs firmadas',
  'Un **emisor de URLs firmadas con reglas**: la lógica pura fija prefijo, método, vencimiento y, en subidas, el `Content-Type` exacto y la precondición `x-goog-if-generation-match: 0`; el adaptador firma con V4 mediante `Storage.signUrl` usando las credenciales adjuntas como `ServiceAccountSigner` (firma vía IAM `signBlob`, sin llaves). El servicio devuelve también las cabeceras que el cliente debe enviar tal cual.',
  [('urls.bucket', 'modalima-tienda-prod-fotos')],
  [('Política de firma (lógica pura)', POL, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Urls', '/storage/urls', 'ServicioDeUrls', 'FirmadorGcs', [],
  'return new FirmadorGcs(cred, proyecto, bucket);',
  [dict(n='descarga', v='GET', p='/descarga', args=[('String', 'objeto', 'q')], ret='ServicioDeUrls.Emitida', call='s.descarga(objeto)'),
   dict(n='subida', v='POST', p='/subida/{id}', args=[('String', 'id', 'p'), ('String', 'tipo', 'q')], ret='ServicioDeUrls.Emitida', call='s.subida(id, tipo)')],
  [('Firmar sin llaves', '`roles/iam.serviceAccountTokenCreator` de la SA sobre sí misma (signBlob)'),
   ('Permisos delegados', '`roles/storage.objectCreator` (subidas) / `objectViewer` (descargas) en el bucket')],
  ['No firmes con llaves JSON.',
   'No dejes que el cliente elija el nombre del objeto.',
   'No registres URLs firmadas.',
   'No firmes por más tiempo del necesario: no se pueden revocar.'])
