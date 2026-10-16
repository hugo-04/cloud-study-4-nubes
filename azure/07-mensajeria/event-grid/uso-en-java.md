# Azure · Event Grid · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-messaging-eventgrid`, `azure-messaging-eventgrid-namespaces`, `azure-messaging-servicebus`, `azure-identity`). Verifica las vigentes.

Principios: eventos en **CloudEvents**, `data` mínimo (ids, no la entidad), publicación con **identidad**, consumo **idempotente** y tolerante al desorden.

```properties
# Spring Boot / Quarkus
app.eventgrid.endpoint=https://evgt-pedidos.eastus2-1.eventgrid.azure.net/api/events
app.eventgrid.namespace.endpoint=https://evgns-modalima.eastus2-1.eventgrid.azure.net
app.servicebus.namespace=sb-modalima.servicebus.windows.net
```
```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-eventgrid</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-eventgrid-namespaces</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
```
Rol del publicador: *EventGrid Data Sender* en el tópico. Tópico con `local_auth_enabled=false`.

## 1. Publicar eventos de dominio (tópico personalizado)

```java
import com.azure.core.models.CloudEvent;
import com.azure.core.models.CloudEventDataFormat;
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.EventGridPublisherClient;
import com.azure.messaging.eventgrid.EventGridPublisherClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

record PedidoCreado(String pedidoId, String clienteId, String region, BigDecimal total) {
}

@Configuration
class EventGridConfig {

    @Bean
    EventGridPublisherClient<CloudEvent> publicador(@Value("${app.eventgrid.endpoint}") String endpoint) {
        return new EventGridPublisherClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())      // sin claves del tópico
                .buildCloudEventPublisherClient();
    }
}

@Service
class PublicadorDeEventos {

    private static final String ORIGEN = "/servicios/pedidos";

    private final EventGridPublisherClient<CloudEvent> publicador;

    PublicadorDeEventos(EventGridPublisherClient<CloudEvent> publicador) {
        this.publicador = publicador;
    }

    /** `type` con prefijo de dominio y versión; `subject` jerárquico para filtrar por prefijo. */
    void pedidoCreado(PedidoCreado pedido) {
        CloudEvent evento = new CloudEvent(ORIGEN, "pe.modalima.pedido.creado",
                BinaryData.fromObject(pedido), CloudEventDataFormat.JSON, "application/json")
                .setId(UUID.randomUUID().toString())
                .setSubject("pedidos/" + pedido.region() + "/" + pedido.pedidoId())
                .setTime(OffsetDateTime.now());
        publicador.sendEvent(evento);
    }

    /** Varios eventos en una sola llamada (menos operaciones, más caudal). */
    void pedidosCreados(List<PedidoCreado> pedidos) {
        List<CloudEvent> lote = new ArrayList<>();
        for (PedidoCreado pedido : pedidos) {
            lote.add(new CloudEvent(ORIGEN, "pe.modalima.pedido.creado",
                    BinaryData.fromObject(pedido), CloudEventDataFormat.JSON, "application/json")
                    .setId(UUID.randomUUID().toString())
                    .setSubject("pedidos/" + pedido.region() + "/" + pedido.pedidoId())
                    .setTime(OffsetDateTime.now()));
        }
        publicador.sendEvents(lote);
    }
}
```
Importante: publicar el evento **después** de confirmar el cambio en la base de datos. Si necesitas garantía entre ambos, usa **Outbox** (ver [Service Bus · caso 7](../service-bus/casos-reales.md#caso-7--outbox-base-de-datos--mensaje-sin-perder-nada)).

## 2. Dominio multi-cliente: un tópico hijo por cliente

En un dominio con CloudEvents, el atributo `source` identifica el **tópico del dominio** destino (el cliente). *Verifica el mapeo vigente en la doc.*

```java
import com.azure.core.models.CloudEvent;
import com.azure.core.models.CloudEventDataFormat;
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.EventGridPublisherClient;
import com.azure.messaging.eventgrid.EventGridPublisherClientBuilder;

import java.util.Map;
import java.util.UUID;

class PublicadorDeDominio {

    private final EventGridPublisherClient<CloudEvent> dominio;

    PublicadorDeDominio(String endpointDelDominio) {
        this.dominio = new EventGridPublisherClientBuilder()
                .endpoint(endpointDelDominio)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildCloudEventPublisherClient();
    }

    /** El evento llega solo a las suscripciones del tópico hijo `clienteId`. */
    void publicarParaCliente(String clienteId, String tipo, Map<String, Object> datos) {
        dominio.sendEvent(new CloudEvent(clienteId, tipo, BinaryData.fromObject(datos), CloudEventDataFormat.JSON, "application/json")
                .setId(UUID.randomUUID().toString())
                .setSubject("facturas/" + datos.get("facturaId")));
    }
}
```

## 3. Consumir eventos de Azure vía Service Bus: rotación de secretos

Key Vault publica `Microsoft.KeyVault.SecretNearExpiry` a un tópico del sistema; una suscripción lo entrega a una cola; el consumidor rota el secreto. (Rotación completa en [Key Vault](../../03-secretos/key-vault/README.md).)

```java
import com.azure.core.models.CloudEvent;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.SystemEventNames;
import com.azure.messaging.eventgrid.systemevents.KeyVaultSecretNearExpiryEventData;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

interface RotadorDeSecretos {
    /** Debe ser idempotente: rotar dos veces el mismo secreto no puede romper nada. */
    void rotar(String vault, String secreto);
}

@Component
class ConsumidorDeVencimientos implements SmartLifecycle {

    private static final Logger LOG = LoggerFactory.getLogger(ConsumidorDeVencimientos.class);

    private final RotadorDeSecretos rotador;
    private final ServiceBusProcessorClient procesador;

    ConsumidorDeVencimientos(RotadorDeSecretos rotador, @Value("${app.servicebus.namespace}") String namespace) {
        this.rotador = rotador;
        this.procesador = new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(new DefaultAzureCredentialBuilder().build())
                .processor().queueName("kv-eventos")
                .disableAutoComplete()
                .processMessage(this::procesar)
                .processError(ctx -> LOG.error("Service Bus: {}", ctx.getException().toString()))
                .buildProcessorClient();
    }

    private void procesar(ServiceBusReceivedMessageContext ctx) {
        try {
            for (CloudEvent evento : CloudEvent.fromString(ctx.getMessage().getBody().toString())) {
                if (SystemEventNames.KEY_VAULT_SECRET_NEAR_EXPIRY.equals(evento.getType())) {
                    KeyVaultSecretNearExpiryEventData datos = evento.getData().toObject(KeyVaultSecretNearExpiryEventData.class);
                    LOG.info("Secreto {} del vault {} por vencer", datos.getObjectName(), datos.getVaultName());
                    rotador.rotar(datos.getVaultName(), datos.getObjectName());
                }
            }
            ctx.complete();
        } catch (IllegalArgumentException e) {
            ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("EVENTO_INVALIDO").setDeadLetterErrorDescription(e.getMessage()));
        } catch (RuntimeException e) {
            LOG.warn("Rotación fallida; se reintenta: {}", e.toString());
            ctx.abandon();
        }
    }

    @Override
    public void start() {
        procesador.start();
    }

    @Override
    public void stop() {
        procesador.close();
    }

    @Override
    public boolean isRunning() {
        return procesador.isRunning();
    }
}
```

## 4. Webhook con enrutamiento por `type` (eventos propios)

Handshake de CloudEvents (`OPTIONS`) + recepción. El despachador decide qué hacer según el `type`, con idempotencia por `id`. Para el detalle del handshake y la autenticación, ver [Eventos de Blob · Java](../../06-storage/eventos-blob/uso-en-java.md#1-webhook-imperativo-spring-mvc-handshake--recepción).

```java
import com.azure.core.models.CloudEvent;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.Map;
import java.util.function.Consumer;

record PedidoCreado(String pedidoId, String clienteId, String region, BigDecimal total) {
}

interface Deduplicador {
    /** true la primera vez que ve el id; false si ya lo había visto. */
    boolean primeraVez(String eventoId);
}

@RestController
@RequestMapping("/eventos/pedidos")
class WebhookPedidos {

    private final Deduplicador deduplicador;
    private final Map<String, Consumer<CloudEvent>> manejadores;

    WebhookPedidos(Deduplicador deduplicador) {
        this.deduplicador = deduplicador;
        this.manejadores = Map.of(
                "pe.modalima.pedido.creado", this::alCrearse,
                "pe.modalima.pedido.pagado", this::alPagarse);
    }

    @RequestMapping(method = RequestMethod.OPTIONS)
    ResponseEntity<Void> handshake(@RequestHeader(value = "WebHook-Request-Origin", required = false) String origen) {
        if (origen == null) {
            return ResponseEntity.badRequest().build();
        }
        return ResponseEntity.ok()
                .header("WebHook-Allowed-Origin", origen)
                .header("WebHook-Allowed-Rate", "*")
                .header("Allow", "POST")
                .build();
    }

    @PostMapping(consumes = {"application/cloudevents+json", "application/cloudevents-batch+json", "application/json"})
    ResponseEntity<Void> recibir(@RequestBody String cuerpo) {
        for (CloudEvent evento : CloudEvent.fromString(cuerpo)) {
            if (!deduplicador.primeraVez(evento.getId())) {
                continue;                                                    // duplicado: ya atendido
            }
            Consumer<CloudEvent> manejador = manejadores.get(evento.getType());
            if (manejador != null) {
                manejador.accept(evento);                                    // corto: encola o persiste, no trabajo de minutos
            }
        }
        return ResponseEntity.ok().build();                                  // 2xx = entregado
    }

    private void alCrearse(CloudEvent evento) {
        PedidoCreado pedido = evento.getData().toObject(PedidoCreado.class);
        // encolar en Service Bus / persistir para procesar luego
    }

    private void alPagarse(CloudEvent evento) {
        // ...
    }
}
```

## 5. Namespaces: entrega *pull* (tú controlas el ritmo)

Con tópicos de namespace, el consumidor **pide** eventos, los procesa y los **confirma**: parecido a un broker, con bloqueo por evento.

```java
import com.azure.core.models.CloudEvent;
import com.azure.core.models.CloudEventDataFormat;
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.namespaces.EventGridReceiverClient;
import com.azure.messaging.eventgrid.namespaces.EventGridReceiverClientBuilder;
import com.azure.messaging.eventgrid.namespaces.EventGridSenderClient;
import com.azure.messaging.eventgrid.namespaces.EventGridSenderClientBuilder;
import com.azure.messaging.eventgrid.namespaces.models.ReceiveDetails;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

class NamespaceTopic {

    private final EventGridSenderClient emisor;
    private final EventGridReceiverClient receptor;

    NamespaceTopic(String endpoint, String topico, String suscripcion) {
        var credencial = new DefaultAzureCredentialBuilder().build();
        this.emisor = new EventGridSenderClientBuilder().endpoint(endpoint).credential(credencial).topicName(topico).buildClient();
        this.receptor = new EventGridReceiverClientBuilder().endpoint(endpoint).credential(credencial)
                .topicName(topico).subscriptionName(suscripcion).buildClient();
    }

    void publicar(String json) {
        emisor.send(new CloudEvent("/servicios/pedidos", "pe.modalima.pedido.creado",
                BinaryData.fromString(json), CloudEventDataFormat.JSON, "application/json")
                .setId(UUID.randomUUID().toString()));
    }

    /** Recibe hasta 10 eventos, procesa y liquida: confirmar (acknowledge), devolver (release) o rechazar (reject). */
    void consumirUnaVez() {
        List<String> confirmar = new ArrayList<>();
        List<String> devolver = new ArrayList<>();
        List<String> rechazar = new ArrayList<>();

        for (ReceiveDetails detalle : receptor.receive(10, Duration.ofSeconds(10)).getDetails()) {
            String ficha = detalle.getBrokerProperties().getLockToken();     // identifica el bloqueo de ESTE evento
            CloudEvent evento = detalle.getEvent();
            try {
                if (evento.getData() == null) {
                    rechazar.add(ficha);                                     // inválido: no se reintenta
                } else {
                    // ... procesar de forma idempotente ...
                    confirmar.add(ficha);
                }
            } catch (RuntimeException e) {
                devolver.add(ficha);                                         // transitorio: vuelve a la cola
            }
        }
        if (!confirmar.isEmpty()) {
            receptor.acknowledge(confirmar);
        }
        if (!devolver.isEmpty()) {
            receptor.release(devolver);
        }
        if (!rechazar.isEmpty()) {
            receptor.reject(rechazar);
        }
    }
}
```
Rol del consumidor: *EventGrid Data Receiver* en el tópico del namespace. Crea la suscripción *pull* con la CLI ([ejemplo](ejemplos/cli/event-grid.sh)).

## 6. Reactivo (Reactor / WebFlux)

```java
import com.azure.core.models.CloudEvent;
import com.azure.core.models.CloudEventDataFormat;
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.EventGridPublisherAsyncClient;
import com.azure.messaging.eventgrid.EventGridPublisherClientBuilder;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.UUID;

record PedidoCreado(String pedidoId, String clienteId, String region, BigDecimal total) {
}

@RestController
@RequestMapping("/pedidos")
class PedidosReactivoController {

    private final EventGridPublisherAsyncClient<CloudEvent> publicador;

    PedidosReactivoController(String endpoint) {
        this.publicador = new EventGridPublisherClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildCloudEventPublisherAsyncClient();
    }

    /** Guarda el pedido (aquí omitido) y publica el evento sin bloquear; reintenta fallos transitorios. */
    @PostMapping
    Mono<ResponseEntity<Void>> crear(@RequestBody PedidoCreado pedido) {
        CloudEvent evento = new CloudEvent("/servicios/pedidos", "pe.modalima.pedido.creado",
                BinaryData.fromObject(pedido), CloudEventDataFormat.JSON, "application/json")
                .setId(UUID.randomUUID().toString())
                .setSubject("pedidos/" + pedido.region() + "/" + pedido.pedidoId())
                .setTime(OffsetDateTime.now());
        return publicador.sendEvent(evento)
                .retryWhen(Retry.backoff(3, Duration.ofMillis(300)))
                .thenReturn(ResponseEntity.accepted().build());
    }
}
```

## 7. Quarkus (Mutiny)

```java
import com.azure.core.models.CloudEvent;
import com.azure.core.models.CloudEventDataFormat;
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.EventGridPublisherAsyncClient;
import com.azure.messaging.eventgrid.EventGridPublisherClientBuilder;
import io.smallrye.mutiny.Uni;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.time.OffsetDateTime;
import java.util.UUID;

@ApplicationScoped
class PublicadorQuarkus {

    @ConfigProperty(name = "app.eventgrid.endpoint")
    String endpoint;

    private EventGridPublisherAsyncClient<CloudEvent> cliente;

    @PostConstruct
    void iniciar() {
        cliente = new EventGridPublisherClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildCloudEventPublisherAsyncClient();
    }

    Uni<Void> publicar(String tipo, String subject, String json) {
        CloudEvent evento = new CloudEvent("/servicios/pedidos", tipo, BinaryData.fromString(json), CloudEventDataFormat.JSON, "application/json")
                .setId(UUID.randomUUID().toString())
                .setSubject(subject)
                .setTime(OffsetDateTime.now());
        return Uni.createFrom().completionStage(() -> cliente.sendEvent(evento).toFuture());
    }
}

@Path("/pedidos")
@ApplicationScoped
public class PedidosEventosResource {

    @Inject
    PublicadorQuarkus publicador;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Uni<Response> crear(String json) {
        return publicador.publicar("pe.modalima.pedido.creado", "pedidos/nuevo", json)
                .replaceWith(Response.accepted().build());
    }
}
```

## 8. Funciones (Azure Functions) con disparador de Event Grid
Para trabajo corto y sin servidores, una Function con `@EventGridTrigger` recibe el evento ya entregado. Ejemplo y despliegue en [Eventos de Blob · Java](../../06-storage/eventos-blob/uso-en-java.md#5-azure-function-con-disparador-de-event-grid) y [Function Apps](../../04-compute/function-apps/README.md).

## 9. Imperativo vs reactivo en este caso

| | Imperativo | Reactivo |
|---|---|---|
| Publicar desde un endpoint | `sendEvent` bloqueante (corto) | `Mono`/`Uni`, sin bloquear el hilo de red |
| Reintentos | Políticas del SDK + código | `retryWhen` |
| Consumo | Webhook, cola de Service Bus, o *pull* | Igual; con WebFlux el webhook no bloquea |
| Procesamiento pesado | Hilos (virtuales en Java 21) | `boundedElastic` |

## 10. Qué NO hacer en el código
- Publicar con claves del tópico en la configuración.
- Meter la entidad completa o datos personales en `data`.
- Publicar **antes** de confirmar el cambio en la base de datos.
- Procesar trabajo largo dentro del webhook.
- Ignorar el `id` del evento (duplicados) o asumir orden.
- Suscribir al propio publicador a sus eventos (bucle).
- Crear un cliente por evento (reutiliza el `Publisher`).
