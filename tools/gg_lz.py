import ggen
PLAN = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/** Planificador de direcciones: propone el primer bloque libre del tamaño pedido dentro de un rango. Puro. */
public class PlanificadorDeCidr {

    public record Bloque(long inicio, int prefijo) {
        public long fin() {
            return inicio + (1L << (32 - prefijo)) - 1;
        }

        public boolean solapa(Bloque o) {
            return inicio <= o.fin() && o.inicio() <= fin();
        }

        public static Bloque de(String cidr) {
            String[] p = cidr.split("/");
            String[] o = p[0].split("\\\\.");
            if (o.length != 4) {
                throw new IllegalArgumentException("CIDR inválido: " + cidr);
            }
            long ip = 0;
            for (String x : o) {
                int v = Integer.parseInt(x);
                if (v < 0 || v > 255) {
                    throw new IllegalArgumentException("CIDR inválido: " + cidr);
                }
                ip = (ip << 8) | v;
            }
            int pre = Integer.parseInt(p[1]);
            long mascara = pre == 0 ? 0 : (0xFFFFFFFFL << (32 - pre)) & 0xFFFFFFFFL;
            return new Bloque(ip & mascara, pre);
        }

        @Override
        public String toString() {
            return ((inicio >> 24) & 255) + "." + ((inicio >> 16) & 255) + "." + ((inicio >> 8) & 255) + "." + (inicio & 255) + "/" + prefijo;
        }
    }

    public Optional<String> proponer(String rangoPadre, int prefijo, List<String> ocupados) {
        Bloque padre = Bloque.de(rangoPadre);
        if (prefijo < padre.prefijo() || prefijo > 28) {
            throw new IllegalArgumentException("prefijo fuera de rango");
        }
        List<Bloque> usados = new ArrayList<>(ocupados.stream().map(Bloque::de).toList());
        long paso = 1L << (32 - prefijo);
        for (long ini = padre.inicio(); ini + paso - 1 <= padre.fin(); ini += paso) {
            Bloque candidato = new Bloque(ini, prefijo);
            if (usados.stream().noneMatch(candidato::solapa)) {
                return Optional.of(candidato.toString());
            }
        }
        return Optional.empty();
    }

    /** Pares solapados entre los rangos dados (para el verificador). */
    public List<String> solapes(List<String> cidrs) {
        var out = new ArrayList<String>();
        for (int i = 0; i < cidrs.size(); i++) {
            for (int j = i + 1; j < cidrs.size(); j++) {
                if (Bloque.de(cidrs.get(i)).solapa(Bloque.de(cidrs.get(j)))) {
                    out.add(cidrs.get(i) + " ∩ " + cidrs.get(j));
                }
            }
        }
        return out;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: rangos primarios y secundarios de todas las subredes de los proyectos host. */
public class RedesGcp implements AutoCloseable {

    private final SubnetworksClient subredes;

    public RedesGcp(GoogleCredentials cred) {
        try {
            this.subredes = SubnetworksClient.create(SubnetworksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<String> cidrsEnUso(List<String> proyectosHost) {
        var out = new ArrayList<String>();
        for (String p : proyectosHost) {
            for (var region : subredes.aggregatedList(p).iterateAll()) {
                for (var s : region.getValue().getSubnetworksList()) {
                    out.add(s.getIpCidrRange());
                    s.getSecondaryIpRangesList().forEach(r -> out.add(r.getIpCidrRange()));   // pods y servicios de GKE
                }
            }
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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class ServicioDeLandingZone {

    public record Propuesta(String cidr, List<String> enUso) { }

    private final RedesGcp redes;
    private final PlanificadorDeCidr planificador = new PlanificadorDeCidr();

    public ServicioDeLandingZone(RedesGcp redes) {
        this.redes = redes;
    }

    private static List<String> lista(String csv) {
        return Arrays.stream(csv.split(",")).map(String::trim).filter(x -> !x.isEmpty()).toList();
    }

    /** hosts: proyectos host separados por coma; redesLocales: rangos de oficinas conectadas (no visibles en la VPC). */
    public Propuesta proponer(String hosts, List<String> redesLocales) {
        var enUso = new ArrayList<>(redes.cidrsEnUso(lista(hosts)));
        enUso.addAll(redesLocales);
        String cidr = planificador.proponer("10.0.0.0/8", 16, enUso)
            .orElseThrow(() -> new IllegalStateException("no quedan /16 libres en 10.0.0.0/8"));
        return new Propuesta(cidr, enUso);
    }

    public List<String> verificarSolapes(String hosts) {
        return planificador.solapes(redes.cidrsEnUso(lista(hosts)));
    }
}
'''
ggen.gcp('gcp/11-casos-integrados/landing-zone', 'Caso integrado · Landing zone',
  'El **planificador de direcciones** de la landing zone: lee las subredes de los proyectos host con `SubnetworksClient.aggregatedList` (todas las regiones), suma **rangos primarios y secundarios** (pods y servicios de GKE) y las redes locales conectadas, y propone el primer /16 libre de `10.0.0.0/8`; el verificador reporta solapes existentes. La propuesta alimenta `cidr_unidad` del Terraform del caso.',
  [],
  [('Planificador de CIDR (lógica pura)', PLAN, True), ('Adaptador de Compute', SDK, True), ('Servicio', SERV, True)],
  'LandingZone', '/plataforma/landing-zone', 'ServicioDeLandingZone', 'RedesGcp', [],
  'return new RedesGcp(cred);',
  [dict(n='proponer', v='POST', p='/cidr', args=[('String', 'hosts', 'q'), ('java.util.List<String>', 'redesLocales', 'b')], ret='ServicioDeLandingZone.Propuesta', call='s.proponer(hosts, redesLocales)'),
   dict(n='solapes', v='GET', p='/solapes', args=[('String', 'hosts', 'q')], ret='java.util.List<String>', call='s.verificarSolapes(hosts)')],
  [('Leer subredes', '`roles/compute.networkViewer` en los proyectos host')],
  ['No olvides los rangos secundarios.',
   'No asumas que la VPC muestra todo: pide las redes locales.',
   'No apliques la propuesta sin el `plan` revisado.',
   'No uses la SA del pipeline para leer.'])
