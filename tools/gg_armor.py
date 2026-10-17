import ggen
AUD = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Audita una política de Cloud Armor contra el mínimo de la empresa. Puro. */
public class AuditorDeArmor {

    public record Regla(int prioridad, String accion, boolean vistaPrevia, String expresion, boolean tasa) { }

    public record Hallazgo(String severidad, String mensaje) { }

    private final Set<String> conjuntosObligatorios;

    public AuditorDeArmor(Set<String> conjuntosObligatorios) {
        this.conjuntosObligatorios = Set.copyOf(conjuntosObligatorios);
    }

    public List<Hallazgo> auditar(List<Regla> reglas, boolean adaptativa) {
        var h = new ArrayList<Hallazgo>();
        for (String c : conjuntosObligatorios) {
            var regla = reglas.stream().filter(r -> r.expresion() != null && r.expresion().contains("'" + c)).findFirst();
            if (regla.isEmpty()) {
                h.add(new Hallazgo("ALTA", "falta el conjunto WAF " + c));
            } else if (regla.get().vistaPrevia()) {
                h.add(new Hallazgo("MEDIA", c + " en vista previa (no bloquea)"));
            }
        }
        if (reglas.stream().noneMatch(Regla::tasa)) {
            h.add(new Hallazgo("MEDIA", "sin limitación de tasa"));
        }
        var porDefecto = reglas.stream().filter(r -> r.prioridad() == Integer.MAX_VALUE).findFirst();
        reglas.stream()
            .filter(r -> r.accion().equals("allow") && r.prioridad() < 1000 && r.expresion() != null && r.expresion().contains("true"))
            .forEach(r -> h.add(new Hallazgo("ALTA", "regla allow " + r.prioridad() + " antes del WAF puede saltárselo")));
        if (porDefecto.isEmpty()) {
            h.add(new Hallazgo("BAJA", "no se encontró la regla por defecto"));
        }
        if (!adaptativa) {
            h.add(new Hallazgo("BAJA", "Adaptive Protection desactivado"));
        }
        return h;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.SecurityPoliciesClient;
import com.google.cloud.compute.v1.SecurityPoliciesSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador: lee la política y la convierte al modelo del auditor. */
public class ArmorGcp implements AutoCloseable {

    public record Politica(List<AuditorDeArmor.Regla> reglas, boolean adaptativa) { }

    private final SecurityPoliciesClient cliente;
    private final String proyecto;

    public ArmorGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = SecurityPoliciesClient.create(SecurityPoliciesSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public Politica leer(String nombre) {
        var p = cliente.get(proyecto, nombre);
        var reglas = p.getRulesList().stream().map(r -> new AuditorDeArmor.Regla(r.getPriority(), r.getAction(), r.getPreview(),
            r.getMatch().hasExpr() ? r.getMatch().getExpr().getExpression() : null, r.hasRateLimitOptions())).toList();
        boolean adaptativa = p.hasAdaptiveProtectionConfig()
            && p.getAdaptiveProtectionConfig().getLayer7DdosDefenseConfig().getEnable();
        return new Politica(reglas, adaptativa);
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

public class ServicioDeArmor {

    private final ArmorGcp armor;
    private final AuditorDeArmor auditor = new AuditorDeArmor(Set.of("sqli-", "xss-"));

    public ServicioDeArmor(ArmorGcp armor) {
        this.armor = armor;
    }

    public List<AuditorDeArmor.Hallazgo> auditar(String politica) {
        var p = armor.leer(politica);
        return auditor.auditar(p.reglas(), p.adaptativa());
    }
}
'''
ggen.gcp('gcp/05-ingress-api/cloud-armor', 'Ingress y API · Cloud Armor',
  'Un **auditor de políticas de Cloud Armor**: lee la política con `SecurityPoliciesClient.get` y verifica que existan los conjuntos WAF obligatorios (SQLi, XSS) y que no estén en vista previa, que haya limitación de tasa, que ninguna regla `allow` temprana se salte el WAF y que Adaptive Protection esté activo.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Armor', '/ingress/armor', 'ServicioDeArmor', 'ArmorGcp', ['import java.util.List;'],
  'return new ArmorGcp(cred, proyecto);',
  [dict(n='auditar', v='GET', p='/{politica}', args=[('String', 'politica', 'p')], ret='List<AuditorDeArmor.Hallazgo>', call='s.auditar(politica)')],
  [('Leer políticas', '`roles/compute.viewer` (o `compute.securityAdmin` para modificar)')],
  ['No uses Cloud Armor como única validación de entradas.',
   'No corrijas reglas desde la app: Terraform y revisión.',
   'No confíes en `X-Forwarded-For` para tus propios límites salvo que sepas cuántos proxies hay delante.'])
