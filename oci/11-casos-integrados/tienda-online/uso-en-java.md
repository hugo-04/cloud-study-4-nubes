# Oracle OCI · Caso integrado · Tienda online · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

El corazón del caso: **outbox + relay + inbox**. El núcleo puro define el relay (publica lotes, marca enviados y aparta los fallidos definitivos sin detener el lote) y el inbox (procesa solo ids nuevos). El adaptador publica con `QueueClient`. El servicio de demostración guarda el outbox en memoria; en la app real es la tabla de [`ejemplos/sql/outbox.sql`](ejemplos/sql/outbox.sql) escrita en la misma transacción que el pedido (`JdbcTemplate`/`@Transactional` o Panache).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
cola:
  id: ocid1.queue.oc1.sa-saopaulo-1.aaaa
  endpoint: https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
cola.id=ocid1.queue.oc1.sa-saopaulo-1.aaaa
cola.endpoint=https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com
```

## 2. Núcleo común

### 2.1 Autenticación según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
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

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.queue.QueueClient;
import com.oracle.bmc.queue.model.PutMessagesDetails;
import com.oracle.bmc.queue.model.PutMessagesDetailsEntry;
import com.oracle.bmc.queue.requests.PutMessagesRequest;
import java.util.List;

/** Adaptador del SDK: publica el evento del outbox en la cola de facturación. */
public class PublicadorOci implements Outbox.Publicador, AutoCloseable {

    private final QueueClient cola;
    private final String colaId;

    public PublicadorOci(QueueClient cola, String colaId) {
        this.cola = cola;
        this.colaId = colaId;
    }

    @Override
    public void publicar(Outbox.Evento e) {
        // sobre mínimo: id para el inbox, tipo versionado y la carga
        String sobre = "{\"id\":\"" + e.id() + "\",\"tipo\":\"" + e.tipo() + "\",\"clave\":\"" + e.clave()
            + "\",\"carga\":" + e.carga() + "}";
        cola.putMessages(PutMessagesRequest.builder().queueId(colaId)
            .putMessagesDetails(PutMessagesDetails.builder()
                .messages(List.of(PutMessagesDetailsEntry.builder().content(sobre).build())).build())
            .build());
    }

    @Override
    public void close() {
        cola.close();
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

    private final PublicadorOci publicador;
    // Demo en memoria; en la app real es la tabla OUTBOX en la misma transacción que el pedido.
    private final Map<String, Outbox.Evento> outbox = new ConcurrentHashMap<>();
    private final Map<String, String> estados = new ConcurrentHashMap<>();

    public ServicioDePedidos(PublicadorOci publicador) {
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
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.queue.QueueClient;
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
    PublicadorOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${cola.id}") String id, @Value("${cola.endpoint}") String endpoint) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new PublicadorOci(QueueClient.builder().endpoint(endpoint).build(auth), id);
    }

    @Bean
    ServicioDePedidos servicio(PublicadorOci a) {
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
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.queue.QueueClient;
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
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.queue.QueueClient;
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

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "cola.id")
    String id;

    @ConfigProperty(name = "cola.endpoint")
    String endpoint;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PublicadorOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new PublicadorOci(QueueClient.builder().endpoint(endpoint).build(auth), id);
    }

    void cerrar(@Disposes PublicadorOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePedidos servicio(PublicadorOci a) {
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
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.queue.QueueClient;
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
| Acción en Java | Política |
|---|---|
| Publicar en la cola (workload identity) | Política con `request.principal.type = 'workload'`, namespace y service account (ver Terraform del caso) |

## 8. Qué NO hacer desde Java
- No publiques dentro de la transacción de base de datos (alarga bloqueos): escribe el outbox y publica después con el relay.
- No marques enviado antes de publicar.
- No proceses un evento sin pasar por el inbox.
- No pongas datos de tarjeta en eventos.
- No corras varios relays sin `SKIP LOCKED` (o un único relay con elección de líder).
