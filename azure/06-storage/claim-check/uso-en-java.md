# Azure · Claim Check · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-storage-blob`, `azure-messaging-servicebus`, `azure-identity`). Verifica las vigentes.

Principios del código: **blob primero, ticket después**; **ticket sin SAS** (lectura por identidad); **streaming** y **hash**; **liquidación manual** del mensaje (completar, abandonar o *dead-letter* con motivo); **idempotencia** con estado en base de datos.

```properties
# Spring Boot
app.storage.endpoint=https://stmodalima01.blob.core.windows.net
app.servicebus.namespace=sb-modalima.servicebus.windows.net
app.servicebus.queue=archivos
```
```properties
# Quarkus
app.storage.endpoint=https://stmodalima01.blob.core.windows.net
app.servicebus.namespace=sb-modalima.servicebus.windows.net
app.servicebus.queue=archivos
```
Roles: productor → *Storage Blob Data Contributor* + *Azure Service Bus Data Sender*; consumidor → *Storage Blob Data Reader* (+ *Contributor* si etiqueta) + *Azure Service Bus Data Receiver*. Namespace con `local_auth_enabled=false` (sin cadenas de conexión).

## 1. El ticket

```java
record TicketArchivo(
        String mensajeId,
        String tipo,
        int version,
        String blobUrl,          // SIN SAS
        String blobVersionId,    // lee exactamente esta versión inmutable
        String etag,
        long tamanoBytes,
        String contentType,
        String sha256,
        String propietario,
        String correlacionId,
        String creadoEn) {
}
```
Se serializa con `BinaryData.fromObject(...)` (JSON) y se lee con `getBody().toObject(TicketArchivo.class)`. Versiona el contrato (`version`) y **añade campos, no los quites**.

## 2. Productor: subir en streaming, calcular el hash y publicar el ticket

```java
import com.azure.core.util.BinaryData;
import com.azure.core.util.Context;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.BlobRequestConditions;
import com.azure.storage.blob.models.BlockBlobItem;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Map;
import java.util.UUID;

record TicketArchivo(String mensajeId, String tipo, int version, String blobUrl, String blobVersionId, String etag,
                     long tamanoBytes, String contentType, String sha256, String propietario,
                     String correlacionId, String creadoEn) {
}

@Configuration
class ServiceBusConfig {

    @Bean
    ServiceBusSenderClient emisor(@Value("${app.servicebus.namespace}") String namespace,
                                  @Value("${app.servicebus.queue}") String cola) {
        return new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(new DefaultAzureCredentialBuilder().build())
                .sender().queueName(cola)
                .buildClient();
    }
}

@Service
class ProductorTickets {

    private final BlobContainerClient contenedor;
    private final ServiceBusSenderClient emisor;

    ProductorTickets(BlobServiceClient blobs, ServiceBusSenderClient emisor) {
        this.contenedor = blobs.getBlobContainerClient("subidas");
        this.emisor = emisor;
    }

    /** Variante C (servicio a servicio): sube el archivo y SOLO después publica el ticket. */
    TicketArchivo subirYPublicar(InputStream origen, long tamano, String contentType, String propietario, String correlacionId)
            throws IOException, NoSuchAlgorithmException {
        String id = UUID.randomUUID().toString();
        BlobClient blob = contenedor.getBlobClient("usuarios/" + propietario + "/" + id);
        MessageDigest sha = MessageDigest.getInstance("SHA-256");

        BlockBlobItem subido;
        try (DigestInputStream entrada = new DigestInputStream(origen, sha)) {          // el hash se calcula MIENTRAS se sube
            BlobParallelUploadOptions opciones = new BlobParallelUploadOptions(BinaryData.fromStream(entrada, tamano))
                    .setHeaders(new BlobHttpHeaders().setContentType(contentType))
                    .setTags(Map.of("estado", "sin-confirmar"))                            // si algo falla, el ciclo de vida lo limpia
                    .setRequestConditions(new BlobRequestConditions().setIfNoneMatch("*"));
            subido = blob.uploadWithResponse(opciones, Duration.ofMinutes(30), Context.NONE).getValue();
        }

        TicketArchivo ticket = new TicketArchivo(id, "archivo.recibido", 1,
                blob.getBlobUrl(), subido.getVersionId(), subido.getETag(), tamano, contentType,
                HexFormat.of().formatHex(sha.digest()), propietario, correlacionId, Instant.now().toString());

        emisor.sendMessage(new ServiceBusMessage(BinaryData.fromObject(ticket))
                .setMessageId(id)                         // clave de la detección de duplicados
                .setSubject(ticket.tipo())
                .setContentType("application/json")
                .setCorrelationId(correlacionId));

        blob.setTags(Map.of("estado", "publicado"));      // ya hay ticket: deja de ser candidato a limpieza
        return ticket;
    }
}
```
Si el envío falla, el blob queda con `estado=sin-confirmar` y se borra solo ([ciclo de vida](../blob-storage/ejemplos/cli/lifecycle.json)).

## 3. Consumidor imperativo: verificar, procesar, liquidar

Estado de procesamiento en base de datos para **idempotencia** (tabla `procesados(mensaje_id text primary key, estado text, actualizado timestamptz)`):

```java
import com.azure.core.credential.TokenCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobClientBuilder;
import com.azure.storage.blob.models.BlobStorageException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.SmartLifecycle;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.HexFormat;
import java.util.Map;

record TicketArchivo(String mensajeId, String tipo, int version, String blobUrl, String blobVersionId, String etag,
                     long tamanoBytes, String contentType, String sha256, String propietario,
                     String correlacionId, String creadoEn) {
}

@Component
class ConsumidorTickets implements SmartLifecycle {

    private static final Logger LOG = LoggerFactory.getLogger(ConsumidorTickets.class);

    private final TokenCredential credencial = new DefaultAzureCredentialBuilder().build();
    private final JdbcClient jdbc;
    private final ServiceBusProcessorClient procesador;

    ConsumidorTickets(JdbcClient jdbc,
                      @Value("${app.servicebus.namespace}") String namespace,
                      @Value("${app.servicebus.queue}") String cola) {
        this.jdbc = jdbc;
        this.procesador = new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(credencial)
                .processor().queueName(cola)
                .disableAutoComplete()                                   // liquidamos NOSOTROS cada mensaje
                .maxConcurrentCalls(4)
                .maxAutoLockRenewDuration(Duration.ofMinutes(30))        // procesos largos: renueva el bloqueo
                .processMessage(this::procesar)
                .processError(ctx -> LOG.error("Error en Service Bus: {}", ctx.getException().toString()))
                .buildProcessorClient();
    }

    private void procesar(ServiceBusReceivedMessageContext ctx) {
        TicketArchivo ticket;
        try {
            ticket = ctx.getMessage().getBody().toObject(TicketArchivo.class);
        } catch (RuntimeException e) {
            ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("TICKET_INVALIDO").setDeadLetterErrorDescription(String.valueOf(e.getMessage())));
            return;
        }

        // --- Idempotencia: ¿ya se procesó con éxito? ---
        jdbc.sql("insert into procesados(mensaje_id, estado) values (?, 'EN_CURSO') on conflict do nothing")
                .param(ticket.mensajeId()).update();
        String estado = jdbc.sql("select estado from procesados where mensaje_id = ?")
                .param(ticket.mensajeId()).query(String.class).single();
        if ("OK".equals(estado)) {
            ctx.complete();                                              // duplicado: nada que hacer
            return;
        }

        Path temporal = null;
        try {
            // Se lee EXACTAMENTE la versión anunciada, con la identidad del consumidor (sin SAS)
            BlobClient blob = new BlobClientBuilder().endpoint(ticket.blobUrl()).credential(credencial).buildClient()
                    .getVersionClient(ticket.blobVersionId());
            temporal = Files.createTempFile("ticket-", ".dat");
            blob.downloadToFile(temporal.toString(), true);              // al disco, no a la memoria

            if (!ticket.sha256().equalsIgnoreCase(sha256(temporal))) {
                ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("HASH_INVALIDO")
                        .setDeadLetterErrorDescription("El contenido no coincide con el ticket " + ticket.mensajeId()));
                return;
            }

            long filas = procesarCsv(temporal);                          // streaming línea a línea
            blob.getContainerClient().getBlobClient(blob.getBlobName()).setTags(Map.of("estado", "procesado"));
            jdbc.sql("update procesados set estado = 'OK', actualizado = now() where mensaje_id = ?")
                    .param(ticket.mensajeId()).update();
            ctx.complete();
            LOG.info("Ticket {} procesado ({} filas)", ticket.mensajeId(), filas);
        } catch (BlobStorageException e) {
            if (e.getStatusCode() == 404) {
                ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("BLOB_AUSENTE").setDeadLetterErrorDescription(e.getErrorCode().toString()));
            } else {
                LOG.warn("Storage {} al leer {}; se reintentará", e.getStatusCode(), ticket.blobUrl());
                ctx.abandon();                                           // vuelve a la cola (cuenta una entrega)
            }
        } catch (IOException | NoSuchAlgorithmException | RuntimeException e) {
            LOG.warn("Fallo procesando {}: {}", ticket.mensajeId(), e.toString());
            ctx.abandon();
        } finally {
            if (temporal != null) {
                try {
                    Files.deleteIfExists(temporal);
                } catch (IOException ignorado) {
                    // el volumen temporal se limpia al reiniciar
                }
            }
        }
    }

    private static String sha256(Path archivo) throws IOException, NoSuchAlgorithmException {
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        try (InputStream in = Files.newInputStream(archivo)) {
            byte[] buffer = new byte[1 << 16];
            int n;
            while ((n = in.read(buffer)) > 0) {
                sha.update(buffer, 0, n);
            }
        }
        return HexFormat.of().formatHex(sha.digest());
    }

    private static long procesarCsv(Path archivo) throws IOException {
        long filas = 0;
        try (BufferedReader lector = Files.newBufferedReader(archivo, StandardCharsets.UTF_8)) {
            String linea;
            while ((linea = lector.readLine()) != null) {
                // aquí: validar/insertar por lotes (nunca fila por fila contra la BD)
                filas++;
            }
        }
        return filas;
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
Notas: `abandon()` suma una entrega; al llegar a `maxDeliveryCount` el broker lo manda a la DLQ. Los errores **irrecuperables** (hash, ticket inválido, blob ausente) van a *dead-letter* directo con motivo.

## 4. Consumidor reactivo (Reactor)

```java
import com.azure.core.credential.TokenCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusReceiverAsyncClient;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import com.azure.storage.blob.BlobAsyncClient;
import com.azure.storage.blob.BlobClientBuilder;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;

import java.security.MessageDigest;
import java.time.Duration;
import java.util.HexFormat;

record TicketArchivo(String mensajeId, String tipo, int version, String blobUrl, String blobVersionId, String etag,
                     long tamanoBytes, String contentType, String sha256, String propietario,
                     String correlacionId, String creadoEn) {
}

class ConsumidorReactivo {

    private final TokenCredential credencial = new DefaultAzureCredentialBuilder().build();
    private final ServiceBusReceiverAsyncClient receptor;

    ConsumidorReactivo(String namespace, String cola) {
        this.receptor = new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(credencial)
                .receiver().queueName(cola)
                .disableAutoComplete()
                .maxAutoLockRenewDuration(Duration.ofMinutes(30))
                .buildAsyncClient();
    }

    Disposable iniciar() {
        return receptor.receiveMessages()
                .flatMap(mensaje -> {
                    TicketArchivo ticket = mensaje.getBody().toObject(TicketArchivo.class);
                    BlobAsyncClient blob = new BlobClientBuilder()
                            .endpoint(ticket.blobUrl()).credential(credencial).versionId(ticket.blobVersionId())
                            .buildAsyncClient();
                    return hashDe(blob)
                            .flatMap(hash -> hash.equalsIgnoreCase(ticket.sha256())
                                    ? receptor.complete(mensaje)
                                    : receptor.deadLetter(mensaje, new DeadLetterOptions().setDeadLetterReason("HASH_INVALIDO")))
                            .onErrorResume(error -> receptor.abandon(mensaje));
                }, 4)                                                    // 4 tickets a la vez
                .subscribe();
    }

    /** Hash incremental del flujo: memoria constante, sin escribir a disco. */
    private Mono<String> hashDe(BlobAsyncClient blob) {
        return Mono.fromCallable(() -> MessageDigest.getInstance("SHA-256"))
                .flatMap(sha -> blob.downloadStream()
                        .doOnNext(buffer -> sha.update(buffer.asReadOnlyBuffer()))
                        .then(Mono.fromSupplier(() -> HexFormat.of().formatHex(sha.digest()))));
    }

    void detener(Disposable suscripcion) {
        suscripcion.dispose();
        receptor.close();
    }
}
```

## 5. Quarkus (imperativo con ciclo de vida CDI)

```java
import com.azure.core.credential.TokenCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobClientBuilder;
import com.azure.storage.blob.models.BlobStorageException;
import io.quarkus.runtime.ShutdownEvent;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

import java.time.Duration;

record TicketArchivo(String mensajeId, String tipo, int version, String blobUrl, String blobVersionId, String etag,
                     long tamanoBytes, String contentType, String sha256, String propietario,
                     String correlacionId, String creadoEn) {
}

@ApplicationScoped
public class ConsumidorQuarkus {

    private static final Logger LOG = Logger.getLogger(ConsumidorQuarkus.class);

    @ConfigProperty(name = "app.servicebus.namespace")
    String namespace;

    @ConfigProperty(name = "app.servicebus.queue")
    String cola;

    private final TokenCredential credencial = new DefaultAzureCredentialBuilder().build();
    private ServiceBusProcessorClient procesador;

    void alArrancar(@Observes StartupEvent evento) {
        procesador = new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(credencial)
                .processor().queueName(cola)
                .disableAutoComplete()
                .maxConcurrentCalls(4)
                .maxAutoLockRenewDuration(Duration.ofMinutes(30))
                .processMessage(this::procesar)
                .processError(ctx -> LOG.errorf("Service Bus: %s", ctx.getException()))
                .buildProcessorClient();
        procesador.start();
    }

    void alApagar(@Observes ShutdownEvent evento) {
        if (procesador != null) {
            procesador.close();
        }
    }

    private void procesar(ServiceBusReceivedMessageContext ctx) {
        TicketArchivo ticket = ctx.getMessage().getBody().toObject(TicketArchivo.class);
        try {
            BlobClient blob = new BlobClientBuilder().endpoint(ticket.blobUrl()).credential(credencial).buildClient()
                    .getVersionClient(ticket.blobVersionId());
            long tamano = blob.getProperties().getBlobSize();
            if (tamano != ticket.tamanoBytes()) {
                ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("TAMANO_INVALIDO"));
                return;
            }
            // ... descargar en streaming, verificar hash, procesar ...
            ctx.complete();
        } catch (BlobStorageException e) {
            if (e.getStatusCode() == 404) {
                ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("BLOB_AUSENTE"));
            } else {
                ctx.abandon();
            }
        }
    }
}
```
Para flujos con **SmallRye Reactive Messaging**, Service Bus habla AMQP 1.0 y puede usarse con el conector AMQP, pero el SDK oficial ofrece más control (bloqueos, DLQ, sesiones): *evalúa según tu caso*.

## 6. Imperativo vs reactivo para el consumidor

| | Imperativo (`ServiceBusProcessorClient`) | Reactivo (`ServiceBusReceiverAsyncClient`) |
|---|---|---|
| Concurrencia | `maxConcurrentCalls` hilos | `flatMap(..., N)` |
| Descarga | A disco o `InputStream` | `Flux<ByteBuffer>` (hash incremental) |
| Procesamiento pesado (CPU, JDBC) | Natural | Cuidado de no bloquear el event loop (`publishOn(boundedElastic)`) |
| Liquidación | `ctx.complete()/abandon()/deadLetter()` | `receptor.complete(m)` etc. devuelven `Mono` |
| Hilos virtuales (Java 21) | Excelentes para procesos largos con E/S bloqueante | No necesarios |

## 7. Qué NO hacer en el código
- `autoComplete` activo con procesamiento que puede fallar (se completaría un mensaje no procesado).
- Capturar excepciones y no liquidar el mensaje (queda bloqueado hasta expirar).
- Leer el blob "último" en vez de la versión del ticket.
- Procesar antes de verificar el hash.
- Cadenas de conexión con `SharedAccessKey` en la configuración.
- Registrar el ticket completo con datos personales.
