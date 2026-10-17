# Google Cloud · Caso integrado · Tienda online · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

El corazón del caso: **outbox + relay + inbox**. El núcleo puro define el relay (publica lotes, marca enviados y aparta los fallidos definitivos sin detener el lote) y el inbox (procesa solo ids nuevos). El adaptador publica con `Publisher` de Pub/Sub, **espera la confirmación** antes de que el relay marque enviado, usa la clave de orden del pedido y reanuda la clave tras un fallo. El servicio de demostración guarda el outbox en memoria; en la app real es la tabla de [`ejemplos/sql/outbox.sql`](ejemplos/sql/outbox.sql) escrita en la misma transacción que el pedido (`@Transactional` o Panache).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
pubsub:
  tema: pedido-pagado
  endpoint: southamerica-west1-pubsub.googleapis.com:443
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
pubsub.tema=pedido-pagado
pubsub.endpoint=southamerica-west1-pubsub.googleapis.com:443
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

### 2.2 Outbox, relay e inbox (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.function.Function;

/** Relay del outbox e inbox idempotente. Puro: los repositorios y el publicador son interfaces. */
public final class Outbox {

    private Outbox() { }

    public record Evento(String id, String tipo, String clave, String carga, int intentos) { }

    public interface Repositorio {
        /** En SQL: SELECT … WHERE estado='PENDIENTE' … FOR UPDATE SKIP LOCKED. */
        List<Evento> pendientes(int max);

        void marcarEnviado(String id);

        void registrarFallo(String id, boolean definitivo);
    }

    public interface Publicador {
        void publicar(Evento e);
    }

    public record Resultado(int enviados, int reintentables, int fallidos) { }

    public static final class Relay {
        private final Repositorio repo;
        private final Publicador publicador;
        private final int maxIntentos;

        public Relay(Repositorio repo, Publicador publicador, int maxIntentos) {
            this.repo = repo;
            this.publicador = publicador;
            this.maxIntentos = maxIntentos;
        }

        /** Un evento que falla no detiene al resto del lote. */
        public Resultado ejecutar(int lote) {
            int ok = 0, reint = 0, mal = 0;
            for (Evento e : repo.pendientes(lote)) {
                try {
                    publicador.publicar(e);
                    repo.marcarEnviado(e.id());
                    ok++;
                } catch (RuntimeException ex) {
                    boolean definitivo = e.intentos() + 1 >= maxIntentos;
                    repo.registrarFallo(e.id(), definitivo);
                    if (definitivo) {
                        mal++;
                    } else {
                        reint++;
                    }
                }
            }
            return new Resultado(ok, reint, mal);
        }
    }

    /** Inbox: procesa solo si el id es nuevo (en SQL, INSERT con clave única). */
    public static final class Inbox {
        private final Function<String, Boolean> registrarSiNuevo;

        public Inbox(Function<String, Boolean> registrarSiNuevo) {
            this.registrarSiNuevo = registrarSiNuevo;
        }

        public boolean procesar(String idEvento, Runnable efecto) {
            if (!registrarSiNuevo.apply(idEvento)) {
                return false; // duplicado: se ignora sin error
            }
            efecto.run();
            return true;
        }
    }
}
```

### 2.3 Adaptador de Pub/Sub
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.PubsubMessage;
import com.google.pubsub.v1.TopicName;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;

/** Adaptador: publica el evento del outbox en Pub/Sub con clave de orden = pedido. */
public class PublicadorGcp implements Outbox.Publicador, AutoCloseable {

    private final Publisher publisher;

    public PublicadorGcp(GoogleCredentials cred, String proyecto, String tema, String endpointRegional) {
        try {
            this.publisher = Publisher.newBuilder(TopicName.of(proyecto, tema))
                .setCredentialsProvider(FixedCredentialsProvider.create(cred))
                .setEnableMessageOrdering(true)
                .setEndpoint(endpointRegional)        // el orden exige endpoint regional
                .build();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @Override
    public void publicar(Outbox.Evento e) {
        var msg = PubsubMessage.newBuilder()
            .setData(ByteString.copyFromUtf8(e.carga()))
            .putAttributes("id", e.id())             // para el inbox del consumidor
            .putAttributes("tipo", e.tipo())
            .setOrderingKey(e.clave())
            .build();
        try {
            publisher.publish(msg).get(10, TimeUnit.SECONDS);   // confirmar antes de marcar enviado
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(ex);
        } catch (ExecutionException | java.util.concurrent.TimeoutException ex) {
            publisher.resumePublish(e.clave());     // tras un fallo, la clave queda pausada
            throw new IllegalStateException("no se publicó " + e.id(), ex);
        }
    }

    @Override
    public void close() {
        publisher.shutdown();
        try {
            publisher.awaitTermination(10, TimeUnit.SECONDS);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDePedidos {

    public record Pedido(String idPedido, String total) { }

    private final PublicadorGcp publicador;
    // Demo en memoria; en la app real es la tabla OUTBOX en la misma transacción que el pedido.
    private final Map<String, Outbox.Evento> outbox = new ConcurrentHashMap<>();
    private final Map<String, String> estados = new ConcurrentHashMap<>();

    public ServicioDePedidos(PublicadorGcp publicador) {
        this.publicador = publicador;
    }

    public String crear(Pedido p) {
        if (!p.idPedido().matches("P-[0-9]{1,12}") || !p.total().matches("[0-9]{1,7}(\\.[0-9]{2})?")) {
            throw new IllegalArgumentException("pedido inválido");
        }
        String id = UUID.randomUUID().toString();
        // INSERT pedido + INSERT outbox en una sola transacción
        outbox.put(id, new Outbox.Evento(id, "PedidoPagado.v1", p.idPedido(), "{\"total\":" + p.total() + "}", 0));
        estados.put(id, "PENDIENTE");
        return id;
    }

    public Outbox.Resultado relay() {
        var repo = new Outbox.Repositorio() {
            public List<Outbox.Evento> pendientes(int max) {
                return new ArrayList<>(outbox.values()).stream().filter(e -> "PENDIENTE".equals(estados.get(e.id()))).limit(max).toList();
            }

            public void marcarEnviado(String id) {
                estados.put(id, "ENVIADO");
            }

            public void registrarFallo(String id, boolean definitivo) {
                outbox.computeIfPresent(id, (k, e) -> new Outbox.Evento(e.id(), e.tipo(), e.clave(), e.carga(), e.intentos() + 1));
                if (definitivo) {
                    estados.put(id, "FALLIDO");
                }
            }
        };
        return new Outbox.Relay(repo, publicador, 5).ejecutar(50);
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
class PedidosConfiguracion {

    @Bean(destroyMethod = "close")
    PublicadorGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${pubsub.tema}") String tema, @Value("${pubsub.endpoint}") String endpoint) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PublicadorGcp(cred, proyecto, tema, endpoint);
    }

    @Bean
    ServicioDePedidos servicio(PublicadorGcp a) {
        return new ServicioDePedidos(a);
    }
}

@RestController
@RequestMapping("/tienda/pedidos")
class PedidosControlador {

    private final ServicioDePedidos s;

    PedidosControlador(ServicioDePedidos s) {
        this.s = s;
    }

    @PostMapping("")
    String crear(@RequestBody ServicioDePedidos.Pedido p) {
        return s.crear(p);
    }

    @PostMapping("/relay")
    Outbox.Resultado relay() {
        return s.relay();
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
@RequestMapping("/reactivo/tienda/pedidos")
class PedidosReactivoControlador {

    private final ServicioDePedidos s;

    PedidosReactivoControlador(ServicioDePedidos s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<String> crear(@RequestBody ServicioDePedidos.Pedido p) {
        return Mono.fromCallable(() -> s.crear(p));
    }

    @PostMapping("/relay")
    Mono<Outbox.Resultado> relay() {
        return Mono.fromCallable(() -> s.relay()).subscribeOn(Schedulers.boundedElastic());
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
class PedidosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "pubsub.tema")
    String tema;

    @ConfigProperty(name = "pubsub.endpoint")
    String endpoint;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PublicadorGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PublicadorGcp(cred, proyecto, tema, endpoint);
    }

    void cerrar(@Disposes PublicadorGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePedidos servicio(PublicadorGcp a) {
        return new ServicioDePedidos(a);
    }
}

@Path("/tienda/pedidos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class PedidosRecurso {

    @Inject
    ServicioDePedidos s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public String crear(ServicioDePedidos.Pedido p) {
        return s.crear(p);
    }

    @POST
    @Path("/relay")
    public Outbox.Resultado relay() {
        return s.relay();
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

@Path("/reactivo/tienda/pedidos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class PedidosRecursoReactivo {

    @Inject
    ServicioDePedidos s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> crear(ServicioDePedidos.Pedido p) {
        return Uni.createFrom().item(() -> s.crear(p));
    }

    @POST
    @Path("/relay")
    public Uni<Outbox.Resultado> relay() {
        return Uni.createFrom().item(() -> s.relay()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Publicar en el tema | `roles/pubsub.publisher` en `pedido-pagado` para `run-pedidos` |
| Consumir (push) | `roles/run.invoker` para `pubsub-push` en facturación |

## 8. Qué NO hacer desde Java
- No publiques dentro de la transacción de base de datos: escribe el outbox y publica después con el relay.
- No marques enviado antes de la confirmación de Pub/Sub.
- No proceses un evento sin pasar por el inbox.
- No pongas datos de tarjeta en eventos.
- No corras varios relays sin `SKIP LOCKED`.
