# Transversal · Apache Kafka · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1 (Spring for Apache Kafka 4.x), Reactor Kafka 1.3, Quarkus 3.40 (Messaging Kafka)**. Verifica las vigentes.

El patrón es siempre el mismo: **productor seguro** (clave por entidad, `acks=all`, idempotencia), **consumidor al menos una vez** (procesar → confirmar) que es **idempotente** (registra el id del evento) y **reintentos acotados con DLT** para los mensajes venenosos.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  kafka:
    bootstrap-servers: kafka-1:9093,kafka-2:9093,kafka-3:9093
    security:
      protocol: SSL                     # o SASL_SSL según el clúster
    producer:
      acks: all
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
      properties:
        enable.idempotence: true
        linger.ms: 10
        compression.type: zstd
    consumer:
      group-id: facturacion
      auto-offset-reset: earliest
      enable-auto-commit: false
      max-poll-records: 200
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      properties:
        partition.assignment.strategy: org.apache.kafka.clients.consumer.CooperativeStickyAssignor
    listener:
      ack-mode: manual
```
```properties
# Quarkus (application.properties)
kafka.bootstrap.servers=kafka-1:9093,kafka-2:9093,kafka-3:9093
mp.messaging.outgoing.pedidos-out.connector=smallrye-kafka
mp.messaging.outgoing.pedidos-out.topic=ventas.pedido.pagado.v1
mp.messaging.outgoing.pedidos-out.acks=all
mp.messaging.outgoing.pedidos-out.enable.idempotence=true
mp.messaging.incoming.pedidos-in.connector=smallrye-kafka
mp.messaging.incoming.pedidos-in.topic=ventas.pedido.pagado.v1
mp.messaging.incoming.pedidos-in.group.id=facturacion
mp.messaging.incoming.pedidos-in.enable.auto.commit=false
mp.messaging.incoming.pedidos-in.failure-strategy=dead-letter-queue
mp.messaging.incoming.pedidos-in.dead-letter-queue.topic=ventas.pedido.pagado.v1.dlt
```

## 2. Núcleo común (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Evento con sobre mínimo y consumidor idempotente. Puro: el inbox es una interfaz. */
public final class Eventos {

    private Eventos() {
    }

    public record PedidoPagado(String idEvento, String idPedido, long totalCentimos) {

        /** Formato del valor: idEvento|idPedido|totalCentimos (en la vida real: Avro/Protobuf/JSON con esquema). */
        public String serializar() {
            return idEvento + "|" + idPedido + "|" + totalCentimos;
        }

        public static Optional<PedidoPagado> leer(String valor) {
            String[] p = valor == null ? new String[0] : valor.split("\\|");
            if (p.length != 3 || p[0].isBlank() || !p[2].matches("\\d{1,12}")) {
                return Optional.empty();   // mensaje venenoso: no reintentar
            }
            return Optional.of(new PedidoPagado(p[0], p[1], Long.parseLong(p[2])));
        }
    }

    /** En producción: tabla con clave única (INSERT … ON CONFLICT DO NOTHING). */
    public interface Inbox {
        boolean registrarSiNuevo(String idEvento);
    }

    public static final class InboxEnMemoria implements Inbox {
        private final Set<String> vistos = ConcurrentHashMap.newKeySet();

        @Override
        public boolean registrarSiNuevo(String idEvento) {
            return vistos.add(idEvento);
        }
    }

    public static class MensajeInvalido extends RuntimeException {
        public MensajeInvalido(String m) {
            super(m);
        }
    }

    public static final class Facturador {
        private final Inbox inbox;
        private long facturado;

        public Facturador(Inbox inbox) {
            this.inbox = inbox;
        }

        /** Devuelve true si facturó; false si era duplicado. Lanza MensajeInvalido si no se puede leer. */
        public synchronized boolean procesar(String valor) {
            var e = PedidoPagado.leer(valor).orElseThrow(() -> new MensajeInvalido("valor ilegible"));
            if (!inbox.registrarSiNuevo(e.idEvento())) {
                return false;
            }
            facturado += e.totalCentimos();
            return true;
        }

        public synchronized long facturado() {
            return facturado;
        }
    }
}
```

## 3. Spring Kafka (imperativo)
```java
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaOperations;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;
import org.springframework.util.backoff.FixedBackOff;

@Configuration
class KafkaConfiguracion {

    static final String TEMA = "ventas.pedido.pagado.v1";

    /** 3 reintentos cada 1 s; luego al tema <tema>.DLT. Los inválidos van directo, sin reintentar. */
    @Bean
    DefaultErrorHandler manejadorDeErrores(KafkaOperations<String, String> ops) {
        var h = new DefaultErrorHandler(new DeadLetterPublishingRecoverer(ops), new FixedBackOff(1000L, 3));
        h.addNotRetryableExceptions(Eventos.MensajeInvalido.class);
        return h;
    }

    @Bean
    Eventos.Facturador facturador() {
        return new Eventos.Facturador(new Eventos.InboxEnMemoria());
    }
}

@Component
class ProductorDePedidos {

    private final KafkaTemplate<String, String> kafka;

    ProductorDePedidos(KafkaTemplate<String, String> kafka) {
        this.kafka = kafka;
    }

    /** Clave = idPedido (orden por pedido). Espera la confirmación: en un relay de outbox, marcar enviado después. */
    String publicar(String idPedido, long totalCentimos) throws Exception {
        var e = new Eventos.PedidoPagado(UUID.randomUUID().toString(), idPedido, totalCentimos);
        var r = kafka.send(KafkaConfiguracion.TEMA, idPedido, e.serializar()).get(10, TimeUnit.SECONDS);
        return r.getRecordMetadata().partition() + "@" + r.getRecordMetadata().offset();
    }
}

@Component
class ConsumidorDeFacturacion {

    private final Eventos.Facturador facturador;

    ConsumidorDeFacturacion(Eventos.Facturador facturador) {
        this.facturador = facturador;
    }

    @KafkaListener(topics = KafkaConfiguracion.TEMA, groupId = "facturacion")
    void alRecibir(String valor, Acknowledgment ack) {
        facturador.procesar(valor);   // si lanza, el manejador reintenta o envía a la DLT
        ack.acknowledge();            // confirmar solo después de procesar
    }
}
```

## 4. Reactor Kafka (reactivo)
```java
import java.util.List;
import java.util.Map;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import reactor.kafka.receiver.KafkaReceiver;
import reactor.kafka.receiver.ReceiverOptions;

class ConsumidorReactivo {

    private final Eventos.Facturador facturador;

    ConsumidorReactivo(Eventos.Facturador facturador) {
        this.facturador = facturador;
    }

    Flux<Boolean> iniciar(String bootstrap) {
        ReceiverOptions<String, String> opciones = ReceiverOptions.<String, String>create(Map.of(
                ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap,
                ConsumerConfig.GROUP_ID_CONFIG, "facturacion-reactiva",
                ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false,
                ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest",
                ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class,
                ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class))
            .subscription(List.of("ventas.pedido.pagado.v1"));
        // concatMap: en orden y uno a la vez por suscripción; el acknowledge marca el offset para el commit periódico
        return KafkaReceiver.create(opciones).receive()
            .concatMap(r -> Mono.fromCallable(() -> facturador.procesar(r.value()))
                .subscribeOn(Schedulers.boundedElastic())
                .onErrorResume(Eventos.MensajeInvalido.class, e -> Mono.just(false))   // aquí: publicar en la DLT
                .doOnSuccess(x -> r.receiverOffset().acknowledge()));
    }
}
```

## 5. Quarkus Messaging (imperativo)
```java
import io.smallrye.common.annotation.Blocking;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.UUID;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.eclipse.microprofile.reactive.messaging.Incoming;

@ApplicationScoped
class PedidosQuarkus {

    private final Eventos.Facturador facturador = new Eventos.Facturador(new Eventos.InboxEnMemoria());

    @Inject
    @Channel("pedidos-out")
    Emitter<String> emisor;

    public void publicar(String idPedido, long total) {
        var e = new Eventos.PedidoPagado(UUID.randomUUID().toString(), idPedido, total);
        // la clave se fija con OutgoingKafkaRecordMetadata; aquí basta el valor para el ejemplo
        emisor.send(e.serializar()).toCompletableFuture().join();
    }

    /** Si lanza excepción, la estrategia dead-letter-queue envía el mensaje a la DLT y continúa. */
    @Incoming("pedidos-in")
    @Blocking
    public void consumir(String valor) {
        facturador.procesar(valor);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.eclipse.microprofile.reactive.messaging.Message;

@ApplicationScoped
class PedidosMutiny {

    private final Eventos.Facturador facturador = new Eventos.Facturador(new Eventos.InboxEnMemoria());

    /** ack/nack explícitos: nack con estrategia DLQ envía a la DLT. */
    @Incoming("pedidos-in")
    public Uni<Void> consumir(Message<String> m) {
        return Uni.createFrom().item(() -> facturador.procesar(m.getPayload()))
            .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
            .onItem().transformToUni(x -> Uni.createFrom().completionStage(m.ack()))
            .onFailure().recoverWithUni(e -> Uni.createFrom().completionStage(m.nack(e)));
    }
}
```

## 7. Pruebas
- Núcleo puro: pruebas unitarias del `Facturador` (duplicado, inválido, válido).
- Integración: un broker efímero (contenedor) y el listener real; verifica que el duplicado no factura dos veces y que el inválido llega a la DLT.

## 8. Qué NO hacer
- No confirmes antes de procesar.
- No reintentes sin límite un mensaje inválido: bloquea la partición.
- No uses claves aleatorias si importa el orden.
- No publiques dentro de una transacción de base de datos: usa outbox y relay.
