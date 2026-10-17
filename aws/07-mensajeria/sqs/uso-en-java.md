# AWS · SQS · Uso desde Java

Cuatro piezas puras que se repiten en cualquier consumidor y productor de SQS: **backoff** (cuánto esperar antes de reintentar), **claves FIFO** (grupo y deduplicación), **partición en lotes** (≤ 10 mensajes y límite de bytes) y **envío con reintento parcial**. Versiones: Java 21, Spring Boot 4.1 (Spring Cloud AWS 4.2), Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  cloud:
    aws:
      region:
        static: us-east-1
      sqs:
        listener:
          max-concurrent-messages: 10
          max-messages-per-poll: 10
          poll-timeout: 20s
app:
  cola-ordenes: prod-ordenes
  cola-ordenes-url: https://sqs.us-east-1.amazonaws.com/111122223333/prod-ordenes
```
```properties
# Quarkus (application.properties)
quarkus.sqs.aws.region=us-east-1
app.cola-ordenes-url=https://sqs.us-east-1.amazonaws.com/111122223333/prod-ordenes
```

## 2. Núcleo común

### 2.1 Backoff para reintentos
```java
// (clase reutilizada en los bloques siguientes, ambos)
public final class BackoffReintentos {
    /** Máximo permitido por SQS para el visibility timeout: 12 horas. */
    public static final int MAXIMO_SQS = 12 * 3600;

    private BackoffReintentos() {}

    /** base · 2^(intento-1), acotado por "tope" y por el máximo de SQS. intento empieza en 1. */
    public static int segundos(int intento, int base, int tope) {
        if (intento < 1 || base < 1 || tope < base) {
            throw new IllegalArgumentException("parámetros inválidos");
        }
        long v = base;
        for (int i = 1; i < intento && v < tope; i++) {
            v *= 2;
        }
        return (int) Math.min(Math.min(v, tope), MAXIMO_SQS);
    }

    /** «Jitter completo»: reparte los reintentos para que no lleguen todos a la vez. azar01 en [0,1). */
    public static int conJitter(int intento, int base, int tope, double azar01) {
        int max = segundos(intento, base, tope);
        return Math.max(1, (int) Math.floor(azar01 * max));
    }
}
```

### 2.2 Claves de colas FIFO
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.regex.Pattern;

public final class ClavesFifo {
    private static final Pattern VALIDO = Pattern.compile("[A-Za-z0-9!\"#$%&'()*+,./:;<=>?@\\[\\\\\\]^_`{|}~-]{1,128}");

    private ClavesFifo() {}

    /** El grupo es la unidad de orden: un pedido, un cliente. Debe ser estable y de ≤128 caracteres válidos. */
    public static String grupo(String idNegocio) {
        if (idNegocio == null || !VALIDO.matcher(idNegocio).matches()) {
            throw new IllegalArgumentException("MessageGroupId inválido: " + idNegocio);
        }
        return idNegocio;
    }

    /** Deduplicación estable: el mismo hecho de negocio (tipo + id + versión) produce siempre el mismo valor. */
    public static String dedup(String tipo, String idNegocio, int version) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] h = md.digest((tipo + "|" + idNegocio + "|" + version).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(h);                         // 64 caracteres
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
```

### 2.3 Partir en lotes y enviar con reintento parcial
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.BatchResultErrorEntry;
import software.amazon.awssdk.services.sqs.model.MessageAttributeValue;
import software.amazon.awssdk.services.sqs.model.SendMessageBatchRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageBatchRequestEntry;
import software.amazon.awssdk.services.sqs.model.SendMessageBatchResponse;

public final class EnvioPorLotes {
    public record Mensaje(String id, String cuerpo, Map<String, String> atributos, String grupo, String dedup) {
        int bytes() {
            int n = cuerpo.getBytes(StandardCharsets.UTF_8).length;
            for (var e : atributos.entrySet()) {
                n += e.getKey().length() + "String".length() + e.getValue().getBytes(StandardCharsets.UTF_8).length;
            }
            return n;
        }
    }

    public static final class EnvioParcialException extends RuntimeException {
        private final List<String> fallidos;

        EnvioParcialException(List<String> fallidos) {
            super("no se pudieron enviar: " + fallidos);
            this.fallidos = List.copyOf(fallidos);
        }

        public List<String> fallidos() {
            return fallidos;
        }
    }

    private final SqsClient sqs;
    private final String colaUrl;
    private final long maxBytesLote;
    private final int reintentos;

    public EnvioPorLotes(SqsClient sqs, String colaUrl, long maxBytesLote, int reintentos) {
        this.sqs = sqs;
        this.colaUrl = colaUrl;
        this.maxBytesLote = maxBytesLote;
        this.reintentos = reintentos;
    }

    /** Agrupa respetando ≤10 entradas y ≤ maxBytes por llamada. Un mensaje mayor que el límite es un error del llamador. */
    static List<List<Mensaje>> partir(List<Mensaje> mensajes, int maxEntradas, long maxBytes) {
        List<List<Mensaje>> lotes = new ArrayList<>();
        List<Mensaje> actual = new ArrayList<>();
        long bytes = 0;
        for (Mensaje m : mensajes) {
            int b = m.bytes();
            if (b > maxBytes) {
                throw new IllegalArgumentException("el mensaje " + m.id() + " pesa " + b + " bytes (máximo " + maxBytes + ")");
            }
            if (!actual.isEmpty() && (actual.size() == maxEntradas || bytes + b > maxBytes)) {
                lotes.add(actual);
                actual = new ArrayList<>();
                bytes = 0;
            }
            actual.add(m);
            bytes += b;
        }
        if (!actual.isEmpty()) {
            lotes.add(actual);
        }
        return lotes;
    }

    /** Envía todo; reintenta solo las entradas que fallaron por causa del servicio. Lanza si alguna no se pudo enviar. */
    public void enviar(List<Mensaje> mensajes) {
        List<String> definitivos = new ArrayList<>();
        for (List<Mensaje> lote : partir(mensajes, 10, maxBytesLote)) {
            List<Mensaje> pendientes = lote;
            for (int intento = 0; intento <= reintentos && !pendientes.isEmpty(); intento++) {
                SendMessageBatchResponse r = sqs.sendMessageBatch(SendMessageBatchRequest.builder().queueUrl(colaUrl)
                        .entries(pendientes.stream().map(EnvioPorLotes::entrada).toList()).build());
                List<Mensaje> siguientes = new ArrayList<>();
                for (BatchResultErrorEntry f : r.failed()) {
                    Mensaje m = pendientes.stream().filter(x -> x.id().equals(f.id())).findFirst().orElseThrow();
                    if (f.senderFault()) {
                        definitivos.add(m.id());           // un error nuestro no mejora al reintentar
                    } else {
                        siguientes.add(m);
                    }
                }
                pendientes = siguientes;
            }
            pendientes.forEach(m -> definitivos.add(m.id()));
        }
        if (!definitivos.isEmpty()) {
            throw new EnvioParcialException(definitivos);
        }
    }

    private static SendMessageBatchRequestEntry entrada(Mensaje m) {
        var b = SendMessageBatchRequestEntry.builder().id(m.id()).messageBody(m.cuerpo());
        Map<String, MessageAttributeValue> atributos = new HashMap<>();
        m.atributos().forEach((k, v) ->
                atributos.put(k, MessageAttributeValue.builder().dataType("String").stringValue(v).build()));
        if (!atributos.isEmpty()) {
            b.messageAttributes(atributos);                 // se asigna el mapa completo de una vez
        }
        if (m.grupo() != null) {
            b.messageGroupId(m.grupo());
        }
        if (m.dedup() != null) {
            b.messageDeduplicationId(m.dedup());
        }
        return b.build();
    }
}
```

### 2.4 Consumidor con backoff y borrado por lotes
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.ChangeMessageVisibilityRequest;
import software.amazon.awssdk.services.sqs.model.DeleteMessageBatchRequest;
import software.amazon.awssdk.services.sqs.model.DeleteMessageBatchRequestEntry;
import software.amazon.awssdk.services.sqs.model.Message;
import software.amazon.awssdk.services.sqs.model.MessageSystemAttributeName;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;

public final class ConsumidorSqs {
    @FunctionalInterface
    public interface Procesador {
        /** Debe ser idempotente: SQS puede entregar el mismo mensaje más de una vez. */
        void procesar(String id, String cuerpo) throws Exception;
    }

    private final SqsClient sqs;
    private final String colaUrl;
    private final Procesador procesador;
    private final int baseBackoff;
    private final int topeBackoff;

    public ConsumidorSqs(SqsClient sqs, String colaUrl, Procesador procesador, int baseBackoff, int topeBackoff) {
        this.sqs = sqs;
        this.colaUrl = colaUrl;
        this.procesador = procesador;
        this.baseBackoff = baseBackoff;
        this.topeBackoff = topeBackoff;
    }

    /** Una pasada de long polling. Devuelve cuántos mensajes se procesaron y borraron. */
    public int unaPasada() {
        var resp = sqs.receiveMessage(ReceiveMessageRequest.builder().queueUrl(colaUrl)
                .maxNumberOfMessages(10).waitTimeSeconds(20)
                .messageSystemAttributeNames(MessageSystemAttributeName.APPROXIMATE_RECEIVE_COUNT).build());
        List<DeleteMessageBatchRequestEntry> aBorrar = new ArrayList<>();
        for (Message m : resp.messages()) {
            try {
                procesador.procesar(m.messageId(), m.body());
                aBorrar.add(DeleteMessageBatchRequestEntry.builder().id(m.messageId()).receiptHandle(m.receiptHandle()).build());
            } catch (Exception e) {
                int intento = Integer.parseInt(m.attributes().getOrDefault(
                        MessageSystemAttributeName.APPROXIMATE_RECEIVE_COUNT, "1"));
                sqs.changeMessageVisibility(ChangeMessageVisibilityRequest.builder().queueUrl(colaUrl)
                        .receiptHandle(m.receiptHandle())
                        .visibilityTimeout(BackoffReintentos.segundos(intento, baseBackoff, topeBackoff)).build());
            }
        }
        if (!aBorrar.isEmpty()) {
            sqs.deleteMessageBatch(DeleteMessageBatchRequest.builder().queueUrl(colaUrl).entries(aBorrar).build());
        }
        return aBorrar.size();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import io.awspring.cloud.sqs.operations.SqsTemplate;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.sqs.SqsClient;

@Configuration
class SqsConfig {
    @Bean
    EnvioPorLotes envio(SqsClient sqs, @Value("${app.cola-ordenes-url}") String url) {
        return new EnvioPorLotes(sqs, url, 1_000_000, 3);
    }
}

@RestController
class OrdenesController {
    private final SqsTemplate plantilla;
    private final EnvioPorLotes envio;
    private final String cola;

    OrdenesController(SqsTemplate plantilla, EnvioPorLotes envio, @Value("${app.cola-ordenes}") String cola) {
        this.plantilla = plantilla;
        this.envio = envio;
        this.cola = cola;
    }

    /** Un mensaje: SqsTemplate (alto nivel). */
    @PostMapping("/ordenes")
    Map<String, String> crear(@RequestBody Map<String, Object> orden) {
        plantilla.send(to -> to.queue(cola).payload(orden).header("tipo", "OrdenCreada"));
        return Map.of("estado", "encolada");
    }

    /** Varios mensajes: lotes de 10 con reintento parcial. */
    @PostMapping("/ordenes/lote")
    Map<String, Object> crearLote(@RequestBody List<String> cuerpos) {
        int[] i = {0};
        envio.enviar(cuerpos.stream().map(c -> new EnvioPorLotes.Mensaje("m" + i[0]++, c, Map.of("tipo", "OrdenCreada"), null, null)).toList());
        return Map.of("enviados", cuerpos.size());
    }
}

@Component
class OrdenesListener {
    /** Si lanza excepción NO se borra: reaparece tras el visibility timeout y, tras N intentos, va a la DLQ. */
    @SqsListener(value = "${app.cola-ordenes}", maxConcurrentMessages = "10")
    void recibir(String cuerpo) {
        System.out.println("orden recibida: " + cuerpo);          // tu negocio (idempotente)
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import io.awspring.cloud.sqs.operations.SqsTemplate;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class OrdenesReactivoController {
    private final SqsTemplate plantilla;
    private final String cola;

    OrdenesReactivoController(SqsTemplate plantilla, @Value("${app.cola-ordenes}") String cola) {
        this.plantilla = plantilla;
        this.cola = cola;
    }

    /** sendAsync no bloquea el hilo de eventos. */
    @PostMapping("/ordenes-r")
    Mono<Map<String, String>> crear(@RequestBody Map<String, Object> orden) {
        return Mono.fromFuture(plantilla.sendAsync(to -> to.queue(cola).payload(orden)))
                .thenReturn(Map.of("estado", "encolada"));
    }
}

@Component
class OrdenesReactivoListener {
    /** Listener asíncrono: el trabajo bloqueante va a boundedElastic y se devuelve el futuro. */
    @SqsListener("${app.cola-ordenes}")
    CompletableFuture<Void> recibir(String cuerpo) {
        return Mono.fromRunnable(() -> System.out.println("orden recibida: " + cuerpo))
                .subscribeOn(Schedulers.boundedElastic())
                .then()
                .toFuture();
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.sqs.SqsClient;

@ApplicationScoped
class SqsProductores {
    @Produces
    @Singleton
    EnvioPorLotes envio(SqsClient sqs, @ConfigProperty(name = "app.cola-ordenes-url") String url) {
        return new EnvioPorLotes(sqs, url, 1_000_000, 3);
    }

    @Produces
    @Singleton
    ConsumidorSqs consumidor(SqsClient sqs, @ConfigProperty(name = "app.cola-ordenes-url") String url) {
        return new ConsumidorSqs(sqs, url, (id, cuerpo) -> System.out.println("orden " + id + ": " + cuerpo), 10, 900);
    }
}

/** Quarkus no trae @SqsListener: un planificador ejecuta el long polling sin solaparse. */
@ApplicationScoped
class OrdenesPlanificadas {
    private final ConsumidorSqs consumidor;

    OrdenesPlanificadas(ConsumidorSqs consumidor) {
        this.consumidor = consumidor;
    }

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void sondear() {
        consumidor.unaPasada();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.sqs.SqsAsyncClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

@Path("/ordenes-r")
class OrdenesMutinyRecurso {
    @Inject
    SqsAsyncClient sqs;

    @ConfigProperty(name = "app.cola-ordenes-url")
    String colaUrl;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Map<String, String>> crear(String cuerpo) {
        return Uni.createFrom().completionStage(() -> sqs.sendMessage(
                        SendMessageRequest.builder().queueUrl(colaUrl).messageBody(cuerpo).build()))
                .map(r -> Map.of("messageId", r.messageId()));
    }
}
```

## 7. Permisos
Productor: `sqs:SendMessage`. Consumidor: `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:ChangeMessageVisibility`, `sqs:GetQueueAttributes`; y `kms:Decrypt` si la cola usa KMS. Ver [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).

## 8. Qué NO hacer desde Java
- **No** borres el mensaje antes de terminar el trabajo.
- **No** asumas que llega una sola vez: el procesamiento debe ser idempotente.
- **No** envíes de uno en uno cuando hay muchos: usa `EnvioPorLotes`.
- **No** reintentes errores del emisor (`senderFault`): no mejoran.
- **No** uses `Thread.sleep` para el backoff: usa `ChangeMessageVisibility`.
- **No** hagas short polling: `WaitTimeSeconds = 20`.
- **No** uses `MessageGroupId` con valores de alta cardinalidad sin necesidad ni uno solo para todo (se serializa todo el tráfico).
