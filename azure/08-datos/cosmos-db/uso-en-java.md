# Azure · Cosmos DB · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1 (Spring Framework 7), SDK `azure-cosmos` 4.83 (BOM de Azure SDK 1.3), Quarkus 3.40**. Verifica las vigentes.

Principios: **un solo cliente por aplicación**, **Entra ID sin claves** (`DefaultAzureCredential`), **lecturas puntuales** antes que consultas, **clave de partición siempre explícita**, **`id` determinista** para idempotencia, **ETag** en actualizaciones concurrentes, y **medir RU** (`getRequestCharge()`) desde el primer día.

```xml
<!-- Spring Boot (versión administrada por azure-sdk-bom) -->
<dependency><groupId>com.azure</groupId><artifactId>azure-cosmos</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-webmvc</artifactId></dependency>      <!-- imperativo -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-webflux</artifactId></dependency>    <!-- reactivo -->
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-servicebus</artifactId></dependency>                       <!-- relevo del Outbox -->
<!-- Quarkus (no hay extensión oficial de Cosmos: se usa el SDK directamente) -->
<dependency><groupId>com.azure</groupId><artifactId>azure-cosmos</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-rest-jackson</artifactId></dependency>
```
Permisos: la identidad de la aplicación necesita un **rol de datos de Cosmos** (ver [Terraform](ejemplos/terraform/main.tf)); el rol *Contributor* de Azure no basta.

## 1. El modelo del documento (y dos trampas: fechas y dinero)

Un documento es un **agregado**: el pedido con sus líneas. Usa `record` con anotaciones Jackson (el SDK de Cosmos trae su propio Jackson 2, independiente del Jackson 3 de Spring Boot 4; las anotaciones `com.fasterxml.jackson.annotation` valen para ambos).

- **Fechas:** el SDK serializa `Instant` **como número** (segundos desde 1970) si no lo indicas. Con `@JsonFormat(shape = STRING)` se guarda como texto ISO-8601 (`2026-10-16T14:05:00Z`), que es ordenable y comparable en consultas.
- **Dinero:** los números de Cosmos son **IEEE 754 de 64 bits**. Guarda importes como **enteros en la unidad menor** (`totalCentimos`), no como `BigDecimal`/`double`.
- **`_etag`:** el SDK lo devuelve en cada documento; lo mapeamos para usarlo en actualizaciones concurrentes (y se omite al escribir si es nulo).
- **`id` y clave de partición** forman la identidad: el `id` lo decides tú y debe ser **determinista** (por ejemplo, la `Idempotency-Key` del cliente).

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

enum Estado { PENDIENTE_PAGO, PAGADO, ENVIADO, ENTREGADO, CANCELADO }

@JsonIgnoreProperties(ignoreUnknown = true)
record Linea(String sku, int cantidad, long precioCentimos) { }

@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
record Pedido(
        String id,                                  // determinista: viene de la Idempotency-Key
        String clienteId,                           // CLAVE DE PARTICIÓN (/clienteId)
        String tipo,
        Estado estado,
        long totalCentimos,
        String moneda,
        List<Linea> lineas,
        @JsonFormat(shape = JsonFormat.Shape.STRING) Instant creadoEn,
        @JsonProperty("_etag") String etag) {      // versión para concurrencia optimista

    static Pedido nuevo(String id, String clienteId, List<Linea> lineas) {
        long total = lineas.stream().mapToLong(l -> l.cantidad() * l.precioCentimos()).sum();
        return new Pedido(id, clienteId, "pedido", Estado.PENDIENTE_PAGO, total, "PEN",
                List.copyOf(lineas), Instant.now(), null);
    }

    Pedido agregarLinea(Linea linea) {
        List<Linea> nuevas = new ArrayList<>(lineas);
        nuevas.add(linea);
        long total = nuevas.stream().mapToLong(l -> l.cantidad() * l.precioCentimos()).sum();
        return new Pedido(id, clienteId, tipo, estado, total, moneda, List.copyOf(nuevas), creadoEn, etag);
    }

    Pedido conEtag(String nuevoEtag) {
        return new Pedido(id, clienteId, tipo, estado, totalCentimos, moneda, lineas, creadoEn, nuevoEtag);
    }
}
```

## 2. Spring Boot imperativo: el cliente único

`CosmosClient` es **seguro entre hilos y caro de crear**: una instancia por aplicación, cerrada al apagar. Modo directo (TCP) para menor latencia; `preferredRegions` en el orden de cercanía; `contentResponseOnWriteEnabled(false)` evita que el servidor devuelva el documento en cada escritura (ahorra red).

```yaml
# application.yml
app:
  cosmos:
    endpoint: https://cosmos-modalima-abc123.documents.azure.com:443/
    base: pedidos-db
    regiones-preferidas: eastus2,centralus
```

```java
import com.azure.cosmos.ConsistencyLevel;
import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.cosmos.ThrottlingRetryOptions;
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;
import java.util.List;

@Configuration
class CosmosConfig {

    @Bean(destroyMethod = "close")
    CosmosClient cosmosClient(
            @Value("${app.cosmos.endpoint}") String endpoint,
            @Value("${app.cosmos.regiones-preferidas:}") List<String> regiones) {

        return new CosmosClientBuilder()
                .endpoint(endpoint)
                // En Azure: identidad administrada / Workload Identity. En tu máquina: az login.
                .credential(new DefaultAzureCredentialBuilder().build())
                .consistencyLevel(ConsistencyLevel.SESSION)          // igual o más débil que el de la cuenta
                .preferredRegions(regiones)
                .directMode()                                         // TCP; con Private Endpoint abre 10250-10255
                .contentResponseOnWriteEnabled(false)
                .throttlingRetryOptions(new ThrottlingRetryOptions()  // reintentos automáticos ante 429
                        .setMaxRetryAttemptsOnThrottledRequests(9)
                        .setMaxRetryWaitTime(Duration.ofSeconds(30)))
                .userAgentSuffix("pedidos-api")                       // aparece en los registros de diagnóstico
                .buildClient();
    }
}
```

## 3. Repositorio: lectura puntual, ETag, patch condicional, consulta paginada y token de sesión

Las operaciones y sus equivalentes:

| Necesito | Método | Notas |
|---|---|---|
| Crear (idempotente) | `createItem` | 409 si ya existe: tratarlo como "ya hecho" |
| Leer por `id` + clave | `readItem` | La más barata (~1 RU/KB); 404 si no existe |
| Reemplazar con control | `replaceItem` + `setIfMatchETag` | 412 si alguien cambió el documento |
| Cambiar campos | `patchItem` | `set/replace/add/remove/increment`; predicado opcional |
| Insertar o reemplazar | `upsertItem` | Sin control de versiones |
| Borrar | `deleteItem` | |
| Consultar | `queryItems` + `SqlQuerySpec` | Fija la clave en las opciones |

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.CosmosException;
import com.azure.cosmos.models.CosmosItemRequestOptions;
import com.azure.cosmos.models.CosmosItemResponse;
import com.azure.cosmos.models.CosmosPatchItemRequestOptions;
import com.azure.cosmos.models.CosmosPatchOperations;
import com.azure.cosmos.models.CosmosQueryRequestOptions;
import com.azure.cosmos.models.FeedResponse;
import com.azure.cosmos.models.PartitionKey;
import com.azure.cosmos.models.SqlParameter;
import com.azure.cosmos.models.SqlQuerySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Repository;
import org.springframework.web.bind.annotation.ResponseStatus;

import java.time.Instant;
import java.util.Iterator;
import java.util.List;
import java.util.Optional;

@ResponseStatus(HttpStatus.PRECONDITION_FAILED)
class ConflictoDeConcurrenciaException extends RuntimeException {
    ConflictoDeConcurrenciaException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}

record Pagina<T>(List<T> items, String continuacion, double ru) { }

record Lectura(Pedido pedido, String tokenSesion, double ru) { }

@Repository
class PedidoRepositorio {

    private final CosmosContainer pedidos;

    PedidoRepositorio(CosmosClient cliente, @Value("${app.cosmos.base}") String base) {
        // getContainer no hace llamadas de red: es solo una referencia
        this.pedidos = cliente.getDatabase(base).getContainer("pedidos");
    }

    /** Crea el pedido. Devuelve false si ya existía (misma id y clienteId): la operación es idempotente. */
    boolean crear(Pedido pedido) {
        try {
            pedidos.createItem(pedido, new PartitionKey(pedido.clienteId()), new CosmosItemRequestOptions());
            return true;
        } catch (CosmosException e) {
            if (e.getStatusCode() == 409) {
                return false;
            }
            throw e;
        }
    }

    /** Lectura puntual: id + clave de partición. Lo más barato que existe. */
    Optional<Pedido> leer(String id, String clienteId) {
        try {
            return Optional.ofNullable(pedidos.readItem(id, new PartitionKey(clienteId), Pedido.class).getItem());
        } catch (CosmosException e) {
            if (e.getStatusCode() == 404) {
                return Optional.empty();
            }
            throw e;
        }
    }

    /** Igual que leer, pero propaga el token de sesión: lees lo que otra instancia acaba de escribir. */
    Optional<Lectura> leerConSesion(String id, String clienteId, String tokenSesion) {
        CosmosItemRequestOptions opciones = new CosmosItemRequestOptions();
        if (tokenSesion != null && !tokenSesion.isBlank()) {
            opciones.setSessionToken(tokenSesion);
        }
        try {
            CosmosItemResponse<Pedido> r = pedidos.readItem(id, new PartitionKey(clienteId), opciones, Pedido.class);
            return Optional.of(new Lectura(r.getItem(), r.getSessionToken(), r.getRequestCharge()));
        } catch (CosmosException e) {
            if (e.getStatusCode() == 404) {
                return Optional.empty();
            }
            throw e;
        }
    }

    /** Reemplazo con concurrencia optimista: falla con 412 si el documento cambió desde que lo leíste. */
    void reemplazar(Pedido pedido) {
        CosmosItemRequestOptions opciones = new CosmosItemRequestOptions().setIfMatchETag(pedido.etag());
        try {
            pedidos.replaceItem(pedido, pedido.id(), new PartitionKey(pedido.clienteId()), opciones);
        } catch (CosmosException e) {
            if (e.getStatusCode() == 412) {
                throw new ConflictoDeConcurrenciaException("El pedido " + pedido.id() + " cambió; vuelve a leerlo", e);
            }
            throw e;
        }
    }

    /**
     * Cambia el estado SOLO si sigue en el estado esperado (patch condicional, sin leer antes).
     * El predicado no admite parámetros: por eso se arma con un enum y no con texto libre (evita inyección).
     */
    boolean cambiarEstado(String id, String clienteId, Estado esperado, Estado nuevo) {
        CosmosPatchOperations operaciones = CosmosPatchOperations.create()
                .set("/estado", nuevo.name())
                .set("/actualizadoEn", Instant.now().toString());
        CosmosPatchItemRequestOptions opciones = new CosmosPatchItemRequestOptions()
                .setFilterPredicate("FROM c WHERE c.estado = '" + esperado.name() + "'");
        try {
            pedidos.patchItem(id, new PartitionKey(clienteId), operaciones, opciones, Pedido.class);
            return true;
        } catch (CosmosException e) {
            if (e.getStatusCode() == 412) {
                return false;                       // el predicado no se cumplió: otro ya lo cambió
            }
            throw e;
        }
    }

    void eliminar(String id, String clienteId) {
        try {
            pedidos.deleteItem(id, new PartitionKey(clienteId), new CosmosItemRequestOptions());
        } catch (CosmosException e) {
            if (e.getStatusCode() != 404) {         // borrar algo que ya no existe no es un error
                throw e;
            }
        }
    }

    /** Una página de pedidos del cliente. Se pagina con el token de continuación, no con OFFSET. */
    Pagina<Pedido> pedidosDelCliente(String clienteId, Estado estado, int tamano, String continuacion) {
        SqlQuerySpec consulta = new SqlQuerySpec(
                "SELECT * FROM c WHERE c.clienteId = @clienteId AND c.estado = @estado "
                        + "ORDER BY c.estado ASC, c.creadoEn DESC",
                List.of(new SqlParameter("@clienteId", clienteId), new SqlParameter("@estado", estado.name())));

        // Fijar la clave de partición envía la consulta a UNA sola partición
        CosmosQueryRequestOptions opciones = new CosmosQueryRequestOptions()
                .setPartitionKey(new PartitionKey(clienteId));

        Iterator<FeedResponse<Pedido>> paginas = pedidos
                .queryItems(consulta, opciones, Pedido.class)
                .iterableByPage(continuacion, tamano)
                .iterator();

        if (!paginas.hasNext()) {
            return new Pagina<>(List.of(), null, 0);
        }
        FeedResponse<Pedido> pagina = paginas.next();
        return new Pagina<>(pagina.getResults(), pagina.getContinuationToken(), pagina.getRequestCharge());
    }
}
```

**Servicio con reintento por conflicto** (leer → modificar → reemplazar con ETag; si otro cambió el documento, se vuelve a leer):

```java
import org.springframework.stereotype.Service;

@Service
class PedidoServicio {

    private final PedidoRepositorio repositorio;

    PedidoServicio(PedidoRepositorio repositorio) {
        this.repositorio = repositorio;
    }

    void agregarLinea(String id, String clienteId, Linea linea) {
        for (int intento = 1; ; intento++) {
            Pedido actual = repositorio.leer(id, clienteId)
                    .orElseThrow(() -> new IllegalArgumentException("Pedido inexistente: " + id));
            try {
                repositorio.reemplazar(actual.agregarLinea(linea));   // usa el ETag leído
                return;
            } catch (ConflictoDeConcurrenciaException e) {
                if (intento == 3) {
                    throw e;                                            // demasiada contención: que lo vea el cliente
                }
            }
        }
    }
}
```

## 4. Controlador REST: `Idempotency-Key`, `ETag` y `If-Match`

El HTTP ya tiene el vocabulario: el `ETag` de Cosmos viaja como `ETag`; el cliente lo devuelve en `If-Match`; un 412 llega como `412 Precondition Failed`. El token de sesión viaja en una cabecera propia.

```java
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;

record CrearPedido(List<Linea> lineas) { }

@RestController
@RequestMapping("/clientes/{clienteId}/pedidos")
class PedidoControlador {

    private static final String CABECERA_SESION = "X-Cosmos-Session";

    private final PedidoRepositorio repositorio;

    PedidoControlador(PedidoRepositorio repositorio) {
        this.repositorio = repositorio;
    }

    /** La Idempotency-Key del cliente es el id del documento: reintentar no duplica el pedido. */
    @PostMapping
    ResponseEntity<Void> crear(@PathVariable String clienteId,
                               @RequestHeader("Idempotency-Key") String claveIdempotencia,
                               @RequestBody CrearPedido cuerpo) {
        boolean nuevo = repositorio.crear(Pedido.nuevo(claveIdempotencia, clienteId, cuerpo.lineas()));
        URI ubicacion = URI.create("/clientes/" + clienteId + "/pedidos/" + claveIdempotencia);
        return nuevo ? ResponseEntity.created(ubicacion).build() : ResponseEntity.ok().location(ubicacion).build();
    }

    @GetMapping("/{id}")
    ResponseEntity<Pedido> leer(@PathVariable String clienteId, @PathVariable String id,
                                @RequestHeader(name = CABECERA_SESION, required = false) String sesion) {
        return repositorio.leerConSesion(id, clienteId, sesion)
                .map(l -> ResponseEntity.ok()
                        .eTag(l.pedido().etag())
                        .header(CABECERA_SESION, l.tokenSesion())
                        .header("X-Cosmos-RU", String.valueOf(l.ru()))   // útil en pruebas y diagnóstico
                        .body(l.pedido()))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PutMapping("/{id}")
    ResponseEntity<Void> reemplazar(@PathVariable String clienteId, @PathVariable String id,
                                    @RequestHeader("If-Match") String etag,
                                    @RequestBody Pedido cuerpo) {
        // Si el ETag ya no coincide, el repositorio lanza ConflictoDeConcurrenciaException → HTTP 412
        repositorio.reemplazar(cuerpo.conEtag(etag));
        return ResponseEntity.noContent().build();
    }
}
```

## 5. Lote transaccional: pedido + evento Outbox en un solo paso

Un **lote transaccional** (hasta 100 operaciones, **misma clave de partición**, todo o nada) permite el patrón **Outbox** sin base de datos relacional: el pedido y su evento se guardan juntos o no se guarda nada. Un procesador del change feed (siguiente sección) publica después el evento. El evento va en el mismo contenedor, con el mismo `clienteId`, un `ttl` propio y un `id` determinista.

```java
import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.models.CosmosBatch;
import com.azure.cosmos.models.CosmosBatchResponse;
import com.azure.cosmos.models.PartitionKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@JsonIgnoreProperties(ignoreUnknown = true)
record EventoOutbox(String id, String clienteId, String tipo, String evento, String pedidoId,
                    long totalCentimos,
                    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant creadoEn,
                    int ttl) {

    static EventoOutbox pedidoCreado(Pedido p) {
        // id determinista: si el cliente reintenta, el lote entero falla con 409 y no hay duplicados
        return new EventoOutbox("EVT-" + p.id() + "-CREADO", p.clienteId(), "evento-outbox", "PedidoCreado",
                p.id(), p.totalCentimos(), Instant.now(), 604_800);   // se borra solo a los 7 días
    }
}

@Service
class CreacionDePedidos {

    private final CosmosContainer pedidos;

    CreacionDePedidos(CosmosClient cliente, @Value("${app.cosmos.base}") String base) {
        this.pedidos = cliente.getDatabase(base).getContainer("pedidos");
    }

    /** @return true si se creó; false si ya existía (reintento idempotente) */
    boolean crearConEvento(Pedido pedido) {
        CosmosBatch lote = CosmosBatch.createCosmosBatch(new PartitionKey(pedido.clienteId()));
        lote.createItemOperation(pedido);
        lote.createItemOperation(EventoOutbox.pedidoCreado(pedido));

        CosmosBatchResponse respuesta = pedidos.executeCosmosBatch(lote);
        if (respuesta.isSuccessStatusCode()) {
            return true;
        }
        if (respuesta.getStatusCode() == 409) {
            return false;
        }
        throw new IllegalStateException("Lote rechazado: " + respuesta.getStatusCode()
                + " " + respuesta.getErrorMessage());
    }
}
```

## 6. Change feed: el relevo del Outbox (procesador con arrendamientos)

El **procesador del change feed** lee los cambios del contenedor `pedidos` y guarda su progreso en el contenedor `leases`. Con varias réplicas del servicio, **los rangos de particiones se reparten solos**. La entrega es **al menos una vez**: publica en Service Bus con `messageId = id del evento` (la detección de duplicados lo descarta) y haz idempotentes a los consumidores. Para el lado de mensajería, ver [Service Bus](../../07-mensajeria/service-bus/uso-en-java.md).

```java
import com.azure.cosmos.ChangeFeedProcessor;
import com.azure.cosmos.ChangeFeedProcessorBuilder;
import com.azure.cosmos.CosmosAsyncClient;
import com.azure.cosmos.CosmosAsyncDatabase;
import com.azure.cosmos.models.ChangeFeedProcessorOptions;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.UUID;

@Component
class RelevoOutbox implements SmartLifecycle {

    private final ChangeFeedProcessor procesador;
    private final ServiceBusSenderClient emisor;
    private volatile boolean corriendo;

    RelevoOutbox(CosmosAsyncClient cliente, ServiceBusSenderClient emisor,
                 @Value("${app.cosmos.base}") String base) {
        this.emisor = emisor;
        CosmosAsyncDatabase bd = cliente.getDatabase(base);

        this.procesador = new ChangeFeedProcessorBuilder()
                // Nombre único por instancia (en Kubernetes: el nombre del pod)
                .hostName(System.getenv().getOrDefault("HOSTNAME", UUID.randomUUID().toString()))
                .feedContainer(bd.getContainer("pedidos"))
                .leaseContainer(bd.getContainer("leases"))
                .options(new ChangeFeedProcessorOptions()
                        .setLeasePrefix("outbox-")                 // un prefijo por procesador lógico
                        .setFeedPollDelay(Duration.ofSeconds(1))
                        .setMaxItemCount(100))
                .handleChanges(this::publicar)
                .buildChangeFeedProcessor();
    }

    /** Si lanza una excepción, el lote se reintenta desde el último punto guardado (al menos una vez). */
    private void publicar(List<JsonNode> cambios) {
        for (JsonNode documento : cambios) {
            if (!"evento-outbox".equals(documento.path("tipo").asText())) {
                continue;                                          // el feed trae todos los cambios del contenedor
            }
            ServiceBusMessage mensaje = new ServiceBusMessage(documento.path("payload").isMissingNode()
                    ? documento.toString() : documento.path("payload").toString())
                    .setMessageId(documento.path("id").asText())   // detección de duplicados
                    .setSubject(documento.path("evento").asText())
                    .setPartitionKey(documento.path("clienteId").asText());
            emisor.sendMessage(mensaje);
        }
    }

    @Override
    public void start() {
        procesador.start().block(Duration.ofSeconds(60));
        corriendo = true;
    }

    @Override
    public void stop() {
        procesador.stop().block(Duration.ofSeconds(60));          // libera los arrendamientos para otras réplicas
        corriendo = false;
    }

    @Override
    public boolean isRunning() {
        return corriendo;
    }
}
```
Este componente necesita un `CosmosAsyncClient` (ver sección 8). Puntos delicados:
- **No esperes trabajo asíncrono sin terminar dentro del manejador**: el progreso se guarda al terminar tu método.
- Los **borrados no aparecen** en el modo por defecto: usa borrado lógico + TTL.
- Cada instancia de procesador lee **todos los cambios del contenedor**; filtra por `tipo`.
- Usa el **punto de conexión global** y regiones preferidas; los puntos regionales crean arrendamientos por región.
- Monitorea el retraso (*lag*) y las RU del contenedor `leases`.

## 7. Importaciones masivas (bulk) y reintentos adicionales

La **ejecución masiva** agrupa operaciones por partición, ajusta el ritmo a las RU disponibles y reintenta los 429 sola. Úsala para cargas iniciales, migraciones y reprocesos (no para tráfico normal).

```java
import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.models.CosmosBulkOperationResponse;
import com.azure.cosmos.models.CosmosBulkOperations;
import com.azure.cosmos.models.CosmosItemOperation;
import com.azure.cosmos.models.PartitionKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.List;

record ResumenImportacion(int correctas, int fallidas, double ru) { }

@Service
class ImportadorDePedidos {

    private final CosmosContainer pedidos;

    ImportadorDePedidos(CosmosClient cliente, @Value("${app.cosmos.base}") String base) {
        this.pedidos = cliente.getDatabase(base).getContainer("pedidos");
    }

    ResumenImportacion importar(List<Pedido> lista) {
        List<CosmosItemOperation> operaciones = lista.stream()
                .map(p -> (CosmosItemOperation) CosmosBulkOperations.getUpsertItemOperation(
                        p, new PartitionKey(p.clienteId())))
                .toList();

        int correctas = 0;
        int fallidas = 0;
        double ru = 0;
        for (CosmosBulkOperationResponse<Object> r : pedidos.executeBulkOperations(operaciones)) {
            if (r.getResponse() != null && r.getResponse().isSuccessStatusCode()) {
                correctas++;
                ru += r.getResponse().getRequestCharge();
            } else {
                fallidas++;                    // r.getException() / r.getResponse().getStatusCode() para el detalle
            }
        }
        return new ResumenImportacion(correctas, fallidas, ru);
    }
}
```

El SDK ya reintenta los 429 (hasta 9 veces / 30 s). Para **errores transitorios que el SDK no reintenta en tu operación** (por ejemplo un 408 agotado, un 503 o un 429 que persistió), añade un reintento acotado y respetuoso con `retry-after`. Reglas: **solo operaciones idempotentes**, pocos intentos, espera creciente.

| Código | Significado | Qué hacer |
|---|---|---|
| 400 | Solicitud inválida (consulta mal formada, documento demasiado grande) | Corregir; no reintentar |
| 401 / 403 | Sin autenticar / sin rol de datos | Revisar identidad y asignación de rol |
| 404 | No existe (documento, contenedor o clave de partición equivocada) | Tratar como "no existe" si es lectura |
| 408 | Tiempo agotado | Reintentar (idempotente) |
| 409 | Ya existe (`id` + clave) o viola clave única | Idempotencia: considerarlo hecho |
| 412 | ETag o predicado no coincide | Releer y reintentar |
| 413 | Documento mayor de 2 MB | Reducir / mover a Blob |
| 429 | Sin RU suficientes | El SDK reintenta; si persiste, subir RU o corregir partición caliente |
| 449 | Conflicto de escritura concurrente | Reintentar |
| 503 | Servicio no disponible / región en conmutación | Reintentar con espera |

```java
import com.azure.cosmos.CosmosException;

import java.time.Duration;
import java.util.function.Supplier;

final class Reintentos {

    private Reintentos() { }

    static <T> T conReintento(Supplier<T> operacion, int maximo) {
        for (int intento = 1; ; intento++) {
            try {
                return operacion.get();
            } catch (CosmosException e) {
                int codigo = e.getStatusCode();
                boolean transitorio = codigo == 408 || codigo == 429 || codigo == 449 || codigo == 503;
                if (!transitorio || intento >= maximo) {
                    throw e;
                }
                // El servidor sugiere cuánto esperar (429); si no, espera creciente
                Duration espera = e.getRetryAfterDuration() != null && !e.getRetryAfterDuration().isZero()
                        ? e.getRetryAfterDuration()
                        : Duration.ofMillis(100L * (1L << intento));
                try {
                    Thread.sleep(espera.toMillis());
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
            }
        }
    }
}
```

## 8. Spring WebFlux (reactivo): `CosmosAsyncClient` y Reactor

El SDK es **reactivo por dentro** (Reactor): `CosmosAsyncClient` y `CosmosAsyncContainer` devuelven `Mono`/`Flux` (`CosmosPagedFlux` es un `Flux`). No hace falta ningún puente: encaja directo con WebFlux.

```java
import com.azure.cosmos.ConsistencyLevel;
import com.azure.cosmos.CosmosAsyncClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

@Configuration
class CosmosReactivaConfig {

    @Bean(destroyMethod = "close")
    CosmosAsyncClient cosmosAsyncClient(
            @Value("${app.cosmos.endpoint}") String endpoint,
            @Value("${app.cosmos.regiones-preferidas:}") List<String> regiones) {

        return new CosmosClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .consistencyLevel(ConsistencyLevel.SESSION)
                .preferredRegions(regiones)
                .directMode()
                .contentResponseOnWriteEnabled(false)
                .buildAsyncClient();
    }
}
```

```java
import com.azure.cosmos.CosmosAsyncClient;
import com.azure.cosmos.CosmosAsyncContainer;
import com.azure.cosmos.CosmosException;
import com.azure.cosmos.models.CosmosItemRequestOptions;
import com.azure.cosmos.models.CosmosItemResponse;
import com.azure.cosmos.models.CosmosQueryRequestOptions;
import com.azure.cosmos.models.PartitionKey;
import com.azure.cosmos.models.SqlParameter;
import com.azure.cosmos.models.SqlQuerySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Repository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Repository
class PedidoRepositorioReactivo {

    private final CosmosAsyncContainer pedidos;

    PedidoRepositorioReactivo(CosmosAsyncClient cliente, @Value("${app.cosmos.base}") String base) {
        this.pedidos = cliente.getDatabase(base).getContainer("pedidos");
    }

    Mono<Pedido> leer(String id, String clienteId) {
        return pedidos.readItem(id, new PartitionKey(clienteId), Pedido.class)
                .map(CosmosItemResponse::getItem)
                .onErrorResume(CosmosException.class,
                        e -> e.getStatusCode() == 404 ? Mono.empty() : Mono.error(e));
    }

    /** @return true si se creó, false si ya existía */
    Mono<Boolean> crear(Pedido pedido) {
        return pedidos.createItem(pedido, new PartitionKey(pedido.clienteId()), new CosmosItemRequestOptions())
                .thenReturn(true)
                .onErrorResume(CosmosException.class,
                        e -> e.getStatusCode() == 409 ? Mono.just(false) : Mono.error(e));
    }

    Flux<Pedido> pedidosDelCliente(String clienteId, Estado estado, int limite) {
        SqlQuerySpec consulta = new SqlQuerySpec(
                "SELECT * FROM c WHERE c.clienteId = @clienteId AND c.estado = @estado "
                        + "ORDER BY c.estado ASC, c.creadoEn DESC",
                List.of(new SqlParameter("@clienteId", clienteId), new SqlParameter("@estado", estado.name())));
        CosmosQueryRequestOptions opciones = new CosmosQueryRequestOptions()
                .setPartitionKey(new PartitionKey(clienteId));

        return pedidos.queryItems(consulta, opciones, Pedido.class)
                .byPage(limite)                                   // páginas de hasta "limite" elementos
                .next()                                           // solo la primera página
                .flatMapMany(pagina -> Flux.fromIterable(pagina.getResults()));
    }
}

@RestController
@RequestMapping("/reactivo/clientes/{clienteId}/pedidos")
class PedidoControladorReactivo {

    private final PedidoRepositorioReactivo repositorio;

    PedidoControladorReactivo(PedidoRepositorioReactivo repositorio) {
        this.repositorio = repositorio;
    }

    @GetMapping("/{id}")
    Mono<ResponseEntity<Pedido>> leer(@PathVariable String clienteId, @PathVariable String id) {
        return repositorio.leer(id, clienteId)
                .map(p -> ResponseEntity.ok().eTag(p.etag()).body(p))
                .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @GetMapping
    Flux<Pedido> listar(@PathVariable String clienteId,
                        @RequestParam(defaultValue = "PAGADO") Estado estado,
                        @RequestParam(defaultValue = "20") int limite) {
        return repositorio.pedidosDelCliente(clienteId, estado, Math.min(limite, 100));
    }
}
```
Reglas en reactivo: **nunca bloquees** (`block()`, `Thread.sleep`) dentro de un hilo de evento; el único `block()` aceptable es el arranque/parada del procesador del change feed. Las operaciones de **Cosmos ya son no bloqueantes**, así que no necesitan `subscribeOn(boundedElastic())`.

## 9. Quarkus · imperativo (CDI + JAX-RS)

No hay extensión oficial de Cosmos para Quarkus: se usa el SDK con un **productor CDI** (un cliente por aplicación) y la configuración de MicroProfile. En modo JVM funciona sin más; para **imagen nativa** el SDK necesita configuración de reflexión y puede requerir ajustes (*verifica el estado vigente antes de comprometerte con nativo*).

```properties
# application.properties
app.cosmos.endpoint=https://cosmos-modalima-abc123.documents.azure.com:443/
app.cosmos.base=pedidos-db
app.cosmos.regiones-preferidas=eastus2,centralus
```

```java
import com.azure.cosmos.ConsistencyLevel;
import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.identity.DefaultAzureCredentialBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.util.List;

@ApplicationScoped
class CosmosProductor {

    @ConfigProperty(name = "app.cosmos.endpoint")
    String endpoint;

    @ConfigProperty(name = "app.cosmos.regiones-preferidas")
    List<String> regiones;

    @Produces
    @Singleton
    CosmosClient cosmosClient() {
        return new CosmosClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .consistencyLevel(ConsistencyLevel.SESSION)
                .preferredRegions(regiones)
                .directMode()
                .contentResponseOnWriteEnabled(false)
                .buildClient();
    }

    void cerrar(@Disposes CosmosClient cliente) {
        cliente.close();
    }
}
```

```java
import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.CosmosException;
import com.azure.cosmos.models.CosmosItemRequestOptions;
import com.azure.cosmos.models.PartitionKey;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.net.URI;
import java.util.Optional;

@ApplicationScoped
class PedidoRepositorioQuarkus {

    private final CosmosContainer pedidos;

    @Inject
    PedidoRepositorioQuarkus(CosmosClient cliente, @ConfigProperty(name = "app.cosmos.base") String base) {
        this.pedidos = cliente.getDatabase(base).getContainer("pedidos");
    }

    boolean crear(Pedido p) {
        try {
            pedidos.createItem(p, new PartitionKey(p.clienteId()), new CosmosItemRequestOptions());
            return true;
        } catch (CosmosException e) {
            if (e.getStatusCode() == 409) {
                return false;
            }
            throw e;
        }
    }

    Optional<Pedido> leer(String id, String clienteId) {
        try {
            return Optional.ofNullable(pedidos.readItem(id, new PartitionKey(clienteId), Pedido.class).getItem());
        } catch (CosmosException e) {
            if (e.getStatusCode() == 404) {
                return Optional.empty();
            }
            throw e;
        }
    }

    boolean reemplazar(Pedido p) {
        try {
            pedidos.replaceItem(p, p.id(), new PartitionKey(p.clienteId()),
                    new CosmosItemRequestOptions().setIfMatchETag(p.etag()));
            return true;
        } catch (CosmosException e) {
            if (e.getStatusCode() == 412) {
                return false;
            }
            throw e;
        }
    }
}

@Path("/clientes/{clienteId}/pedidos")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class PedidoRecurso {

    @Inject
    PedidoRepositorioQuarkus repositorio;

    @POST
    Response crear(@PathParam("clienteId") String clienteId,
                   @HeaderParam("Idempotency-Key") String clave,
                   CrearPedidoQ cuerpo) {
        boolean nuevo = repositorio.crear(Pedido.nuevo(clave, clienteId, cuerpo.lineas()));
        URI ubicacion = URI.create("/clientes/" + clienteId + "/pedidos/" + clave);
        return (nuevo ? Response.created(ubicacion) : Response.ok().location(ubicacion)).build();
    }

    @GET
    @Path("/{id}")
    Response leer(@PathParam("clienteId") String clienteId, @PathParam("id") String id) {
        return repositorio.leer(id, clienteId)
                .map(p -> Response.ok(p).tag(p.etag()).build())
                .orElseGet(() -> Response.status(Response.Status.NOT_FOUND).build());
    }

    @PUT
    @Path("/{id}")
    Response reemplazar(@PathParam("clienteId") String clienteId, @PathParam("id") String id,
                        @HeaderParam("If-Match") String etag, Pedido cuerpo) {
        boolean ok = repositorio.reemplazar(cuerpo.conEtag(etag));
        return ok ? Response.noContent().build() : Response.status(Response.Status.PRECONDITION_FAILED).build();
    }
}

record CrearPedidoQ(List<Linea> lineas) { }
```
En Quarkus, los métodos que devuelven objetos planos (como arriba) se ejecutan en **hilos de trabajo**, así que el cliente síncrono es válido. Para el procesador del change feed, un `@Startup` bean con `@PostConstruct`/`@PreDestroy` hace el mismo papel que el `SmartLifecycle` de Spring.

## 10. Quarkus · reactivo (Mutiny + cliente asíncrono)

Los puntos que devuelven `Uni`/`Multi` corren en el **hilo de eventos**: ahí solo vale el cliente **asíncrono**. El SDK habla Reactor (`Mono`/`Flux`); Mutiny habla `java.util.concurrent.Flow`. El puente es `JdkFlowAdapter` de Reactor.

```java
import com.azure.cosmos.ConsistencyLevel;
import com.azure.cosmos.CosmosAsyncClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.identity.DefaultAzureCredentialBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.util.List;

@ApplicationScoped
class CosmosAsincronoProductor {

    @ConfigProperty(name = "app.cosmos.endpoint")
    String endpoint;

    @ConfigProperty(name = "app.cosmos.regiones-preferidas")
    List<String> regiones;

    @Produces
    @Singleton
    CosmosAsyncClient cosmosAsyncClient() {
        return new CosmosClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .consistencyLevel(ConsistencyLevel.SESSION)
                .preferredRegions(regiones)
                .directMode()
                .contentResponseOnWriteEnabled(false)
                .buildAsyncClient();
    }

    void cerrar(@Disposes CosmosAsyncClient cliente) {
        cliente.close();
    }
}
```

```java
import com.azure.cosmos.CosmosAsyncClient;
import com.azure.cosmos.CosmosAsyncContainer;
import com.azure.cosmos.CosmosException;
import com.azure.cosmos.models.CosmosItemRequestOptions;
import com.azure.cosmos.models.CosmosQueryRequestOptions;
import com.azure.cosmos.models.PartitionKey;
import com.azure.cosmos.models.SqlParameter;
import com.azure.cosmos.models.SqlQuerySpec;
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import reactor.adapter.JdkFlowAdapter;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@ApplicationScoped
class PedidoRepositorioMutiny {

    private final CosmosAsyncContainer pedidos;

    @Inject
    PedidoRepositorioMutiny(CosmosAsyncClient cliente, @ConfigProperty(name = "app.cosmos.base") String base) {
        this.pedidos = cliente.getDatabase(base).getContainer("pedidos");
    }

    // ---- Puentes Reactor → Mutiny -------------------------------------------------
    private static <T> Uni<T> aUni(Mono<T> mono) {
        return Uni.createFrom().publisher(JdkFlowAdapter.publisherToFlowPublisher(mono));   // Mono vacío → item nulo
    }

    private static <T> Multi<T> aMulti(Flux<T> flux) {
        return Multi.createFrom().publisher(JdkFlowAdapter.publisherToFlowPublisher(flux));
    }

    // ---- Operaciones ---------------------------------------------------------------
    Uni<Pedido> leer(String id, String clienteId) {
        return aUni(pedidos.readItem(id, new PartitionKey(clienteId), Pedido.class)
                .map(r -> r.getItem())
                .onErrorResume(CosmosException.class,
                        e -> e.getStatusCode() == 404 ? Mono.empty() : Mono.error(e)));
    }

    Uni<Boolean> crear(Pedido p) {
        return aUni(pedidos.createItem(p, new PartitionKey(p.clienteId()), new CosmosItemRequestOptions())
                .thenReturn(true)
                .onErrorResume(CosmosException.class,
                        e -> e.getStatusCode() == 409 ? Mono.just(false) : Mono.error(e)));
    }

    Multi<Pedido> pedidosDelCliente(String clienteId, Estado estado, int limite) {
        SqlQuerySpec consulta = new SqlQuerySpec(
                "SELECT * FROM c WHERE c.clienteId = @clienteId AND c.estado = @estado ORDER BY c.estado ASC, c.creadoEn DESC",
                List.of(new SqlParameter("@clienteId", clienteId), new SqlParameter("@estado", estado.name())));
        CosmosQueryRequestOptions opciones = new CosmosQueryRequestOptions()
                .setPartitionKey(new PartitionKey(clienteId));
        return aMulti(pedidos.queryItems(consulta, opciones, Pedido.class).byPage(limite).next()
                .flatMapMany(pagina -> Flux.fromIterable(pagina.getResults())));
    }
}

@Path("/reactivo/clientes/{clienteId}/pedidos")
@Produces(MediaType.APPLICATION_JSON)
class PedidoRecursoReactivo {

    @Inject
    PedidoRepositorioMutiny repositorio;

    @GET
    @Path("/{id}")
    Uni<Response> leer(@PathParam("clienteId") String clienteId, @PathParam("id") String id) {
        return repositorio.leer(id, clienteId)
                .map(p -> p == null
                        ? Response.status(Response.Status.NOT_FOUND).build()
                        : Response.ok(p).tag(p.etag()).build());
    }

    @GET
    Multi<Pedido> listar(@PathParam("clienteId") String clienteId,
                         @QueryParam("estado") Estado estado,
                         @QueryParam("limite") Integer limite) {
        return repositorio.pedidosDelCliente(clienteId, estado == null ? Estado.PAGADO : estado,
                limite == null ? 20 : Math.min(limite, 100));
    }
}
```

## 11. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| Unitarias | Repositorio detrás de una interfaz; dobles en memoria | Sin red; rápidas |
| Integración local | **Emulador de Cosmos DB** en contenedor (Testcontainers `CosmosDBEmulatorContainer`) | Usa **clave** (el emulador no admite Entra); modo **Gateway**; hay que confiar en su certificado; *verifica la imagen y el soporte del emulador vigentes* |
| Integración en la nube | Cuenta de desarrollo **serverless** con RBAC y una base por rama/ejecución | Más fiel (consistencia, red, RBAC); limpia al terminar |
| Rendimiento | Mide `getRequestCharge()` de tus 5 consultas principales | Falla la prueba si superan un presupuesto de RU |

```java
// nocheck — requiere la dependencia org.testcontainers:azure y el emulador en Docker
@Testcontainers
class PedidoRepositorioIT {

    @Container
    static CosmosDBEmulatorContainer emulador = new CosmosDBEmulatorContainer(
            DockerImageName.parse("mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest"));

    @Test
    void lecturaPuntualCuestaPoco() {
        CosmosClient cliente = new CosmosClientBuilder()
                .endpoint(emulador.getEmulatorEndpoint())
                .key(emulador.getEmulatorKey())          // solo en pruebas: en producción, Entra ID
                .gatewayMode()
                .buildClient();
        // crea base y contenedor, inserta un pedido, lee y afirma: getRequestCharge() < 3
    }
}
```
En pruebas **no apagues el RBAC de producción**: la política de la cuenta real sigue siendo "sin claves".

## 12. ¿Y Spring Data Cosmos?

`azure-spring-data-cosmos` ofrece repositorios al estilo Spring Data (`CosmosRepository`). Antes de adoptarlo:
- **Confirma la compatibilidad con Spring Boot 4 / Spring Data 4** en el mapa de versiones de Spring Cloud Azure; las matrices publicadas históricamente cubren líneas anteriores.
- Tiene menos control fino (ETag, patch condicional, lotes, change feed, medición de RU) que el SDK; para microservicios con requisitos de consistencia y costo, el SDK directo es más predecible.
- Si lo usas, sigue aplicando las mismas reglas: **clave de partición explícita**, índices afinados y consultas dirigidas a una partición.

## 13. Resumen de buenas prácticas en código

- **Un cliente** por aplicación (síncrono *o* asíncrono según el modelo), cerrado al apagar.
- **Entra ID**, jamás claves en configuración; `preferredRegions` y modo directo.
- **Lectura puntual** (`id` + clave) siempre que sea posible; consultas con la clave fijada.
- **`id` determinista** + tratar 409 como "ya hecho" = escrituras idempotentes.
- **ETag** (`If-Match`) para actualizar; **patch** para cambios parciales; reintento acotado ante 412.
- **Fechas ISO-8601 como texto** y **dinero en enteros**.
- **Lote transaccional** para atomicidad dentro de una partición (Outbox).
- **Change feed** idempotente, con cola de errores y alerta de retraso.
- **Paginación con token de continuación**; nunca `OFFSET` profundo.
- Registrar `getRequestCharge()` y `getDiagnostics()` ante lentitud; alertar por 429.
- En reactivo: sin bloqueos; en Quarkus, cliente asíncrono + `Uni`/`Multi` solo cuando el endpoint sea reactivo.
