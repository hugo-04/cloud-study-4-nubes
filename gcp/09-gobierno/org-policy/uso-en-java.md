# Google Cloud · Gobierno · Organization Policy · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: una **comparación pura** entre la línea base que quieres (aplicada, denegar todo o solo ciertos valores) y lo que realmente aplica; y un adaptador que pide la **política efectiva** de cada restricción en un proyecto con `OrgPolicyClient.getEffectivePolicy` (ya resuelta la herencia) y la resume. Útil como control continuo o como paso del pipeline de alta de proyectos.

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

### 2.2 Línea base (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Compara la política efectiva de cada restricción con la línea base esperada. Puro: recibe un resumen
 * por restricción (enforce / denyAll / valores permitidos) ya extraído del API.
 */
public final class LineaBase {

    public record Efectiva(boolean enforce, boolean denyAll, boolean allowAll, List<String> permitidos) { }

    public record Esperada(String tipo, List<String> permitidos) {
        public static Esperada aplicada() {
            return new Esperada("enforce", List.of());
        }

        public static Esperada denegarTodo() {
            return new Esperada("denyAll", List.of());
        }

        public static Esperada soloValores(List<String> v) {
            return new Esperada("valores", v);
        }
    }

    public record Brecha(String restriccion, String detalle) { }

    private LineaBase() {
    }

    public static List<Brecha> comparar(Map<String, Esperada> base, Map<String, Efectiva> efectivas) {
        var out = new ArrayList<Brecha>();
        base.forEach((c, esp) -> {
            var ef = efectivas.get(c);
            if (ef == null) {
                out.add(new Brecha(c, "sin política efectiva (valor por defecto de Google)"));
                return;
            }
            switch (esp.tipo()) {
                case "enforce" -> {
                    if (!ef.enforce()) {
                        out.add(new Brecha(c, "no está aplicada"));
                    }
                }
                case "denyAll" -> {
                    if (!ef.denyAll()) {
                        out.add(new Brecha(c, ef.allowAll() ? "permite todo" : "no deniega todo"));
                    }
                }
                default -> {
                    if (ef.allowAll()) {
                        out.add(new Brecha(c, "permite todo"));
                    } else {
                        var extra = ef.permitidos().stream().filter(v -> !esp.permitidos().contains(v)).toList();
                        if (!extra.isEmpty() || ef.permitidos().isEmpty()) {
                            out.add(new Brecha(c, "valores fuera de la base: " + extra));
                        }
                    }
                }
            }
        });
        return out;
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.api.gax.rpc.NotFoundException;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.orgpolicy.v2.OrgPolicyClient;
import com.google.cloud.orgpolicy.v2.OrgPolicySettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/** Adaptador: lee la política efectiva de cada restricción en un proyecto y la resume. */
public class OrgPolicyGcp implements AutoCloseable {

    private final OrgPolicyClient cliente;

    public OrgPolicyGcp(GoogleCredentials cred) {
        try {
            this.cliente = OrgPolicyClient.create(OrgPolicySettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Map<String, LineaBase.Efectiva> efectivas(String proyecto, Set<String> restricciones) {
        var out = new HashMap<String, LineaBase.Efectiva>();
        for (String c : restricciones) {
            try {
                var pol = cliente.getEffectivePolicy("projects/" + proyecto + "/policies/" + c);
                boolean enforce = false;
                boolean deny = false;
                boolean allow = false;
                var permitidos = new ArrayList<String>();
                // Ojo: reglas con condición (tags) se resumen como si aplicaran siempre; revísalas aparte
                for (var r : pol.getSpec().getRulesList()) {
                    enforce |= r.getEnforce();
                    deny |= r.getDenyAll();
                    allow |= r.getAllowAll();
                    if (r.hasValues()) {
                        permitidos.addAll(r.getValues().getAllowedValuesList());
                    }
                }
                out.put(c, new LineaBase.Efectiva(enforce, deny, allow, permitidos));
            } catch (NotFoundException e) {
                // sin política: queda fuera del mapa
            }
        }
        return out;
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
import java.util.Map;

public class ServicioDeLineaBase {

    private static final Map<String, LineaBase.Esperada> BASE = Map.of(
        "sql.restrictPublicIp", LineaBase.Esperada.aplicada(),
        "iam.disableServiceAccountKeyCreation", LineaBase.Esperada.aplicada(),
        "storage.publicAccessPrevention", LineaBase.Esperada.aplicada(),
        "compute.vmExternalIpAccess", LineaBase.Esperada.denegarTodo(),
        "gcp.resourceLocations", LineaBase.Esperada.soloValores(List.of("in:southamerica-locations")));

    private final OrgPolicyGcp gcp;

    public ServicioDeLineaBase(OrgPolicyGcp gcp) {
        this.gcp = gcp;
    }

    public List<LineaBase.Brecha> revisar(String proyecto) {
        return LineaBase.comparar(BASE, gcp.efectivas(proyecto, BASE.keySet()));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class LineaBaseConfiguracion {

    @Bean(destroyMethod = "close")
    OrgPolicyGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new OrgPolicyGcp(cred);
    }

    @Bean
    ServicioDeLineaBase servicio(OrgPolicyGcp a) {
        return new ServicioDeLineaBase(a);
    }
}

@RestController
@RequestMapping("/gobierno/politicas")
class LineaBaseControlador {

    private final ServicioDeLineaBase s;

    LineaBaseControlador(ServicioDeLineaBase s) {
        this.s = s;
    }

    @GetMapping("/{proyecto}")
    java.util.List<LineaBase.Brecha> revisar(@PathVariable String proyecto) {
        return s.revisar(proyecto);
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
@RequestMapping("/reactivo/gobierno/politicas")
class LineaBaseReactivoControlador {

    private final ServicioDeLineaBase s;

    LineaBaseReactivoControlador(ServicioDeLineaBase s) {
        this.s = s;
    }

    @GetMapping("/{proyecto}")
    Mono<java.util.List<LineaBase.Brecha>> revisar(@PathVariable String proyecto) {
        return Mono.fromCallable(() -> s.revisar(proyecto)).subscribeOn(Schedulers.boundedElastic());
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
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class LineaBaseProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    OrgPolicyGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new OrgPolicyGcp(cred);
    }

    void cerrar(@Disposes OrgPolicyGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeLineaBase servicio(OrgPolicyGcp a) {
        return new ServicioDeLineaBase(a);
    }
}

@Path("/gobierno/politicas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class LineaBaseRecurso {

    @Inject
    ServicioDeLineaBase s;

    @GET
    @Path("/{proyecto}")
    public java.util.List<LineaBase.Brecha> revisar(@PathParam("proyecto") String proyecto) {
        return s.revisar(proyecto);
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

@Path("/reactivo/gobierno/politicas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class LineaBaseRecursoReactivo {

    @Inject
    ServicioDeLineaBase s;

    @GET
    @Path("/{proyecto}")
    public Uni<java.util.List<LineaBase.Brecha>> revisar(@PathParam("proyecto") String proyecto) {
        return Uni.createFrom().item(() -> s.revisar(proyecto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer políticas efectivas | `roles/orgpolicy.policyViewer` (en la organización o carpeta) |

## 8. Qué NO hacer desde Java
- No uses esta revisión como sustituto de aplicar las políticas: solo detecta brechas.
- No des `policyAdmin` a la cuenta de auditoría.
- No ignores las reglas con condición: revísalas por separado.
- No apliques cambios de política desde la app: hazlo por código revisado.
