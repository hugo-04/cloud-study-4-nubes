# Google Cloud · Gobierno · Jerarquía y etiquetas · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: un **validador puro** de labels obligatorios y su formato (minúsculas, ≤ 63 caracteres) que además comprueba que el tag `entorno` (el que manda en IAM y políticas) no contradiga al label; y un adaptador que recorre los proyectos de una carpeta con `ProjectsClient.searchProjects` y lee sus **tags efectivos** (incluidos los heredados) con `TagBindingsClient.listEffectiveTags`.

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

### 2.2 Validador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Valida labels obligatorios y su formato, y que el tag de entorno sea coherente con el label. Puro.
 */
public final class ValidadorDeEtiquetas {

    public record Resultado(String recurso, boolean cumple, List<String> problemas) { }

    private static final Pattern FORMATO = Pattern.compile("[a-z][a-z0-9_-]{0,62}");
    private static final Set<String> ENTORNOS = Set.of("prod", "no-prod", "compartido");

    private ValidadorDeEtiquetas() {
    }

    public static Resultado validar(String recurso, Map<String, String> labels, Set<String> obligatorios, String tagEntorno) {
        var p = new ArrayList<String>();
        for (String k : obligatorios) {
            if (!labels.containsKey(k)) {
                p.add("falta label " + k);
            }
        }
        labels.forEach((k, v) -> {
            if (!FORMATO.matcher(k).matches()) {
                p.add("clave con formato inválido: " + k);
            }
            if (!v.isEmpty() && !v.matches("[a-z0-9_-]{1,63}")) {
                p.add("valor con formato inválido en " + k);
            }
        });
        if (tagEntorno == null) {
            p.add("sin tag de entorno (ni propio ni heredado)");
        } else if (!ENTORNOS.contains(tagEntorno)) {
            p.add("tag de entorno desconocido: " + tagEntorno);
        } else if (labels.containsKey("entorno") && !labels.get("entorno").equals(tagEntorno)) {
            p.add("label entorno=" + labels.get("entorno") + " contradice el tag " + tagEntorno);
        }
        return new Resultado(recurso, p.isEmpty(), p);
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.resourcemanager.v3.ProjectsClient;
import com.google.cloud.resourcemanager.v3.ProjectsSettings;
import com.google.cloud.resourcemanager.v3.TagBindingsClient;
import com.google.cloud.resourcemanager.v3.TagBindingsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Adaptador: recorre los proyectos de una carpeta y valida labels y el tag efectivo «entorno». */
public class JerarquiaGcp implements AutoCloseable {

    private final ProjectsClient proyectos;
    private final TagBindingsClient tags;

    public JerarquiaGcp(GoogleCredentials cred) {
        var cp = FixedCredentialsProvider.create(cred);
        try {
            this.proyectos = ProjectsClient.create(ProjectsSettings.newBuilder().setCredentialsProvider(cp).build());
            this.tags = TagBindingsClient.create(TagBindingsSettings.newBuilder().setCredentialsProvider(cp).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<ValidadorDeEtiquetas.Resultado> auditar(String carpeta, Set<String> obligatorios) {
        var out = new ArrayList<ValidadorDeEtiquetas.Resultado>();
        for (var p : proyectos.searchProjects("parent:folders/" + carpeta).iterateAll()) {
            String entorno = null;
            // p.getName() = projects/<número>; los tags efectivos incluyen los heredados de carpetas
            for (var t : tags.listEffectiveTags("//cloudresourcemanager.googleapis.com/" + p.getName()).iterateAll()) {
                if (t.getNamespacedTagKey().endsWith("/entorno")) {
                    entorno = t.getNamespacedTagValue().substring(t.getNamespacedTagValue().lastIndexOf('/') + 1);
                }
            }
            out.add(ValidadorDeEtiquetas.validar(p.getProjectId(), p.getLabelsMap(), obligatorios, entorno));
        }
        return out;
    }

    @Override
    public void close() {
        proyectos.close();
        tags.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ServicioDeEtiquetas {

    private static final Set<String> OBLIGATORIOS = Set.of("equipo", "entorno", "centro-costo");
    private final JerarquiaGcp gcp;

    public ServicioDeEtiquetas(JerarquiaGcp gcp) {
        this.gcp = gcp;
    }

    /** Para el pipeline: valida antes de aplicar. */
    public ValidadorDeEtiquetas.Resultado validar(String recurso, String tagEntorno, Map<String, String> labels) {
        return ValidadorDeEtiquetas.validar(recurso, labels, OBLIGATORIOS, tagEntorno);
    }

    public List<ValidadorDeEtiquetas.Resultado> auditar(String carpeta) {
        return gcp.auditar(carpeta, OBLIGATORIOS);
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EtiquetasConfiguracion {

    @Bean(destroyMethod = "close")
    JerarquiaGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new JerarquiaGcp(cred);
    }

    @Bean
    ServicioDeEtiquetas servicio(JerarquiaGcp a) {
        return new ServicioDeEtiquetas(a);
    }
}

@RestController
@RequestMapping("/gobierno/etiquetas")
class EtiquetasControlador {

    private final ServicioDeEtiquetas s;

    EtiquetasControlador(ServicioDeEtiquetas s) {
        this.s = s;
    }

    @PostMapping("/validacion")
    ValidadorDeEtiquetas.Resultado validar(@RequestParam String recurso, @RequestParam String tagEntorno, @RequestBody java.util.Map<String, String> labels) {
        return s.validar(recurso, tagEntorno, labels);
    }

    @GetMapping("/carpetas/{carpeta}")
    java.util.List<ValidadorDeEtiquetas.Resultado> auditar(@PathVariable String carpeta) {
        return s.auditar(carpeta);
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/etiquetas")
class EtiquetasReactivoControlador {

    private final ServicioDeEtiquetas s;

    EtiquetasReactivoControlador(ServicioDeEtiquetas s) {
        this.s = s;
    }

    @PostMapping("/validacion")
    Mono<ValidadorDeEtiquetas.Resultado> validar(@RequestParam String recurso, @RequestParam String tagEntorno, @RequestBody java.util.Map<String, String> labels) {
        return Mono.fromCallable(() -> s.validar(recurso, tagEntorno, labels));
    }

    @GetMapping("/carpetas/{carpeta}")
    Mono<java.util.List<ValidadorDeEtiquetas.Resultado>> auditar(@PathVariable String carpeta) {
        return Mono.fromCallable(() -> s.auditar(carpeta)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EtiquetasProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    JerarquiaGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new JerarquiaGcp(cred);
    }

    void cerrar(@Disposes JerarquiaGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEtiquetas servicio(JerarquiaGcp a) {
        return new ServicioDeEtiquetas(a);
    }
}

@Path("/gobierno/etiquetas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EtiquetasRecurso {

    @Inject
    ServicioDeEtiquetas s;

    @POST
    @Path("/validacion")
    @Consumes(MediaType.APPLICATION_JSON)
    public ValidadorDeEtiquetas.Resultado validar(@QueryParam("recurso") String recurso, @QueryParam("tagEntorno") String tagEntorno, java.util.Map<String, String> labels) {
        return s.validar(recurso, tagEntorno, labels);
    }

    @GET
    @Path("/carpetas/{carpeta}")
    public java.util.List<ValidadorDeEtiquetas.Resultado> auditar(@PathParam("carpeta") String carpeta) {
        return s.auditar(carpeta);
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/gobierno/etiquetas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EtiquetasRecursoReactivo {

    @Inject
    ServicioDeEtiquetas s;

    @POST
    @Path("/validacion")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ValidadorDeEtiquetas.Resultado> validar(@QueryParam("recurso") String recurso, @QueryParam("tagEntorno") String tagEntorno, java.util.Map<String, String> labels) {
        return Uni.createFrom().item(() -> s.validar(recurso, tagEntorno, labels));
    }

    @GET
    @Path("/carpetas/{carpeta}")
    public Uni<java.util.List<ValidadorDeEtiquetas.Resultado>> auditar(@PathParam("carpeta") String carpeta) {
        return Uni.createFrom().item(() -> s.auditar(carpeta)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar proyectos | `roles/resourcemanager.folderViewer` en la carpeta |
| Leer tags efectivos | `roles/resourcemanager.tagViewer` |

## 8. Qué NO hacer desde Java
- No uses labels para decisiones de seguridad.
- No des permisos de edición de tags a los equipos: `tagUser` sobre valores concretos.
- No corrijas labels a mano en la consola: hazlo en el código de infraestructura.
- No ejecutes la auditoría con una cuenta con permisos de escritura.
