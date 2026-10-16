# Azure · Function Apps · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, `azure-functions-java-library` 3.2, `durabletask-azure-functions` 1.6, Azure SDK BOM 1.3**. Verifica las vigentes.

> **Idea central:** una función Java es un **método anotado**. El host crea la instancia de la clase, llama al método y entrega el resultado. No hay contenedor de inyección de dependencias propio: lo compartido (clientes, pools) va en campos **estáticos**.

## 1. Proyecto Maven
```xml
<dependencies>
  <dependency>
    <groupId>com.microsoft.azure.functions</groupId>
    <artifactId>azure-functions-java-library</artifactId>
    <version>3.2.0</version>
  </dependency>
  <dependency>                                   <!-- solo si usas Durable -->
    <groupId>com.microsoft</groupId>
    <artifactId>durabletask-azure-functions</artifactId>
    <version>1.6.1</version>
  </dependency>
</dependencies>

<build>
  <plugins>
    <plugin>
      <groupId>com.microsoft.azure</groupId>
      <artifactId>azure-functions-maven-plugin</artifactId>
      <version>1.41.0</version>
      <configuration>
        <appName>func-modalima01</appName>
        <resourceGroup>rg-estudio-compute</resourceGroup>
        <runtime>
          <os>linux</os>
          <javaVersion>21</javaVersion>
        </runtime>
      </configuration>
      <executions>
        <execution>
          <id>package-functions</id>
          <goals><goal>package</goal></goals>
        </execution>
      </executions>
    </plugin>
  </plugins>
</build>
```
El plugin genera los `function.json` leyendo las anotaciones. Flex Consumption se despliega con `func azure functionapp publish` o con el paquete subido al contenedor de despliegue; verifica el flujo vigente.

## 2. HTTP
```java
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.HttpMethod;
import com.microsoft.azure.functions.HttpRequestMessage;
import com.microsoft.azure.functions.HttpResponseMessage;
import com.microsoft.azure.functions.HttpStatus;
import com.microsoft.azure.functions.annotation.AuthorizationLevel;
import com.microsoft.azure.functions.annotation.BindingName;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.HttpTrigger;
import java.util.Optional;

public class FuncionesHttp {

    @FunctionName("estadoPedido")
    public HttpResponseMessage estado(
            @HttpTrigger(name = "req", methods = {HttpMethod.GET},
                         authLevel = AuthorizationLevel.ANONYMOUS,   // la autenticación la hace la plataforma (Entra ID)
                         route = "pedidos/{id}")
            HttpRequestMessage<Optional<String>> request,
            @BindingName("id") String id,
            final ExecutionContext ctx) {

        ctx.getLogger().info("Consulta del pedido " + id + " (invocación " + ctx.getInvocationId() + ")");
        if (id == null || id.isBlank()) {
            return request.createResponseBuilder(HttpStatus.BAD_REQUEST).body("{\"error\":\"id requerido\"}").build();
        }
        return request.createResponseBuilder(HttpStatus.OK)
                .header("Content-Type", "application/json")
                .body("{\"id\":\"" + id + "\",\"estado\":\"EN_PREPARACION\"}")
                .build();
    }
}
```
> Con `ANONYMOUS`, la función es pública salvo que actives autenticación de la plataforma (Easy Auth con Entra ID) o valides el token tú mismo. **No** pongas `ANONYMOUS` sin autenticación delante.

## 3. Service Bus: idempotencia y salida a otra cola
```java
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.OutputBinding;
import com.microsoft.azure.functions.annotation.BindingName;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.ServiceBusQueueOutput;
import com.microsoft.azure.functions.annotation.ServiceBusQueueTrigger;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class FuncionesMensajeria {

    // DEMO. En producción: tabla/Redis/Cosmos con clave única (messageId o pedidoId) y TTL.
    private static final Set<String> PROCESADOS = ConcurrentHashMap.newKeySet();

    @FunctionName("procesarPedido")
    public void procesar(
            @ServiceBusQueueTrigger(name = "mensaje", queueName = "pedidos", connection = "SBCONN") String mensaje,
            @BindingName("MessageId") String messageId,
            @BindingName("DeliveryCount") int intentos,
            @ServiceBusQueueOutput(name = "salida", queueName = "facturas", connection = "SBCONN") OutputBinding<String> salida,
            final ExecutionContext ctx) {

        if (!PROCESADOS.add(messageId)) {
            ctx.getLogger().info("Duplicado ignorado: " + messageId);
            return;                                     // éxito: el mensaje se completa
        }
        try {
            // 1) validar  2) guardar con upsert  3) publicar el siguiente paso
            salida.setValue("{\"pedido\":" + mensaje + "}");
        } catch (RuntimeException e) {
            PROCESADOS.remove(messageId);               // permitir el reintento
            ctx.getLogger().severe("Fallo en el intento " + intentos + ": " + e.getMessage());
            throw e;                                    // el host abandona el mensaje: vuelve a la cola y, al agotar maxDeliveryCount, va a la DLQ
        }
    }
}
```
Notas:
- Lanzar la excepción **abandona** el mensaje (vuelve a la cola). Al superar `maxDeliveryCount` del Service Bus, pasa a la **DLQ**. Las directivas `@FixedDelayRetry`/`@ExponentialBackoffRetry` **no aplican** a Service Bus (usa la entrega del propio bus).
- Con la conexión por identidad: `SBCONN__fullyQualifiedNamespace=sb-modalima.servicebus.windows.net` y roles *Data Receiver* / *Data Sender*.
- Ajustes de concurrencia en `host.json` (sección 8).

## 4. Timer
```java
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.TimerTrigger;
import java.time.ZoneId;
import java.time.ZonedDateTime;

public class FuncionesProgramadas {

    // NCRONTAB de 6 campos: segundo minuto hora día mes díaSemana  (UTC por defecto)
    @FunctionName("resumenDiario")
    public void resumen(@TimerTrigger(name = "reloj", schedule = "0 0 12 * * *") String info, // 12:00 UTC = 07:00 Lima
                        final ExecutionContext ctx) {
        ZonedDateTime lima = ZonedDateTime.now(ZoneId.of("America/Lima"));
        ctx.getLogger().info("Resumen diario a las " + lima);
        // El timer usa un lease: una sola ejecución a la vez aunque haya muchas instancias.
    }
}
```
Para una zona horaria fija usa el setting `WEBSITE_TIME_ZONE` donde esté soportado (*verifica en Flex*) o calcula en UTC como arriba.

## 5. Blob con Event Grid y salida a otro blob
```java
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.OutputBinding;
import com.microsoft.azure.functions.annotation.BindingName;
import com.microsoft.azure.functions.annotation.BlobOutput;
import com.microsoft.azure.functions.annotation.BlobTrigger;
import com.microsoft.azure.functions.annotation.FunctionName;

public class FuncionesBlob {

    @FunctionName("miniaturas")
    public void miniaturas(
            @BlobTrigger(name = "contenido", path = "originales/{nombre}", source = "EventGrid",
                         connection = "STORAGE_FOTOS") byte[] contenido,
            @BindingName("nombre") String nombre,
            @BlobOutput(name = "salida", path = "miniaturas/{nombre}", connection = "STORAGE_FOTOS")
            OutputBinding<byte[]> salida,
            final ExecutionContext ctx) {

        ctx.getLogger().info("Procesando " + nombre + " (" + contenido.length + " bytes)");
        salida.setValue(redimensionar(contenido));      // entrada y salida en CONTENEDORES DISTINTOS
    }

    private byte[] redimensionar(byte[] original) {
        return original;                                // reemplaza por tu lógica de imagen
    }
}
```
Conexión por identidad: `STORAGE_FOTOS__blobServiceUri=https://stfotos.blob.core.windows.net` (+ `queueServiceUri` si el trigger lo requiere). Para el origen **Event Grid** se crea además una suscripción de eventos del storage hacia la función ([Eventos de Blob](../../06-storage/eventos-blob/README.md)).

## 6. Event Hubs: lotes con reintento
```java
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.annotation.Cardinality;
import com.microsoft.azure.functions.annotation.EventHubTrigger;
import com.microsoft.azure.functions.annotation.ExponentialBackoffRetry;
import com.microsoft.azure.functions.annotation.FunctionName;
import java.util.List;

public class FuncionesEventos {

    @FunctionName("telemetria")
    @ExponentialBackoffRetry(maxRetryCount = 5, minimumInterval = "00:00:05", maximumInterval = "00:01:00")
    public void telemetria(
            @EventHubTrigger(name = "eventos", eventHubName = "telemetria", connection = "EHCONN",
                             cardinality = Cardinality.MANY, consumerGroup = "$Default") List<String> eventos,
            final ExecutionContext ctx) {

        ctx.getLogger().info("Lote de " + eventos.size() + " eventos");
        for (String e : eventos) {
            // procesar de forma idempotente: si el lote se reintenta, TODOS vuelven a pasar
        }
    }
}
```
Si una excepción interrumpe el lote, el reintento repite **todo el lote**. Atrapa los errores por evento y manda los malos a un destino de revisión.

## 7. Durable Functions (saga con espera de aprobación)
```java
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.HttpMethod;
import com.microsoft.azure.functions.HttpRequestMessage;
import com.microsoft.azure.functions.HttpResponseMessage;
import com.microsoft.azure.functions.annotation.AuthorizationLevel;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.HttpTrigger;
import com.microsoft.durabletask.DurableTaskClient;
import com.microsoft.durabletask.Task;
import com.microsoft.durabletask.TaskCanceledException;
import com.microsoft.durabletask.TaskOrchestrationContext;
import com.microsoft.durabletask.azurefunctions.DurableActivityTrigger;
import com.microsoft.durabletask.azurefunctions.DurableClientContext;
import com.microsoft.durabletask.azurefunctions.DurableClientInput;
import com.microsoft.durabletask.azurefunctions.DurableOrchestrationTrigger;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

public class SagaPedido {

    /** Cliente: inicia la orquestación y devuelve 202 con las URLs de estado. */
    @FunctionName("IniciarSaga")
    public HttpResponseMessage iniciar(
            @HttpTrigger(name = "req", methods = {HttpMethod.POST}, authLevel = AuthorizationLevel.ANONYMOUS)
            HttpRequestMessage<Optional<String>> request,
            @DurableClientInput(name = "durable") DurableClientContext durable,
            final ExecutionContext ctx) {
        DurableTaskClient cliente = durable.getClient();
        String instanciaId = cliente.scheduleNewOrchestrationInstance("Saga", request.getBody().orElse(""));
        return durable.createCheckStatusResponse(request, instanciaId);
    }

    /** Orquestador: DETERMINISTA. Sin hora actual, sin UUID, sin I/O: eso va en actividades. */
    @FunctionName("Saga")
    public String saga(@DurableOrchestrationTrigger(name = "ctx") TaskOrchestrationContext ctx) {
        String pedidoId = ctx.getInput(String.class);

        boolean reservado = ctx.callActivity("ReservarStock", pedidoId, Boolean.class).await();
        if (!reservado) {
            return "SIN_STOCK";
        }

        // fan-out / fan-in: varias actividades en paralelo
        List<Task<Boolean>> validaciones = new ArrayList<>();
        for (String regla : List.of("fraude", "credito", "direccion")) {
            validaciones.add(ctx.callActivity("Validar", pedidoId + ":" + regla, Boolean.class));
        }
        List<Boolean> resultados = ctx.allOf(validaciones).await();
        if (resultados.contains(Boolean.FALSE)) {
            ctx.callActivity("LiberarStock", pedidoId, Void.class).await();
            return "RECHAZADO";
        }

        // interacción humana: espera un evento externo con timeout de 72 h
        try {
            boolean aprobado = ctx.waitForExternalEvent("Aprobacion", Duration.ofHours(72), Boolean.class).await();
            if (!aprobado) {
                ctx.callActivity("LiberarStock", pedidoId, Void.class).await();
                return "NO_APROBADO";
            }
        } catch (TaskCanceledException expiro) {
            ctx.callActivity("LiberarStock", pedidoId, Void.class).await();
            return "EXPIRADO";
        }
        return "CONFIRMADO";
    }

    /** Actividad: aquí SÍ se hace I/O. Debe ser idempotente: puede reintentarse. */
    @FunctionName("ReservarStock")
    public boolean reservar(@DurableActivityTrigger(name = "pedidoId") String pedidoId, final ExecutionContext ctx) {
        ctx.getLogger().info("Reservando stock de " + pedidoId);
        return true;
    }

    @FunctionName("Validar")
    public boolean validar(@DurableActivityTrigger(name = "entrada") String entrada, final ExecutionContext ctx) {
        return true;
    }

    @FunctionName("LiberarStock")
    public void liberar(@DurableActivityTrigger(name = "pedidoId") String pedidoId, final ExecutionContext ctx) {
        ctx.getLogger().info("Liberando stock de " + pedidoId);
    }
}
```
Reglas del orquestador: se **re-ejecuta desde el principio** (replay) cada vez que una actividad termina; si usas `System.currentTimeMillis()`, `UUID.randomUUID()` o llamas a un servicio, el replay diverge y la orquestación falla. Para esperar, usa `ctx.createTimer(...)`, no `Thread.sleep`.

## 8. `host.json`: concurrencia, tiempos y extensiones
```json
{
  "version": "2.0",
  "functionTimeout": "00:10:00",
  "extensionBundle": { "id": "Microsoft.Azure.Functions.ExtensionBundle", "version": "[4.*, 5.0.0)" },
  "extensions": {
    "serviceBus": {
      "maxConcurrentCalls": 16,
      "autoCompleteMessages": true,
      "maxAutoLockRenewalDuration": "00:05:00",
      "prefetchCount": 0
    },
    "eventHubs": { "maxEventBatchSize": 100, "batchCheckpointFrequency": 1 }
  },
  "logging": { "logLevel": { "default": "Information", "Host.Results": "Warning" } }
}
```
`maxConcurrentCalls` por **instancia**: 16 mensajes en paralelo × N instancias. Calcula el tope que tu base de datos soporta y limita la escala (`maximum-instance-count`). Los nombres exactos de las propiedades dependen de la versión de la extensión: *verifica en la documentación de `host.json`*.

## 9. Clientes compartidos (no crear uno por invocación)
Cada invocación crea un objeto de tu clase, pero los **campos estáticos** viven mientras viva la instancia. Ahí van el cliente HTTP, el `SecretClient`, el pool, etc.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;

final class Clientes {
    private Clientes() {}

    private static final class Holder {
        static final SecretClient SECRETOS = new SecretClientBuilder()
                .vaultUrl(System.getenv("KEYVAULT_URL"))
                .credential(new DefaultAzureCredentialBuilder().build())   // identidad administrada en Azure
                .buildClient();
    }

    static SecretClient secretos() {
        return Holder.SECRETOS;       // se crea en el primer uso y se reutiliza
    }
}
```
> En el arranque en frío, crear clientes pesados cuesta. Inicialízalos perezosamente (como arriba) y evita trabajo en el constructor de la clase de funciones.

## 10. Frameworks: Spring y Quarkus
- **Spring Cloud Function** (adaptador de Azure): escribes `@Bean Function<I,O>` y una clase puente que extiende `FunctionInvoker`. Útil para reutilizar lógica y el contenedor de Spring. Aumenta el arranque en frío: úsalo con Flex *always-ready* o Premium.

```java
// nocheck  (requiere spring-cloud-function-adapter-azure; verifica la versión compatible con tu Spring Boot)
@Bean
public Function<String, String> mayusculas() {
    return String::toUpperCase;
}
```
- **Quarkus**: existe integración con Azure Functions (Quarkiverse) para empaquetar endpoints JAX-RS o funciones Funqy; la compilación nativa reduce mucho el arranque en frío. *Verifica el estado y la versión de la extensión para tu Quarkus.*
- Si ya tienes una API completa en Spring/Quarkus, probablemente **no** es un caso de Functions: mejor [Container Apps](../container-apps/README.md) o [App Service](../app-service/README.md).

## 11. Reactivo
El worker de Java invoca tu método de forma **síncrona**: cuando el método devuelve (o termina), la invocación se da por completada. Por eso:
- No devuelvas un `Mono`/`Uni` esperando que la plataforma lo suscriba: **termina el trabajo antes de retornar** (`.block()` / `.join()` al final del método, nunca dentro de un hilo de event loop).
- La concurrencia viene de **varias invocaciones en paralelo** y de **más instancias**, no de un solo método reactivo.
- Dentro del método sí puedes usar Reactor/Mutiny/`CompletableFuture` para paralelizar varias llamadas a servicios y esperar el conjunto.

```java
import java.util.List;
import java.util.concurrent.CompletableFuture;

class Paralelo {
    static List<String> consultarEnParalelo() {
        CompletableFuture<String> stock = CompletableFuture.supplyAsync(() -> "stock-ok");
        CompletableFuture<String> precio = CompletableFuture.supplyAsync(() -> "precio-ok");
        return List.of(stock.join(), precio.join());      // espera ambos antes de retornar
    }
}
```

## 12. Pruebas
Las funciones son métodos normales: pruébalos con JUnit y mocks de `ExecutionContext` y `HttpRequestMessage` (por ejemplo con Mockito). Para integración local usa `func start` con Azurite, y publica mensajes reales en una cola de pruebas.

## 13. Qué NO hacer
- No crear `SecretClient`/`HttpClient`/pools en cada invocación.
- No usar `@Scheduled` de Spring dentro de una función: para eso existe el timer.
- No procesar sin idempotencia.
- No dejar la clave de la función en el código del cliente.
- No poner I/O ni aleatoriedad dentro de un orquestador Durable.
- No asumir que un secreto rotado llega al instante: los *app settings* con referencia a Key Vault se resuelven por la plataforma y pueden tardar en reflejarse; para rotaciones usa el SDK con caché corta ([Key Vault](../../03-secretos/key-vault/uso-en-java.md)).
