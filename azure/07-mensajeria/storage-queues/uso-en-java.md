# Azure · Storage Queues · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-storage-queue`, `azure-identity`). Verifica las vigentes.

Principios: **mensaje pequeño con ids**, trabajador **idempotente**, `delete` solo **después** de terminar, **cola de veneno** con umbral de `dequeueCount`, retroceso con `updateMessage`, y **sin claves** (Entra ID).

```properties
app.queue.endpoint=https://stqmodalima.queue.core.windows.net
app.queue.name=tareas
app.queue.poison=tareas-poison
```
```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-queue</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
```
Roles: productor → *Storage Queue Data Message Sender*; trabajador → *Storage Queue Data Message Processor* (recibe, actualiza y borra).

## 1. Productor (Spring Boot, imperativo)

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.azure.storage.queue.QueueMessageEncoding;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

import java.time.Duration;

record TareaMiniatura(int v, String productoId, String blobUrl) {
}

@Configuration
class ColasConfig {

    @Bean
    QueueClient cola(@Value("${app.queue.endpoint}") String endpoint, @Value("${app.queue.name}") String nombre) {
        return clienteDe(endpoint, nombre);
    }

    @Bean
    QueueClient colaVeneno(@Value("${app.queue.endpoint}") String endpoint, @Value("${app.queue.poison}") String nombre) {
        return clienteDe(endpoint, nombre);
    }

    private static QueueClient clienteDe(String endpoint, String nombre) {
        return new QueueClientBuilder()
                .endpoint(endpoint)
                .queueName(nombre)
                .credential(new DefaultAzureCredentialBuilder().build())   // sin claves de la cuenta
                .messageEncoding(QueueMessageEncoding.BASE64)              // coincide con Functions y otras herramientas
                .buildClient();
    }
}

@Service
class PublicadorDeTareas {

    private final QueueClient cola;

    PublicadorDeTareas(QueueClient cola) {
        this.cola = cola;
    }

    /** Envía ahora, con vencimiento a las 48 h (no infinito sin motivo). */
    void encolar(TareaMiniatura tarea) {
        String cuerpo = BinaryData.fromObject(tarea).toString();
        cola.sendMessageWithResponse(cuerpo, Duration.ZERO, Duration.ofHours(48), null, null);
    }

    /** Mensaje diferido: no será visible hasta pasado el retraso (máximo 7 días). */
    void encolarConRetraso(TareaMiniatura tarea, Duration retraso) {
        String cuerpo = BinaryData.fromObject(tarea).toString();
        cola.sendMessageWithResponse(cuerpo, retraso, Duration.ofDays(2), null, null);
    }
}
```

## 2. Trabajador (Spring Boot, imperativo con hilo virtual)

Recibe de a 16, procesa, **borra solo si terminó**, aplica **retroceso** si falla y envía a la **cola de veneno** si supera 5 intentos.

```java
import com.azure.core.util.BinaryData;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.models.QueueMessageItem;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

import java.time.Duration;

record TareaMiniatura(int v, String productoId, String blobUrl) {
}

@Component
class TrabajadorDeTareas implements SmartLifecycle {

    private static final Logger log = LoggerFactory.getLogger(TrabajadorDeTareas.class);
    private static final int MAX_INTENTOS = 5;
    private static final Duration VISIBILIDAD = Duration.ofSeconds(60);   // mayor que el peor tiempo de proceso

    private final QueueClient cola;
    private final QueueClient veneno;
    private volatile boolean activo;
    private Thread hilo;

    TrabajadorDeTareas(QueueClient cola, @Qualifier("colaVeneno") QueueClient veneno) {
        this.cola = cola;
        this.veneno = veneno;
    }

    @Override
    public void start() {
        activo = true;
        hilo = Thread.ofVirtual().name("trabajador-tareas").start(this::bucle);
    }

    @Override
    public void stop() {
        activo = false;
        if (hilo != null) {
            hilo.interrupt();
        }
    }

    @Override
    public boolean isRunning() {
        return activo;
    }

    private void bucle() {
        while (activo) {
            try {
                boolean huboTrabajo = false;
                for (QueueMessageItem m : cola.receiveMessages(16, VISIBILIDAD, Duration.ofSeconds(10), null)) {
                    huboTrabajo = true;
                    atender(m);
                }
                if (!huboTrabajo) {
                    Thread.sleep(2000);               // cola vacía: no martilles el servicio
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            } catch (RuntimeException e) {
                log.error("Fallo al recibir", e);
                pausa(5000);
            }
        }
    }

    private void atender(QueueMessageItem m) {
        String cuerpo = m.getBody().toString();

        if (m.getDequeueCount() > MAX_INTENTOS) {                 // mensaje venenoso
            veneno.sendMessage(cuerpo);                            // (en la práctica añade el motivo en un envoltorio JSON)
            cola.deleteMessage(m.getMessageId(), m.getPopReceipt());
            log.warn("Mensaje {} a la cola de veneno tras {} intentos", m.getMessageId(), m.getDequeueCount());
            return;
        }
        try {
            TareaMiniatura tarea = BinaryData.fromString(cuerpo).toObject(TareaMiniatura.class);
            generarMiniatura(tarea);                              // idempotente: misma tarea dos veces = mismo resultado
            cola.deleteMessage(m.getMessageId(), m.getPopReceipt());   // SOLO al terminar
        } catch (RuntimeException e) {
            long espera = Math.min(600, 10L * (1L << Math.min(m.getDequeueCount(), 6)));   // 20 s, 40 s, 80 s... tope 10 min
            cola.updateMessage(m.getMessageId(), m.getPopReceipt(), cuerpo, Duration.ofSeconds(espera));
            log.warn("Tarea {} falló; reintento en {} s", m.getMessageId(), espera, e);
        }
    }

    private void generarMiniatura(TareaMiniatura tarea) {
        // leer el blob original, redimensionar y escribir la miniatura con nombre determinista
    }

    private static void pausa(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```

**Trabajos largos:** si el proceso puede superar la invisibilidad, renueva con `updateMessage(id, popReceipt, cuerpo, Duration.ofSeconds(60))` periódicamente. Cada actualización devuelve un **popReceipt nuevo**: guárdalo y úsalo para el siguiente `updateMessage` o `deleteMessage`.

```java
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.models.QueueMessageItem;

import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

class RenovadorDeVisibilidad {

    private final ScheduledExecutorService reloj = Executors.newSingleThreadScheduledExecutor();

    /** Mantiene invisible el mensaje mientras dura el trabajo largo y devuelve el popReceipt vigente. */
    <T> T conRenovacion(QueueClient cola, QueueMessageItem m, java.util.function.Supplier<T> trabajo) {
        AtomicReference<String> popReceipt = new AtomicReference<>(m.getPopReceipt());
        ScheduledFuture<?> tarea = reloj.scheduleAtFixedRate(() -> {
            var r = cola.updateMessage(m.getMessageId(), popReceipt.get(), m.getBody().toString(), Duration.ofSeconds(60));
            popReceipt.set(r.getPopReceipt());
        }, 30, 30, TimeUnit.SECONDS);
        try {
            T resultado = trabajo.get();
            cola.deleteMessage(m.getMessageId(), popReceipt.get());
            return resultado;
        } finally {
            tarea.cancel(false);
        }
    }
}
```

## 3. Reactivo (Spring WebFlux): productor y trabajador con `QueueAsyncClient`

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.queue.QueueAsyncClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.azure.storage.queue.QueueMessageEncoding;
import com.azure.storage.queue.models.QueueMessageItem;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.Disposable;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.time.Duration;

record TareaMiniatura(int v, String productoId, String blobUrl) {
}

@RestController
class TareasReactivas {

    private final QueueAsyncClient cola;
    private Disposable suscripcion;

    TareasReactivas(@Value("${app.queue.endpoint}") String endpoint, @Value("${app.queue.name}") String nombre) {
        this.cola = new QueueClientBuilder()
                .endpoint(endpoint)
                .queueName(nombre)
                .credential(new DefaultAzureCredentialBuilder().build())
                .messageEncoding(QueueMessageEncoding.BASE64)
                .buildAsyncClient();
    }

    @PostMapping("/tareas")
    @ResponseStatus(HttpStatus.ACCEPTED)
    Mono<Void> encolar(@RequestBody TareaMiniatura tarea) {
        return cola.sendMessage(BinaryData.fromObject(tarea).toString()).then();
    }

    /** Cada 2 s pide hasta 16 mensajes y los procesa de uno en uno (concatMap = sin solapar lotes). */
    @PostConstruct
    void iniciar() {
        suscripcion = Flux.interval(Duration.ofSeconds(2))
                .onBackpressureDrop()
                .concatMap(tic -> cola.receiveMessages(16, Duration.ofSeconds(60)))
                .concatMap(this::atender)
                .onErrorContinue((e, o) -> System.err.println("Error: " + e))
                .subscribe();
    }

    @PreDestroy
    void detener() {
        if (suscripcion != null) {
            suscripcion.dispose();
        }
    }

    private Mono<Void> atender(QueueMessageItem m) {
        return Mono.fromRunnable(() -> generarMiniatura(m.getBody().toString()))
                .subscribeOn(Schedulers.boundedElastic())            // trabajo bloqueante fuera del hilo de eventos
                .then(cola.deleteMessage(m.getMessageId(), m.getPopReceipt()))
                .onErrorResume(e -> cola.updateMessage(m.getMessageId(), m.getPopReceipt(),
                        m.getBody().toString(), Duration.ofSeconds(30)).then());
    }

    private void generarMiniatura(String cuerpo) {
        // idempotente
    }
}
```

## 4. Azure Functions (Java) con disparador de cola

La Function **recibe, y si termina sin excepción, borra** el mensaje; tras 5 intentos fallidos lo mueve a `<cola>-poison`. Sin claves: conexión basada en identidad.

```java
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.OutputBinding;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.QueueOutput;
import com.microsoft.azure.functions.annotation.QueueTrigger;

class FuncionesDeTareas {

    @FunctionName("generarMiniatura")
    public void generar(
            @QueueTrigger(name = "mensaje", queueName = "tareas", connection = "ColaStorage") String mensaje,
            @QueueOutput(name = "siguiente", queueName = "tareas-publicadas", connection = "ColaStorage") OutputBinding<String> siguiente,
            final ExecutionContext contexto) {
        contexto.getLogger().info("Tarea recibida: " + mensaje);
        // procesar (idempotente) ...
        siguiente.setValue(mensaje);        // encadena la siguiente etapa
    }
}
```
```properties
# local.settings.json / configuración de la Function App (conexión por identidad, sin cadena)
ColaStorage__queueServiceUri=https://stqmodalima.queue.core.windows.net
ColaStorage__credential=managedidentity
# Si el productor usa otra codificación, ajusta host.json: "extensions": { "queues": { "messageEncoding": "base64" } }
```
Ver [Function Apps](../../04-compute/function-apps/README.md) para identidad, planes y escalado.

## 5. Quarkus (imperativo y reactivo con Mutiny)

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.queue.QueueAsyncClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.azure.storage.queue.QueueMessageEncoding;
import com.azure.storage.queue.models.QueueMessageItem;
import io.quarkus.runtime.StartupEvent;
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import reactor.adapter.JdkFlowAdapter;

import java.time.Duration;

record TareaMiniatura(int v, String productoId, String blobUrl) {
}

@ApplicationScoped
class TrabajadorQuarkus {

    @ConfigProperty(name = "app.queue.endpoint")
    String endpoint;

    @ConfigProperty(name = "app.queue.name")
    String nombre;

    private QueueAsyncClient cola;

    void alIniciar(@Observes StartupEvent evento) {
        cola = new QueueClientBuilder()
                .endpoint(endpoint)
                .queueName(nombre)
                .credential(new DefaultAzureCredentialBuilder().build())
                .messageEncoding(QueueMessageEncoding.BASE64)
                .buildAsyncClient();

        // Cada 2 s: pedir lote -> procesar de uno en uno -> borrar solo si terminó
        Multi.createFrom().ticks().every(Duration.ofSeconds(2))
                .onOverflow().drop()
                .onItem().transformToMultiAndConcatenate(t -> recibir())
                .onItem().transformToUniAndConcatenate(this::atender)
                .subscribe().with(x -> { }, e -> System.err.println("Trabajador detenido: " + e));
    }

    Uni<Void> encolar(TareaMiniatura tarea) {
        return Uni.createFrom().completionStage(() -> cola.sendMessage(BinaryData.fromObject(tarea).toString()).toFuture())
                .replaceWithVoid();
    }

    private Multi<QueueMessageItem> recibir() {
        return Multi.createFrom().publisher(
                JdkFlowAdapter.publisherToFlowPublisher(cola.receiveMessages(16, Duration.ofSeconds(60))));
    }

    private Uni<Void> atender(QueueMessageItem m) {
        return Uni.createFrom().item(() -> {
                    generar(m.getBody().toString());     // idempotente
                    return m;
                })
                .runSubscriptionOn(io.smallrye.mutiny.infrastructure.Infrastructure.getDefaultWorkerPool())
                .chain(ok -> Uni.createFrom().completionStage(() -> cola.deleteMessage(ok.getMessageId(), ok.getPopReceipt()).toFuture()))
                .onFailure().recoverWithUni(e -> Uni.createFrom().completionStage(() ->
                        cola.updateMessage(m.getMessageId(), m.getPopReceipt(), m.getBody().toString(), Duration.ofSeconds(30)).toFuture()
                ).replaceWithVoid());
    }

    private void generar(String cuerpo) {
        // procesamiento
    }
}
```

## 6. Escalar los trabajadores por el largo de la cola (KEDA en AKS o Container Apps)

El escalador `azure-queue` de KEDA ajusta las réplicas según los mensajes pendientes. Archivo listo en [ejemplos/keda](ejemplos/keda/escalado-por-cola.yaml).

## 7. Pruebas
- **Azurite** (emulador de Storage, incluye colas): `docker run -p 10001:10001 mcr.microsoft.com/azure-storage/azurite azurite-queue --queueHost 0.0.0.0`; cadena de conexión de desarrollo `UseDevelopmentStorage=true`.
- Pruebas de idempotencia: envía el mismo mensaje dos veces y verifica que el efecto es único.
- Pruebas del camino de veneno: fuerza `dequeueCount > 5` con una tarea que siempre falla.

## 8. Resumen de buenas prácticas en código
- `delete` **después** de procesar; nunca antes.
- Visibilidad > tiempo máximo de proceso, o renovación con `updateMessage` (guardando el nuevo `popReceipt`).
- Umbral de `dequeueCount` → cola de veneno con motivo y alerta.
- Retroceso exponencial en reintentos.
- Pausa cuando la cola está vacía.
- Mensaje con versión (`v`) y solo ids.
- Sin claves: `DefaultAzureCredential` + roles de datos.
