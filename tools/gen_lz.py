import genlib
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
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.requests.ListVcnsRequest;
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.requests.ListCompartmentsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: todos los CIDR de VCN del tenancy (recorre compartimentos). */
public class RedesOci implements AutoCloseable {

    private final VirtualNetworkClient red;
    private final IdentityClient identidad;

    public RedesOci(VirtualNetworkClient red, IdentityClient identidad) {
        this.red = red;
        this.identidad = identidad;
    }

    public List<String> cidrsEnUso(String tenancyId) {
        var compartimentos = new ArrayList<String>(List.of(tenancyId));
        String pagina = null;
        do {
            var r = identidad.listCompartments(ListCompartmentsRequest.builder().compartmentId(tenancyId)
                .compartmentIdInSubtree(true).accessLevel(ListCompartmentsRequest.AccessLevel.Accessible).page(pagina).build());
            r.getItems().forEach(c -> compartimentos.add(c.getId()));
            pagina = r.getOpcNextPage();
        } while (pagina != null);
        var cidrs = new ArrayList<String>();
        for (String c : compartimentos) {
            String p = null;
            do {
                var r = red.listVcns(ListVcnsRequest.builder().compartmentId(c).page(p).build());
                r.getItems().forEach(v -> cidrs.addAll(v.getCidrBlocks()));
                p = r.getOpcNextPage();
            } while (p != null);
        }
        return cidrs;
    }

    @Override
    public void close() {
        red.close();
        identidad.close();
    }
}
'''
SERV = '''
import java.util.ArrayList;
import java.util.List;

public class ServicioDeLandingZone {

    public record Propuesta(String cidr, List<String> enUso) { }

    private final RedesOci redes;
    private final PlanificadorDeCidr planificador = new PlanificadorDeCidr();

    public ServicioDeLandingZone(RedesOci redes) {
        this.redes = redes;
    }

    /** redesLocales: rangos de oficinas o centros de datos conectados (no visibles como VCN). */
    public Propuesta proponer(String tenancyId, List<String> redesLocales) {
        var enUso = new ArrayList<>(redes.cidrsEnUso(tenancyId));
        enUso.addAll(redesLocales);
        String cidr = planificador.proponer("10.0.0.0/8", 16, enUso)
            .orElseThrow(() -> new IllegalStateException("no quedan /16 libres en 10.0.0.0/8"));
        return new Propuesta(cidr, enUso);
    }

    public List<String> verificarSolapes(String tenancyId) {
        return planificador.solapes(redes.cidrsEnUso(tenancyId));
    }
}
'''
genlib.oci('oci/11-casos-integrados/landing-zone', 'Caso integrado · Landing zone',
  'El **planificador de direcciones** de la landing zone: recorre todos los compartimentos y lee los CIDR de cada VCN (`IdentityClient` + `VirtualNetworkClient.listVcns`, paginando), suma las redes locales conectadas y propone el primer /16 libre de `10.0.0.0/8`; el verificador reporta solapes existentes. La propuesta alimenta `cidr_unidad` del Terraform del caso.',
  [],
  [('Planificador de CIDR (lógica pura)', PLAN, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'LandingZone', '/casos/landing', 'ServicioDeLandingZone', 'RedesOci',
  ['import com.oracle.bmc.core.VirtualNetworkClient;', 'import com.oracle.bmc.identity.IdentityClient;', 'import java.util.List;'],
  'var r = Region.fromRegionId(region);\nreturn new RedesOci(VirtualNetworkClient.builder().region(r).build(auth), IdentityClient.builder().region(r).build(auth));',
  [dict(n='proponer', v='POST', p='/cidr', args=[('String', 'tenancy', 'q'), ('List<String>', 'locales', 'b')], ret='ServicioDeLandingZone.Propuesta', call='s.proponer(tenancy, locales)'),
   dict(n='solapes', v='GET', p='/solapes', args=[('String', 'tenancy', 'q')], ret='List<String>', call='s.verificarSolapes(tenancy)')],
  [('Listar compartimentos', '`Allow dynamic-group plataforma to inspect compartments in tenancy`'),
   ('Listar VCN', '`Allow dynamic-group plataforma to read virtual-network-family in tenancy`')],
  ['No olvides las redes locales conectadas por VPN/FastConnect: no aparecen como VCN.',
   'No uses solo la región actual si hay VCN en otras regiones conectadas: consulta cada región.',
   'No apliques la landing desde la app: la propuesta va al pipeline de Terraform.'])
