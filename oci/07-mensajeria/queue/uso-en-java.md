# Oracle OCI · Mensajería · Queue · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **consumidor correcto** de OCI Queue: recibe con *long polling*, procesa de forma idempotente, **borra solo al terminar** y, si falla, pospone el mensaje extendiendo su visibilidad con *backoff* exponencial (la DLQ la aplica la cola al superar las entregas).

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

### 2.2 Política de reintento (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
/** Backoff por visibilidad: tras un fallo, el mensaje se oculta más tiempo en cada entrega. Puro. */
public class PoliticaDeReintento {

    public record Decision(boolean posponer, int segundos) { }

    private final int baseSegundos;
    private final int topeSegundos;

    public PoliticaDeReintento(int baseSegundos, int topeSegundos) {
        this.baseSegundos = baseSegundos;
        this.topeSegundos = topeSegundos;
    }

    /** deliveryCount empieza en 1. La DLQ la decide la cola (dead_letter_queue_delivery_count). */
    public Decision trasFallo(int deliveryCount) {
        int exp = Math.max(0, Math.min(deliveryCount - 1, 16));
        long s = (long) baseSegundos << exp;
        return new Decision(true, (int) Math.min(topeSegundos, s));
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.queue.QueueClient;
import com.oracle.bmc.queue.model.PutMessagesDetails;
import com.oracle.bmc.queue.model.PutMessagesDetailsEntry;
import com.oracle.bmc.queue.model.UpdateMessageDetails;
import com.oracle.bmc.queue.requests.DeleteMessageRequest;
import com.oracle.bmc.queue.requests.GetMessagesRequest;
import com.oracle.bmc.queue.requests.PutMessagesRequest;
import com.oracle.bmc.queue.requests.UpdateMessageRequest;
import java.util.List;

/** Adaptador del SDK: recibir con long polling, confirmar (borrar) y posponer (extender visibilidad). */
public class ColaOci implements AutoCloseable {

    public record Mensaje(String receipt, String contenido, int entregas) { }

    private final QueueClient cliente;
    private final String colaId;

    public ColaOci(QueueClient cliente, String colaId) {
        this.cliente = cliente;
        this.colaId = colaId;
    }

    public void enviar(String contenido) {
        cliente.putMessages(PutMessagesRequest.builder().queueId(colaId)
            .putMessagesDetails(PutMessagesDetails.builder()
                .messages(List.of(PutMessagesDetailsEntry.builder().content(contenido).build())).build())
            .build());
    }

    public List<Mensaje> recibir(int max) {
        return cliente.getMessages(GetMessagesRequest.builder().queueId(colaId)
                .limit(max).timeoutInSeconds(20).visibilityInSeconds(120).build())
            .getGetMessages().getMessages().stream()
            .map(m -> new Mensaje(m.getReceipt(), m.getContent(), m.getDeliveryCount()))
            .toList();
    }

    public void confirmar(String receipt) {
        cliente.deleteMessage(DeleteMessageRequest.builder().queueId(colaId).messageReceipt(receipt).build());
    }

    public void posponer(String receipt, int segundos) {
        cliente.updateMessage(UpdateMessageRequest.builder().queueId(colaId).messageReceipt(receipt)
            .updateMessageDetails(UpdateMessageDetails.builder().visibilityInSeconds(segundos).build()).build());
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
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDeFacturacion {

    public record Resumen(int recibidos, int procesados, int duplicados, int pospuestos) { }

    private final ColaOci cola;
    private final PoliticaDeReintento politica = new PoliticaDeReintento(15, 900);
    // idempotencia: en producción, tabla con clave única (id de pedido) en la base
    private final Set<String> facturados = ConcurrentHashMap.newKeySet();

    public ServicioDeFacturacion(ColaOci cola) {
        this.cola = cola;
    }

    public String encolar(String idPedido) {
        cola.enviar(idPedido);
        return "encolado " + idPedido;
    }

    /** Un ciclo del consumidor; en producción corre en un bucle o un @Scheduled. */
    public Resumen procesarLote() {
        int ok = 0, dup = 0, pos = 0;
        var lote = cola.recibir(10);
        for (var m : lote) {
            try {
                if (!m.contenido().matches("P-[0-9]{1,12}")) {
                    throw new IllegalArgumentException("pedido inválido");
                }
                if (facturados.add(m.contenido())) {
                    ok++;
                } else {
                    dup++;
                }
                cola.confirmar(m.receipt()); // borrar solo al terminar
            } catch (RuntimeException e) {
                cola.posponer(m.receipt(), politica.trasFallo(m.entregas()).segundos());
                pos++;
            }
        }
        return new Resumen(lote.size(), ok, dup, pos);
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
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class FacturacionConfiguracion {

    @Bean(destroyMethod = "close")
    ColaOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${cola.id}") String id, @Value("${cola.endpoint}") String endpoint) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ColaOci(QueueClient.builder().endpoint(endpoint).build(auth), id);
    }

    @Bean
    ServicioDeFacturacion servicio(ColaOci a) {
        return new ServicioDeFacturacion(a);
    }
}

@RestController
@RequestMapping("/mensajeria/facturacion")
class FacturacionControlador {

    private final ServicioDeFacturacion s;

    FacturacionControlador(ServicioDeFacturacion s) {
        this.s = s;
    }

    @PostMapping("/{pedido}")
    String encolar(@PathVariable String pedido) {
        return s.encolar(pedido);
    }

    @PostMapping("/lote")
    ServicioDeFacturacion.Resumen procesar() {
        return s.procesarLote();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.queue.QueueClient;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/mensajeria/facturacion")
class FacturacionReactivoControlador {

    private final ServicioDeFacturacion s;

    FacturacionReactivoControlador(ServicioDeFacturacion s) {
        this.s = s;
    }

    @PostMapping("/{pedido}")
    Mono<String> encolar(@PathVariable String pedido) {
        return Mono.fromCallable(() -> s.encolar(pedido)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/lote")
    Mono<ServicioDeFacturacion.Resumen> procesar() {
        return Mono.fromCallable(() -> s.procesarLote()).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class FacturacionProductores {

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
    ColaOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ColaOci(QueueClient.builder().endpoint(endpoint).build(auth), id);
    }

    void cerrar(@Disposes ColaOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeFacturacion servicio(ColaOci a) {
        return new ServicioDeFacturacion(a);
    }
}

@Path("/mensajeria/facturacion")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class FacturacionRecurso {

    @Inject
    ServicioDeFacturacion s;

    @POST
    @Path("/{pedido}")
    public String encolar(@PathParam("pedido") String pedido) {
        return s.encolar(pedido);
    }

    @POST
    @Path("/lote")
    public ServicioDeFacturacion.Resumen procesar() {
        return s.procesarLote();
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
import jakarta.ws.rs.PathParam;

@Path("/reactivo/mensajeria/facturacion")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class FacturacionRecursoReactivo {

    @Inject
    ServicioDeFacturacion s;

    @POST
    @Path("/{pedido}")
    public Uni<String> encolar(@PathParam("pedido") String pedido) {
        return Uni.createFrom().item(() -> s.encolar(pedido)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/lote")
    public Uni<ServicioDeFacturacion.Resumen> procesar() {
        return Uni.createFrom().item(() -> s.procesarLote()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Enviar, recibir, borrar y posponer | `Allow dynamic-group consumidores-facturacion to use queues in compartment tienda-prod where target.queue.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No borres el mensaje al recibirlo.
- No uses `region(...)` para `QueueClient`: necesita el `messages_endpoint` de la cola.
- No hagas `GetMessages` en bucle sin `timeoutInSeconds`.
- No llames al SDK bloqueante dentro del hilo de eventos en WebFlux/Mutiny.
- No reintentes infinitamente: deja que la DLQ actúe.
