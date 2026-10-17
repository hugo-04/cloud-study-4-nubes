import ggen
AUD = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Audita VMs: IP externa, cuenta por defecto, Shielded VM, etiquetas obligatorias, protección de borrado. Puro. */
public class AuditorDeVms {

    public record Vm(String nombre, String zona, String estado, boolean ipExterna, String cuenta, boolean arranqueSeguro,
                     Map<String, String> etiquetas, boolean proteccionBorrado) { }

    public record Hallazgo(String vm, String severidad, String mensaje) { }

    private final Set<String> etiquetasObligatorias;

    public AuditorDeVms(Set<String> etiquetasObligatorias) {
        this.etiquetasObligatorias = Set.copyOf(etiquetasObligatorias);
    }

    public List<Hallazgo> auditar(List<Vm> vms) {
        var h = new ArrayList<Hallazgo>();
        for (Vm v : vms) {
            if (v.ipExterna()) {
                h.add(new Hallazgo(v.nombre(), "ALTA", "tiene IP externa"));
            }
            if (v.cuenta() != null && v.cuenta().endsWith("-compute@developer.gserviceaccount.com")) {
                h.add(new Hallazgo(v.nombre(), "ALTA", "usa la cuenta de servicio por defecto de Compute"));
            }
            if (!v.arranqueSeguro()) {
                h.add(new Hallazgo(v.nombre(), "MEDIA", "sin arranque seguro (Shielded VM)"));
            }
            for (String e : etiquetasObligatorias) {
                if (!v.etiquetas().containsKey(e)) {
                    h.add(new Hallazgo(v.nombre(), "BAJA", "falta la etiqueta " + e));
                }
            }
            if ("TERMINATED".equals(v.estado())) {
                h.add(new Hallazgo(v.nombre(), "BAJA", "detenida: sigue cobrando discos e IPs"));
            }
        }
        return h;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.InstancesClient;
import com.google.cloud.compute.v1.InstancesSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Adaptador: todas las VMs del proyecto en todas las zonas. */
public class VmsGcp implements AutoCloseable {

    private final InstancesClient cliente;
    private final String proyecto;

    public VmsGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = InstancesClient.create(InstancesSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeVms.Vm> todas() {
        var out = new ArrayList<AuditorDeVms.Vm>();
        for (var zona : cliente.aggregatedList(proyecto).iterateAll()) {
            for (var i : zona.getValue().getInstancesList()) {
                boolean ipExt = i.getNetworkInterfacesList().stream().anyMatch(n -> n.getAccessConfigsCount() > 0);
                String cuenta = i.getServiceAccountsList().isEmpty() ? null : i.getServiceAccountsList().get(0).getEmail();
                boolean seguro = i.hasShieldedInstanceConfig() && i.getShieldedInstanceConfig().getEnableSecureBoot();
                out.add(new AuditorDeVms.Vm(i.getName(), zona.getKey(), i.getStatus(), ipExt, cuenta, seguro,
                    Map.copyOf(i.getLabelsMap()), i.getDeletionProtection()));
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
import java.util.Set;

public class ServicioDeVms {

    private final VmsGcp vms;
    private final AuditorDeVms auditor = new AuditorDeVms(Set.of("centro_costo", "entorno"));

    public ServicioDeVms(VmsGcp vms) {
        this.vms = vms;
    }

    public List<AuditorDeVms.Hallazgo> auditar() {
        return auditor.auditar(vms.todas());
    }
}
'''
ggen.gcp('gcp/04-compute/compute-engine', 'Compute · Compute Engine',
  'Un **auditor de VMs**: recorre todas las zonas con `InstancesClient.aggregatedList` y marca VMs con IP externa, con la cuenta de servicio por defecto de Compute, sin arranque seguro, sin las etiquetas obligatorias o detenidas (que siguen cobrando discos e IPs).',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Vms', '/compute/vms', 'ServicioDeVms', 'VmsGcp', ['import java.util.List;'],
  'return new VmsGcp(cred, proyecto);',
  [dict(n='auditar', v='GET', p='/auditoria', args=[], ret='List<AuditorDeVms.Hallazgo>', call='s.auditar()')],
  [('Listar VMs', '`roles/compute.viewer`')],
  ['No corrijas VMs desde la app: reporta y corrige la plantilla.',
   'No leas metadatos con secretos: los scripts de inicio no son un cofre.',
   'No crees un cliente por llamada.'])
