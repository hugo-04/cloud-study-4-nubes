import ggen
AUD = '''
import java.util.ArrayList;
import java.util.List;

/** Audita subredes: solapes entre todos los rangos, Private Google Access y flow logs. Puro. */
public class AuditorDeSubredes {

    public record Subred(String nombre, String region, String primario, List<String> secundarios, boolean pga, boolean flowLogs) { }

    public record Hallazgo(String subred, String severidad, String mensaje) { }

    record Rango(String duenio, long inicio, long fin) { }

    static Rango rango(String duenio, String cidr) {
        String[] p = cidr.split("/");
        long ip = 0;
        for (String o : p[0].split("\\\\.")) {
            ip = (ip << 8) | Integer.parseInt(o);
        }
        int pre = Integer.parseInt(p[1]);
        long tam = 1L << (32 - pre);
        long ini = ip & ~(tam - 1) & 0xFFFFFFFFL;
        return new Rango(duenio, ini, ini + tam - 1);
    }

    public List<Hallazgo> auditar(List<Subred> subredes) {
        var h = new ArrayList<Hallazgo>();
        var rangos = new ArrayList<Rango>();
        for (Subred s : subredes) {
            rangos.add(rango(s.nombre() + "@" + s.region(), s.primario()));
            s.secundarios().forEach(c -> rangos.add(rango(s.nombre() + "@" + s.region() + " (secundario)", c)));
            if (!s.pga()) {
                h.add(new Hallazgo(s.nombre(), "MEDIA", "sin Private Google Access"));
            }
            if (!s.flowLogs()) {
                h.add(new Hallazgo(s.nombre(), "BAJA", "sin flow logs"));
            }
        }
        for (int i = 0; i < rangos.size(); i++) {
            for (int j = i + 1; j < rangos.size(); j++) {
                var a = rangos.get(i);
                var b = rangos.get(j);
                if (a.inicio() <= b.fin() && b.inicio() <= a.fin()) {
                    h.add(new Hallazgo(a.duenio(), "ALTA", "se solapa con " + b.duenio()));
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
import com.google.cloud.compute.v1.SubnetworkSecondaryRange;
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: todas las subredes del proyecto en todas las regiones (aggregatedList). */
public class SubredesGcp implements AutoCloseable {

    private final SubnetworksClient cliente;
    private final String proyecto;

    public SubredesGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = SubnetworksClient.create(SubnetworksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeSubredes.Subred> todas() {
        var out = new ArrayList<AuditorDeSubredes.Subred>();
        for (var entrada : cliente.aggregatedList(proyecto).iterateAll()) {
            for (var s : entrada.getValue().getSubnetworksList()) {
                out.add(new AuditorDeSubredes.Subred(s.getName(), s.getRegion().substring(s.getRegion().lastIndexOf('/') + 1),
                    s.getIpCidrRange(), s.getSecondaryIpRangesList().stream().map(SubnetworkSecondaryRange::getIpCidrRange).toList(),
                    s.getPrivateIpGoogleAccess(), s.hasLogConfig() && s.getLogConfig().getEnable()));
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

public class ServicioDeRed {

    private final SubredesGcp subredes;
    private final AuditorDeSubredes auditor = new AuditorDeSubredes();

    public ServicioDeRed(SubredesGcp subredes) {
        this.subredes = subredes;
    }

    public List<AuditorDeSubredes.Hallazgo> auditar() {
        return auditor.auditar(subredes.todas());
    }
}
'''
ggen.gcp('gcp/01-red/vpc-subredes', 'Red · VPC y subredes',
  'Un **auditor de subredes**: lee todas las subredes del proyecto en todas las regiones con `SubnetworksClient.aggregatedList` y marca solapes entre rangos primarios y secundarios, subredes sin Private Google Access y sin flow logs. Útil antes de emparejar redes o crear clústeres.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Red', '/red/subredes', 'ServicioDeRed', 'SubredesGcp', ['import java.util.List;'],
  'return new SubredesGcp(cred, proyecto);',
  [dict(n='auditar', v='GET', p='/auditoria', args=[], ret='List<AuditorDeSubredes.Hallazgo>', call='s.auditar()')],
  [('Listar subredes', '`roles/compute.networkViewer` en el proyecto host')],
  ['No crees un cliente por petición: son pesados (gRPC/HTTP); uno por aplicación y ciérralo al apagar.',
   'No uses llaves JSON para autenticar: ADC con la cuenta de servicio adjunta.',
   'No modifiques la red desde la app: eso es Terraform.'])
