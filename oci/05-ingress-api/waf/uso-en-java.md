# Oracle OCI · Ingress y API · WAF · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **auditor de políticas WAF**: lee la política real con `WafClient`, la resume (qué acciones bloquean, qué capacidades de protección hay, si inspecciona el cuerpo, cuántas reglas de tasa) y la compara con el mínimo de la empresa. Sirve para un control en el pipeline o un tablero de cumplimiento.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
```

## 2. Núcleo común

### 2.1 Autenticación según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
        }
    }
}
```

### 2.2 Auditor (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
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
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
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
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
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
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.waf.WafClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class WafConfiguracion {

    @Bean(destroyMethod = "close")
    WafOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new WafOci(WafClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeAuditoriaWaf servicio(WafOci a) {
        return new ServicioDeAuditoriaWaf(a);
    }
}

@RestController
@RequestMapping("/ingress/waf")
class WafControlador {

    private final ServicioDeAuditoriaWaf s;

    WafControlador(ServicioDeAuditoriaWaf s) {
        this.s = s;
    }

    @GetMapping("/{id}/auditoria")
    ServicioDeAuditoriaWaf.Informe auditar(@PathVariable String id) {
        return s.auditar(id);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.waf.WafClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/waf")
class WafReactivoControlador {

    private final ServicioDeAuditoriaWaf s;

    WafReactivoControlador(ServicioDeAuditoriaWaf s) {
        this.s = s;
    }

    @GetMapping("/{id}/auditoria")
    Mono<ServicioDeAuditoriaWaf.Informe> auditar(@PathVariable String id) {
        return Mono.fromCallable(() -> s.auditar(id)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.waf.WafClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class WafProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    WafOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new WafOci(WafClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes WafOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeAuditoriaWaf servicio(WafOci a) {
        return new ServicioDeAuditoriaWaf(a);
    }
}

@Path("/ingress/waf")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class WafRecurso {

    @Inject
    ServicioDeAuditoriaWaf s;

    @GET
    @Path("/{id}/auditoria")
    public ServicioDeAuditoriaWaf.Informe auditar(@PathParam("id") String id) {
        return s.auditar(id);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.waf.WafClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/ingress/waf")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class WafRecursoReactivo {

    @Inject
    ServicioDeAuditoriaWaf s;

    @GET
    @Path("/{id}/auditoria")
    public Uni<ServicioDeAuditoriaWaf.Informe> auditar(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> s.auditar(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer la política | `Allow dynamic-group auditoria to read waf-family in compartment seguridad` |

## 8. Qué NO hacer desde Java
- No uses el WAF como sustituto de validar entradas y parametrizar consultas.
- No cambies la política a mano: que el auditor corra contra lo que dejó Terraform.
- No registres cuerpos de peticiones bloqueadas con datos personales.
- No confíes en la IP del socket detrás del LB para tus propios límites: usa `X-Forwarded-For` confiable.
