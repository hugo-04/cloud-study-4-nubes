# Google Cloud · IAM · Workload Identity en GKE · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

En la app no hace falta código especial: **ADC** obtiene el token del servidor de metadatos de GKE. Lo que sí construyes es una **prueba de humo** para el despliegue: la lógica pura arma el principal directo de la KSA (o el miembro del modo suplantación) validando nombres y prohibiendo la KSA `default`; el adaptador lee la identidad vista por el pod en el servidor de metadatos y comprueba con `ProjectsClient.getIamPolicy` que ese principal tenga el rol esperado.

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

### 2.2 Principales (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

/** Construye y valida principales de Workload Identity de GKE. Puro. */
public final class PrincipalesDeGke {

    private PrincipalesDeGke() { }

    private static final String NOMBRE_K8S = "[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?";

    public static String directo(long numeroProyecto, String proyecto, String namespace, String ksa) {
        validar(namespace, ksa);
        return "principal://iam.googleapis.com/projects/" + numeroProyecto + "/locations/global/workloadIdentityPools/"
            + proyecto + ".svc.id.goog/subject/ns/" + namespace + "/sa/" + ksa;
    }

    /** Todo un namespace (útil para lectura común; con cuidado). */
    public static String namespaceCompleto(long numeroProyecto, String proyecto, String namespace) {
        validar(namespace, "x");
        return "principalSet://iam.googleapis.com/projects/" + numeroProyecto + "/locations/global/workloadIdentityPools/"
            + proyecto + ".svc.id.goog/namespace/" + namespace;
    }

    /** Miembro para roles/iam.workloadIdentityUser en el modo suplantación. */
    public static String paraSuplantacion(String proyecto, String namespace, String ksa) {
        validar(namespace, ksa);
        return "serviceAccount:" + proyecto + ".svc.id.goog[" + namespace + "/" + ksa + "]";
    }

    public static boolean tieneRol(List<String> miembrosDelRol, String principal) {
        return miembrosDelRol.contains(principal);
    }

    private static void validar(String ns, String ksa) {
        if (!ns.matches(NOMBRE_K8S) || !ksa.matches(NOMBRE_K8S) || "default".equals(ksa)) {
            throw new IllegalArgumentException("namespace o KSA inválidos (y nunca la KSA default)");
        }
    }
}
```

### 2.3 Adaptador
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.resourcemanager.v3.ProjectName;
import com.google.cloud.resourcemanager.v3.ProjectsClient;
import com.google.cloud.resourcemanager.v3.ProjectsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;

/** Adaptador: identidad vista por el pod (servidor de metadatos) y miembros de un rol en el proyecto. */
public class IdentidadGke implements AutoCloseable {

    private static final String METADATOS = "http://metadata.google.internal/computeMetadata/v1/";

    private final ProjectsClient proyectos;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();

    public IdentidadGke(GoogleCredentials cred) {
        try {
            this.proyectos = ProjectsClient.create(ProjectsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public String metadato(String ruta) {
        var req = HttpRequest.newBuilder(URI.create(METADATOS + ruta)).header("Metadata-Flavor", "Google")
            .timeout(Duration.ofSeconds(2)).build();
        try {
            return http.send(req, HttpResponse.BodyHandlers.ofString()).body().strip();
        } catch (IOException e) {
            throw new UncheckedIOException("sin servidor de metadatos (¿fuera de GKE?)", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    public List<String> miembros(String proyecto, String rol) {
        return proyectos.getIamPolicy(ProjectName.of(proyecto)).getBindingsList().stream()
            .filter(b -> b.getRole().equals(rol) && !b.hasCondition())
            .flatMap(b -> b.getMembersList().stream()).toList();
    }

    @Override
    public void close() {
        proyectos.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
public class ServicioDeIdentidad {

    public record Verificacion(String identidadDelPod, String principalEsperado, boolean tieneRol) { }

    private final IdentidadGke gke;

    public ServicioDeIdentidad(IdentidadGke gke) {
        this.gke = gke;
    }

    /** Prueba de humo al desplegar: ¿la KSA de este pod tiene el rol esperado en el proyecto? */
    public Verificacion verificar(String proyecto, long numero, String namespace, String ksa, String rol) {
        String vista = gke.metadato("instance/service-accounts/default/email");
        String esperado = PrincipalesDeGke.directo(numero, proyecto, namespace, ksa);
        return new Verificacion(vista, esperado, PrincipalesDeGke.tieneRol(gke.miembros(proyecto, rol), esperado));
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class IdentidadConfiguracion {

    @Bean(destroyMethod = "close")
    IdentidadGke adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new IdentidadGke(cred);
    }

    @Bean
    ServicioDeIdentidad servicio(IdentidadGke a) {
        return new ServicioDeIdentidad(a);
    }
}

@RestController
@RequestMapping("/iam/gke")
class IdentidadControlador {

    private final ServicioDeIdentidad s;

    IdentidadControlador(ServicioDeIdentidad s) {
        this.s = s;
    }

    @GetMapping("/verificacion")
    ServicioDeIdentidad.Verificacion verificar(@RequestParam String proyecto, @RequestParam long numero, @RequestParam String ns, @RequestParam String ksa, @RequestParam String rol) {
        return s.verificar(proyecto, numero, ns, ksa, rol);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/iam/gke")
class IdentidadReactivoControlador {

    private final ServicioDeIdentidad s;

    IdentidadReactivoControlador(ServicioDeIdentidad s) {
        this.s = s;
    }

    @GetMapping("/verificacion")
    Mono<ServicioDeIdentidad.Verificacion> verificar(@RequestParam String proyecto, @RequestParam long numero, @RequestParam String ns, @RequestParam String ksa, @RequestParam String rol) {
        return Mono.fromCallable(() -> s.verificar(proyecto, numero, ns, ksa, rol)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class IdentidadProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    IdentidadGke adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new IdentidadGke(cred);
    }

    void cerrar(@Disposes IdentidadGke a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeIdentidad servicio(IdentidadGke a) {
        return new ServicioDeIdentidad(a);
    }
}

@Path("/iam/gke")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class IdentidadRecurso {

    @Inject
    ServicioDeIdentidad s;

    @GET
    @Path("/verificacion")
    public ServicioDeIdentidad.Verificacion verificar(@QueryParam("proyecto") String proyecto, @QueryParam("numero") long numero, @QueryParam("ns") String ns, @QueryParam("ksa") String ksa, @QueryParam("rol") String rol) {
        return s.verificar(proyecto, numero, ns, ksa, rol);
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
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/iam/gke")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class IdentidadRecursoReactivo {

    @Inject
    ServicioDeIdentidad s;

    @GET
    @Path("/verificacion")
    public Uni<ServicioDeIdentidad.Verificacion> verificar(@QueryParam("proyecto") String proyecto, @QueryParam("numero") long numero, @QueryParam("ns") String ns, @QueryParam("ksa") String ksa, @QueryParam("rol") String rol) {
        return Uni.createFrom().item(() -> s.verificar(proyecto, numero, ns, ksa, rol)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer la política del proyecto (solo para la verificación) | `roles/iam.securityReviewer` |
| La app en sí | Los roles de datos otorgados a su principal de KSA |

## 8. Qué NO hacer desde Java
- No montes llaves JSON como secretos de Kubernetes.
- No uses la KSA `default` para nada con permisos.
- No uses el ID del proyecto donde va el **número** en `principal://`.
- No asumas que el metadata server responde en el primer milisegundo del arranque: reintenta.
