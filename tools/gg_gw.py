import ggen
RES = '''
import java.util.List;
import java.util.Optional;

/**
 * IP real del cliente detrás del balanceador de aplicación de Google.
 * El balanceador AGREGA «<ip-cliente>, <ip-balanceador>» al final de X-Forwarded-For; lo anterior lo pudo escribir el cliente.
 * Con N proxies propios adicionales delante de la app (dentro de tu red), se saltan también. Puro.
 */
public final class IpDelCliente {

    private IpDelCliente() { }

    public static Optional<String> resolver(String xForwardedFor, int proxiesPropiosDetras) {
        if (xForwardedFor == null || xForwardedFor.isBlank()) {
            return Optional.empty();
        }
        List<String> saltos = List.of(xForwardedFor.split(",")).stream().map(String::strip).toList();
        int indice = saltos.size() - 2 - proxiesPropiosDetras; // último = balanceador; penúltimo = cliente
        if (indice < 0) {
            return Optional.empty();
        }
        String ip = saltos.get(indice);
        return ip.matches("[0-9a-fA-F:.]{3,45}") ? Optional.of(ip) : Optional.empty();
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.GlobalForwardingRulesClient;
import com.google.cloud.compute.v1.GlobalForwardingRulesSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: reglas de reenvío globales creadas por el controlador de Gateway (nombre «gkegw…»). */
public class GatewayGcp implements AutoCloseable {

    public record Regla(String nombre, String ip, String puertos, String esquema) { }

    private final GlobalForwardingRulesClient cliente;
    private final String proyecto;

    public GatewayGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = GlobalForwardingRulesClient.create(GlobalForwardingRulesSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Regla> deGateways(String filtroNombre) {
        var out = new ArrayList<Regla>();
        for (var f : cliente.list(proyecto).iterateAll()) {
            if (f.getName().startsWith("gkegw") && f.getName().contains(filtroNombre)) {
                out.add(new Regla(f.getName(), f.getIPAddress(), f.getPortRange(), f.getLoadBalancingScheme()));
            }
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

public class ServicioDeEntradaGke {

    private final GatewayGcp gateway;

    public ServicioDeEntradaGke(GatewayGcp gateway) {
        this.gateway = gateway;
    }

    public String ipCliente(String xff) {
        return IpDelCliente.resolver(xff, 0).orElse("desconocida");
    }

    public List<GatewayGcp.Regla> reglas(String filtro) {
        return gateway.deGateways(filtro);
    }
}
'''
ggen.gcp('gcp/05-ingress-api/ingress-gke', 'Ingress y API · Entrada a GKE',
  'Lo que la app necesita detrás del Gateway: **la IP real del cliente** (el balanceador de Google agrega «cliente, balanceador» al final de `X-Forwarded-For`, así que el cliente es el **penúltimo** valor; lo anterior pudo inventarlo el cliente) y, para inventario, las **reglas de reenvío** que creó el controlador (`GlobalForwardingRulesClient`, nombres `gkegw…`).',
  [],
  [('IP del cliente (lógica pura)', RES, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'EntradaGke', '/ingress/gke', 'ServicioDeEntradaGke', 'GatewayGcp', ['import java.util.List;'],
  'return new GatewayGcp(cred, proyecto);',
  [dict(n='ipCliente', v='GET', p='/ip', args=[('String', 'xff', 'q')], ret='String', call='s.ipCliente(xff)', cpu=True),
   dict(n='reglas', v='GET', p='/reglas', args=[('String', 'filtro', 'q')], ret='List<GatewayGcp.Regla>', call='s.reglas(filtro)')],
  [('Listar reglas de reenvío', '`roles/compute.viewer`')],
  ['No tomes el primer valor de `X-Forwarded-For`.',
   'No asumas el formato si hay otros proxies (CDN externo, malla): ajusta `proxiesPropiosDetras`.',
   'No crees balanceadores desde la app: los crea el controlador a partir del Gateway.'])
