import genlib
AUD = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Revisa que una política WAF cumpla el mínimo de la empresa. Puro: trabaja sobre un resumen. */
public class AuditorDePoliticaWaf {

    public record Resumen(String nombre, Set<String> accionesQueBloquean, List<String> accionesDeProteccion,
                          Set<String> clavesDeProteccion, boolean inspeccionaCuerpo, int reglasDeTasa) { }

    public record Hallazgo(String severidad, String mensaje) { }

    private final Set<String> clavesObligatorias;

    public AuditorDePoliticaWaf(Set<String> clavesObligatorias) {
        this.clavesObligatorias = Set.copyOf(clavesObligatorias);
    }

    public List<Hallazgo> auditar(Resumen r) {
        var h = new ArrayList<Hallazgo>();
        if (r.accionesDeProteccion().isEmpty()) {
            h.add(new Hallazgo("ALTA", "sin reglas de protección"));
        }
        long enModoCheck = r.accionesDeProteccion().stream().filter(a -> !r.accionesQueBloquean().contains(a)).count();
        if (enModoCheck > 0) {
            h.add(new Hallazgo("MEDIA", enModoCheck + " regla(s) de protección solo detectan (CHECK)"));
        }
        for (String clave : clavesObligatorias) {
            if (!r.clavesDeProteccion().contains(clave)) {
                h.add(new Hallazgo("ALTA", "falta la capacidad de protección " + clave));
            }
        }
        if (!r.inspeccionaCuerpo()) {
            h.add(new Hallazgo("MEDIA", "no inspecciona el cuerpo de las peticiones"));
        }
        if (r.reglasDeTasa() == 0) {
            h.add(new Hallazgo("MEDIA", "sin límite de tasa"));
        }
        return h;
    }
}
'''
SDK = '''
import com.oracle.bmc.waf.WafClient;
import com.oracle.bmc.waf.model.ProtectionCapability;
import com.oracle.bmc.waf.model.ProtectionRule;
import com.oracle.bmc.waf.model.ReturnHttpResponseAction;
import com.oracle.bmc.waf.requests.GetWebAppFirewallPolicyRequest;
import java.util.HashSet;
import java.util.List;
import java.util.stream.Collectors;

/** Adaptador del SDK: convierte la política real en el resumen que audita la lógica pura. */
public class WafOci implements AutoCloseable {

    private final WafClient cliente;

    public WafOci(WafClient cliente) {
        this.cliente = cliente;
    }

    public AuditorDePoliticaWaf.Resumen resumen(String politicaId) {
        var p = cliente.getWebAppFirewallPolicy(GetWebAppFirewallPolicyRequest.builder()
            .webAppFirewallPolicyId(politicaId).build()).getWebAppFirewallPolicy();
        var bloquean = p.getActions() == null ? new HashSet<String>() : p.getActions().stream()
            .filter(a -> a instanceof ReturnHttpResponseAction r && r.getCode() >= 400)
            .map(a -> a.getName()).collect(Collectors.toSet());
        List<ProtectionRule> reglas = p.getRequestProtection() == null || p.getRequestProtection().getRules() == null
            ? List.of() : p.getRequestProtection().getRules();
        var claves = reglas.stream().flatMap(r -> r.getProtectionCapabilities().stream())
            .map(ProtectionCapability::getKey).collect(Collectors.toSet());
        boolean cuerpo = reglas.stream().anyMatch(r -> Boolean.TRUE.equals(r.getIsBodyInspectionEnabled()));
        int tasa = p.getRequestRateLimiting() == null || p.getRequestRateLimiting().getRules() == null
            ? 0 : p.getRequestRateLimiting().getRules().size();
        return new AuditorDePoliticaWaf.Resumen(p.getDisplayName(), bloquean,
            reglas.stream().map(ProtectionRule::getActionName).toList(), claves, cuerpo, tasa);
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

public class ServicioDeAuditoriaWaf {

    public record Informe(String politica, boolean cumple, List<AuditorDePoliticaWaf.Hallazgo> hallazgos) { }

    private final WafOci waf;
    // SQLi, XSS y RCE (claves colaborativas; verifica las vigentes con «protection-capability list»)
    private final AuditorDePoliticaWaf auditor = new AuditorDePoliticaWaf(Set.of("9420000", "9410000", "9330000"));

    public ServicioDeAuditoriaWaf(WafOci waf) {
        this.waf = waf;
    }

    public Informe auditar(String politicaId) {
        var r = waf.resumen(politicaId);
        var h = auditor.auditar(r);
        return new Informe(r.nombre(), h.stream().noneMatch(x -> x.severidad().equals("ALTA")), h);
    }
}
'''
genlib.oci('oci/05-ingress-api/waf', 'Ingress y API · WAF',
  'Un **auditor de políticas WAF**: lee la política real con `WafClient`, la resume (qué acciones bloquean, qué capacidades de protección hay, si inspecciona el cuerpo, cuántas reglas de tasa) y la compara con el mínimo de la empresa. Sirve para un control en el pipeline o un tablero de cumplimiento.',
  [],
  [('Auditor (lógica pura)', AUD, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Waf', '/ingress/waf', 'ServicioDeAuditoriaWaf', 'WafOci',
  ['import com.oracle.bmc.waf.WafClient;'],
  'return new WafOci(WafClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='auditar', v='GET', p='/{id}/auditoria', args=[('String', 'id', 'p')], ret='ServicioDeAuditoriaWaf.Informe', call='s.auditar(id)')],
  [('Leer la política', '`Allow dynamic-group auditoria to read waf-family in compartment seguridad`')],
  ['No uses el WAF como sustituto de validar entradas y parametrizar consultas.',
   'No cambies la política a mano: que el auditor corra contra lo que dejó Terraform.',
   'No registres cuerpos de peticiones bloqueadas con datos personales.',
   'No confíes en la IP del socket detrás del LB para tus propios límites: usa `X-Forwarded-For` confiable.'])
