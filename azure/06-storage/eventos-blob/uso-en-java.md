# Azure · Eventos de Blob · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-messaging-eventgrid`, `azure-messaging-servicebus`, `azure-storage-blob`, `azure-identity`, `azure-functions-java-library`). Verifica las vigentes.

Idea central: el evento es **un aviso con una referencia**. El código (1) valida el origen, (2) responde rápido, (3) procesa de forma **idempotente**, (4) tolera el **desorden** y (5) lee el blob con **`If-Match: eTag`** para procesar justo lo anunciado.

```xml
<!-- Maven -->
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-eventgrid</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-servicebus</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-blob</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
```
```properties
app.eventos.clave=${EVENTOS_CLAVE}                       # solo si autenticas el webhook con clave en la URL
app.servicebus.namespace=sb-modalima.servicebus.windows.net
app.servicebus.queue=eventos-blob
```

## 1. Webhook imperativo (Spring MVC): handshake + recepción

Hace tres cosas: contesta el **handshake** (Event Grid schema y CloudEvents), verifica la **clave**, y **encola el trabajo** sin procesarlo dentro de la petición.

```java
import com.azure.core.models.CloudEvent;
import com.azure.messaging.eventgrid.EventGridEvent;
import com.azure.messaging.eventgrid.systemevents.StorageBlobCreatedEventData;
import com.azure.messaging.eventgrid.systemevents.SubscriptionValidationEventData;
import com.azure.messaging.eventgrid.SystemEventNames;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;
import java.util.Map;

record TrabajoBlob(String eventoId, String url, String eTag, String sequencer, long tamano) {
}

interface Despachador {
    /** Persiste el trabajo (cola, tabla) y vuelve de inmediato. */
    void encolar(TrabajoBlob trabajo);
}

@RestController
@RequestMapping("/eventos/blob")
class WebhookBlob {

    private final Despachador despachador;
    private final byte[] clave;

    WebhookBlob(Despachador despachador, @Value("${app.eventos.clave}") String clave) {
        this.despachador = despachador;
        this.clave = clave.getBytes(StandardCharsets.UTF_8);
    }

    /** Handshake de CloudEvents: Event Grid pregunta con OPTIONS antes de crear la suscripción. */
    @RequestMapping(method = RequestMethod.OPTIONS)
    ResponseEntity<Void> validarCloudEvents(@RequestParam("clave") String claveRecibida,
                                            @RequestHeader(value = "WebHook-Request-Origin", required = false) String origen) {
        if (!claveValida(claveRecibida) || origen == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok()
                .header("WebHook-Allowed-Origin", origen)
                .header("WebHook-Allowed-Rate", "*")
                .header("Allow", "POST")
                .build();
    }

    @PostMapping
    ResponseEntity<Object> recibir(@RequestParam("clave") String claveRecibida,
                                   @RequestHeader(value = "Content-Type", required = false) String contentType,
                                   @RequestBody String cuerpo) {
        if (!claveValida(claveRecibida)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        boolean cloudEvents = contentType != null && contentType.contains("cloudevents");
        return cloudEvents ? procesarCloudEvents(cuerpo) : procesarEventGrid(cuerpo);
    }

    private ResponseEntity<Object> procesarEventGrid(String cuerpo) {
        List<EventGridEvent> eventos = EventGridEvent.fromString(cuerpo);
        for (EventGridEvent evento : eventos) {
            String tipo = evento.getEventType();
            if (SystemEventNames.EVENT_GRID_SUBSCRIPTION_VALIDATION.equals(tipo)) {
                SubscriptionValidationEventData validacion = evento.getData().toObject(SubscriptionValidationEventData.class);
                return ResponseEntity.ok(Map.of("validationResponse", validacion.getValidationCode()));
            }
            if (SystemEventNames.STORAGE_BLOB_CREATED.equals(tipo)) {
                StorageBlobCreatedEventData datos = evento.getData().toObject(StorageBlobCreatedEventData.class);
                despachador.encolar(new TrabajoBlob(evento.getId(), datos.getUrl(), datos.getETag(), datos.getSequencer(),
                        datos.getContentLength() == null ? -1 : datos.getContentLength()));
            }
        }
        return ResponseEntity.ok().build();       // 2xx = entregado; cualquier otra cosa = reintento
    }

    private ResponseEntity<Object> procesarCloudEvents(String cuerpo) {
        for (CloudEvent evento : CloudEvent.fromString(cuerpo)) {
            if (SystemEventNames.STORAGE_BLOB_CREATED.equals(evento.getType())) {
                StorageBlobCreatedEventData datos = evento.getData().toObject(StorageBlobCreatedEventData.class);
                despachador.encolar(new TrabajoBlob(evento.getId(), datos.getUrl(), datos.getETag(), datos.getSequencer(),
                        datos.getContentLength() == null ? -1 : datos.getContentLength()));
            }
        }
        return ResponseEntity.ok().build();
    }

    /** Comparación en tiempo constante: no filtra información por tiempos de respuesta. */
    private boolean claveValida(String recibida) {
        return recibida != null && MessageDigest.isEqual(clave, recibida.getBytes(StandardCharsets.UTF_8));
    }
}
```
Notas:
- Prefiere autenticar con **Microsoft Entra ID** (la suscripción presenta un token con la audiencia de tu app); la clave en la URL es la opción mínima. Con Entra ID usas `spring-boot-starter-oauth2-resource-server` y validas el emisor y la audiencia como en cualquier API.
- Si `encolar` falla, deja que la excepción devuelva **500**: Event Grid reintentará. No tragues errores.
- Los webhooks no deben hacer trabajo pesado; el tiempo de espera de Event Grid es corto (decenas de segundos).

## 2. Consumidor de la cola (el camino recomendado): idempotente, ordenado y con `If-Match`

Event Grid entrega a la cola `eventos-blob` (Service Bus) en esquema **CloudEvents**. Tablas de apoyo:

```sql
create table eventos_procesados (evento_id text primary key, procesado_en timestamptz not null default now());
create table blob_secuencia (url text primary key, sequencer text not null);
```

```java
import com.azure.core.credential.TokenCredential;
import com.azure.core.models.CloudEvent;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventgrid.systemevents.StorageBlobCreatedEventData;
import com.azure.messaging.eventgrid.SystemEventNames;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.messaging.servicebus.models.DeadLetterOptions;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobClientBuilder;
import com.azure.storage.blob.models.BlobRequestConditions;
import com.azure.storage.blob.models.BlobStorageException;
import com.azure.storage.blob.options.BlobInputStreamOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.SmartLifecycle;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;

@Component
class ConsumidorEventosBlob implements SmartLifecycle {

    private static final Logger LOG = LoggerFactory.getLogger(ConsumidorEventosBlob.class);
    private static final String CONTENEDOR_ENTRADA = "/containers/subidas/blobs/entrada/";

    private final TokenCredential credencial = new DefaultAzureCredentialBuilder().build();
    private final JdbcClient jdbc;
    private final ServiceBusProcessorClient procesador;

    ConsumidorEventosBlob(JdbcClient jdbc,
                          @Value("${app.servicebus.namespace}") String namespace,
                          @Value("${app.servicebus.queue}") String cola) {
        this.jdbc = jdbc;
        this.procesador = new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(namespace)
                .credential(credencial)
                .processor().queueName(cola)
                .disableAutoComplete()
                .maxConcurrentCalls(4)
                .maxAutoLockRenewDuration(Duration.ofMinutes(10))
                .processMessage(this::procesar)
                .processError(ctx -> LOG.error("Service Bus: {}", ctx.getException().toString()))
                .buildProcessorClient();
    }

    private void procesar(ServiceBusReceivedMessageContext ctx) {
        List<CloudEvent> eventos;
        try {
            eventos = CloudEvent.fromString(ctx.getMessage().getBody().toString());
        } catch (RuntimeException e) {
            ctx.deadLetter(new DeadLetterOptions().setDeadLetterReason("EVENTO_INVALIDO").setDeadLetterErrorDescription(String.valueOf(e.getMessage())));
            return;
        }
        try {
            for (CloudEvent evento : eventos) {
                tratar(evento);
            }
            ctx.complete();
        } catch (BlobStorageException e) {
            if (e.getStatusCode() == 403) {
                LOG.error("Sin permiso para leer el blob; revisa el rol 'Storage Blob Data Reader'");
                ctx.abandon();                                    // se reintenta; al agotar entregas va a la DLQ
            } else {
                ctx.abandon();
            }
        } catch (IOException | RuntimeException e) {
            LOG.warn("Fallo procesando el evento: {}", e.toString());
            ctx.abandon();
        }
    }

    private void tratar(CloudEvent evento) throws IOException {
        if (!SystemEventNames.STORAGE_BLOB_CREATED.equals(evento.getType()) || evento.getSubject() == null
                || !evento.getSubject().contains(CONTENEDOR_ENTRADA)) {
            return;                                               // no es para nosotros (el filtro del lado del consumidor es la 2.ª red)
        }
        StorageBlobCreatedEventData datos = evento.getData().toObject(StorageBlobCreatedEventData.class);
        if (yaProcesado(evento.getId(), datos.getUrl(), datos.getSequencer())) {
            LOG.info("Evento {} duplicado u obsoleto; se ignora", evento.getId());
            return;
        }

        BlobClient blob = new BlobClientBuilder().endpoint(datos.getUrl()).credential(credencial).buildClient();
        // El ETag del evento va entre comillas en el encabezado If-Match: lee EXACTAMENTE lo anunciado
        BlobRequestConditions condicion = new BlobRequestConditions().setIfMatch("\"" + datos.getETag() + "\"");
        try (InputStream in = blob.openInputStream(new BlobInputStreamOptions().setRequestConditions(condicion));
             BufferedReader lector = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            long filas = 0;
            while (lector.readLine() != null) {
                filas++;                                          // aquí: validar y cargar por lotes
            }
            LOG.info("{} procesado: {} filas", datos.getUrl(), filas);
        } catch (BlobStorageException e) {
            if (e.getStatusCode() == 412 || e.getStatusCode() == 404) {
                LOG.info("El blob cambió o ya no existe ({}): llegará un evento más reciente", e.getStatusCode());
                return;                                           // se completa el mensaje: nada que hacer con este evento
            }
            throw e;
        }
        registrar(evento.getId(), datos.getUrl(), datos.getSequencer());
    }

    /** Duplicado (mismo id) u obsoleto (sequencer menor o igual al ya procesado para ese blob). */
    private boolean yaProcesado(String eventoId, String url, String sequencer) {
        boolean duplicado = jdbc.sql("select count(*) from eventos_procesados where evento_id = ?")
                .param(eventoId).query(Integer.class).single() > 0;
        if (duplicado) {
            return true;
        }
        return jdbc.sql("select sequencer from blob_secuencia where url = ?")
                .param(url).query(String.class).optional()
                .map(ultimo -> ultimo.compareTo(sequencer) >= 0)   // misma longitud hexadecimal: orden lexicográfico
                .orElse(false);
    }

    private void registrar(String eventoId, String url, String sequencer) {
        jdbc.sql("insert into eventos_procesados(evento_id) values (?) on conflict do nothing").param(eventoId).update();
        jdbc.sql("""
                insert into blob_secuencia(url, sequencer) values (?, ?)
                on conflict (url) do update set sequencer = excluded.sequencer
                where blob_secuencia.sequencer < excluded.sequencer""")
                .param(url).param(sequencer).update();
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
Por qué así:
- **Idempotencia**: `eventos_procesados` descarta el mismo `id`.
- **Desorden**: `blob_secuencia` descarta eventos con `sequencer` menor al ya procesado para ese blob.
- **`If-Match`**: si el blob ya cambió, Storage responde **412**; el evento viejo se ignora porque habrá otro más nuevo.
- Se registra **después** de procesar: si el proceso cae a medias, el reintento vuelve a procesar (el trabajo debe ser idempotente).

## 3. Webhook reactivo (Spring WebFlux)

Solo el esquema Event Grid, para ver la forma reactiva. El despachador devuelve `Mono<Void>`; no se bloquea el *event loop*.

```java
import com.azure.messaging.eventgrid.EventGridEvent;
import com.azure.messaging.eventgrid.systemevents.StorageBlobCreatedEventData;
import com.azure.messaging.eventgrid.systemevents.SubscriptionValidationEventData;
import com.azure.messaging.eventgrid.SystemEventNames;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.Map;

record TrabajoBlob(String eventoId, String url, String eTag, String sequencer, long tamano) {
}

interface DespachadorReactivo {
    Mono<Void> encolar(TrabajoBlob trabajo);
}

@RestController
@RequestMapping("/eventos/blob")
class WebhookBlobReactivo {

    private final DespachadorReactivo despachador;

    WebhookBlobReactivo(DespachadorReactivo despachador) {
        this.despachador = despachador;
    }

    @PostMapping
    Mono<ResponseEntity<Object>> recibir(@RequestBody String cuerpo) {
        return Mono.fromCallable(() -> EventGridEvent.fromString(cuerpo))
                .flatMapMany(Flux::fromIterable)
                .concatMap(evento -> {
                    if (SystemEventNames.EVENT_GRID_SUBSCRIPTION_VALIDATION.equals(evento.getEventType())) {
                        String codigo = evento.getData().toObject(SubscriptionValidationEventData.class).getValidationCode();
                        return Mono.just(ResponseEntity.<Object>ok(Map.of("validationResponse", codigo)));
                    }
                    if (SystemEventNames.STORAGE_BLOB_CREATED.equals(evento.getEventType())) {
                        StorageBlobCreatedEventData d = evento.getData().toObject(StorageBlobCreatedEventData.class);
                        return despachador.encolar(new TrabajoBlob(evento.getId(), d.getUrl(), d.getETag(), d.getSequencer(),
                                        d.getContentLength() == null ? -1 : d.getContentLength()))
                                .then(Mono.<ResponseEntity<Object>>empty());
                    }
                    return Mono.<ResponseEntity<Object>>empty();
                })
                .next()                                              // si hubo validación, responde con ella
                .switchIfEmpty(Mono.fromSupplier(() -> ResponseEntity.ok().build()));
    }
}
```
Si el despachador falla, el `Mono` termina en error y Spring responde 5xx: Event Grid reintenta.

## 4. Quarkus (Mutiny): webhook con `Uni`

```java
import com.azure.messaging.eventgrid.EventGridEvent;
import com.azure.messaging.eventgrid.systemevents.StorageBlobCreatedEventData;
import com.azure.messaging.eventgrid.systemevents.SubscriptionValidationEventData;
import com.azure.messaging.eventgrid.SystemEventNames;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.OPTIONS;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

record TrabajoBlob(String eventoId, String url, String eTag, String sequencer, long tamano) {
}

interface DespachadorUni {
    Uni<Void> encolar(TrabajoBlob trabajo);
}

@Path("/eventos/blob")
@ApplicationScoped
public class WebhookQuarkus {

    @Inject
    DespachadorUni despachador;

    @OPTIONS
    public Response handshake(@HeaderParam("WebHook-Request-Origin") String origen) {
        if (origen == null) {
            return Response.status(Response.Status.BAD_REQUEST).build();
        }
        return Response.ok()
                .header("WebHook-Allowed-Origin", origen)
                .header("WebHook-Allowed-Rate", "*")
                .header("Allow", "POST")
                .build();
    }

    @POST
    @Consumes(MediaType.WILDCARD)
    public Uni<Response> recibir(String cuerpo) {
        List<EventGridEvent> eventos = EventGridEvent.fromString(cuerpo);
        List<Uni<Void>> trabajos = new ArrayList<>();
        for (EventGridEvent evento : eventos) {
            if (SystemEventNames.EVENT_GRID_SUBSCRIPTION_VALIDATION.equals(evento.getEventType())) {
                String codigo = evento.getData().toObject(SubscriptionValidationEventData.class).getValidationCode();
                return Uni.createFrom().item(Response.ok(Map.of("validationResponse", codigo)).build());
            }
            if (SystemEventNames.STORAGE_BLOB_CREATED.equals(evento.getEventType())) {
                StorageBlobCreatedEventData d = evento.getData().toObject(StorageBlobCreatedEventData.class);
                trabajos.add(despachador.encolar(new TrabajoBlob(evento.getId(), d.getUrl(), d.getETag(), d.getSequencer(),
                        d.getContentLength() == null ? -1 : d.getContentLength())));
            }
        }
        if (trabajos.isEmpty()) {
            return Uni.createFrom().item(Response.ok().build());
        }
        return Uni.join().all(trabajos).andFailFast()
                .replaceWith(Response.ok().build());
    }
}
```
Quarkus no tiene una extensión oficial de Event Grid: se usa el SDK de Azure. El consumidor de la cola es el mismo patrón que en [Claim Check](../claim-check/uso-en-java.md#5-quarkus-imperativo-con-ciclo-de-vida-cdi) (procesador de Service Bus con `StartupEvent`/`ShutdownEvent`).

## 5. Azure Function con disparador de Event Grid

Código mínimo cuando el trabajo es corto (reenviar a Service Bus, indexar un registro). Conexiones con **identidad** (`ConexionSb__fullyQualifiedNamespace`).

```java
import com.azure.messaging.eventgrid.EventGridEvent;
import com.azure.messaging.eventgrid.systemevents.StorageBlobCreatedEventData;
import com.azure.messaging.eventgrid.SystemEventNames;
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.OutputBinding;
import com.microsoft.azure.functions.annotation.EventGridTrigger;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.ServiceBusQueueOutput;

public class FuncionBlobCreado {

    @FunctionName("alCrearBlob")
    public void ejecutar(
            @EventGridTrigger(name = "evento") String contenido,
            @ServiceBusQueueOutput(name = "salida", queueName = "archivos", connection = "ConexionSb") OutputBinding<String> salida,
            final ExecutionContext contexto) {
        for (EventGridEvent evento : EventGridEvent.fromString(contenido)) {
            if (!SystemEventNames.STORAGE_BLOB_CREATED.equals(evento.getEventType())) {
                continue;
            }
            StorageBlobCreatedEventData datos = evento.getData().toObject(StorageBlobCreatedEventData.class);
            contexto.getLogger().info("Blob nuevo: " + datos.getUrl() + " (" + datos.getContentLength() + " bytes)");
            salida.setValue(datos.getUrl());      // en la práctica: el ticket JSON completo del Claim Check
        }
    }
}
```
Detalles de Functions (planes, identidades, conexiones) en [Function Apps](../../04-compute/function-apps/README.md).

## 6. Probar el parseo sin Azure
Los eventos de [ejemplos/eventos](ejemplos/eventos/) sirven para pruebas unitarias del mapeo (sin red ni credenciales):

```java
import com.azure.messaging.eventgrid.EventGridEvent;
import com.azure.messaging.eventgrid.systemevents.StorageBlobCreatedEventData;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

class PruebaParseo {

    public static void main(String[] args) throws IOException {
        String json = Files.readString(Path.of("ejemplos/eventos/blobcreated-eventgrid.json"));
        EventGridEvent evento = EventGridEvent.fromString(json).get(0);
        StorageBlobCreatedEventData datos = evento.getData().toObject(StorageBlobCreatedEventData.class);
        System.out.println(evento.getId() + " " + datos.getUrl() + " " + datos.getETag() + " " + datos.getSequencer());
    }
}
```
Para el webhook, envía los JSON con `curl` a tu endpoint local (ver [CLI](ejemplos/cli/eventos-blob.sh)).

## 7. Imperativo vs reactivo en este caso

| | Imperativo | Reactivo |
|---|---|---|
| Webhook | Simple; hilo por petición mientras encola | `Mono`/`Uni`; sin bloquear el *event loop* |
| Consumidor de cola | `ServiceBusProcessorClient` + descarga por `InputStream` | `ServiceBusReceiverAsyncClient` + `downloadStream()` |
| Procesamiento pesado (CPU/JDBC) | Natural | Cuidado: `publishOn(boundedElastic)` |
| Hilos virtuales (Java 21) | Muy buena opción para E/S bloqueante | No hacen falta |

## 8. Qué NO hacer en el código
- Procesar el archivo **dentro** del webhook (reintentos y duplicados).
- Tragar excepciones en el webhook y devolver 200 sin haber encolado.
- Asumir que cada evento llega una sola vez y en orden.
- Leer el blob sin `If-Match` y procesar un contenido distinto al anunciado.
- Escribir el resultado en la ruta que dispara el mismo evento.
- Registrar el cuerpo completo del evento con datos personales en el nombre del blob.
- Usar la clave de la URL sin HTTPS ni rotación.
