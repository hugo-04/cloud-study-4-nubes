# Azure · Service Bus · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-messaging-servicebus`, `azure-identity`). Verifica las vigentes.

Principios del código: **peek-lock**, **liquidación explícita** en cada ruta, **idempotencia**, **errores clasificados** (transitorio → reintentar; permanente → *dead-letter* con motivo), **clientes reutilizados** y **autenticación con identidad**.

```properties
# Spring Boot (y Quarkus con sus propias claves equivalentes)
app.servicebus.namespace=sb-modalima.servicebus.windows.net
# Solo para desarrollo local con el emulador (deja el namespace vacío):
app.servicebus.connection-string=
```
```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-servicebus</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
```
Roles: productor → *Azure Service Bus Data Sender*; consumidor → *Azure Service Bus Data Receiver*; administrar reglas con el SDK → *Data Owner*. Namespace con `local_auth_enabled=false`.

## 1. Fábrica de clientes y productor

Un solo `ServiceBusClientBuilder` comparte **una conexión AMQP** entre todos los clientes que crees con él. En local se usa la cadena de conexión del emulador; en Azure, identidad.

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusMessageBatch;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

record PedidoCreado(String pedidoId, String clienteId, BigDecimal total, String region) {
}

@Configuration
class ServiceBusConfig {

    @Bean
    ServiceBusClientBuilder constructorServiceBus(@Value("${app.servicebus.namespace:}") String namespace,
                                                  @Value("${app.servicebus.connection-string:}") String cadena) {
        ServiceBusClientBuilder constructor = new ServiceBusClientBuilder();
        if (!cadena.isBlank()) {
            return constructor.connectionString(cadena);                       // emulador local
        }
        return constructor.fullyQualifiedNamespace(namespace)
                .credential(new DefaultAzureCredentialBuilder().build());     // Azure: sin claves
    }

    @Bean(destroyMethod = "close")
    ServiceBusSenderClient emisorPedidos(ServiceBusClientBuilder constructor) {
        return constructor.sender().queueName("pedidos").buildClient();
    }

    @Bean(destroyMethod = "close")
    ServiceBusSenderClient emisorEventos(ServiceBusClientBuilder constructor) {
        return constructor.sender().topicName("eventos-pedido").buildClient();
    }
}

@Service
class ProductorPedidos {

    private final ServiceBusSenderClient emisorPedidos;
    private final ServiceBusSenderClient emisorEventos;

    ProductorPedidos(ServiceBusSenderClient emisorPedidos, ServiceBusSenderClient emisorEventos) {
        this.emisorPedidos = emisorPedidos;
        this.emisorEventos = emisorEventos;
    }

    /** Comando a una cola. El MessageId estable permite que el broker descarte reenvíos duplicados. */
    void enviarComando(PedidoCreado pedido, String correlacionId) {
        ServiceBusMessage mensaje = new ServiceBusMessage(BinaryData.fromObject(pedido))
                .setMessageId("pedido-" + pedido.pedidoId())              // estable: mismo pedido => mismo id
                .setSubject("pedido.crear")
                .setContentType("application/json")
                .setCorrelationId(correlacionId);
        mensaje.getApplicationProperties().put("region", pedido.region());
        emisorPedidos.sendMessage(mensaje);
    }

    /** Evento a un tópico: cada suscripción recibe una copia si su filtro coincide. */
    void publicarEvento(PedidoCreado pedido, String tipo) {
        ServiceBusMessage mensaje = new ServiceBusMessage(BinaryData.fromObject(pedido))
                .setMessageId(tipo + "-" + pedido.pedidoId())
                .setSubject(tipo)                                         // filtro por Subject (correlación)
                .setContentType("application/json");
        mensaje.getApplicationProperties().put("region", pedido.region());
        mensaje.getApplicationProperties().put("total", pedido.total().doubleValue());
        emisorEventos.sendMessage(mensaje);
    }

    /** Envío por lotes: mucho más caudal que mensaje a mensaje. Parte el lote cuando se llena. */
    int enviarLote(List<PedidoCreado> pedidos) {
        int enviados = 0;
        ServiceBusMessageBatch lote = emisorPedidos.createMessageBatch();
        for (PedidoCreado pedido : pedidos) {
            ServiceBusMessage mensaje = new ServiceBusMessage(BinaryData.fromObject(pedido))
                    .setMessageId("pedido-" + pedido.pedidoId()).setSubject("pedido.crear");
            if (!lote.tryAddMessage(mensaje)) {                            // lote lleno: envía y empieza otro
                emisorPedidos.sendMessages(lote);
                enviados += lote.getCount();
                lote = emisorPedidos.createMessageBatch();
                if (!lote.tryAddMessage(mensaje)) {
                    throw new IllegalArgumentException("Un mensaje no cabe ni en un lote vacío");
                }
            }
        }
        if (lote.getCount() > 0) {
            emisorPedidos.sendMessages(lote);
            enviados += lote.getCount();
        }
        return enviados;
    }

    /** Mensaje programado: llega a la cola dentro de 30 minutos (recordatorio de pago). Devuelve el número de secuencia para poder cancelarlo. */
    long programarRecordatorio(PedidoCreado pedido) {
        ServiceBusMessage mensaje = new ServiceBusMessage(BinaryData.fromObject(pedido))
                .setMessageId("recordatorio-" + pedido.pedidoId() + "-" + UUID.randomUUID())
                .setSubject("pedido.recordar");
        return emisorPedidos.scheduleMessage(mensaje, OffsetDateTime.now().plusMinutes(30));
    }

    void cancelarRecordatorio(long numeroSecuencia) {
        emisorPedidos.cancelScheduledMessage(numeroSecuencia);
    }
}
```

## 2. Consumidor imperativo: idempotencia, errores clasificados y reintento con espera

- **Transitorio** (BD caída, 503): reintento con espera creciente. Dos formas: `abandon()` (rápido, cuenta contra `maxDeliveryCount`) o **reenviar programado** (espera real) y completar el original.
- **Permanente** (JSON inválido, regla de negocio): `deadLetter` con motivo.

Tabla de apoyo: `create table procesados (mensaje_id text primary key, procesado_en timestamptz default now());`

```java
import com.azure.core.util.BinaryData;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.messaging.servicebus.ServiceBusReceivedMessage;
import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.SmartLifecycle;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.OffsetDateTime;

record PedidoCreado(String pedidoId, String clienteId, BigDecimal total, String region) {
}

class ErrorTransitorio extends RuntimeException {
    ErrorTransitorio(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}

class ErrorPermanente extends RuntimeException {
    ErrorPermanente(String mensaje) {
        super(mensaje);
    }
}

@Component
class ConsumidorPedidos implements SmartLifecycle {

    private static final Logger LOG = LoggerFactory.getLogger(ConsumidorPedidos.class);
    private static final int MAX_INTENTOS_PROPIOS = 5;

    private final JdbcClient jdbc;
    private final ServiceBusSenderClient reenvio;
    private final ServiceBusProcessorClient procesador;

    ConsumidorPedidos(ServiceBusClientBuilder constructor, JdbcClient jdbc) {
        this.jdbc = jdbc;
        this.reenvio = constructor.sender().queueName("pedidos").buildClient();
        this.procesador = constructor.processor().queueName("pedidos")
                .disableAutoComplete()                                      // liquidamos nosotros
                .maxConcurrentCalls(8)
                .prefetchCount(0)                                           // procesos lentos: sin prefetch (el bloqueo corre desde que llega)
                .maxAutoLockRenewDuration(Duration.ofMinutes(10))           // renueva el bloqueo mientras procesas
                .processMessage(this::procesar)
                .processError(ctx -> LOG.error("Service Bus {} en {}: {}", ctx.getErrorSource(), ctx.getEntityPath(), ctx.getException().toString()))
                .buildProcessorClient();
    }

    private void procesar(ServiceBusReceivedMessageContext ctx) {
        ServiceBusReceivedMessage mensaje = ctx.getMessage();
        try {
            PedidoCreado pedido = leer(mensaje);
            if (yaProcesado(mensaje.getMessageId())) {
                ctx.complete();                                             // duplicado: éxito sin repetir el efecto
                return;
            }
            tratar(pedido);                                                 // lógica de negocio (idempotente)
            marcarProcesado(mensaje.getMessageId());
            ctx.complete();
        } catch (ErrorPermanente e) {
            ctx.deadLetter(new DeadLetterOptions()
                    .setDeadLetterReason("NEGOCIO_INVALIDO")
                    .setDeadLetterErrorDescription(e.getMessage()));
        } catch (ErrorTransitorio e) {
            reintentarConEspera(ctx, mensaje, e);
        } catch (RuntimeException e) {
            LOG.warn("Fallo inesperado con {}: {}", mensaje.getMessageId(), e.toString());
            ctx.abandon();                                                  // el broker cuenta la entrega; al agotar va a la DLQ
        }
    }

    private PedidoCreado leer(ServiceBusReceivedMessage mensaje) {
        try {
            return mensaje.getBody().toObject(PedidoCreado.class);
        } catch (RuntimeException e) {
            throw new ErrorPermanente("Cuerpo no es un PedidoCreado válido: " + e.getMessage());
        }
    }

    private void tratar(PedidoCreado pedido) {
        if (pedido.total().signum() <= 0) {
            throw new ErrorPermanente("Total no positivo en pedido " + pedido.pedidoId());
        }
        // ... guardar/llamar sistemas externos; si fallan por red/timeouts: throw new ErrorTransitorio(...)
    }

    /**
     * Espera exponencial real: reenvía una copia PROGRAMADA y completa el original.
     * La copia lleva un MessageId NUEVO (con duplicate detection activa, el mismo id se descartaría).
     */
    private void reintentarConEspera(ServiceBusReceivedMessageContext ctx, ServiceBusReceivedMessage original, ErrorTransitorio causa) {
        int intento = original.getApplicationProperties().containsKey("intento")
                ? ((Number) original.getApplicationProperties().get("intento")).intValue() : 0;
        if (intento >= MAX_INTENTOS_PROPIOS) {
            ctx.deadLetter(new DeadLetterOptions()
                    .setDeadLetterReason("REINTENTOS_AGOTADOS")
                    .setDeadLetterErrorDescription(causa.getMessage()));
            return;
        }
        long esperaSegundos = (long) Math.pow(2, intento) * 10;             // 10 s, 20 s, 40 s, 80 s, 160 s
        ServiceBusMessage copia = new ServiceBusMessage(BinaryData.fromBytes(original.getBody().toBytes()))
                .setMessageId(original.getMessageId() + "-r" + (intento + 1))
                .setSubject(original.getSubject())
                .setCorrelationId(original.getCorrelationId())
                .setContentType(original.getContentType());
        copia.getApplicationProperties().putAll(original.getApplicationProperties());
        copia.getApplicationProperties().put("intento", intento + 1);
        reenvio.scheduleMessage(copia, OffsetDateTime.now().plusSeconds(esperaSegundos));
        ctx.complete();                                                     // primero programa, después completa
    }

    private boolean yaProcesado(String mensajeId) {
        return jdbc.sql("select count(*) from procesados where mensaje_id = ?").param(mensajeId).query(Integer.class).single() > 0;
    }

    private void marcarProcesado(String mensajeId) {
        jdbc.sql("insert into procesados(mensaje_id) values (?) on conflict do nothing").param(mensajeId).update();
    }

    @Override
    public void start() {
        procesador.start();
    }

    @Override
    public void stop() {
        procesador.close();
        reenvio.close();
    }

    @Override
    public boolean isRunning() {
        return procesador.isRunning();
    }
}
```
Notas:
- `yaProcesado` + `marcarProcesado` no es atómico con el efecto de negocio: si el efecto vive en la **misma base de datos**, hazlo **en una sola transacción** (efecto + inserción en `procesados`).
- Si programas la copia y falla `ctx.complete()`, el original volverá y habrá dos copias: la idempotencia lo absorbe.

## 3. Procesar y publicar de forma atómica (transacción entre entidades)

Consumir de `pedidos`, publicar en `facturas` y completar **o todo o nada**. Requiere `enableCrossEntityTransactions()` para que el emisor y el receptor compartan la conexión.

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusReceivedMessage;
import com.azure.messaging.servicebus.ServiceBusReceiverClient;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import com.azure.messaging.servicebus.ServiceBusTransactionContext;
import com.azure.messaging.servicebus.models.CompleteOptions;

import java.time.Duration;

class PedidoAFactura {

    private final ServiceBusReceiverClient receptor;
    private final ServiceBusSenderClient emisor;

    PedidoAFactura(String namespace) {
        ServiceBusClientBuilder constructor = new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(new DefaultAzureCredentialBuilder().build())
                .enableCrossEntityTransactions();                                 // permite transacciones entre entidades
        this.receptor = constructor.receiver().queueName("pedidos").disableAutoComplete().buildClient();
        this.emisor = constructor.sender().queueName("facturas").buildClient();
    }

    int procesarUnLote() {
        int hechos = 0;
        for (ServiceBusReceivedMessage mensaje : receptor.receiveMessages(10, Duration.ofSeconds(5))) {
            ServiceBusTransactionContext tx = receptor.createTransaction();
            try {
                ServiceBusMessage factura = new ServiceBusMessage(BinaryData.fromBytes(mensaje.getBody().toBytes()))
                        .setMessageId("factura-" + mensaje.getMessageId())
                        .setSubject("factura.emitir");
                emisor.sendMessage(factura, tx);                            // publicar...
                receptor.complete(mensaje, new CompleteOptions().setTransactionContext(tx));   // ...y completar, en la misma transacción
                receptor.commitTransaction(tx);
                hechos++;
            } catch (RuntimeException e) {
                receptor.rollbackTransaction(tx);                           // nada se publicó ni se completó
                receptor.abandon(mensaje);
            }
        }
        return hechos;
    }

    void cerrar() {
        receptor.close();
        emisor.close();
    }
}
```
Las transacciones **no incluyen tu base de datos**: para consistencia con la BD usa **Outbox** (ver [casos reales](casos-reales.md#caso-7--outbox-base-de-datos--mensaje-sin-perder-nada)).

## 4. Sesiones: orden por cliente

Envía con `SessionId = clienteId`; el procesador de sesiones garantiza **un solo consumidor por sesión** y orden FIFO. La cola debe crearse con sesiones habilitadas.

```java
import com.azure.core.util.BinaryData;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;

class PedidosOrdenados {

    private static final Logger LOG = LoggerFactory.getLogger(PedidosOrdenados.class);

    private final ServiceBusSenderClient emisor;
    private final ServiceBusProcessorClient procesador;

    PedidosOrdenados(ServiceBusClientBuilder constructor) {
        this.emisor = constructor.sender().queueName("pedidos-ordenados").buildClient();
        this.procesador = constructor.sessionProcessor().queueName("pedidos-ordenados")
                .disableAutoComplete()
                .maxConcurrentSessions(8)                                   // 8 clientes en paralelo...
                .maxConcurrentCalls(1)                                      // ...y 1 mensaje a la vez dentro de cada sesión (orden)
                .sessionIdleTimeout(Duration.ofSeconds(30))
                .processMessage(ctx -> {
                    LOG.info("Sesión {} mensaje {}", ctx.getMessage().getSessionId(), ctx.getMessage().getMessageId());
                    ctx.complete();
                })
                .processError(ctx -> LOG.error("Error de sesión: {}", ctx.getException().toString()))
                .buildProcessorClient();
    }

    void enviar(String clienteId, String evento) {
        emisor.sendMessage(new ServiceBusMessage(BinaryData.fromString(evento)).setSessionId(clienteId));
    }

    void iniciar() {
        procesador.start();
    }

    void detener() {
        procesador.close();
        emisor.close();
    }
}
```

## 5. Suscripciones con filtros: crear reglas desde código

Lo habitual es definirlas en Terraform; desde código sirve para herramientas de plataforma o pruebas.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.administration.ServiceBusAdministrationClient;
import com.azure.messaging.servicebus.administration.ServiceBusAdministrationClientBuilder;
import com.azure.messaging.servicebus.administration.models.CorrelationRuleFilter;
import com.azure.messaging.servicebus.administration.models.CreateRuleOptions;
import com.azure.messaging.servicebus.administration.models.CreateSubscriptionOptions;

class AdministradorDeReglas {

    private final ServiceBusAdministrationClient admin;

    AdministradorDeReglas(String namespace) {
        this.admin = new ServiceBusAdministrationClientBuilder()
                .endpoint("https://" + namespace)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }

    /** Suscripción que solo recibe los eventos 'pedido.pagado' (filtro de correlación: igualdad, muy rápido). */
    void crearSuscripcionDeFacturacion() {
        admin.createSubscription("eventos-pedido", "facturacion", new CreateSubscriptionOptions().setMaxDeliveryCount(8));
        admin.deleteRule("eventos-pedido", "facturacion", "$Default");        // quita el filtro "todo"
        admin.createRule("eventos-pedido", "facturacion", "solo-pagados",
                new CreateRuleOptions(new CorrelationRuleFilter().setLabel("pedido.pagado"))); // Label = Subject del mensaje
    }
}
```

## 6. DLQ: inspeccionar y reprocesar

La DLQ **no se vacía sola**. Reprocesar = leer, corregir la causa, **reenviar a la cola original** y completar el mensaje de la DLQ.

```java
import com.azure.core.util.BinaryData;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusReceivedMessage;
import com.azure.messaging.servicebus.ServiceBusReceiverClient;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import com.azure.messaging.servicebus.models.SubQueue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;

class ReprocesadorDlq {

    private static final Logger LOG = LoggerFactory.getLogger(ReprocesadorDlq.class);

    private final ServiceBusReceiverClient dlq;
    private final ServiceBusSenderClient original;

    ReprocesadorDlq(ServiceBusClientBuilder constructor, String cola) {
        this.dlq = constructor.receiver().queueName(cola).subQueue(SubQueue.DEAD_LETTER_QUEUE).disableAutoComplete().buildClient();
        this.original = constructor.sender().queueName(cola).buildClient();
    }

    /** Reenvía solo los mensajes cuyo motivo está en la lista "reprocesables". Devuelve cuántos reenvió. */
    int reprocesar(java.util.Set<String> motivosReprocesables, int maximo) {
        int reenviados = 0;
        for (ServiceBusReceivedMessage m : dlq.receiveMessages(maximo, Duration.ofSeconds(5))) {
            LOG.info("DLQ {} motivo={} detalle={} entregas={}", m.getMessageId(), m.getDeadLetterReason(),
                    m.getDeadLetterErrorDescription(), m.getDeliveryCount());
            if (!motivosReprocesables.contains(m.getDeadLetterReason())) {
                dlq.abandon(m);                                             // se queda en la DLQ para revisión humana
                continue;
            }
            ServiceBusMessage copia = new ServiceBusMessage(BinaryData.fromBytes(m.getBody().toBytes()))
                    .setMessageId(m.getMessageId() + "-dlq")                // id nuevo: evita el descarte por duplicado
                    .setSubject(m.getSubject())
                    .setCorrelationId(m.getCorrelationId())
                    .setContentType(m.getContentType());
            copia.getApplicationProperties().putAll(m.getApplicationProperties());
            original.sendMessage(copia);
            dlq.complete(m);                                                // primero reenvía, después completa
            reenviados++;
        }
        return reenviados;
    }
}
```

## 7. Reactivo (Reactor): recibir con concurrencia y liquidar

```java
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusReceivedMessage;
import com.azure.messaging.servicebus.ServiceBusReceiverAsyncClient;
import com.azure.messaging.servicebus.ServiceBusSenderAsyncClient;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import reactor.util.retry.Retry;

import java.time.Duration;

class ConsumidorReactivo {

    private final ServiceBusReceiverAsyncClient receptor;
    private final ServiceBusSenderAsyncClient emisor;
    private Disposable suscripcion;

    ConsumidorReactivo(ServiceBusClientBuilder constructor) {
        this.receptor = constructor.receiver().queueName("pedidos")
                .disableAutoComplete()
                .maxAutoLockRenewDuration(Duration.ofMinutes(10))
                .prefetchCount(0)
                .buildAsyncClient();
        this.emisor = constructor.sender().queueName("facturas").buildAsyncClient();
    }

    void iniciar() {
        suscripcion = receptor.receiveMessages()
                .flatMap(this::tratar, 8)                                   // 8 mensajes a la vez, con contrapresión
                .subscribe();
    }

    private Mono<Void> tratar(ServiceBusReceivedMessage mensaje) {
        return Mono.fromCallable(() -> validar(mensaje))
                .subscribeOn(Schedulers.boundedElastic())                   // trabajo bloqueante fuera del hilo de red
                .flatMap(valido -> valido
                        ? emisor.sendMessage(new com.azure.messaging.servicebus.ServiceBusMessage(mensaje.getBody()))
                                .retryWhen(Retry.backoff(3, Duration.ofSeconds(1)))
                                .then(receptor.complete(mensaje))
                        : receptor.deadLetter(mensaje, new DeadLetterOptions().setDeadLetterReason("INVALIDO")))
                .onErrorResume(error -> receptor.abandon(mensaje));         // fallo: vuelve a la cola (cuenta entrega)
    }

    private boolean validar(ServiceBusReceivedMessage mensaje) {
        return mensaje.getBody().getLength() != null && mensaje.getBody().getLength() > 0;
    }

    void detener() {
        if (suscripcion != null) {
            suscripcion.dispose();
        }
        receptor.close();
        emisor.close();
    }
}
```
Endpoint WebFlux que **encola y responde 202** sin bloquear:

```java
import com.azure.core.util.BinaryData;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusSenderAsyncClient;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

import java.math.BigDecimal;

record PedidoCreado(String pedidoId, String clienteId, BigDecimal total, String region) {
}

@RestController
@RequestMapping("/pedidos")
class PedidosController {

    private final ServiceBusSenderAsyncClient emisor;

    PedidosController(ServiceBusSenderAsyncClient emisor) {
        this.emisor = emisor;
    }

    @PostMapping
    Mono<ResponseEntity<Void>> crear(@RequestBody PedidoCreado pedido,
                                     @RequestHeader(value = "X-Correlation-Id", required = false) String correlacion) {
        ServiceBusMessage mensaje = new ServiceBusMessage(BinaryData.fromObject(pedido))
                .setMessageId("pedido-" + pedido.pedidoId())
                .setSubject("pedido.crear")
                .setCorrelationId(correlacion);
        return emisor.sendMessage(mensaje).thenReturn(ResponseEntity.accepted().build());
    }
}
```

## 8. Quarkus (Mutiny)

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.messaging.servicebus.ServiceBusSenderAsyncClient;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import io.quarkus.runtime.ShutdownEvent;
import io.quarkus.runtime.StartupEvent;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.time.Duration;

@ApplicationScoped
public class ServiceBusQuarkus {

    private static final Logger LOG = Logger.getLogger(ServiceBusQuarkus.class);

    @ConfigProperty(name = "app.servicebus.namespace")
    String namespace;

    private ServiceBusSenderAsyncClient emisor;
    private ServiceBusProcessorClient procesador;

    void alArrancar(@Observes StartupEvent evento) {
        ServiceBusClientBuilder constructor = new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(new DefaultAzureCredentialBuilder().build());
        emisor = constructor.sender().queueName("pedidos").buildAsyncClient();
        procesador = constructor.processor().queueName("pedidos")
                .disableAutoComplete()
                .maxConcurrentCalls(4)
                .maxAutoLockRenewDuration(Duration.ofMinutes(10))
                .processMessage(ctx -> {
                    try {
                        LOG.infof("Pedido %s", ctx.getMessage().getMessageId());
                        ctx.complete();
                    } catch (IllegalArgumentException e) {
                        ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("INVALIDO"));
                    }
                })
                .processError(ctx -> LOG.errorf("Service Bus: %s", ctx.getException()))
                .buildProcessorClient();
        procesador.start();
    }

    void alApagar(@Observes ShutdownEvent evento) {
        procesador.close();
        emisor.close();
    }

    /** Envío no bloqueante: Mono de Reactor convertido a Uni. */
    public Uni<Void> enviar(String id, String json) {
        ServiceBusMessage mensaje = new ServiceBusMessage(BinaryData.fromString(json)).setMessageId(id).setSubject("pedido.crear");
        return Uni.createFrom().completionStage(() -> emisor.sendMessage(mensaje).toFuture());
    }
}

@Path("/pedidos")
@ApplicationScoped
class PedidosResource {

    @Inject
    ServiceBusQuarkus bus;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Uni<Response> crear(String json) {
        String id = "pedido-" + Math.abs(json.hashCode());
        return bus.enviar(id, json).replaceWith(Response.accepted().build());
    }
}
```
Para Quarkus también existe el conector **AMQP** de SmallRye Reactive Messaging apuntando a Service Bus, pero usa claves SAS (incompatible con `local_auth_enabled=false`) y ofrece menos control (bloqueos, sesiones, DLQ): para producción en Azure, el SDK oficial.

## 9. Local y pruebas: emulador
El [emulador](ejemplos/emulator/docker-compose.yaml) levanta colas y tópicos en Docker con una cadena de conexión (sin Entra ID). Con la fábrica de la sección 1, basta `app.servicebus.connection-string=Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;` y dejar el namespace vacío. Para pruebas automatizadas, el mismo contenedor con Testcontainers. *Verifica las funciones que el emulador aún no soporta.*

## 10. Imperativo vs reactivo

| | Imperativo (`ServiceBusProcessorClient`) | Reactivo (`ReceiverAsyncClient`) |
|---|---|---|
| Concurrencia | `maxConcurrentCalls` | `flatMap(..., N)` |
| Procesamiento con JDBC/CPU | Natural (con hilos virtuales, aún mejor) | `boundedElastic`; no bloquear el hilo de red |
| Liquidación | `ctx.complete()/abandon()/deadLetter()` | `receptor.complete(m)` → `Mono` |
| Reintentos | Código + `scheduleMessage` | `retryWhen` + `scheduleMessage` |
| Backpressure | Por `maxConcurrentCalls`/prefetch | Nativo del flujo |
| Endpoint que solo encola | `sendMessage` bloqueante corto | `Mono` → 202 sin bloquear |

## 11. Qué NO hacer en el código
- `autoComplete` activo con lógica que puede fallar.
- Un cliente (conexión) por mensaje en vez de reutilizarlo.
- `MessageId` aleatorio en reenvíos del mismo hecho (anula el descarte de duplicados) — o el mismo id en la copia de reintento con duplicate detection (se descarta).
- Procesar sin idempotencia o fuera de una transacción de BD.
- Excepciones tragadas sin liquidar.
- Prefetch alto con procesos largos (bloqueos que vencen antes de empezar).
- Llamadas bloqueantes dentro del hilo reactivo.
- Registrar el cuerpo completo del mensaje con datos personales.
