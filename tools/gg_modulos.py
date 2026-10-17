import ggen
REG = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Reglas por entorno (las mismas que validan las variables del módulo) y comparación con lo desplegado:
 * sirve para detectar deriva hecha a mano en la consola. Puro.
 */
public final class ReglasDeEntorno {

    public record Esperado(String entorno, int minInstancias, int maxInstancias) { }

    public record Desplegado(String servicio, Map<String, String> labels, int minInstancias, int maxInstancias, String ingress) { }

    public record Hallazgo(String servicio, List<String> problemas) { }

    private static final Set<String> LABELS = Set.of("equipo", "entorno", "modulo");

    private ReglasDeEntorno() {
    }

    public static List<String> validar(Esperado e) {
        var p = new ArrayList<String>();
        if (!Set.of("dev", "staging", "prod").contains(e.entorno())) {
            p.add("entorno desconocido");
        }
        if ("prod".equals(e.entorno()) && e.minInstancias() < 1) {
            p.add("prod requiere min_instancias >= 1");
        }
        if (e.maxInstancias() < e.minInstancias()) {
            p.add("max < min");
        }
        if (!"prod".equals(e.entorno()) && e.maxInstancias() > 10) {
            p.add("no-prod limitado a 10 instancias (costo)");
        }
        return p;
    }

    public static Hallazgo comparar(Esperado e, Desplegado d) {
        var p = new ArrayList<String>(validar(e));
        for (String l : LABELS) {
            if (!d.labels().containsKey(l)) {
                p.add("falta label " + l + " (¿creado fuera del módulo?)");
            }
        }
        if (d.minInstancias() != e.minInstancias() || d.maxInstancias() != e.maxInstancias()) {
            p.add("deriva de escalado: desplegado " + d.minInstancias() + "-" + d.maxInstancias()
                + ", código " + e.minInstancias() + "-" + e.maxInstancias());
        }
        if ("INGRESS_TRAFFIC_ALL".equals(d.ingress())) {
            p.add("ingress abierto a Internet");
        }
        return new Hallazgo(d.servicio(), p);
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.run.v2.ServicesClient;
import com.google.cloud.run.v2.ServicesSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee los servicios de Cloud Run creados por el módulo y los resume. */
public class EntornoGcp implements AutoCloseable {

    private final ServicesClient cliente;
    private final String proyecto;
    private final String region;

    public EntornoGcp(GoogleCredentials cred, String proyecto, String region) {
        try {
            this.cliente = ServicesClient.create(ServicesSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
        this.region = region;
    }

    public List<ReglasDeEntorno.Desplegado> servicios() {
        var out = new ArrayList<ReglasDeEntorno.Desplegado>();
        for (var s : cliente.listServices("projects/" + proyecto + "/locations/" + region).iterateAll()) {
            var esc = s.getTemplate().getScaling();
            out.add(new ReglasDeEntorno.Desplegado(s.getName().substring(s.getName().lastIndexOf('/') + 1),
                s.getLabelsMap(), esc.getMinInstanceCount(), esc.getMaxInstanceCount(), s.getIngress().name()));
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
import java.util.Map;

public class ServicioDeEntornos {

    private final EntornoGcp gcp;

    public ServicioDeEntornos(EntornoGcp gcp) {
        this.gcp = gcp;
    }

    public List<String> validar(ReglasDeEntorno.Esperado e) {
        return ReglasDeEntorno.validar(e);
    }

    /** esperado: servicio → valores del código (en la práctica, leídos de los tfvars del entorno). */
    public List<ReglasDeEntorno.Hallazgo> deriva(Map<String, ReglasDeEntorno.Esperado> esperado) {
        return gcp.servicios().stream().filter(d -> esperado.containsKey(d.servicio()))
            .map(d -> ReglasDeEntorno.comparar(esperado.get(d.servicio()), d))
            .filter(h -> !h.problemas().isEmpty()).toList();
    }
}
'''
ggen.gcp('gcp/10-terraform/modulos-y-entornos', 'Terraform · Módulos y entornos',
  'Las reglas del módulo (prod con al menos una instancia, no-prod con tope de costo, labels obligatorios) se escriben **también** en Java puro para dos usos: validar los `tfvars` en el pipeline antes del `plan`, y comparar contra lo **desplegado** en Cloud Run (`ServicesClient.listServices`) para detectar **deriva** hecha a mano: escalado distinto, labels faltantes o ingress abierto.',
  [('entorno.region', 'southamerica-west1')],
  [('Reglas (lógica pura)', REG, True), ('Adaptador de Cloud Run', SDK, True), ('Servicio', SERV, True)],
  'Entornos', '/terraform/entornos', 'ServicioDeEntornos', 'EntornoGcp', [],
  'return new EntornoGcp(cred, proyecto, region);',
  [dict(n='validar', v='POST', p='/validacion', args=[('ReglasDeEntorno.Esperado', 'esperado', 'b')], ret='java.util.List<String>', call='s.validar(esperado)', cpu=True),
   dict(n='deriva', v='POST', p='/deriva', args=[('java.util.Map<String, ReglasDeEntorno.Esperado>', 'esperado', 'b')], ret='java.util.List<ReglasDeEntorno.Hallazgo>', call='s.deriva(esperado)')],
  [('Leer servicios', '`roles/run.viewer` en el proyecto del entorno')],
  ['No corrijas la deriva desde la app: corrige el código y aplica.',
   'No dupliques reglas sin pruebas que las mantengan iguales a las del módulo.',
   'No uses la SA de Terraform para leer.',
   'No compares contra prod con credenciales de dev.'])
