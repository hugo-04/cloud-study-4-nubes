# Google Cloud · Terraform · Autenticación y pipelines · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

La autenticación del pipeline no se programa (la resuelve ADC con el archivo `external_account` de la federación). Lo que sí aporta Java es la **política sobre el plan**: lee `plan.json` (`terraform show -json`) desde el bucket de artefactos y **bloquea en prod** la destrucción de recursos con datos (avisando si es un reemplazo que pide un bloque `moved`), prohíbe llaves de cuentas de servicio y avisa de IAM autoritativo. El mismo núcleo puro se empaqueta como CLI (`politica-plan.jar`) para el paso del pipeline.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
planes:
  bucket: modalima-ci-artefactos
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
planes.bucket=modalima-ci-artefactos
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

### 2.2 Política (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/**
 * Política sobre el plan (terraform show -json): bloquea destrucciones de recursos con datos,
 * recursos prohibidos y cambios de IAM amplios en prod. Puro.
 */
public final class PoliticaDePlan {

    public record Cambio(String direccion, String tipo, List<String> acciones) { }

    public record Veredicto(boolean permitido, List<String> bloqueos, List<String> avisos) { }

    private static final Set<String> CON_DATOS = Set.of("google_sql_database_instance", "google_storage_bucket",
        "google_spanner_database", "google_bigtable_instance", "google_firestore_database", "google_kms_crypto_key");
    private static final Set<String> PROHIBIDOS = Set.of("google_service_account_key");
    private static final Set<String> IAM_AMPLIO = Set.of("google_project_iam_binding", "google_project_iam_policy");

    private PoliticaDePlan() {
    }

    public static Veredicto evaluar(List<Cambio> cambios, String entorno) {
        var bloqueos = new ArrayList<String>();
        var avisos = new ArrayList<String>();
        for (var c : cambios) {
            boolean destruye = c.acciones().contains("delete");
            if (destruye && CON_DATOS.contains(c.tipo())) {
                (("prod".equals(entorno)) ? bloqueos : avisos).add("destruye recurso con datos: " + c.direccion()
                    + (c.acciones().contains("create") ? " (reemplazo: ¿falta un bloque moved?)" : ""));
            }
            if (PROHIBIDOS.contains(c.tipo()) && c.acciones().contains("create")) {
                bloqueos.add("recurso prohibido: " + c.direccion());
            }
            if (IAM_AMPLIO.contains(c.tipo()) && !c.acciones().equals(List.of("no-op"))) {
                avisos.add("IAM autoritativo (puede quitar accesos ajenos): " + c.direccion());
            }
        }
        return new Veredicto(bloqueos.isEmpty(), bloqueos, avisos);
    }
}
```

### 2.3 Adaptador (Cloud Storage + Jackson)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee plan.json del bucket de artefactos del pipeline y extrae resource_changes. */
public class PlanGcp implements AutoCloseable {

    private final Storage storage;
    private final String bucket;
    private final ObjectMapper json = new ObjectMapper();

    public PlanGcp(GoogleCredentials cred, String proyecto, String bucket) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public List<PoliticaDePlan.Cambio> cambios(String objeto) {
        byte[] bytes = storage.readAllBytes(BlobId.of(bucket, objeto));
        try {
            return desdeJson(bytes);
        } catch (IOException e) {
            throw new UncheckedIOException("plan.json ilegible", e);
        }
    }

    List<PoliticaDePlan.Cambio> desdeJson(byte[] bytes) throws IOException {
        var out = new ArrayList<PoliticaDePlan.Cambio>();
        for (var rc : json.readTree(bytes).path("resource_changes")) {
            var acciones = new ArrayList<String>();
            rc.path("change").path("actions").forEach(a -> acciones.add(a.asText()));
            out.add(new PoliticaDePlan.Cambio(rc.path("address").asText(), rc.path("type").asText(), acciones));
        }
        return out;
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public class ServicioDePlanes {

    private final PlanGcp gcp;

    public ServicioDePlanes(PlanGcp gcp) {
        this.gcp = gcp;
    }

    public PoliticaDePlan.Veredicto evaluar(String objeto, String entorno) {
        return PoliticaDePlan.evaluar(gcp.cambios(objeto), entorno);
    }

    public PoliticaDePlan.Veredicto simular(String entorno, List<PoliticaDePlan.Cambio> cambios) {
        return PoliticaDePlan.evaluar(cambios, entorno);
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class PlanesConfiguracion {

    @Bean(destroyMethod = "close")
    PlanGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${planes.bucket}") String bucket) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PlanGcp(cred, proyecto, bucket);
    }

    @Bean
    ServicioDePlanes servicio(PlanGcp a) {
        return new ServicioDePlanes(a);
    }
}

@RestController
@RequestMapping("/terraform/planes")
class PlanesControlador {

    private final ServicioDePlanes s;

    PlanesControlador(ServicioDePlanes s) {
        this.s = s;
    }

    @GetMapping("/evaluacion")
    PoliticaDePlan.Veredicto evaluar(@RequestParam String objeto, @RequestParam String entorno) {
        return s.evaluar(objeto, entorno);
    }

    @PostMapping("/simulacion")
    PoliticaDePlan.Veredicto simular(@RequestParam String entorno, @RequestBody java.util.List<PoliticaDePlan.Cambio> cambios) {
        return s.simular(entorno, cambios);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/terraform/planes")
class PlanesReactivoControlador {

    private final ServicioDePlanes s;

    PlanesReactivoControlador(ServicioDePlanes s) {
        this.s = s;
    }

    @GetMapping("/evaluacion")
    Mono<PoliticaDePlan.Veredicto> evaluar(@RequestParam String objeto, @RequestParam String entorno) {
        return Mono.fromCallable(() -> s.evaluar(objeto, entorno)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/simulacion")
    Mono<PoliticaDePlan.Veredicto> simular(@RequestParam String entorno, @RequestBody java.util.List<PoliticaDePlan.Cambio> cambios) {
        return Mono.fromCallable(() -> s.simular(entorno, cambios));
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class PlanesProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "planes.bucket")
    String bucket;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PlanGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PlanGcp(cred, proyecto, bucket);
    }

    void cerrar(@Disposes PlanGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePlanes servicio(PlanGcp a) {
        return new ServicioDePlanes(a);
    }
}

@Path("/terraform/planes")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class PlanesRecurso {

    @Inject
    ServicioDePlanes s;

    @GET
    @Path("/evaluacion")
    public PoliticaDePlan.Veredicto evaluar(@QueryParam("objeto") String objeto, @QueryParam("entorno") String entorno) {
        return s.evaluar(objeto, entorno);
    }

    @POST
    @Path("/simulacion")
    @Consumes(MediaType.APPLICATION_JSON)
    public PoliticaDePlan.Veredicto simular(@QueryParam("entorno") String entorno, java.util.List<PoliticaDePlan.Cambio> cambios) {
        return s.simular(entorno, cambios);
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
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/terraform/planes")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class PlanesRecursoReactivo {

    @Inject
    ServicioDePlanes s;

    @GET
    @Path("/evaluacion")
    public Uni<PoliticaDePlan.Veredicto> evaluar(@QueryParam("objeto") String objeto, @QueryParam("entorno") String entorno) {
        return Uni.createFrom().item(() -> s.evaluar(objeto, entorno)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/simulacion")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<PoliticaDePlan.Veredicto> simular(@QueryParam("entorno") String entorno, java.util.List<PoliticaDePlan.Cambio> cambios) {
        return Uni.createFrom().item(() -> s.simular(entorno, cambios));
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer plan.json | `roles/storage.objectViewer` en el bucket de artefactos |
| Plan/apply | Las SAs de plan y apply del pipeline (no este servicio) |

## 8. Qué NO hacer desde Java
- No registres el contenido de `plan.json`: puede tener secretos.
- No uses la política como única revisión: la humana sigue en prod.
- No le des a este servicio permisos de apply.
- No relajes bloqueos en prod con una variable de entorno.
