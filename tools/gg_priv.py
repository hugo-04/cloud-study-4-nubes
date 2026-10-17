import ggen
VER = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Verifica que el camino privado a las APIs de Google esté completo. Puro. */
public class VerificadorDeAccesoPrivado {

    public enum Modo { PGA, PSC }

    public record Subred(String nombre, boolean pga) { }

    /** zonas: nombre DNS de la zona (con punto final) -> registros "nombre TIPO datos". */
    public record Hallazgo(String severidad, String mensaje) { }

    public List<Hallazgo> verificar(Modo modo, String ipEndpoint, List<Subred> subredes, Map<String, List<String>> zonas) {
        var h = new ArrayList<Hallazgo>();
        subredes.stream().filter(s -> !s.pga()).forEach(s ->
            h.add(new Hallazgo(modo == Modo.PGA ? "ALTA" : "BAJA", "subred " + s.nombre() + " sin Private Google Access")));
        if (modo == Modo.PSC) {
            var registros = zonas.get("googleapis.com.");
            if (registros == null) {
                h.add(new Hallazgo("ALTA", "no hay zona privada googleapis.com.: el endpoint PSC no se usará"));
            } else if (registros.stream().noneMatch(r -> r.startsWith("*.googleapis.com. A") && r.contains(ipEndpoint))) {
                h.add(new Hallazgo("ALTA", "la zona googleapis.com. no apunta *.googleapis.com al endpoint " + ipEndpoint));
            }
        }
        return h;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import com.google.cloud.dns.Dns;
import com.google.cloud.dns.DnsOptions;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Adaptador: subredes de una red (PGA) y zonas DNS del proyecto con sus registros. */
public class AccesoPrivadoGcp implements AutoCloseable {

    private final SubnetworksClient subredes;
    private final Dns dns;
    private final String proyecto;

    public AccesoPrivadoGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.subredes = SubnetworksClient.create(SubnetworksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.dns = DnsOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.proyecto = proyecto;
    }

    public List<VerificadorDeAccesoPrivado.Subred> subredes(String red) {
        var out = new ArrayList<VerificadorDeAccesoPrivado.Subred>();
        for (var e : subredes.aggregatedList(proyecto).iterateAll()) {
            e.getValue().getSubnetworksList().stream().filter(s -> s.getNetwork().endsWith("/" + red))
                .forEach(s -> out.add(new VerificadorDeAccesoPrivado.Subred(s.getName(), s.getPrivateIpGoogleAccess())));
        }
        return out;
    }

    public Map<String, List<String>> zonas() {
        var out = new HashMap<String, List<String>>();
        for (var z : dns.listZones().iterateAll()) {
            var regs = new ArrayList<String>();
            for (var r : dns.listRecordSets(z.getName()).iterateAll()) {
                regs.add(r.getName() + " " + r.getType() + " " + String.join(",", r.getRecords()));
            }
            out.put(z.getDnsName(), regs);
        }
        return out;
    }

    @Override
    public void close() {
        subredes.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeAccesoPrivado {

    private final AccesoPrivadoGcp gcp;
    private final VerificadorDeAccesoPrivado verificador = new VerificadorDeAccesoPrivado();

    public ServicioDeAccesoPrivado(AccesoPrivadoGcp gcp) {
        this.gcp = gcp;
    }

    public List<VerificadorDeAccesoPrivado.Hallazgo> verificar(String red, VerificadorDeAccesoPrivado.Modo modo, String ip) {
        return verificador.verificar(modo, ip, gcp.subredes(red), gcp.zonas());
    }
}
'''
ggen.gcp('gcp/01-red/acceso-privado', 'Red · Acceso privado',
  'Un **verificador del camino privado** a las APIs: con `SubnetworksClient` revisa Private Google Access en cada subred de la red, y con la biblioteca de Cloud DNS (`Dns.listZones` / `listRecordSets`) comprueba que, si usas un endpoint PSC, exista la zona privada `googleapis.com.` con `*.googleapis.com` apuntando a la IP del endpoint.',
  [],
  [('Verificador (lógica pura)', VER, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'AccesoPrivado', '/red/acceso-privado', 'ServicioDeAccesoPrivado', 'AccesoPrivadoGcp', ['import java.util.List;'],
  'return new AccesoPrivadoGcp(cred, proyecto);',
  [dict(n='verificar', v='GET', p='/verificacion', args=[('String', 'red', 'q'), ('VerificadorDeAccesoPrivado.Modo', 'modo', 'q'), ('String', 'ip', 'q')], ret='List<VerificadorDeAccesoPrivado.Hallazgo>', call='s.verificar(red, modo, ip)')],
  [('Leer subredes', '`roles/compute.networkViewer`'), ('Leer zonas y registros', '`roles/dns.reader`')],
  ['No asumas que el camino privado da permisos: cada API sigue pidiendo su rol.',
   'No mezcles en la misma red PGA con dominios públicos y una zona privada a medias.',
   'No pruebes solo desde tu laptop: la resolución se comprueba desde la VM o el pod.'])
