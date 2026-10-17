# Google Cloud · Compute · Cloud Run · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Una **llamada servicio-a-servicio** correcta hacia un Cloud Run privado: obtiene un **ID token** con `IdTokenCredentials` (audiencia = URL base del servicio) desde las credenciales ADC, respeta un **plazo total** y reintenta solo métodos seguros (o con clave de idempotencia) ante 429/5xx transitorios. Dentro de Cloud Run, ADC ya entrega credenciales capaces de emitir ID tokens.

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

### 2.2 Política de llamada (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.Set;

/** Política de llamada servicio-a-servicio: plazo total, reintentos solo seguros, backoff. Pura. */
public class PoliticaDeLlamada {

    public record Decision(boolean reintentar, Duration espera) { }

    private static final Set<String> IDEMPOTENTES = Set.of("GET", "HEAD", "PUT", "DELETE", "OPTIONS");
    private static final Set<Integer> TRANSITORIOS = Set.of(429, 502, 503, 504);

    private final int maxIntentos;
    private final Duration base;

    public PoliticaDeLlamada(int maxIntentos, Duration base) {
        this.maxIntentos = maxIntentos;
        this.base = base;
    }

    /** POST solo se reintenta si lleva Idempotency-Key. Respeta el plazo restante del llamador. */
    public Decision tras(String metodo, boolean conClaveIdempotencia, int estado, int intento, Duration restante) {
        boolean seguro = IDEMPOTENTES.contains(metodo) || conClaveIdempotencia;
        Duration espera = base.multipliedBy(1L << Math.min(intento, 10));
        boolean hayTiempo = restante.compareTo(espera.plusMillis(200)) > 0;
        return new Decision(seguro && TRANSITORIOS.contains(estado) && intento + 1 < maxIntentos && hayTiempo, espera);
    }

    /** La audiencia del ID token es la URL base del servicio (sin ruta). */
    public static String audiencia(String url) {
        var u = java.net.URI.create(url);
        if (!"https".equals(u.getScheme()) || u.getHost() == null) {
            throw new IllegalArgumentException("URL de servicio inválida");
        }
        return "https://" + u.getHost();
    }
}
```

### 2.3 Adaptador (google-auth-library + HttpClient)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.IdTokenCredentials;
import com.google.auth.oauth2.IdTokenProvider;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;

/** Adaptador: llama a un servicio privado de Cloud Run con ID token y aplica la política. */
public class LlamadorRun implements AutoCloseable {

    public record Respuesta(int estado, String cuerpo, int intentos) { }

    private final GoogleCredentials cred;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
    private final PoliticaDeLlamada politica = new PoliticaDeLlamada(3, Duration.ofMillis(200));

    public LlamadorRun(GoogleCredentials cred) {
        this.cred = cred;
    }

    private String idToken(String audiencia) throws IOException {
        if (!(cred instanceof IdTokenProvider proveedor)) {
            throw new IllegalStateException("estas credenciales no emiten ID tokens (en local usa suplantación de una SA)");
        }
        var t = IdTokenCredentials.newBuilder().setIdTokenProvider(proveedor).setTargetAudience(audiencia).build();
        t.refreshIfExpired();
        return t.getIdToken().getTokenValue();
    }

    public Respuesta get(String url, Duration plazo) {
        Instant limite = Instant.now().plus(plazo);
        try {
            String token = idToken(PoliticaDeLlamada.audiencia(url));
            for (int intento = 0; ; intento++) {
                Duration restante = Duration.between(Instant.now(), limite);
                var req = HttpRequest.newBuilder(URI.create(url)).timeout(restante).GET()
                    .header("Authorization", "Bearer " + token).build();
                var r = http.send(req, HttpResponse.BodyHandlers.ofString());
                var d = politica.tras("GET", false, r.statusCode(), intento, Duration.between(Instant.now(), limite));
                if (!d.reintentar()) {
                    return new Respuesta(r.statusCode(), r.body(), intento + 1);
                }
                Thread.sleep(d.espera().toMillis());
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    @Override
    public void close() {
        // HttpClient no requiere cierre explícito en Java 21 para este uso
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;

public class ServicioDePrecios {

    private final LlamadorRun run;
    private final String urlPrecios = "https://precios-abc123-tl.a.run.app";

    public ServicioDePrecios(LlamadorRun run) {
        this.run = run;
    }

    public LlamadorRun.Respuesta precio(String sku) {
        if (!sku.matches("[A-Z]{3}-[0-9]{2,6}")) {
            throw new IllegalArgumentException("sku inválido");
        }
        return run.get(urlPrecios + "/precios/" + sku, Duration.ofSeconds(2));
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
class PreciosConfiguracion {

    @Bean(destroyMethod = "close")
    LlamadorRun adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new LlamadorRun(cred);
    }

    @Bean
    ServicioDePrecios servicio(LlamadorRun a) {
        return new ServicioDePrecios(a);
    }
}

@RestController
@RequestMapping("/compute/precios")
class PreciosControlador {

    private final ServicioDePrecios s;

    PreciosControlador(ServicioDePrecios s) {
        this.s = s;
    }

    @GetMapping("/{sku}")
    LlamadorRun.Respuesta precio(@PathVariable String sku) {
        return s.precio(sku);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/compute/precios")
class PreciosReactivoControlador {

    private final ServicioDePrecios s;

    PreciosReactivoControlador(ServicioDePrecios s) {
        this.s = s;
    }

    @GetMapping("/{sku}")
    Mono<LlamadorRun.Respuesta> precio(@PathVariable String sku) {
        return Mono.fromCallable(() -> s.precio(sku)).subscribeOn(Schedulers.boundedElastic());
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
class PreciosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    LlamadorRun adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new LlamadorRun(cred);
    }

    void cerrar(@Disposes LlamadorRun a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePrecios servicio(LlamadorRun a) {
        return new ServicioDePrecios(a);
    }
}

@Path("/compute/precios")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class PreciosRecurso {

    @Inject
    ServicioDePrecios s;

    @GET
    @Path("/{sku}")
    public LlamadorRun.Respuesta precio(@PathParam("sku") String sku) {
        return s.precio(sku);
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

@Path("/reactivo/compute/precios")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class PreciosRecursoReactivo {

    @Inject
    ServicioDePrecios s;

    @GET
    @Path("/{sku}")
    public Uni<LlamadorRun.Respuesta> precio(@PathParam("sku") String sku) {
        return Uni.createFrom().item(() -> s.precio(sku)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Invocar el servicio destino | `roles/run.invoker` sobre **ese** servicio para la SA del llamador |

## 8. Qué NO hacer desde Java
- No hagas público un servicio interno para «evitar el token».
- No reintentes POST sin clave de idempotencia.
- No uses timeouts mayores que el plazo del llamador.
- No arranques hilos de fondo con CPU solo en peticiones.
- No pidas el ID token en cada llamada si puedes reutilizarlo hasta que venza (la biblioteca lo cachea).
