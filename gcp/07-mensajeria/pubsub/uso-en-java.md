# Google Cloud · Mensajería · Pub/Sub · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Publicador y suscriptor bien hechos: el **procesador puro** deduplica por id de negocio y decide **ack** (procesado, duplicado o error permanente registrado) o **nack** (error transitorio, que reentrega la suscripción con backoff). El adaptador publica con **clave de orden** (`setEnableMessageOrdering`, `resumePublish` tras error) y suscribe con **flow control**, confirmando solo después de procesar.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
pubsub:
  tema: pedidos-pagados
  suscripcion: facturacion
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
pubsub.tema=pedidos-pagados
pubsub.suscripcion=facturacion
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
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/** Procesa un mensaje y decide ack/nack según el tipo de falla. Puro (el efecto de negocio se inyecta). */
public class ProcesadorDeMensajes {

    public enum Respuesta { ACK, NACK }

    /** Falla que vale la pena reintentar (base caída, timeout). */
    public static class Transitoria extends RuntimeException {
        public Transitoria(String m) {
            super(m);
        }
    }

    public interface Efecto {
        void aplicar(String clave, String datos, Map<String, String> atributos);
    }

    private final Efecto efecto;
    private final Set<String> hechos = ConcurrentHashMap.newKeySet(); // en producción: tabla con clave única
    private final AtomicLong rechazados = new AtomicLong();

    public ProcesadorDeMensajes(Efecto efecto) {
        this.efecto = efecto;
    }

    public Respuesta procesar(String idMensaje, String datos, Map<String, String> atributos) {
        String clave = atributos.getOrDefault("idEvento", idMensaje); // id de negocio si existe
        if (hechos.contains(clave)) {
            return Respuesta.ACK; // duplicado: confirmar sin repetir el efecto
        }
        try {
            efecto.aplicar(clave, datos, atributos);
            hechos.add(clave);
            return Respuesta.ACK;
        } catch (Transitoria t) {
            return Respuesta.NACK; // se reentrega con backoff de la suscripción
        } catch (RuntimeException permanente) {
            rechazados.incrementAndGet(); // registrar para revisión; reintentar no lo arreglará
            return Respuesta.ACK;
        }
    }

    public long rechazados() {
        return rechazados.get();
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.batching.FlowControlSettings;
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.pubsub.v1.MessageReceiver;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.cloud.pubsub.v1.Subscriber;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.ProjectSubscriptionName;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.TopicName;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/** Adaptador: publicador con clave de orden y suscriptor con flow control que delega al procesador puro. */
public class PubSubGcp implements AutoCloseable {

    private final Publisher publicador;
    private final Subscriber suscriptor;

    public PubSubGcp(GoogleCredentials cred, String proyecto, String tema, String suscripcion, ProcesadorDeMensajes procesador) {
        var cp = FixedCredentialsProvider.create(cred);
        try {
            this.publicador = Publisher.newBuilder(TopicName.of(proyecto, tema)).setCredentialsProvider(cp)
                .setEnableMessageOrdering(true).build();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.suscriptor = Subscriber.newBuilder(ProjectSubscriptionName.of(proyecto, suscripcion), (MessageReceiver) (m, consumidor) -> {
                var r = procesador.procesar(m.getMessageId(), m.getData().toStringUtf8(), m.getAttributesMap());
                if (r == ProcesadorDeMensajes.Respuesta.ACK) {
                    consumidor.ack(); // solo después de procesar
                } else {
                    consumidor.nack();
                }
            })
            .setCredentialsProvider(cp)
            .setFlowControlSettings(FlowControlSettings.newBuilder()
                .setMaxOutstandingElementCount(100L).setMaxOutstandingRequestBytes(50L * 1024 * 1024).build())
            .build();
        this.suscriptor.startAsync().awaitRunning();
    }

    public String publicar(String datos, String claveOrden, Map<String, String> atributos) {
        var m = PubsubMessage.newBuilder().setData(ByteString.copyFromUtf8(datos)).setOrderingKey(claveOrden)
            .putAllAttributes(atributos).build();
        try {
            return publicador.publish(m).get(10, TimeUnit.SECONDS);
        } catch (Exception e) {
            publicador.resumePublish(claveOrden); // tras un error, la clave queda pausada
            throw new IllegalStateException("no se pudo publicar", e);
        }
    }

    @Override
    public void close() {
        try {
            suscriptor.stopAsync().awaitTerminated(30, TimeUnit.SECONDS);
            publicador.shutdown();
            publicador.awaitTermination(10, TimeUnit.SECONDS);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;

public class ServicioDeEventos {

    public record Evento(String idEvento, String idCliente, String datos) { }

    private final PubSubGcp pubsub;

    public ServicioDeEventos(PubSubGcp pubsub) {
        this.pubsub = pubsub;
    }

    /** Clave de orden por cliente: sus eventos llegan en orden, los de distintos clientes en paralelo. */
    public String publicar(Evento e) {
        return pubsub.publicar(e.datos(), e.idCliente(), Map.of("idEvento", e.idEvento(), "tipo", "PedidoPagado.v1"));
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
class EventosConfiguracion {

    @Bean(destroyMethod = "close")
    PubSubGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${pubsub.tema}") String tema, @Value("${pubsub.suscripcion}") String suscripcion) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        var procesador = new ProcesadorDeMensajes((clave, datos, atributos) -> { /* facturar de forma idempotente */ });
        return new PubSubGcp(cred, proyecto, tema, suscripcion, procesador);
    }

    @Bean
    ServicioDeEventos servicio(PubSubGcp a) {
        return new ServicioDeEventos(a);
    }
}

@RestController
@RequestMapping("/mensajeria/eventos")
class EventosControlador {

    private final ServicioDeEventos s;

    EventosControlador(ServicioDeEventos s) {
        this.s = s;
    }

    @PostMapping("")
    String publicar(@RequestBody ServicioDeEventos.Evento e) {
        return s.publicar(e);
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
@RequestMapping("/reactivo/mensajeria/eventos")
class EventosReactivoControlador {

    private final ServicioDeEventos s;

    EventosReactivoControlador(ServicioDeEventos s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<String> publicar(@RequestBody ServicioDeEventos.Evento e) {
        return Mono.fromCallable(() -> s.publicar(e)).subscribeOn(Schedulers.boundedElastic());
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
class EventosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "pubsub.tema")
    String tema;

    @ConfigProperty(name = "pubsub.suscripcion")
    String suscripcion;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PubSubGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        var procesador = new ProcesadorDeMensajes((clave, datos, atributos) -> { /* facturar de forma idempotente */ });
        return new PubSubGcp(cred, proyecto, tema, suscripcion, procesador);
    }

    void cerrar(@Disposes PubSubGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEventos servicio(PubSubGcp a) {
        return new ServicioDeEventos(a);
    }
}

@Path("/mensajeria/eventos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EventosRecurso {

    @Inject
    ServicioDeEventos s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public String publicar(ServicioDeEventos.Evento e) {
        return s.publicar(e);
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

@Path("/reactivo/mensajeria/eventos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EventosRecursoReactivo {

    @Inject
    ServicioDeEventos s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> publicar(ServicioDeEventos.Evento e) {
        return Uni.createFrom().item(() -> s.publicar(e)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Publicar | `roles/pubsub.publisher` en el tema |
| Consumir | `roles/pubsub.subscriber` en la suscripción |

## 8. Qué NO hacer desde Java
- No hagas ack antes de procesar.
- No hagas nack de errores permanentes: los reentregarás para siempre.
- No crees un `Publisher` por mensaje.
- No olvides `resumePublish` tras un error con clave de orden.
- No bloquees el hilo de eventos de WebFlux/Mutiny esperando `publish().get()`.
