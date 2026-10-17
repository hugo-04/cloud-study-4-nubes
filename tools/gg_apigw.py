import ggen
CLA = '''
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;
import java.util.regex.Pattern;

/**
 * Lee las claims que API Gateway reenvía en X-Apigateway-Api-Userinfo (JSON en base64url) y aplica reglas de negocio.
 * Puro. La firma ya la validó el gateway: confía en la cabecera SOLO si el servicio es invocable únicamente por el gateway.
 */
public class ClaimsDelGateway {

    public record Usuario(String sub, String email, List<String> alcances) { }

    private static final Pattern CAMPO = Pattern.compile("\\"(sub|email|scope)\\"\\\\s*:\\\\s*\\"([^\\"]{0,512})\\"");

    public static Optional<Usuario> leer(String cabecera) {
        if (cabecera == null || cabecera.isBlank() || cabecera.length() > 8192) {
            return Optional.empty();
        }
        String json;
        try {
            json = new String(Base64.getUrlDecoder().decode(cabecera.strip()), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
        Map<String, String> c = new TreeMap<>();
        var m = CAMPO.matcher(json);
        while (m.find()) {
            c.put(m.group(1), m.group(2));
        }
        if (!c.containsKey("sub")) {
            return Optional.empty();
        }
        var alcances = c.getOrDefault("scope", "").isBlank() ? List.<String>of() : List.of(c.get("scope").split(" "));
        return Optional.of(new Usuario(c.get("sub"), c.get("email"), alcances));
    }

    /** Regla de negocio que el gateway no conoce: solo el dueño (o soporte) ve el pedido. */
    public static boolean puedeVerPedido(Usuario u, String duenioDelPedido) {
        return u.sub().equals(duenioDelPedido) || u.alcances().contains("pedidos.soporte");
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.apigateway.v1.ApiGatewayServiceClient;
import com.google.cloud.apigateway.v1.ApiGatewayServiceSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: inventario de gateways (todas las ubicaciones) con su configuración activa. */
public class GatewaysGcp implements AutoCloseable {

    public record Gateway(String nombre, String config, String host, String estado) { }

    private final ApiGatewayServiceClient cliente;
    private final String proyecto;

    public GatewaysGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = ApiGatewayServiceClient.create(ApiGatewayServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Gateway> todos() {
        var out = new ArrayList<Gateway>();
        for (var g : cliente.listGateways("projects/" + proyecto + "/locations/-").iterateAll()) {
            out.add(new Gateway(g.getName(), g.getApiConfig(), g.getDefaultHostname(), g.getState().name()));
        }
        return out;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDePedidosApi {

    public record Respuesta(boolean permitido, String usuario) { }

    private final GatewaysGcp gateways;

    public ServicioDePedidosApi(GatewaysGcp gateways) {
        this.gateways = gateways;
    }

    public Respuesta verPedido(String userinfo, String duenio) {
        return ClaimsDelGateway.leer(userinfo)
            .map(u -> new Respuesta(ClaimsDelGateway.puedeVerPedido(u, duenio), u.sub()))
            .orElse(new Respuesta(false, null));
    }

    public List<GatewaysGcp.Gateway> inventario() {
        return gateways.todos();
    }
}
'''
ggen.gcp('gcp/05-ingress-api/api-gateway', 'Ingress y API · API Gateway',
  'En el backend: leer las **claims que reenvía el gateway** en `X-Apigateway-Api-Userinfo` (JSON en base64url), sin volver a validar la firma, y aplicar la **regla de negocio** que el gateway no conoce (solo el dueño ve su pedido). Además, un **inventario de gateways** con `ApiGatewayServiceClient.listGateways`. En el ejemplo la cabecera llega como parámetro para poder probarlo; en la app real se lee con `@RequestHeader`/`@HeaderParam`.',
  [],
  [('Claims del gateway (lógica pura)', CLA, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'PedidosApi', '/ingress/api', 'ServicioDePedidosApi', 'GatewaysGcp', ['import java.util.List;'],
  'return new GatewaysGcp(cred, proyecto);',
  [dict(n='verPedido', v='GET', p='/pedidos/permiso', args=[('String', 'userinfo', 'q'), ('String', 'duenio', 'q')], ret='ServicioDePedidosApi.Respuesta', call='s.verPedido(userinfo, duenio)', cpu=True),
   dict(n='inventario', v='GET', p='/gateways', args=[], ret='List<GatewaysGcp.Gateway>', call='s.inventario()')],
  [('Listar gateways', '`roles/apigateway.viewer`'), ('El gateway invoca el backend', '`roles/run.invoker` a la cuenta del gateway sobre el servicio')],
  ['No confíes en `X-Apigateway-Api-Userinfo` si tu servicio es invocable por otros además del gateway.',
   'No reemplaces la autorización de negocio por la autenticación del gateway.',
   'No registres el JWT ni la cabecera completa.'])
