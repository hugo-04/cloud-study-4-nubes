import genlib
RES = '''
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.List;

/**
 * Obtiene la IP real del cliente detrás del LB/Ingress. Recorre X-Forwarded-For de derecha a izquierda
 * y se detiene en la primera IP que NO es un proxy de confianza. Puro (solo IPv4 en este ejemplo).
 */
public class ResolutorDeIpCliente {

    private record Rango(long red, long mascara) {
        boolean contiene(long ip) {
            return (ip & mascara) == red;
        }
    }

    private final List<Rango> confiables;

    public ResolutorDeIpCliente(List<String> cidrsConfiables) {
        this.confiables = cidrsConfiables.stream().map(ResolutorDeIpCliente::rango).toList();
    }

    public String resolver(String ipSocket, String xForwardedFor) {
        if (!esConfiable(ipSocket) || xForwardedFor == null || xForwardedFor.isBlank()) {
            return ipSocket; // la petición no vino por nuestro proxy: no se cree la cabecera
        }
        String[] saltos = xForwardedFor.split(",");
        for (int i = saltos.length - 1; i >= 0; i--) {
            String ip = saltos[i].strip();
            if (!ip.matches("\\\\d{1,3}(\\\\.\\\\d{1,3}){3}")) {
                return ipSocket; // cabecera manipulada
            }
            if (!esConfiable(ip)) {
                return ip;
            }
        }
        return saltos[0].strip();
    }

    private boolean esConfiable(String ip) {
        long v = aLong(ip);
        return confiables.stream().anyMatch(r -> r.contiene(v));
    }

    private static Rango rango(String cidr) {
        String[] p = cidr.split("/");
        int bits = Integer.parseInt(p[1]);
        long mascara = bits == 0 ? 0 : (0xFFFFFFFFL << (32 - bits)) & 0xFFFFFFFFL;
        return new Rango(aLong(p[0]) & mascara, mascara);
    }

    private static long aLong(String ip) {
        try {
            byte[] b = InetAddress.getByName(ip).getAddress();
            return ((b[0] & 0xFFL) << 24) | ((b[1] & 0xFFL) << 16) | ((b[2] & 0xFFL) << 8) | (b[3] & 0xFFL);
        } catch (UnknownHostException e) {
            throw new IllegalArgumentException("IP inválida: " + ip, e);
        }
    }
}
'''
SDK = '''
import com.oracle.bmc.loadbalancer.LoadBalancerClient;
import com.oracle.bmc.loadbalancer.model.LoadBalancer;
import com.oracle.bmc.loadbalancer.requests.GetLoadBalancerHealthRequest;
import com.oracle.bmc.loadbalancer.requests.ListLoadBalancersRequest;
import java.util.Optional;

/** Adaptador del SDK: encuentra el LB que creó el Ingress (por nombre) y lee su IP y salud. */
public class IngressOci implements AutoCloseable {

    public record InfoLb(String nombre, String ip, String salud) { }

    private final LoadBalancerClient cliente;
    private final String compartimentoId;

    public IngressOci(LoadBalancerClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public Optional<InfoLb> buscar(String nombre) {
        return cliente.listLoadBalancers(ListLoadBalancersRequest.builder()
                .compartmentId(compartimentoId).displayName(nombre)
                .lifecycleState(LoadBalancer.LifecycleState.Active).build())
            .getItems().stream().findFirst()
            .map(lb -> new InfoLb(lb.getDisplayName(),
                lb.getIpAddresses().isEmpty() ? null : lb.getIpAddresses().get(0).getIpAddress(),
                cliente.getLoadBalancerHealth(GetLoadBalancerHealthRequest.builder().loadBalancerId(lb.getId()).build())
                    .getLoadBalancerHealth().getStatus().getValue()));
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeEntrada {

    private final IngressOci ingress;
    // Subred del LB del Ingress (los únicos proxies en los que se confía)
    private final ResolutorDeIpCliente resolutor = new ResolutorDeIpCliente(List.of("10.0.1.0/24"));

    public ServicioDeEntrada(IngressOci ingress) {
        this.ingress = ingress;
    }

    public String ipCliente(String ipSocket, String xff) {
        return resolutor.resolver(ipSocket, xff);
    }

    public IngressOci.InfoLb lb(String nombre) {
        return ingress.buscar(nombre).orElseThrow(() -> new IllegalArgumentException("no existe el LB " + nombre));
    }
}
'''
genlib.oci('oci/05-ingress-api/ingress-oke', 'Ingress y API · Ingress en OKE',
  'Lo que la app necesita detrás de un Ingress: un **resolutor de la IP real del cliente** que solo cree en `X-Forwarded-For` cuando la petición viene de la subred del LB, y un adaptador que **encuentra el LB creado por el Ingress** y reporta su IP y salud. En Spring Boot y Quarkus recuerda además el apagado ordenado (`server.shutdown=graceful` / `quarkus.shutdown.timeout`).',
  [('entrada.compartimento', 'ocid1.compartment.oc1..aaaa')],
  [('Resolutor de IP (lógica pura)', RES, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Entrada', '/ingress/entrada', 'ServicioDeEntrada', 'IngressOci',
  ['import com.oracle.bmc.loadbalancer.LoadBalancerClient;'],
  'return new IngressOci(LoadBalancerClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);',
  [dict(n='ipCliente', v='GET', p='/ip', args=[('String', 'socket', 'q'), ('String', 'xff', 'q')], ret='String', call='s.ipCliente(socket, xff)', cpu=True),
   dict(n='lb', v='GET', p='/lb/{nombre}', args=[('String', 'nombre', 'p')], ret='IngressOci.InfoLb', call='s.lb(nombre)')],
  [('Buscar el LB y su salud', '`Allow dynamic-group plataforma to read load-balancers in compartment red-prod`'),
   ('El controlador crea el LB', '`Allow any-user to manage load-balancers in compartment red-prod where request.principal.type = \'cluster\'` *(o la identidad del controlador nativo; verifica)*')],
  ['No tomes el primer valor de `X-Forwarded-For` sin validar quién lo envió: el cliente puede falsificarlo.',
   'No ignores `SIGTERM`: activa el apagado ordenado del framework.',
   'No respondas *readiness* OK antes de que la app termine de calentar.',
   'No crees `Service LoadBalancer` desde el código de la app.'])
