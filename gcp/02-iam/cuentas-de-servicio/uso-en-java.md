# Google Cloud · IAM · Cuentas de servicio y suplantación · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **emisor de tokens suplantados con reglas**: la lógica pura decide quién puede suplantar qué cuenta, con qué alcances y por cuánto tiempo (máx. 60 min); el adaptador llama a `IamCredentialsClient.generateAccessToken`. El ejemplo devuelve solo la huella y el vencimiento (los tokens no se exponen por HTTP). Para el caso simple de «mi código actúa como otra cuenta», basta `ImpersonatedCredentials` (ver `Credenciales` en 2.1).

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

### 2.2 Política de suplantación (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Reglas para emitir tokens suplantados: quién puede pedir qué cuenta, qué alcances y cuánto dura. Puro. */
public class PoliticaDeSuplantacion {

    public record Pedido(String solicitante, String cuenta, List<String> alcances, Duration vida) { }

    public record Decision(boolean permitido, String motivo) { }

    private final Map<String, Set<String>> permitidas; // solicitante -> cuentas que puede suplantar
    private final Set<String> alcancesPermitidos;
    private final Duration vidaMaxima;

    public PoliticaDeSuplantacion(Map<String, Set<String>> permitidas, Set<String> alcancesPermitidos, Duration vidaMaxima) {
        this.permitidas = Map.copyOf(permitidas);
        this.alcancesPermitidos = Set.copyOf(alcancesPermitidos);
        this.vidaMaxima = vidaMaxima;
    }

    public Decision evaluar(Pedido p) {
        if (!p.cuenta().matches("[a-z][a-z0-9-]{4,29}@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com")) {
            return new Decision(false, "cuenta de servicio inválida");
        }
        if (!permitidas.getOrDefault(p.solicitante(), Set.of()).contains(p.cuenta())) {
            return new Decision(false, p.solicitante() + " no puede suplantar a " + p.cuenta());
        }
        if (p.alcances().isEmpty() || !alcancesPermitidos.containsAll(p.alcances())) {
            return new Decision(false, "alcances no permitidos");
        }
        if (p.vida().isNegative() || p.vida().isZero() || p.vida().compareTo(vidaMaxima) > 0) {
            return new Decision(false, "vida del token fuera de rango (máx. " + vidaMaxima.toMinutes() + " min)");
        }
        return new Decision(true, "ok");
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.iam.credentials.v1.IamCredentialsClient;
import com.google.cloud.iam.credentials.v1.IamCredentialsSettings;
import com.google.cloud.iam.credentials.v1.ServiceAccountName;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.List;

/** Adaptador: genera tokens de acceso de vida corta como otra cuenta (IAM Credentials). */
public class SuplantacionGcp implements AutoCloseable {

    public record Token(String cuenta, Instant vence, String huella) { }

    private final IamCredentialsClient cliente;

    public SuplantacionGcp(GoogleCredentials cred) {
        try {
            this.cliente = IamCredentialsClient.create(IamCredentialsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Token emitir(String cuenta, List<String> alcances, java.time.Duration vida) {
        var r = cliente.generateAccessToken(ServiceAccountName.of("-", cuenta), List.of(), alcances,
            com.google.protobuf.Duration.newBuilder().setSeconds(vida.toSeconds()).build());
        // nunca devolvemos el token a un cliente HTTP en este ejemplo: solo su huella para auditoría
        String huella = Integer.toHexString(r.getAccessToken().hashCode());
        return new Token(cuenta, Instant.ofEpochSecond(r.getExpireTime().getSeconds()), huella);
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
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ServicioDeSuplantacion {

    public record Solicitud(String solicitante, String cuenta, List<String> alcances, int minutos) { }

    public record Resultado(boolean emitido, String motivo, SuplantacionGcp.Token token) { }

    private final SuplantacionGcp gcp;
    // En producción estas reglas viven en configuración versionada y revisada.
    private final PoliticaDeSuplantacion politica = new PoliticaDeSuplantacion(
        Map.of("tarea-reportes", Set.of("lector-ventas@modalima-datos-prod.iam.gserviceaccount.com")),
        Set.of("https://www.googleapis.com/auth/cloud-platform.read-only", "https://www.googleapis.com/auth/devstorage.read_only"),
        Duration.ofMinutes(60));

    public ServicioDeSuplantacion(SuplantacionGcp gcp) {
        this.gcp = gcp;
    }

    public Resultado emitir(Solicitud s) {
        var d = politica.evaluar(new PoliticaDeSuplantacion.Pedido(s.solicitante(), s.cuenta(), s.alcances(), Duration.ofMinutes(s.minutos())));
        if (!d.permitido()) {
            return new Resultado(false, d.motivo(), null);
        }
        return new Resultado(true, "ok", gcp.emitir(s.cuenta(), s.alcances(), Duration.ofMinutes(s.minutos())));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class SuplantacionConfiguracion {

    @Bean(destroyMethod = "close")
    SuplantacionGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SuplantacionGcp(cred);
    }

    @Bean
    ServicioDeSuplantacion servicio(SuplantacionGcp a) {
        return new ServicioDeSuplantacion(a);
    }
}

@RestController
@RequestMapping("/iam/suplantacion")
class SuplantacionControlador {

    private final ServicioDeSuplantacion s;

    SuplantacionControlador(ServicioDeSuplantacion s) {
        this.s = s;
    }

    @PostMapping("")
    ServicioDeSuplantacion.Resultado emitir(@RequestBody ServicioDeSuplantacion.Solicitud sol) {
        return s.emitir(sol);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/iam/suplantacion")
class SuplantacionReactivoControlador {

    private final ServicioDeSuplantacion s;

    SuplantacionReactivoControlador(ServicioDeSuplantacion s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<ServicioDeSuplantacion.Resultado> emitir(@RequestBody ServicioDeSuplantacion.Solicitud sol) {
        return Mono.fromCallable(() -> s.emitir(sol)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class SuplantacionProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SuplantacionGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SuplantacionGcp(cred);
    }

    void cerrar(@Disposes SuplantacionGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeSuplantacion servicio(SuplantacionGcp a) {
        return new ServicioDeSuplantacion(a);
    }
}

@Path("/iam/suplantacion")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class SuplantacionRecurso {

    @Inject
    ServicioDeSuplantacion s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeSuplantacion.Resultado emitir(ServicioDeSuplantacion.Solicitud sol) {
        return s.emitir(sol);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

@Path("/reactivo/iam/suplantacion")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class SuplantacionRecursoReactivo {

    @Inject
    ServicioDeSuplantacion s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeSuplantacion.Resultado> emitir(ServicioDeSuplantacion.Solicitud sol) {
        return Uni.createFrom().item(() -> s.emitir(sol)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Generar tokens como la cuenta destino | `roles/iam.serviceAccountTokenCreator` **sobre esa cuenta** (no en el proyecto) |
| API | Habilitar `iamcredentials.googleapis.com` |

## 8. Qué NO hacer desde Java
- No descargues ni uses llaves JSON.
- No devuelvas tokens por endpoints HTTP ni los registres.
- No pidas `cloud-platform` si basta un alcance de solo lectura (los roles IAM igual mandan).
- No encadenes suplantaciones sin necesidad (`delegates`).
