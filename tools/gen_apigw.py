import genlib
AUT = '''
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

/**
 * Lógica del autorizador propio (CUSTOM_AUTHENTICATION) que corre en una función.
 * Guarda solo el SHA-256 de cada llave de socio; nunca la llave en claro. Puro: reloj inyectado.
 */
public class AutorizadorDeSocios {

    public record Socio(String nombre, List<String> alcances, boolean activo) { }

    /** Forma de la respuesta que espera API Gateway de un autorizador. */
    public record Respuesta(boolean active, String principal, List<String> scope, String expiresAt,
                            Map<String, String> context, String wwwAuthenticate) { }

    private final Map<String, Socio> porHash;
    private final Clock reloj;
    private final Duration validez;

    public AutorizadorDeSocios(Map<String, Socio> porHash, Clock reloj, Duration validez) {
        this.porHash = Map.copyOf(porHash);
        this.reloj = reloj;
        this.validez = validez;
    }

    public static String hash(String llave) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(llave.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(d);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public Respuesta autorizar(String cabecera) {
        if (cabecera == null || !cabecera.startsWith("ApiKey ") || cabecera.length() > 200) {
            return denegar("falta la llave");
        }
        String h = hash(cabecera.substring(7).strip());
        Socio s = null;
        for (var e : porHash.entrySet()) {
            // comparación en tiempo constante para no filtrar información por tiempos
            if (MessageDigest.isEqual(e.getKey().getBytes(StandardCharsets.UTF_8), h.getBytes(StandardCharsets.UTF_8))) {
                s = e.getValue();
            }
        }
        if (s == null || !s.activo()) {
            return denegar("llave inválida o revocada");
        }
        return new Respuesta(true, s.nombre(), s.alcances(), reloj.instant().plus(validez).toString(),
            Map.of("socio", s.nombre()), null);
    }

    private Respuesta denegar(String motivo) {
        return new Respuesta(false, null, List.of(), null, Map.of(), "ApiKey realm=\\"socios\\", error=\\"" + motivo + "\\"");
    }
}
'''
SDK = '''
import com.oracle.bmc.apigateway.DeploymentClient;
import com.oracle.bmc.apigateway.model.Deployment;
import com.oracle.bmc.apigateway.requests.ListDeploymentsRequest;
import java.util.List;

/** Adaptador del SDK: inventario de deployments activos (para un portal interno de APIs). */
public class ApisOci implements AutoCloseable {

    public record Api(String nombre, String prefijo, String endpoint) { }

    private final DeploymentClient cliente;
    private final String compartimentoId;

    public ApisOci(DeploymentClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public List<Api> activas() {
        return cliente.listDeployments(ListDeploymentsRequest.builder()
                .compartmentId(compartimentoId)
                .lifecycleState(Deployment.LifecycleState.Active)
                .build())
            .getDeploymentCollection().getItems().stream()
            .map(d -> new Api(d.getDisplayName(), d.getPathPrefix(), d.getEndpoint()))
            .toList();
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
import java.util.Map;

public class ServicioDeApis {

    private final ApisOci apis;
    // En producción los hashes vienen de un secreto de Vault, no del código.
    private final AutorizadorDeSocios autorizador = new AutorizadorDeSocios(
        Map.of(AutorizadorDeSocios.hash("demo-cafe-andino"),
            new AutorizadorDeSocios.Socio("cafe-andino", List.of("catalogo.leer"), true)),
        Clock.systemUTC(), Duration.ofMinutes(15));

    public ServicioDeApis(ApisOci apis) {
        this.apis = apis;
    }

    public record Peticion(String type, String token) { }

    public AutorizadorDeSocios.Respuesta autorizar(Peticion p) {
        return autorizador.autorizar(p.token());
    }

    public List<ApisOci.Api> inventario() {
        return apis.activas();
    }
}
'''
genlib.oci('oci/05-ingress-api/api-gateway', 'Ingress y API · API Gateway',
  'Dos piezas: la **lógica de un autorizador propio** (`CUSTOM_AUTHENTICATION`) para llaves de socios —guarda solo el SHA-256, compara en tiempo constante y devuelve la respuesta con la forma que espera el gateway (`active`, `principal`, `scope`, `expiresAt`, `context`)— y un **inventario de APIs** con `DeploymentClient`. En producción el autorizador se empaqueta como función (ver [Functions](../../04-compute/functions/README.md)); aquí se expone también por HTTP para probarlo.',
  [('apis.compartimento', 'ocid1.compartment.oc1..aaaa')],
  [('Autorizador (lógica pura)', AUT, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Apis', '/ingress/apis', 'ServicioDeApis', 'ApisOci',
  ['import com.oracle.bmc.apigateway.DeploymentClient;', 'import java.util.List;'],
  'return new ApisOci(DeploymentClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);',
  [dict(n='autorizar', v='POST', p='/autorizar', args=[('ServicioDeApis.Peticion', 'p', 'b')], ret='AutorizadorDeSocios.Respuesta', call='s.autorizar(p)', cpu=True),
   dict(n='inventario', v='GET', p='', args=[], ret='List<ApisOci.Api>', call='s.inventario()')],
  [('Listar deployments', '`Allow dynamic-group portal-apis to read api-deployments in compartment apis-prod`'),
   ('El gateway invoca la función autorizadora', "`Allow any-user to use functions-family in compartment apis-prod where ALL {request.principal.type = 'ApiGateway', request.resource.compartment.id = '<ocid>'}`")],
  ['No guardes llaves de socios en claro: solo su *hash* (y en Vault, no en el código).',
   'No compares llaves con `equals`: usa comparación en tiempo constante.',
   'No hagas que el autorizador consulte la base en cada petición: caché y `expiresAt`.',
   'No reenvíes el token completo al backend si basta con el principal.',
   'No dupliques en Java lo que el gateway ya valida (firma JWT), pero sí las reglas de negocio.'])
