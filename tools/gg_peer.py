import ggen
VER = '''
import java.util.ArrayList;
import java.util.List;

/** Verifica peerings: estado, coherencia de rutas personalizadas entre ambos lados y solapes. Puro. */
public class VerificadorDePeering {

    public record Peering(String red, String nombre, String redPar, String estado, boolean exporta, boolean importa) { }

    public record Hallazgo(String peering, String severidad, String mensaje) { }

    public List<Hallazgo> verificar(List<Peering> peerings, List<String> rangosLocales, List<String> rangosPar) {
        var h = new ArrayList<Hallazgo>();
        for (Peering p : peerings) {
            if (!"ACTIVE".equals(p.estado())) {
                h.add(new Hallazgo(p.nombre(), "ALTA", "estado " + p.estado() + ": falta el otro lado o hay conflicto"));
            }
            var inverso = peerings.stream().filter(q -> q.red().equals(p.redPar()) && q.redPar().equals(p.red())).findFirst();
            if (inverso.isPresent() && p.exporta() && !inverso.get().importa()) {
                h.add(new Hallazgo(p.nombre(), "MEDIA", "exporta rutas personalizadas pero el otro lado no las importa"));
            }
        }
        for (String a : rangosLocales) {
            for (String b : rangosPar) {
                if (solapan(a, b)) {
                    h.add(new Hallazgo("-", "ALTA", a + " se solapa con " + b));
                }
            }
        }
        return h;
    }

    static boolean solapan(String a, String b) {
        long[] x = limites(a);
        long[] y = limites(b);
        return x[0] <= y[1] && y[0] <= x[1];
    }

    static long[] limites(String cidr) {
        String[] p = cidr.split("/");
        long ip = 0;
        for (String o : p[0].split("\\\\.")) {
            ip = (ip << 8) | Integer.parseInt(o);
        }
        long tam = 1L << (32 - Integer.parseInt(p[1]));
        long ini = ip & ~(tam - 1) & 0xFFFFFFFFL;
        return new long[] {ini, ini + tam - 1};
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.NetworksClient;
import com.google.cloud.compute.v1.NetworksSettings;
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: peerings de una red y rangos de subred de un proyecto/red. */
public class PeeringGcp implements AutoCloseable {

    private final NetworksClient redes;
    private final SubnetworksClient subredes;

    public PeeringGcp(GoogleCredentials cred) {
        try {
            var cp = FixedCredentialsProvider.create(cred);
            this.redes = NetworksClient.create(NetworksSettings.newBuilder().setCredentialsProvider(cp).build());
            this.subredes = SubnetworksClient.create(SubnetworksSettings.newBuilder().setCredentialsProvider(cp).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<VerificadorDePeering.Peering> peerings(String proyecto, String red) {
        var n = redes.get(proyecto, red);
        return n.getPeeringsList().stream().map(p -> new VerificadorDePeering.Peering(n.getSelfLink(), p.getName(),
            p.getNetwork(), p.getState(), p.getExportCustomRoutes(), p.getImportCustomRoutes())).toList();
    }

    public List<String> rangos(String proyecto, String red) {
        var out = new ArrayList<String>();
        for (var e : subredes.aggregatedList(proyecto).iterateAll()) {
            e.getValue().getSubnetworksList().stream().filter(s -> s.getNetwork().endsWith("/" + red)).forEach(s -> {
                out.add(s.getIpCidrRange());
                s.getSecondaryIpRangesList().forEach(r -> out.add(r.getIpCidrRange()));
            });
        }
        return out;
    }

    @Override
    public void close() {
        redes.close();
        subredes.close();
    }
}
'''
SERV = '''
import java.util.ArrayList;
import java.util.List;

public class ServicioDePeering {

    public record Pedido(String proyecto, String red, String proyectoPar, String redPar) { }

    private final PeeringGcp gcp;
    private final VerificadorDePeering verificador = new VerificadorDePeering();

    public ServicioDePeering(PeeringGcp gcp) {
        this.gcp = gcp;
    }

    public List<VerificadorDePeering.Hallazgo> verificar(Pedido p) {
        var peerings = new ArrayList<VerificadorDePeering.Peering>(gcp.peerings(p.proyecto(), p.red()));
        List<String> rangosPar;
        try {
            peerings.addAll(gcp.peerings(p.proyectoPar(), p.redPar()));
            rangosPar = gcp.rangos(p.proyectoPar(), p.redPar());
        } catch (RuntimeException sinPermiso) {
            // no poder leer el otro lado es un hallazgo, no un «todo bien»
            var h = new ArrayList<>(verificador.verificar(peerings, List.of(), List.of()));
            h.add(new VerificadorDePeering.Hallazgo("-", "MEDIA", "no se pudo leer la red par: " + sinPermiso.getClass().getSimpleName()));
            return h;
        }
        return verificador.verificar(peerings, gcp.rangos(p.proyecto(), p.red()), rangosPar);
    }
}
'''
ggen.gcp('gcp/01-red/conectividad-hibrida', 'Red · Conectividad entre redes e híbrida',
  'Un **verificador de peering**: lee los peerings de ambos lados con `NetworksClient.get` y los rangos de subred (primarios y secundarios) con `SubnetworksClient.aggregatedList`; reporta peerings no activos, rutas personalizadas exportadas que el otro lado no importa y solapes de rangos. Si no puede leer la red par, lo dice.',
  [],
  [('Verificador (lógica pura)', VER, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Peering', '/red/peering', 'ServicioDePeering', 'PeeringGcp', ['import java.util.List;'],
  'return new PeeringGcp(cred);',
  [dict(n='verificar', v='POST', p='/verificacion', args=[('ServicioDePeering.Pedido', 'p', 'b')], ret='List<VerificadorDePeering.Hallazgo>', call='s.verificar(p)')],
  [('Leer redes y subredes de ambos proyectos', '`roles/compute.networkViewer` en ambos proyectos')],
  ['No trates un error de permisos al leer la red par como «sin hallazgos».',
   'No olvides los rangos secundarios (pods/servicios de GKE): también chocan.',
   'No crees peerings desde la app.'])
