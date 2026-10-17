# Google Cloud · Ingress y API · Cloud Armor · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **auditor de políticas de Cloud Armor**: lee la política con `SecurityPoliciesClient.get` y verifica que existan los conjuntos WAF obligatorios (SQLi, XSS) y que no estén en vista previa, que haya limitación de tasa, que ninguna regla `allow` temprana se salte el WAF y que Adaptive Protection esté activo.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
```

## 2. Núcleo común

### 2.1 Credenciales según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ImpersonatedCredentials;
import java.io.IOException;
import java.util.List;

public final class Credenciales {

    private static final List<String> ALCANCE = List.of("https://www.googleapis.com/auth/cloud-platform");

    private Credenciales() { }

    /**
     * ADC (Application Default Credentials): en la laptop, «gcloud auth application-default login»;
     * en GKE, Cloud Run, Functions o Compute Engine, la cuenta de servicio adjunta (sin llaves).
     * suplantar = correo de una cuenta de servicio para actuar como ella, o "ninguna".
     */
    public static GoogleCredentials crear(String suplantar) {
        try {
            var base = GoogleCredentials.getApplicationDefault().createScoped(ALCANCE);
            if (suplantar == null || suplantar.isBlank() || "ninguna".equals(suplantar)) {
                return base;
            }
            return ImpersonatedCredentials.create(base, suplantar, null, ALCANCE, 3600);
        } catch (IOException e) {
            throw new IllegalStateException("no hay credenciales ADC disponibles", e);
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
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
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
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
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
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ArmorConfiguracion {

    @Bean(destroyMethod = "close")
    ArmorGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ArmorGcp(cred, proyecto);
    }

    @Bean
    ServicioDeArmor servicio(ArmorGcp a) {
        return new ServicioDeArmor(a);
    }
}

@RestController
@RequestMapping("/ingress/armor")
class ArmorControlador {

    private final ServicioDeArmor s;

    ArmorControlador(ServicioDeArmor s) {
        this.s = s;
    }

    @GetMapping("/{politica}")
    List<AuditorDeArmor.Hallazgo> auditar(@PathVariable String politica) {
        return s.auditar(politica);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/armor")
class ArmorReactivoControlador {

    private final ServicioDeArmor s;

    ArmorReactivoControlador(ServicioDeArmor s) {
        this.s = s;
    }

    @GetMapping("/{politica}")
    Mono<List<AuditorDeArmor.Hallazgo>> auditar(@PathVariable String politica) {
        return Mono.fromCallable(() -> s.auditar(politica)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.google.auth.oauth2.GoogleCredentials;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ArmorProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ArmorGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ArmorGcp(cred, proyecto);
    }

    void cerrar(@Disposes ArmorGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeArmor servicio(ArmorGcp a) {
        return new ServicioDeArmor(a);
    }
}

@Path("/ingress/armor")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ArmorRecurso {

    @Inject
    ServicioDeArmor s;

    @GET
    @Path("/{politica}")
    public List<AuditorDeArmor.Hallazgo> auditar(@PathParam("politica") String politica) {
        return s.auditar(politica);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.List;

@Path("/reactivo/ingress/armor")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ArmorRecursoReactivo {

    @Inject
    ServicioDeArmor s;

    @GET
    @Path("/{politica}")
    public Uni<List<AuditorDeArmor.Hallazgo>> auditar(@PathParam("politica") String politica) {
        return Uni.createFrom().item(() -> s.auditar(politica)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer políticas | `roles/compute.viewer` (o `compute.securityAdmin` para modificar) |

## 8. Qué NO hacer desde Java
- No uses Cloud Armor como única validación de entradas.
- No corrijas reglas desde la app: Terraform y revisión.
- No confíes en `X-Forwarded-For` para tus propios límites salvo que sepas cuántos proxies hay delante.
