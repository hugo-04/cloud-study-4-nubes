# Google Cloud · Storage · Eventos de Cloud Storage · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **consumidor push** de las notificaciones del bucket: la lógica pura lee los atributos (`bucketId`, `objectId`, `objectGeneration`, `eventType`), filtra por prefijo y extensión y **deduplica por `bucket/objeto#generación`**; el adaptador comprueba con `Storage.get(BlobId.of(bucket, objeto, generación))` que esa versión exacta siga existiendo antes de procesarla.

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

### 2.2 Procesador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** Decide qué hacer con una notificación de Cloud Storage recibida por Pub/Sub push. Puro. */
public class ProcesadorDeNotificaciones {

    /** Cuerpo del push de Pub/Sub. */
    public record Push(Mensaje message, String subscription) { }

    public record Mensaje(String messageId, Map<String, String> attributes) { }

    public enum Accion { PROCESAR, DUPLICADO, IGNORAR }

    public record Decision(Accion accion, String bucket, String objeto, Long generacion, String motivo) { }

    private final String prefijo;
    private final Set<String> extensiones;
    private final Set<String> vistos;

    public ProcesadorDeNotificaciones(String prefijo, Set<String> extensiones, int memoria) {
        this.prefijo = prefijo;
        this.extensiones = Set.copyOf(extensiones);
        this.vistos = Collections.synchronizedSet(Collections.newSetFromMap(new LinkedHashMap<String, Boolean>(16, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, Boolean> e) {
                return size() > memoria;
            }
        }));
    }

    public Decision decidir(Push p) {
        if (p == null || p.message() == null || p.message().attributes() == null) {
            return new Decision(Accion.IGNORAR, null, null, null, "mensaje incompleto");
        }
        var a = p.message().attributes();
        String bucket = a.get("bucketId");
        String objeto = a.get("objectId");
        String gen = a.get("objectGeneration");
        if (!"OBJECT_FINALIZE".equals(a.get("eventType")) || bucket == null || objeto == null || gen == null) {
            return new Decision(Accion.IGNORAR, bucket, objeto, null, "evento no relevante");
        }
        if (!objeto.startsWith(prefijo) || objeto.contains("..")) {
            return new Decision(Accion.IGNORAR, bucket, objeto, null, "fuera del prefijo");
        }
        String ext = objeto.substring(objeto.lastIndexOf('.') + 1).toLowerCase(java.util.Locale.ROOT);
        if (!extensiones.contains(ext)) {
            return new Decision(Accion.IGNORAR, bucket, objeto, null, "extensión no admitida");
        }
        long generacion = Long.parseLong(gen);
        // la generación identifica la versión exacta: dedupe por bucket/objeto#generación
        if (!vistos.add(bucket + "/" + objeto + "#" + generacion)) {
            return new Decision(Accion.DUPLICADO, bucket, objeto, generacion, "ya procesado");
        }
        return new Decision(Accion.PROCESAR, bucket, objeto, generacion, "ok");
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.util.Optional;

/** Adaptador: comprueba que la generación del evento sigue existiendo. */
public class ObjetosGcs implements AutoCloseable {

    public record Info(long bytes, String tipo) { }

    private final Storage storage;

    public ObjetosGcs(GoogleCredentials cred, String proyecto) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
    }

    public Optional<Info> generacion(String bucket, String objeto, long generacion) {
        var b = storage.get(BlobId.of(bucket, objeto, generacion));
        return b == null ? Optional.empty() : Optional.of(new Info(b.getSize(), b.getContentType()));
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Set;

public class ServicioDeNotificaciones {

    public record Resultado(String accion, String detalle) { }

    private final ObjetosGcs objetos;
    private final ProcesadorDeNotificaciones procesador = new ProcesadorDeNotificaciones("fotos/", Set.of("jpg", "png"), 10_000);

    public ServicioDeNotificaciones(ObjetosGcs objetos) {
        this.objetos = objetos;
    }

    /** Responde 2xx siempre que el mensaje se haya decidido (procesado, duplicado o ignorado): así no se reintenta. */
    public Resultado recibir(ProcesadorDeNotificaciones.Push p) {
        var d = procesador.decidir(p);
        if (d.accion() != ProcesadorDeNotificaciones.Accion.PROCESAR) {
            return new Resultado(d.accion().name(), d.motivo());
        }
        return objetos.generacion(d.bucket(), d.objeto(), d.generacion())
            .map(i -> new Resultado("PROCESAR", d.objeto() + " (" + i.bytes() + " bytes)"))
            .orElse(new Resultado("IGNORAR", "la generación ya no existe"));
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
class NotificacionesConfiguracion {

    @Bean(destroyMethod = "close")
    ObjetosGcs adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ObjetosGcs(cred, proyecto);
    }

    @Bean
    ServicioDeNotificaciones servicio(ObjetosGcs a) {
        return new ServicioDeNotificaciones(a);
    }
}

@RestController
@RequestMapping("/storage/eventos")
class NotificacionesControlador {

    private final ServicioDeNotificaciones s;

    NotificacionesControlador(ServicioDeNotificaciones s) {
        this.s = s;
    }

    @PostMapping("/push")
    ServicioDeNotificaciones.Resultado recibir(@RequestBody ProcesadorDeNotificaciones.Push p) {
        return s.recibir(p);
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
@RequestMapping("/reactivo/storage/eventos")
class NotificacionesReactivoControlador {

    private final ServicioDeNotificaciones s;

    NotificacionesReactivoControlador(ServicioDeNotificaciones s) {
        this.s = s;
    }

    @PostMapping("/push")
    Mono<ServicioDeNotificaciones.Resultado> recibir(@RequestBody ProcesadorDeNotificaciones.Push p) {
        return Mono.fromCallable(() -> s.recibir(p)).subscribeOn(Schedulers.boundedElastic());
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
class NotificacionesProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ObjetosGcs adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ObjetosGcs(cred, proyecto);
    }

    void cerrar(@Disposes ObjetosGcs a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeNotificaciones servicio(ObjetosGcs a) {
        return new ServicioDeNotificaciones(a);
    }
}

@Path("/storage/eventos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class NotificacionesRecurso {

    @Inject
    ServicioDeNotificaciones s;

    @POST
    @Path("/push")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeNotificaciones.Resultado recibir(ProcesadorDeNotificaciones.Push p) {
        return s.recibir(p);
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

@Path("/reactivo/storage/eventos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class NotificacionesRecursoReactivo {

    @Inject
    ServicioDeNotificaciones s;

    @POST
    @Path("/push")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeNotificaciones.Resultado> recibir(ProcesadorDeNotificaciones.Push p) {
        return Uni.createFrom().item(() -> s.recibir(p)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer la generación en el bucket de origen | `roles/storage.objectViewer` en el bucket |
| Recibir el push | Cloud Run privado: `roles/run.invoker` para la cuenta OIDC de la suscripción |

## 8. Qué NO hacer desde Java
- No respondas error a un duplicado: Pub/Sub lo reintentaría.
- No leas «el objeto actual»: lee la generación del evento.
- No uses la deduplicación en memoria con varias réplicas: compártela.
- No escribas el resultado donde dispara la notificación.
