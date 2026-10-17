# Google Cloud · IAM · Roles y políticas de permisos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **auditor de la política de permisos** de un proyecto: la lee con `ProjectsClient.getIamPolicy` y marca acceso público (`allUsers`, `allAuthenticatedUsers`), roles básicos, usuarios individuales en vez de grupos, roles que permiten escalar (crear tokens o llaves de cuentas de servicio, administrar IAM) sin condición, y principales eliminados.

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

/** Audita los bindings de una política de permisos. Puro. */
public class AuditorDePolitica {

    public record Binding(String rol, List<String> miembros, String condicion) { }

    public record Hallazgo(String severidad, String rol, String miembro, String mensaje) { }

    private static final Set<String> BASICOS = Set.of("roles/owner", "roles/editor", "roles/viewer");
    private static final Set<String> PELIGROSOS = Set.of(
        "roles/iam.serviceAccountTokenCreator", "roles/iam.serviceAccountKeyAdmin", "roles/resourcemanager.projectIamAdmin");

    public List<Hallazgo> auditar(List<Binding> bindings) {
        var h = new ArrayList<Hallazgo>();
        for (Binding b : bindings) {
            for (String m : b.miembros()) {
                if (m.equals("allUsers") || m.equals("allAuthenticatedUsers")) {
                    h.add(new Hallazgo("CRITICA", b.rol(), m, "acceso público"));
                }
                if (BASICOS.contains(b.rol())) {
                    h.add(new Hallazgo(b.rol().equals("roles/viewer") ? "MEDIA" : "ALTA", b.rol(), m, "rol básico: usa predefinidos"));
                }
                if (m.startsWith("user:") && !b.rol().startsWith("roles/viewer")) {
                    h.add(new Hallazgo("BAJA", b.rol(), m, "usuario individual: usa un grupo"));
                }
                if (PELIGROSOS.contains(b.rol()) && b.condicion() == null) {
                    h.add(new Hallazgo("ALTA", b.rol(), m, "rol de escalada sin condición a nivel de proyecto"));
                }
                if (m.startsWith("deleted:")) {
                    h.add(new Hallazgo("BAJA", b.rol(), m, "principal eliminado: limpiar"));
                }
            }
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
import com.google.cloud.resourcemanager.v3.ProjectName;
import com.google.cloud.resourcemanager.v3.ProjectsClient;
import com.google.cloud.resourcemanager.v3.ProjectsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador: política de permisos de un proyecto. */
public class PoliticasGcp implements AutoCloseable {

    private final ProjectsClient cliente;

    public PoliticasGcp(GoogleCredentials cred) {
        try {
            this.cliente = ProjectsClient.create(ProjectsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<AuditorDePolitica.Binding> bindings(String proyecto) {
        var politica = cliente.getIamPolicy(ProjectName.of(proyecto));
        return politica.getBindingsList().stream()
            .map(b -> new AuditorDePolitica.Binding(b.getRole(), List.copyOf(b.getMembersList()),
                b.hasCondition() ? b.getCondition().getExpression() : null))
            .toList();
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
import java.util.Comparator;
import java.util.List;

public class ServicioDeIam {

    private final PoliticasGcp politicas;
    private final AuditorDePolitica auditor = new AuditorDePolitica();

    public ServicioDeIam(PoliticasGcp politicas) {
        this.politicas = politicas;
    }

    public List<AuditorDePolitica.Hallazgo> auditar(String proyecto) {
        return auditor.auditar(politicas.bindings(proyecto)).stream()
            .sorted(Comparator.comparing(AuditorDePolitica.Hallazgo::severidad)).toList();
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
class IamConfiguracion {

    @Bean(destroyMethod = "close")
    PoliticasGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PoliticasGcp(cred);
    }

    @Bean
    ServicioDeIam servicio(PoliticasGcp a) {
        return new ServicioDeIam(a);
    }
}

@RestController
@RequestMapping("/iam/politicas")
class IamControlador {

    private final ServicioDeIam s;

    IamControlador(ServicioDeIam s) {
        this.s = s;
    }

    @GetMapping("/{proyecto}")
    List<AuditorDePolitica.Hallazgo> auditar(@PathVariable String proyecto) {
        return s.auditar(proyecto);
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
@RequestMapping("/reactivo/iam/politicas")
class IamReactivoControlador {

    private final ServicioDeIam s;

    IamReactivoControlador(ServicioDeIam s) {
        this.s = s;
    }

    @GetMapping("/{proyecto}")
    Mono<List<AuditorDePolitica.Hallazgo>> auditar(@PathVariable String proyecto) {
        return Mono.fromCallable(() -> s.auditar(proyecto)).subscribeOn(Schedulers.boundedElastic());
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
class IamProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PoliticasGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PoliticasGcp(cred);
    }

    void cerrar(@Disposes PoliticasGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeIam servicio(PoliticasGcp a) {
        return new ServicioDeIam(a);
    }
}

@Path("/iam/politicas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class IamRecurso {

    @Inject
    ServicioDeIam s;

    @GET
    @Path("/{proyecto}")
    public List<AuditorDePolitica.Hallazgo> auditar(@PathParam("proyecto") String proyecto) {
        return s.auditar(proyecto);
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

@Path("/reactivo/iam/politicas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class IamRecursoReactivo {

    @Inject
    ServicioDeIam s;

    @GET
    @Path("/{proyecto}")
    public Uni<List<AuditorDePolitica.Hallazgo>> auditar(@PathParam("proyecto") String proyecto) {
        return Uni.createFrom().item(() -> s.auditar(proyecto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer la política del proyecto | `roles/iam.securityReviewer` (o `roles/resourcemanager.projectIamAdmin` solo para modificar) |

## 8. Qué NO hacer desde Java
- No modifiques políticas sin el ETag (lectura-modificación-escritura).
- No uses `setIamPolicy` desde apps: reemplaza la política entera.
- No audites solo el proyecto: la herencia de carpetas y organización también cuenta (Policy Analyzer).
