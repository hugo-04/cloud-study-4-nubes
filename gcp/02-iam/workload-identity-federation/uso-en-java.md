# Google Cloud · IAM · Workload Identity Federation · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: una **réplica local de la condición del proveedor** (emisor, audiencia, repositorio y rama permitidos por entorno, más su versión en CEL) para probar las reglas en el pipeline antes de aplicarlas, y un adaptador que carga el **archivo de configuración `external_account`** con `GoogleCredentials.fromStream` y hace el intercambio real para comprobar que funciona (sin exponer el token).

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

### 2.2 Condición (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Réplica local (para pruebas) de la condición del proveedor: repositorio y rama permitidos por entorno.
 * Puro: recibe los claims ya decodificados del token externo.
 */
public class CondicionDeFederacion {

    public record Regla(String entorno, String repositorio, List<String> refsPermitidas) { }

    public record Resultado(boolean permitido, String entorno, List<String> motivos) { }

    private final List<Regla> reglas;
    private final String emisorEsperado;
    private final String audienciaEsperada;

    public CondicionDeFederacion(List<Regla> reglas, String emisorEsperado, String audienciaEsperada) {
        this.reglas = List.copyOf(reglas);
        this.emisorEsperado = emisorEsperado;
        this.audienciaEsperada = audienciaEsperada;
    }

    public Resultado evaluar(Map<String, String> claims, String entorno) {
        var motivos = new ArrayList<String>();
        if (!emisorEsperado.equals(claims.get("iss"))) {
            motivos.add("emisor distinto");
        }
        if (!audienciaEsperada.equals(claims.get("aud"))) {
            motivos.add("audiencia distinta");
        }
        var regla = reglas.stream().filter(r -> r.entorno().equals(entorno)).findFirst();
        if (regla.isEmpty()) {
            motivos.add("entorno sin regla: " + entorno);
        } else {
            if (!regla.get().repositorio().equals(claims.get("repository"))) {
                motivos.add("repositorio no permitido");
            }
            if (!regla.get().refsPermitidas().contains(claims.getOrDefault("ref", ""))) {
                motivos.add("rama/ref no permitida para " + entorno);
            }
        }
        return new Resultado(motivos.isEmpty(), entorno, motivos);
    }

    /** La misma regla escrita en CEL para el atributo attribute_condition del proveedor. */
    public static String comoCel(Regla r) {
        String refs = String.join(" || ", r.refsPermitidas().stream().map(x -> "assertion.ref == '" + x + "'").toList());
        return "assertion.repository == '" + r.repositorio() + "' && (" + refs + ")";
    }
}
```

### 2.3 Adaptador de google-auth-library
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.List;

/** Adaptador: credenciales federadas desde el archivo de configuración (tipo external_account). */
public class FederacionGcp implements AutoCloseable {

    public record Estado(String tipo, Instant vence) { }

    private final GoogleCredentials base;

    public FederacionGcp(GoogleCredentials base) {
        this.base = base;
    }

    /** En el pipeline, la ruta suele venir de GOOGLE_APPLICATION_CREDENTIALS (ADC lo resuelve solo). */
    public Estado probar(String rutaConfiguracion) {
        try (var in = new FileInputStream(rutaConfiguracion)) {
            var cred = GoogleCredentials.fromStream(in).createScoped(List.of("https://www.googleapis.com/auth/cloud-platform"));
            cred.refreshIfExpired();
            var token = cred.getAccessToken();
            return new Estado(cred.getClass().getSimpleName(), token.getExpirationTime() == null ? null : token.getExpirationTime().toInstant());
        } catch (IOException e) {
            throw new UncheckedIOException("no se pudo intercambiar el token externo", e);
        }
    }

    public GoogleCredentials base() {
        return base;
    }

    @Override
    public void close() {
        // sin recursos que cerrar
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Map;

public class ServicioDeFederacion {

    private final FederacionGcp gcp;
    private final CondicionDeFederacion condicion = new CondicionDeFederacion(List.of(
            new CondicionDeFederacion.Regla("prod", "modalima/infra", List.of("refs/heads/main")),
            new CondicionDeFederacion.Regla("no-prod", "modalima/infra", List.of("refs/heads/main", "refs/heads/desarrollo"))),
        "https://ci.modalima.example", "https://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/ci-prod/providers/plataforma-ci");

    public ServicioDeFederacion(FederacionGcp gcp) {
        this.gcp = gcp;
    }

    public CondicionDeFederacion.Resultado simular(String entorno, Map<String, String> claims) {
        return condicion.evaluar(claims, entorno);
    }

    public FederacionGcp.Estado probar(String ruta) {
        return gcp.probar(ruta);
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
class FederacionConfiguracion {

    @Bean(destroyMethod = "close")
    FederacionGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FederacionGcp(cred);
    }

    @Bean
    ServicioDeFederacion servicio(FederacionGcp a) {
        return new ServicioDeFederacion(a);
    }
}

@RestController
@RequestMapping("/iam/federacion")
class FederacionControlador {

    private final ServicioDeFederacion s;

    FederacionControlador(ServicioDeFederacion s) {
        this.s = s;
    }

    @PostMapping("/simulacion")
    CondicionDeFederacion.Resultado simular(@RequestParam String entorno, @RequestBody java.util.Map<String, String> claims) {
        return s.simular(entorno, claims);
    }

    @GetMapping("/prueba")
    FederacionGcp.Estado probar(@RequestParam String ruta) {
        return s.probar(ruta);
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
@RequestMapping("/reactivo/iam/federacion")
class FederacionReactivoControlador {

    private final ServicioDeFederacion s;

    FederacionReactivoControlador(ServicioDeFederacion s) {
        this.s = s;
    }

    @PostMapping("/simulacion")
    Mono<CondicionDeFederacion.Resultado> simular(@RequestParam String entorno, @RequestBody java.util.Map<String, String> claims) {
        return Mono.fromCallable(() -> s.simular(entorno, claims));
    }

    @GetMapping("/prueba")
    Mono<FederacionGcp.Estado> probar(@RequestParam String ruta) {
        return Mono.fromCallable(() -> s.probar(ruta)).subscribeOn(Schedulers.boundedElastic());
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
class FederacionProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    FederacionGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FederacionGcp(cred);
    }

    void cerrar(@Disposes FederacionGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeFederacion servicio(FederacionGcp a) {
        return new ServicioDeFederacion(a);
    }
}

@Path("/iam/federacion")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class FederacionRecurso {

    @Inject
    ServicioDeFederacion s;

    @POST
    @Path("/simulacion")
    @Consumes(MediaType.APPLICATION_JSON)
    public CondicionDeFederacion.Resultado simular(@QueryParam("entorno") String entorno, java.util.Map<String, String> claims) {
        return s.simular(entorno, claims);
    }

    @GET
    @Path("/prueba")
    public FederacionGcp.Estado probar(@QueryParam("ruta") String ruta) {
        return s.probar(ruta);
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

@Path("/reactivo/iam/federacion")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class FederacionRecursoReactivo {

    @Inject
    ServicioDeFederacion s;

    @POST
    @Path("/simulacion")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<CondicionDeFederacion.Resultado> simular(@QueryParam("entorno") String entorno, java.util.Map<String, String> claims) {
        return Uni.createFrom().item(() -> s.simular(entorno, claims));
    }

    @GET
    @Path("/prueba")
    public Uni<FederacionGcp.Estado> probar(@QueryParam("ruta") String ruta) {
        return Uni.createFrom().item(() -> s.probar(ruta)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Intercambio de tokens | Ninguno para el intercambio; los roles van al `principalSet` del repositorio |
| Modo suplantación | `roles/iam.workloadIdentityUser` del principalSet sobre la cuenta de servicio |

## 8. Qué NO hacer desde Java
- No confíes solo en tu réplica local: la condición real es la del proveedor (mantenlas sincronizadas con pruebas).
- No registres el token externo ni el federado.
- No guardes llaves JSON en el CI «como respaldo».
- No expongas el endpoint `/prueba` fuera del pipeline.
