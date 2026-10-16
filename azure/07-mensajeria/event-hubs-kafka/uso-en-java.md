# Azure · Event Hubs (Kafka) · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Spring Kafka 4.1, Quarkus 3.40 (SmallRye Reactive Messaging), Azure SDK BOM 1.3** (`azure-messaging-eventhubs`, `azure-messaging-eventhubs-checkpointstore-blob`, `azure-identity`, `azure-data-schemaregistry-apacheavro`). Verifica las vigentes.

## 0. Qué cliente elegir

| Si… | Usa |
|---|---|
| Código nuevo, solo Azure, quieres checkpoints y balanceo ya resueltos | **SDK nativo** (`azure-messaging-eventhubs`) — secciones 1 a 4 |
| Ya tienes (o tendrás) aplicaciones Kafka, o quieres portabilidad | **Cliente Kafka** — secciones 5 a 7 |
| Spring Boot imperativo | **Spring Kafka** (`KafkaTemplate`, `@KafkaListener`) — sección 7 |
| Spring WebFlux (reactivo) | `KafkaTemplate` envuelto en `Mono` + `Sinks`; Reactor Kafka solo si ya lo usas — sección 8 |
| Quarkus (imperativo o reactivo) | **SmallRye Reactive Messaging Kafka** — sección 9 |

Principios comunes: **Entra ID sin claves**, **lotes** en el productor, **clave de partición** = entidad cuyo orden importa, **checkpoint/commit después de procesar**, consumidores **idempotentes**, eventos venenosos a un event hub de errores y **lag medido**.

```properties
# Spring Boot (application.properties) / Quarkus (con el mismo nombre de claves de la app)
app.eventhubs.namespace=evhns-modalima.servicebus.windows.net
app.eventhubs.hub=clics-web
app.eventhubs.hub-errores=errores-clics
app.eventhubs.consumer-group=analitica
app.checkpoints.endpoint=https://stcheckpointsmodalima.blob.core.windows.net
app.checkpoints.container=checkpoints
```
```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-eventhubs</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-eventhubs-checkpointstore-blob</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<!-- Kafka -->
<dependency><groupId>org.springframework.kafka</groupId><artifactId>spring-kafka</artifactId></dependency>
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-messaging-kafka</artifactId></dependency>
```
Roles: productor → *Azure Event Hubs Data Sender* (en el event hub); consumidor → *Azure Event Hubs Data Receiver* (y *Storage Blob Data Contributor* en el contenedor de checkpoints si usas el SDK nativo).

---

## 1. SDK nativo · publicar por lotes con clave de partición

Un `EventDataBatch` pertenece a **una** clave de partición (o a ninguna). Por eso se agrupa por clave. Si en una misma llamada tienes miles de claves distintas, el cliente Kafka (que agrupa por partición internamente) rinde mejor.

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventhubs.EventData;
import com.azure.messaging.eventhubs.EventDataBatch;
import com.azure.messaging.eventhubs.EventHubClientBuilder;
import com.azure.messaging.eventhubs.EventHubProducerClient;
import com.azure.messaging.eventhubs.models.CreateBatchOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

record ClicWeb(String eventId, String clienteId, String pagina, long marcaDeTiempo) {
}

@Configuration
class EventHubsProductorConfig {

    @Bean(destroyMethod = "close")
    EventHubProducerClient productor(@Value("${app.eventhubs.namespace}") String namespace,
                                     @Value("${app.eventhubs.hub}") String hub) {
        return new EventHubClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .eventHubName(hub)
                .credential(new DefaultAzureCredentialBuilder().build())   // sin cadenas de conexión
                .buildProducerClient();
    }
}

@Service
class PublicadorDeClics {

    private final EventHubProducerClient productor;

    PublicadorDeClics(EventHubProducerClient productor) {
        this.productor = productor;
    }

    void publicar(List<ClicWeb> clics) {
        Map<String, List<ClicWeb>> porCliente = clics.stream()
                .collect(Collectors.groupingBy(ClicWeb::clienteId));
        porCliente.forEach(this::enviarLotes);
    }

    private void enviarLotes(String clienteId, List<ClicWeb> clics) {
        // misma clave -> misma partición -> los clics de un cliente se leen en orden
        CreateBatchOptions opciones = new CreateBatchOptions().setPartitionKey(clienteId);
        EventDataBatch lote = productor.createBatch(opciones);

        for (ClicWeb clic : clics) {
            EventData evento = new EventData(BinaryData.fromObject(clic));
            evento.setMessageId(clic.eventId());                 // base de la idempotencia del consumidor
            evento.setContentType("application/json");
            evento.getProperties().put("tipo", "pe.modalima.clic.web");

            if (!lote.tryAdd(evento)) {                           // lote lleno: se envía y se abre otro
                productor.send(lote);
                lote = productor.createBatch(opciones);
                if (!lote.tryAdd(evento)) {
                    throw new IllegalStateException("El evento no cabe en un lote vacío: usa Claim Check");
                }
            }
        }
        if (lote.getCount() > 0) {
            productor.send(lote);
        }
    }
}
```

**Notas**
- `createBatch()` conoce el tamaño máximo del servicio (varía por nivel): **no calcules tamaños a mano**.
- El cliente reintenta errores transitorios; la limitación (`ServerBusy`) se trata como transitoria con retroceso.
- Crea **un** `EventHubProducerClient` por event hub y reutilízalo (mantiene la conexión AMQP).

## 2. SDK nativo · productor reactivo (WebFlux)

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventhubs.EventData;
import com.azure.messaging.eventhubs.EventDataBatch;
import com.azure.messaging.eventhubs.EventHubClientBuilder;
import com.azure.messaging.eventhubs.EventHubProducerAsyncClient;
import com.azure.messaging.eventhubs.models.CreateBatchOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

record ClicWeb(String eventId, String clienteId, String pagina, long marcaDeTiempo) {
}

@Configuration
class EventHubsAsyncConfig {

    @Bean(destroyMethod = "close")
    EventHubProducerAsyncClient productorAsync(@Value("${app.eventhubs.namespace}") String namespace,
                                               @Value("${app.eventhubs.hub}") String hub) {
        return new EventHubClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .eventHubName(hub)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildAsyncProducerClient();
    }
}

@RestController
class ClicsController {

    private final EventHubProducerAsyncClient productor;

    ClicsController(EventHubProducerAsyncClient productor) {
        this.productor = productor;
    }

    @PostMapping("/clientes/{clienteId}/clics")
    @ResponseStatus(HttpStatus.ACCEPTED)
    Mono<Void> recibir(@PathVariable String clienteId, @RequestBody List<ClicWeb> clics) {
        CreateBatchOptions opciones = new CreateBatchOptions().setPartitionKey(clienteId);

        return productor.createBatch(opciones).flatMap(primero -> {
            AtomicReference<EventDataBatch> actual = new AtomicReference<>(primero);

            return Flux.fromIterable(clics)
                    .concatMap(clic -> {
                        EventData evento = new EventData(BinaryData.fromObject(clic));
                        evento.setMessageId(clic.eventId());
                        if (actual.get().tryAdd(evento)) {
                            return Mono.<Void>empty();
                        }
                        // lote lleno: se envía, se abre otro y se reintenta agregar
                        return productor.send(actual.get())
                                .then(productor.createBatch(opciones))
                                .doOnNext(actual::set)
                                .doOnNext(nuevo -> {
                                    if (!nuevo.tryAdd(evento)) {
                                        throw new IllegalStateException("Evento demasiado grande: usa Claim Check");
                                    }
                                })
                                .then();
                    })
                    .then(Mono.defer(() -> {
                        if (actual.get().getCount() > 0) {
                            return productor.send(actual.get());
                        }
                        return Mono.<Void>empty();
                    }));
        });
    }
}
```

## 3. SDK nativo · consumidor con `EventProcessorClient` (checkpoints en Blob)

El procesador **reparte las particiones entre las instancias** del mismo grupo (balanceo de carga), guarda el progreso en un contenedor de Blob y reanuda donde quedó. Aquí: lotes, idempotencia en base de datos, **checkpoint después de procesar** y envío de eventos venenosos a un event hub de errores.

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventhubs.EventData;
import com.azure.messaging.eventhubs.EventHubClientBuilder;
import com.azure.messaging.eventhubs.EventHubProducerClient;
import com.azure.messaging.eventhubs.EventProcessorClient;
import com.azure.messaging.eventhubs.EventProcessorClientBuilder;
import com.azure.messaging.eventhubs.checkpointstore.blob.BlobCheckpointStore;
import com.azure.messaging.eventhubs.models.ErrorContext;
import com.azure.messaging.eventhubs.models.EventBatchContext;
import com.azure.storage.blob.BlobContainerAsyncClient;
import com.azure.storage.blob.BlobContainerClientBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

record ClicWeb(String eventId, String clienteId, String pagina, long marcaDeTiempo) {
}

@Component
class ProcesadorDeClics {

    private static final Logger log = LoggerFactory.getLogger(ProcesadorDeClics.class);
    private static final int CHECKPOINT_CADA = 200;   // eventos, no uno por uno

    private final JdbcClient jdbc;
    private final EventHubProducerClient errores;
    private final Map<String, AtomicInteger> pendientesPorParticion = new ConcurrentHashMap<>();

    ProcesadorDeClics(JdbcClient jdbc, @Qualifier("productorErrores") EventHubProducerClient errores) {
        this.jdbc = jdbc;
        this.errores = errores;
    }

    void procesarLote(EventBatchContext lote) {
        String particion = lote.getPartitionContext().getPartitionId();

        for (EventData evento : lote.getEvents()) {
            try {
                ClicWeb clic = evento.getBodyAsBinaryData().toObject(ClicWeb.class);
                guardarUnaVez(clic);
            } catch (RuntimeException e) {
                enviarAErrores(evento, e);          // el evento venenoso no frena la partición
            }
        }

        int acumulados = pendientesPorParticion
                .computeIfAbsent(particion, p -> new AtomicInteger())
                .addAndGet(lote.getEvents().size());
        if (acumulados >= CHECKPOINT_CADA) {
            lote.updateCheckpoint();                // DESPUÉS de procesar
            pendientesPorParticion.get(particion).set(0);
        }
    }

    // Idempotencia: la clave única es el eventId; el reintento no duplica
    private void guardarUnaVez(ClicWeb clic) {
        jdbc.sql("""
                        INSERT INTO clics (event_id, cliente_id, pagina, ocurrio_en)
                        VALUES (:id, :cliente, :pagina, to_timestamp(:ts / 1000.0))
                        ON CONFLICT (event_id) DO NOTHING
                        """)
                .param("id", clic.eventId())
                .param("cliente", clic.clienteId())
                .param("pagina", clic.pagina())
                .param("ts", clic.marcaDeTiempo())
                .update();
    }

    private void enviarAErrores(EventData original, RuntimeException causa) {
        EventData copia = new EventData(original.getBody());
        copia.getProperties().put("motivo", causa.getClass().getSimpleName());
        copia.getProperties().put("mensajeError", String.valueOf(causa.getMessage()));
        copia.getProperties().put("offsetOriginal", String.valueOf(original.getOffset()));
        copia.getProperties().put("secuenciaOriginal", String.valueOf(original.getSequenceNumber()));
        errores.send(java.util.List.of(copia));
        log.warn("Evento a errores-clics: {}", causa.toString());
    }

    void alError(ErrorContext error) {
        log.error("Error en partición {}", error.getPartitionContext().getPartitionId(), error.getThrowable());
    }
}

@Configuration
class ProcesadorConfig {

    @Bean(name = "productorErrores", destroyMethod = "close")
    EventHubProducerClient productorErrores(@Value("${app.eventhubs.namespace}") String namespace,
                                            @Value("${app.eventhubs.hub-errores}") String hubErrores) {
        return new EventHubClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .eventHubName(hubErrores)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildProducerClient();
    }

    @Bean(initMethod = "start", destroyMethod = "stop")
    EventProcessorClient procesador(@Value("${app.eventhubs.namespace}") String namespace,
                                    @Value("${app.eventhubs.hub}") String hub,
                                    @Value("${app.eventhubs.consumer-group}") String grupo,
                                    @Value("${app.checkpoints.endpoint}") String blobEndpoint,
                                    @Value("${app.checkpoints.container}") String contenedor,
                                    ProcesadorDeClics procesador) {
        DefaultAzureCredential credencial = new DefaultAzureCredentialBuilder().build();

        BlobContainerAsyncClient checkpoints = new BlobContainerClientBuilder()
                .endpoint(blobEndpoint)
                .containerName(contenedor)
                .credential(credencial)
                .buildAsyncClient();

        return new EventProcessorClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .eventHubName(hub)
                .consumerGroup(grupo)
                .credential(credencial)
                .checkpointStore(new BlobCheckpointStore(checkpoints))
                .processEventBatch(procesador::procesarLote, 100, Duration.ofSeconds(5))
                .processError(procesador::alError)
                .buildEventProcessorClient();
    }
}
```

**Cómo razonarlo**
- Si el servicio cae entre procesar y hacer *checkpoint*, al volver recibirá hasta 200 eventos repetidos: por eso la inserción es **idempotente** (`ON CONFLICT DO NOTHING`).
- Si ejecutas 3 réplicas del mismo microservicio con el mismo grupo, el procesador reparte las particiones entre ellas solo. Con más réplicas que particiones, las sobrantes quedan ociosas.
- El contenedor `checkpoints` guarda un blob por partición con el offset: **no lo borres** salvo que quieras reprocesar desde el principio.

## 4. SDK nativo · reproducir (*replay*) desde una fecha

Para reprocesar tras un error de código, lee con un **grupo de consumidores dedicado** (`reproceso`) para no tocar los offsets del servicio en producción.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventhubs.EventHubClientBuilder;
import com.azure.messaging.eventhubs.EventHubConsumerClient;
import com.azure.messaging.eventhubs.models.EventPosition;
import com.azure.messaging.eventhubs.models.PartitionEvent;

import java.time.Duration;
import java.time.Instant;

class ReprocesoDesdeFecha {

    void reproducir(String namespace, String hub, Instant desde) {
        try (EventHubConsumerClient consumidor = new EventHubClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .eventHubName(hub)
                .consumerGroup("reproceso")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildConsumerClient()) {

            for (String particion : consumidor.getPartitionIds()) {
                var eventos = consumidor.receiveFromPartition(
                        particion, 500, EventPosition.fromEnqueuedTime(desde), Duration.ofSeconds(10));
                for (PartitionEvent pe : eventos) {
                    System.out.printf("p%s seq=%d %s%n", particion,
                            pe.getData().getSequenceNumber(), pe.getData().getBodyAsString());
                }
            }
        }
    }
}
```
Para un reproceso grande usa un `EventProcessorClient` con **otro grupo** y `initialPartitionEventPosition(...)`; para reprocesar sin volver a leer desde Event Hubs, usa los archivos de **Capture** (sección 10).

---

## 5. Cliente Kafka · autenticación con Entra ID (OAUTHBEARER)

Event Hubs acepta dos mecanismos SASL sobre TLS (`security.protocol=SASL_SSL`, puerto **9093**):

| Mecanismo | Cómo | Cuándo |
|---|---|---|
| `PLAIN` | usuario `$ConnectionString`, contraseña = cadena de conexión | Pruebas rápidas; requiere claves (`local_authentication_enabled = true`) |
| **`OAUTHBEARER`** | Token de Entra ID con `DefaultAzureCredential` | **Producción** (sin secretos, con identidad administrada) |

Kafka no sabe obtener tokens de Azure: hay que darle un *callback handler* que los pida. Es una clase pequeña que sirve igual para Spring, Quarkus o Java puro.

```java
import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.apache.kafka.common.security.auth.AuthenticateCallbackHandler;
import org.apache.kafka.common.security.oauthbearer.OAuthBearerToken;
import org.apache.kafka.common.security.oauthbearer.OAuthBearerTokenCallback;

import javax.security.auth.callback.Callback;
import javax.security.auth.callback.UnsupportedCallbackException;
import javax.security.auth.login.AppConfigurationEntry;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Entrega a Kafka un token de Entra ID para el namespace de Event Hubs. */
public class EntraIdCallbackHandler implements AuthenticateCallbackHandler {

    private TokenCredential credencial;
    private String ambito;

    @Override
    public void configure(Map<String, ?> configs, String mecanismoSasl, List<AppConfigurationEntry> jaas) {
        // bootstrap.servers = "evhns-modalima.servicebus.windows.net:9093"
        String servidores = String.valueOf(configs.get("bootstrap.servers")).replaceAll("[\\[\\] ]", "");
        String primero = servidores.split(",")[0];
        String host = primero.replaceAll(":\\d+$", "");
        this.ambito = "https://" + host + "/.default";
        this.credencial = new DefaultAzureCredentialBuilder().build();   // identidad administrada en Azure
    }

    @Override
    public void handle(Callback[] callbacks) throws UnsupportedCallbackException {
        for (Callback callback : callbacks) {
            if (callback instanceof OAuthBearerTokenCallback tokenCallback) {
                AccessToken token = credencial.getTokenSync(new TokenRequestContext().addScopes(ambito));
                tokenCallback.token(new TokenDeEntra(token));
            } else {
                throw new UnsupportedCallbackException(callback);
            }
        }
    }

    @Override
    public void close() {
        // nada que cerrar
    }
}

record TokenDeEntra(AccessToken token) implements OAuthBearerToken {

    @Override
    public String value() {
        return token.getToken();
    }

    @Override
    public Set<String> scope() {
        return Set.of();
    }

    @Override
    public long lifetimeMs() {
        return token.getExpiresAt().toInstant().toEpochMilli();
    }

    @Override
    public String principalName() {
        return "entra-id";
    }

    @Override
    public Long startTimeMs() {
        return System.currentTimeMillis();
    }
}
```

La configuración que acompaña al handler (la misma en Java puro, Spring o Quarkus):

```properties
bootstrap.servers=evhns-modalima.servicebus.windows.net:9093
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;
sasl.login.callback.handler.class=pe.modalima.kafka.EntraIdCallbackHandler

# Recomendaciones para Event Hubs (el balanceador de Azure cierra conexiones inactivas ~4 min)
metadata.max.age.ms=180000
connections.max.idle.ms=180000
request.timeout.ms=60000
session.timeout.ms=30000
```
Los archivos listos están en [ejemplos/kafka](ejemplos/kafka/). En AKS con *Workload Identity* o en Container Apps con identidad administrada, `DefaultAzureCredential` toma esa identidad sin configurar secretos. En local usa tu sesión de `az login`.

## 6. Cliente Kafka · Java puro (productor y consumidor)

```java
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

import java.time.Duration;
import java.util.List;
import java.util.Properties;

class KafkaPuroEnEventHubs {

    static Properties base(String namespace) {
        Properties p = new Properties();
        p.put("bootstrap.servers", namespace + ":9093");
        p.put("security.protocol", "SASL_SSL");
        p.put("sasl.mechanism", "OAUTHBEARER");
        p.put("sasl.jaas.config", "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;");
        p.put("sasl.login.callback.handler.class", "pe.modalima.kafka.EntraIdCallbackHandler");
        p.put("metadata.max.age.ms", "180000");
        p.put("connections.max.idle.ms", "180000");
        return p;
    }

    void producir(String namespace, String clienteId, String json) {
        Properties p = base(namespace);
        p.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        p.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        p.put(ProducerConfig.ACKS_CONFIG, "all");
        p.put(ProducerConfig.LINGER_MS_CONFIG, "20");              // junta envíos para ir en lotes
        p.put(ProducerConfig.BATCH_SIZE_CONFIG, "65536");
        p.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");   // verifica soporte en tu nivel

        try (KafkaProducer<String, String> productor = new KafkaProducer<>(p)) {
            // la clave decide la partición: mismo cliente, mismo orden
            productor.send(new ProducerRecord<>("clics-web", clienteId, json), (meta, error) -> {
                if (error != null) {
                    System.err.println("No se pudo enviar: " + error);   // aquí: reintento o evento de errores
                } else {
                    System.out.printf("p%d offset %d%n", meta.partition(), meta.offset());
                }
            });
            productor.flush();
        }
    }

    void consumir(String namespace, String grupo) {
        Properties p = base(namespace);
        p.put(ConsumerConfig.GROUP_ID_CONFIG, grupo);
        p.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        p.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        p.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");      // commit manual, después de procesar
        p.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        p.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, "200");

        try (KafkaConsumer<String, String> consumidor = new KafkaConsumer<>(p)) {
            consumidor.subscribe(List.of("clics-web"));
            while (true) {
                ConsumerRecords<String, String> lote = consumidor.poll(Duration.ofSeconds(1));
                for (ConsumerRecord<String, String> r : lote) {
                    procesar(r);                       // idempotente
                }
                if (!lote.isEmpty()) {
                    consumidor.commitSync();           // DESPUÉS de procesar
                }
            }
        }
    }

    private void procesar(ConsumerRecord<String, String> r) {
        System.out.printf("p%d o%d clave=%s%n", r.partition(), r.offset(), r.key());
    }
}
```

**Reproducir con Kafka** (equivalente al *replay* del SDK): `offsetsForTimes` + `seek`.

```java
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.consumer.OffsetAndTimestamp;
import org.apache.kafka.common.TopicPartition;

import java.time.Instant;
import java.util.Map;
import java.util.stream.Collectors;

class ReproducirKafka {

    void desde(KafkaConsumer<String, String> consumidor, String topic, Instant fecha) {
        var particiones = consumidor.partitionsFor(topic).stream()
                .map(i -> new TopicPartition(topic, i.partition()))
                .toList();
        consumidor.assign(particiones);                          // asignación manual, sin tocar el grupo
        Map<TopicPartition, Long> tiempos = particiones.stream()
                .collect(Collectors.toMap(tp -> tp, tp -> fecha.toEpochMilli()));
        Map<TopicPartition, OffsetAndTimestamp> offsets = consumidor.offsetsForTimes(tiempos);
        offsets.forEach((tp, oat) -> {
            if (oat != null) {
                consumidor.seek(tp, oat.offset());
            } else {
                consumidor.seekToEnd(java.util.List.of(tp));
            }
        });
    }
}
```

## 7. Spring Boot · Spring Kafka (imperativo)

```yaml
# application.yml
spring:
  kafka:
    bootstrap-servers: evhns-modalima.servicebus.windows.net:9093
    properties:
      security.protocol: SASL_SSL
      sasl.mechanism: OAUTHBEARER
      sasl.jaas.config: org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;
      sasl.login.callback.handler.class: pe.modalima.kafka.EntraIdCallbackHandler
      metadata.max.age.ms: 180000
      connections.max.idle.ms: 180000
    producer:
      acks: all
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JacksonJsonSerializer
      properties:
        linger.ms: 20
        enable.idempotence: true            # verifica soporte en tu nivel
    consumer:
      group-id: analitica
      enable-auto-commit: false
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.ErrorHandlingDeserializer
      properties:
        spring.deserializer.value.delegate.class: org.springframework.kafka.support.serializer.JacksonJsonDeserializer
        spring.json.value.default.type: pe.modalima.clics.ClicWeb
        spring.json.trusted.packages: pe.modalima.clics
    listener:
      ack-mode: manual                      # tú confirmas después de procesar
      concurrency: 4                        # hilos = como máximo el número de particiones
```
*(Los nombres de las propiedades de los (de)serializadores JSON cambiaron en Spring Kafka 4 por Jackson 3: verifica los vigentes.)*

```java
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.TopicPartition;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;
import org.springframework.stereotype.Service;
import org.springframework.util.backoff.ExponentialBackOff;

import java.util.concurrent.CompletableFuture;

record ClicWeb(String eventId, String clienteId, String pagina, long marcaDeTiempo) {
}

@Service
class PublicadorKafka {

    private final KafkaTemplate<String, ClicWeb> plantilla;

    PublicadorKafka(KafkaTemplate<String, ClicWeb> plantilla) {
        this.plantilla = plantilla;
    }

    CompletableFuture<Void> publicar(ClicWeb clic) {
        // clave = clienteId -> orden por cliente
        return plantilla.send("clics-web", clic.clienteId(), clic)
                .thenAccept(r -> System.out.printf("p%d o%d%n",
                        r.getRecordMetadata().partition(), r.getRecordMetadata().offset()));
    }
}

@Component
class ConsumidorDeClics {

    private final JdbcClient jdbc;

    ConsumidorDeClics(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @KafkaListener(topics = "clics-web", groupId = "analitica")
    void alRecibir(ConsumerRecord<String, ClicWeb> registro, Acknowledgment ack) {
        ClicWeb clic = registro.value();
        jdbc.sql("""
                        INSERT INTO clics (event_id, cliente_id, pagina) VALUES (:id, :cliente, :pagina)
                        ON CONFLICT (event_id) DO NOTHING
                        """)
                .param("id", clic.eventId())
                .param("cliente", clic.clienteId())
                .param("pagina", clic.pagina())
                .update();
        ack.acknowledge();                         // confirma el offset DESPUÉS de procesar
    }
}

@Configuration
class ErroresKafkaConfig {

    /** Reintentos con retroceso y, si no se logra, el registro va al event hub "errores-clics". */
    @Bean
    DefaultErrorHandler manejadorDeErrores(KafkaTemplate<Object, Object> plantilla) {
        DeadLetterPublishingRecoverer aErrores = new DeadLetterPublishingRecoverer(plantilla,
                (registro, excepcion) -> new TopicPartition("errores-clics", -1));   // -1: que Kafka elija partición

        ExponentialBackOff retroceso = new ExponentialBackOff(500, 2.0);
        retroceso.setMaxAttempts(5);
        return new DefaultErrorHandler(aErrores, retroceso);
    }
}
```
**Detalles de Event Hubs**
- Los *topics* de errores y de reintento **deben existir como event hubs** (los crea Terraform/CLI): Kafka no los auto-crea. Por eso `@RetryableTopic` (que crea topics de reintento) requiere crearlos antes o desactivar la auto-creación.
- `ErrorHandlingDeserializer` evita que un mensaje mal formado bloquee la partición para siempre.
- `concurrency` mayor que las particiones no ayuda.

### 7.1 Lag (retraso) del grupo con `AdminClient`

```java
import org.apache.kafka.clients.admin.Admin;
import org.apache.kafka.clients.admin.OffsetSpec;
import org.apache.kafka.clients.consumer.OffsetAndMetadata;
import org.apache.kafka.common.TopicPartition;

import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

class LagDelGrupo {

    Map<TopicPartition, Long> calcular(Properties conexion, String grupo) throws Exception {
        try (Admin admin = Admin.create(conexion)) {
            Map<TopicPartition, OffsetAndMetadata> comprometidos =
                    admin.listConsumerGroupOffsets(grupo).partitionsToOffsetAndMetadata().get();

            Map<TopicPartition, OffsetSpec> pedido = new HashMap<>();
            comprometidos.keySet().forEach(tp -> pedido.put(tp, OffsetSpec.latest()));
            var finales = admin.listOffsets(pedido).all().get();

            Map<TopicPartition, Long> lag = new HashMap<>();
            comprometidos.forEach((tp, om) -> lag.put(tp, finales.get(tp).offset() - om.offset()));
            return lag;
        }
    }
}
```
Si alguna operación de administración no está soportada en tu nivel, usa las métricas del namespace y [KQL](ejemplos/kql/kql-eventhubs.md). *Verifica compatibilidad del `AdminClient`.*

## 8. Spring WebFlux (reactivo) con Kafka

**Importante:** el proyecto **Reactor Kafka fue descontinuado** (la versión 1.3 es la última; sigue recibiendo solo correcciones mientras dure su soporte) y la plantilla reactiva de Spring Kafka quedó marcada para retiro. Para código nuevo, las dos opciones sanas son:

1. **WebFlux en el borde + Spring Kafka por dentro** (envolver `KafkaTemplate` en `Mono` y puentear los mensajes con `Sinks`), con hilos virtuales para las partes bloqueantes.
2. **Quarkus + SmallRye Reactive Messaging**, reactivo de verdad con *backpressure* (sección 9).

```java
import org.springframework.http.MediaType;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

record ClicWeb(String eventId, String clienteId, String pagina, long marcaDeTiempo) {
}

@RestController
class ClicsReactivoController {

    private final KafkaTemplate<String, ClicWeb> plantilla;
    private final Sinks.Many<ClicWeb> recientes = Sinks.many().multicast().onBackpressureBuffer(1000, false);

    ClicsReactivoController(KafkaTemplate<String, ClicWeb> plantilla) {
        this.plantilla = plantilla;
    }

    /** Publicar: el envío de Kafka es asíncrono; se convierte en Mono sin bloquear el hilo del evento. */
    @PostMapping("/clics")
    Mono<String> publicar(@RequestBody ClicWeb clic) {
        return Mono.fromFuture(() -> plantilla.send("clics-web", clic.clienteId(), clic))
                .map(r -> "p" + r.getRecordMetadata().partition() + "/o" + r.getRecordMetadata().offset());
    }

    /** El listener (hilo de Kafka) alimenta un flujo que los clientes leen por Server-Sent Events. */
    @KafkaListener(topics = "clics-web", groupId = "tablero-en-vivo")
    void alRecibir(ClicWeb clic) {
        recientes.tryEmitNext(clic);
    }

    @GetMapping(path = "/clics/en-vivo", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    Flux<ClicWeb> enVivo() {
        return recientes.asFlux();
    }
}
```
**Reglas del puente**: no bloquees dentro del `Flux` (usa `publishOn(Schedulers.boundedElastic())` para JDBC/IO bloqueante) y cuida los *buffers* (`onBackpressureBuffer(1000, false)` descarta si nadie escucha).

**Heredado (Reactor Kafka 1.3):** si ya lo tienes, así se ve. Está en mantenimiento: no lo elijas para proyectos nuevos.

```java
import org.apache.kafka.clients.producer.ProducerRecord;
import reactor.core.publisher.Flux;
import reactor.kafka.receiver.KafkaReceiver;
import reactor.kafka.receiver.ReceiverOptions;
import reactor.kafka.sender.KafkaSender;
import reactor.kafka.sender.SenderOptions;
import reactor.kafka.sender.SenderRecord;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.List;
import java.util.Map;

class ReactorKafkaHeredado {

    Flux<String> flujo(Map<String, Object> propsProductor, Map<String, Object> propsConsumidor) {
        KafkaSender<String, String> emisor = KafkaSender.create(SenderOptions.<String, String>create(propsProductor));

        emisor.send(Flux.just(SenderRecord.create(new ProducerRecord<>("clics-web", "u-42", "{\"pagina\":\"/home\"}"), "corr-1")))
                .doOnNext(r -> System.out.println("enviado " + r.recordMetadata().offset()))
                .subscribe();

        ReceiverOptions<String, String> opciones = ReceiverOptions.<String, String>create(propsConsumidor)
                .subscription(List.of("clics-web"))
                .commitInterval(Duration.ofSeconds(5));

        return KafkaReceiver.create(opciones).receive()
                .concatMap(r -> Flux.just(r.value())
                        .doOnComplete(() -> r.receiverOffset().acknowledge()))     // ack después de procesar
                .retryWhen(Retry.backoff(5, Duration.ofSeconds(1)));
    }
}
```

## 9. Quarkus · SmallRye Reactive Messaging (Kafka)

Quarkus trata Kafka como **canales** reactivos: el método `@Incoming` recibe, `Emitter` envía, y la configuración enlaza cada canal con un event hub. El mismo `EntraIdCallbackHandler` de la sección 5 sirve aquí.

```properties
# application.properties
kafka.bootstrap.servers=evhns-modalima.servicebus.windows.net:9093
kafka.security.protocol=SASL_SSL
kafka.sasl.mechanism=OAUTHBEARER
kafka.sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;
kafka.sasl.login.callback.handler.class=pe.modalima.kafka.EntraIdCallbackHandler
kafka.metadata.max.age.ms=180000
kafka.connections.max.idle.ms=180000

# Productor: canal "clics-salida" -> event hub clics-web (clave = clienteId)
mp.messaging.outgoing.clics-salida.connector=smallrye-kafka
mp.messaging.outgoing.clics-salida.topic=clics-web
mp.messaging.outgoing.clics-salida.key.serializer=org.apache.kafka.common.serialization.StringSerializer
mp.messaging.outgoing.clics-salida.value.serializer=io.quarkus.kafka.client.serialization.ObjectMapperSerializer
mp.messaging.outgoing.clics-salida.acks=all

# Consumidor: canal "clics-entrada" <- event hub clics-web
mp.messaging.incoming.clics-entrada.connector=smallrye-kafka
mp.messaging.incoming.clics-entrada.topic=clics-web
mp.messaging.incoming.clics-entrada.group.id=analitica
mp.messaging.incoming.clics-entrada.key.deserializer=org.apache.kafka.common.serialization.StringDeserializer
mp.messaging.incoming.clics-entrada.value.deserializer=pe.modalima.clics.ClicWebDeserializer
mp.messaging.incoming.clics-entrada.auto.offset.reset=earliest
mp.messaging.incoming.clics-entrada.commit-strategy=throttled
# Si falla el procesamiento: el registro va al event hub de errores y el flujo continúa
mp.messaging.incoming.clics-entrada.failure-strategy=dead-letter-queue
mp.messaging.incoming.clics-entrada.dead-letter-queue.topic=errores-clics
```

```java
import io.quarkus.kafka.client.serialization.ObjectMapperDeserializer;
import io.smallrye.mutiny.Uni;
import io.smallrye.reactive.messaging.kafka.Record;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.eclipse.microprofile.reactive.messaging.Incoming;
import org.eclipse.microprofile.reactive.messaging.Message;

record ClicWeb(String eventId, String clienteId, String pagina, long marcaDeTiempo) {
}

class ClicWebDeserializer extends ObjectMapperDeserializer<ClicWeb> {
    ClicWebDeserializer() {
        super(ClicWeb.class);
    }
}

@Path("/clics")
@ApplicationScoped
class ClicsRecurso {

    @Inject
    @Channel("clics-salida")
    Emitter<Record<String, ClicWeb>> emisor;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Uni<Response> publicar(ClicWeb clic) {
        // Record.of(clave, valor): la clave decide la partición
        return Uni.createFrom().completionStage(emisor.send(Record.of(clic.clienteId(), clic)))
                .replaceWith(Response.accepted().build());
    }
}

@ApplicationScoped
class ProcesadorDeClics {

    @Inject
    GuardadoReactivo guardado;

    /** Reactivo: devuelve Uni; si falla, nack -> dead-letter-queue (event hub errores-clics). */
    @Incoming("clics-entrada")
    public Uni<Void> procesar(Message<ClicWeb> mensaje) {
        return guardado.guardarUnaVez(mensaje.getPayload())
                .chain(() -> Uni.createFrom().completionStage(mensaje.ack()))
                .onFailure().recoverWithUni(e -> Uni.createFrom().completionStage(mensaje.nack(e)));
    }
}

@ApplicationScoped
class GuardadoReactivo {

    Uni<Void> guardarUnaVez(ClicWeb clic) {
        // aquí iría el cliente reactivo (Hibernate Reactive / pg client) con INSERT ... ON CONFLICT DO NOTHING
        return Uni.createFrom().voidItem();
    }
}
```

**Variante imperativa en Quarkus** (código bloqueante como JDBC): marca el método con `@Blocking` y recibe el payload directamente; Quarkus lo ejecuta en un hilo de trabajo para no bloquear el bucle de eventos.

```java
import io.smallrye.reactive.messaging.annotations.Blocking;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.reactive.messaging.Incoming;

record ClicWeb(String eventId, String clienteId, String pagina, long marcaDeTiempo) {
}

@ApplicationScoped
class ProcesadorBloqueante {

    @Incoming("clics-entrada")
    @Blocking                       // hilo de trabajo: permite JDBC, llamadas HTTP síncronas, etc.
    public void procesar(ClicWeb clic) {
        // INSERT idempotente por eventId con JDBC...
        System.out.println("clic " + clic.eventId());
    }
}
```
- En **Quarkus** también puedes usar el SDK nativo con Mutiny: convierte `Mono` a `Uni` con `Uni.createFrom().completionStage(() -> mono.toFuture())`.
- Para **imagen nativa**, registra el *callback handler* para reflexión (`@RegisterForReflection`) y revisa que `DefaultAzureCredential` funcione en nativo.
- En desarrollo, *Dev Services* levanta un Kafka local si no configuras `kafka.bootstrap.servers` en el perfil `dev`.

## 10. Registro de esquemas (Avro) y lectura de archivos Capture

**Serializar con esquema registrado** (el evento lleva el id del esquema; el consumidor lo recupera):

```java
import com.azure.core.util.serializer.TypeReference;
import com.azure.data.schemaregistry.SchemaRegistryClientBuilder;
import com.azure.data.schemaregistry.apacheavro.SchemaRegistryApacheAvroSerializer;
import com.azure.data.schemaregistry.apacheavro.SchemaRegistryApacheAvroSerializerBuilder;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventhubs.EventData;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;

class AvroConRegistro {

    private static final String ESQUEMA = """
            {"type":"record","name":"ClicWeb","namespace":"pe.modalima",
             "fields":[{"name":"eventId","type":"string"},
                       {"name":"clienteId","type":"string"},
                       {"name":"pagina","type":"string"}]}
            """;

    SchemaRegistryApacheAvroSerializer serializador(String namespace) {
        var cliente = new SchemaRegistryClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildAsyncClient();
        return new SchemaRegistryApacheAvroSerializerBuilder()
                .schemaRegistryClient(cliente)
                .schemaGroup("modalima")          // grupo con regla de compatibilidad Backward
                .autoRegisterSchemas(false)       // en producción: esquemas registrados por el pipeline, no por la app
                .buildSerializer();
    }

    EventData serializar(SchemaRegistryApacheAvroSerializer serializador) {
        Schema schema = new Schema.Parser().parse(ESQUEMA);
        GenericRecord clic = new GenericData.Record(schema);
        clic.put("eventId", "evt-1");
        clic.put("clienteId", "u-42");
        clic.put("pagina", "/home");
        return serializador.serialize(clic, TypeReference.createInstance(EventData.class));
    }

    GenericRecord leer(SchemaRegistryApacheAvroSerializer serializador, EventData evento) {
        return serializador.deserialize(evento, TypeReference.createInstance(GenericRecord.class));
    }
}
```

**Leer un archivo de Capture** (Avro en Blob) para reprocesar o auditar, sin molestar al event hub:

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobClientBuilder;
import org.apache.avro.file.DataFileStream;
import org.apache.avro.generic.GenericDatumReader;
import org.apache.avro.generic.GenericRecord;

import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

class LectorDeCapture {

    void leer(String blobEndpoint, String contenedor, String ruta) throws Exception {
        BlobClient blob = new BlobClientBuilder()
                .endpoint(blobEndpoint)
                .containerName(contenedor)
                .blobName(ruta)       // evhns/clics-web/0/2026/10/16/14/05/00.avro
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();

        try (InputStream entrada = blob.openInputStream();
             DataFileStream<GenericRecord> registros = new DataFileStream<>(entrada, new GenericDatumReader<>())) {
            for (GenericRecord r : registros) {
                long secuencia = (Long) r.get("SequenceNumber");
                String enviadoEn = r.get("EnqueuedTimeUtc").toString();
                ByteBuffer cuerpo = (ByteBuffer) r.get("Body");
                String json = StandardCharsets.UTF_8.decode(cuerpo).toString();
                System.out.printf("seq=%d %s %s%n", secuencia, enviadoEn, json);
            }
        }
    }
}
```
Campos de un registro Capture: `SequenceNumber`, `Offset`, `EnqueuedTimeUtc`, `SystemProperties`, `Properties` y `Body` (bytes).

---

## 11. Pruebas y desarrollo local

| Necesidad | Herramienta |
|---|---|
| Probar el SDK nativo sin nube | **Emulador de Event Hubs** (contenedor) — ver [ejemplos/emulator](ejemplos/emulator/) |
| Probar tu código Kafka | **Kafka local** (Docker, modo KRaft) o `spring-kafka-test` (`@EmbeddedKafka`) |
| Pruebas de integración en CI | **Testcontainers** con la imagen de Kafka o del emulador |
| Quarkus | *Dev Services* (Kafka automático en `quarkus:dev`) |

Con Kafka local la autenticación va en `PLAINTEXT`: separa la configuración por perfiles (`dev`/`prod`) y deja el handler de Entra ID solo en producción.

## 12. Resumen de buenas prácticas en código
- Clave de partición con sentido de negocio; sin clave si el orden no importa.
- `acks=all`, lotes (`linger.ms`), reintentos con retroceso.
- **Commit/checkpoint después de procesar**, no por cada evento.
- Idempotencia por `eventId` (restricción única en la base).
- Event hub de **errores** para venenosos; nunca bloquees la partición.
- Un grupo por microservicio; réplicas ≤ particiones.
- Monitoreo de lag, limitación (`ServerBusy`) y reinicios de rebalance.
- Sin claves: `DefaultAzureCredential` y el handler OAUTHBEARER.
