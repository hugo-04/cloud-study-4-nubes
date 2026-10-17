import genlib
COMP = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/** Compara dos entornos del mismo componente: solo pueden diferir las variables permitidas. Puro. */
public class ComparadorDeEntornos {

    public record Entorno(String nombre, String versionTerraform, String drift, Map<String, String> variables) { }

    public record Diferencia(String tipo, String clave, String valorA, String valorB) { }

    private final Set<String> permitidas;

    public ComparadorDeEntornos(Set<String> permitidas) {
        this.permitidas = Set.copyOf(permitidas);
    }

    public List<Diferencia> comparar(Entorno a, Entorno b) {
        var out = new ArrayList<Diferencia>();
        if (!a.versionTerraform().equals(b.versionTerraform())) {
            out.add(new Diferencia("version-terraform", "-", a.versionTerraform(), b.versionTerraform()));
        }
        var claves = new TreeSet<String>();
        claves.addAll(a.variables().keySet());
        claves.addAll(b.variables().keySet());
        for (String k : claves) {
            if (permitidas.contains(k)) {
                continue;
            }
            String va = a.variables().get(k);
            String vb = b.variables().get(k);
            if (va == null || vb == null) {
                out.add(new Diferencia("variable-ausente", k, va, vb));
            } else if (!va.equals(vb)) {
                out.add(new Diferencia("variable-distinta", k, va, vb));
            }
        }
        for (Entorno e : List.of(a, b)) {
            if ("DRIFTED".equals(e.drift())) {
                out.add(new Diferencia("drift", e.nombre(), "cambios fuera de Terraform", null));
            }
        }
        return out;
    }
}
'''
SDK = '''
import com.oracle.bmc.resourcemanager.ResourceManagerClient;
import com.oracle.bmc.resourcemanager.requests.GetStackRequest;
import java.util.Map;

/** Adaptador del SDK: lee variables, versión de Terraform y estado de drift de un stack. */
public class StacksOci implements AutoCloseable {

    private final ResourceManagerClient cliente;

    public StacksOci(ResourceManagerClient cliente) {
        this.cliente = cliente;
    }

    public ComparadorDeEntornos.Entorno leer(String stackId) {
        var s = cliente.getStack(GetStackRequest.builder().stackId(stackId).build()).getStack();
        return new ComparadorDeEntornos.Entorno(s.getDisplayName(), s.getTerraformVersion(),
            s.getStackDriftStatus() == null ? "NOT_CHECKED" : s.getStackDriftStatus().getValue(),
            s.getVariables() == null ? Map.of() : s.getVariables());
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;
import java.util.Set;

public class ServicioDeEntornos {

    private final StacksOci stacks;
    // Lo único que puede variar entre prod y no-prod
    private final ComparadorDeEntornos comparador = new ComparadorDeEntornos(
        Set.of("entorno", "compartimento_id", "replicas", "ocpus", "memoria_gb", "vcn_id", "nsg_lb_id"));

    public ServicioDeEntornos(StacksOci stacks) {
        this.stacks = stacks;
    }

    public List<ComparadorDeEntornos.Diferencia> comparar(String stackNoProd, String stackProd) {
        return comparador.comparar(stacks.leer(stackNoProd), stacks.leer(stackProd));
    }
}
'''
genlib.oci('oci/10-terraform/modulos-y-entornos', 'Terraform · Módulos y entornos',
  'Un **comparador de entornos**: lee dos stacks de Resource Manager (no-prod y prod del mismo componente) con `ResourceManagerClient.getStack` y reporta diferencias de versión de Terraform, variables que difieren o faltan **fuera de la lista permitida** (tamaño, réplicas, IDs del entorno) y stacks con drift. Sirve como control antes de promover una versión.',
  [],
  [('Comparador (lógica pura)', COMP, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Entornos', '/terraform/entornos', 'ServicioDeEntornos', 'StacksOci',
  ['import com.oracle.bmc.resourcemanager.ResourceManagerClient;', 'import java.util.List;'],
  'return new StacksOci(ResourceManagerClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='comparar', v='GET', p='/comparacion', args=[('String', 'noProd', 'q'), ('String', 'prod', 'q')], ret='List<ComparadorDeEntornos.Diferencia>', call='s.comparar(noProd, prod)')],
  [('Leer stacks', '`Allow dynamic-group plataforma to read orm-stacks in compartment modalima`')],
  ['No expongas las variables de los stacks: pueden contener datos sensibles (márcalas como sensibles en Terraform).',
   'No lances `apply` desde una app de consulta.',
   'No compares entornos por nombre de stack: usa IDs y convenciones explícitas.'])
