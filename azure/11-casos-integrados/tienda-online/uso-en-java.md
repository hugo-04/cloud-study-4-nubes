# Azure · Casos integrados · Tienda online · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3, `azure-messaging-servicebus`, `azure-identity`**. Verifica las vigentes.

## El problema que ningún servicio resuelve solo: «guardar y avisar»

Al crear un pedido la API hace **dos cosas en sistemas distintos**: guarda el pedido en la base de datos y publica el evento `pedido.creado` en Service Bus. No existe una transacción que cubra ambos. Si guardas y luego publicas, un corte entre los dos pasos **pierde el evento**; si publicas y luego guardas, avisas de un pedido que quizá no existe.

| Estrategia | Qué pasa si se corta a la mitad | Veredicto |
|---|---|---|
| Guardar y luego publicar | Pedido sin evento (nadie factura) | ❌ |
| Publicar y luego guardar | Evento sin pedido (se factura algo que no existe) | ❌ |
| **Bandeja de salida (*outbox*)** | Nada se pierde: el evento está en la base de datos y se publica después | ✅ |
| Transacción distribuida (2PC) | Complejo, lento y no lo soporta Service Bus con bases de datos externas | ❌ |

**La bandeja de salida:** el evento se guarda en una tabla **en la misma transacción** que el pedido. Un proceso aparte lee la tabla y publica en Service Bus. Si se cae entre publicar y marcar, el evento se publicará **dos veces**: por eso el consumidor debe ser **idempotente** (bandeja de entrada) y Service Bus puede descartar repetidos con **detección de duplicados** (mismo `MessageId` dentro de la ventana).

```
 API ──► [ transacción: INSERT pedido + INSERT bandeja_salida ] ──► commit
                                                     │
                       Publicador (cada segundo) ◄───┘  SELECT … FOR UPDATE SKIP LOCKED
                            │  publica con MessageId = "evt-<id>"
                            ▼
                      Service Bus (duplicate detection)
                            │
                  Consumidor: INSERT mensajes_procesados (si ya existe → ignorar)
                            + su lógica, en la MISMA transacción
```

El esquema SQL está en [`ejemplos/sql/esquema.sql`](ejemplos/sql/esquema.sql).

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-servicebus</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-json</artifactId></dependency>
```

**Permisos (identidad de cada pod, sin claves):**

| Quién | Operación | Rol | Alcance |
|---|---|---|---|
| Pod de pedidos | Publicar eventos | *Azure Service Bus Data Sender* | El tópico `eventos-pedido` |
| Pod de facturación | Recibir y liquidar | *Azure Service Bus Data Receiver* | La suscripción `facturacion` |
| Pod de pedidos | Leer su cadena de conexión SQL | Ninguno si usas Entra ID en SQL; si no, *Key Vault Secrets User* | La base o el secreto |

## 1. Transacción y bandejas (JDBC puro)

Solo usa `javax.sql.DataSource`: sirve igual en Spring y en Quarkus, y se prueba con una base en memoria.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public final class Transaccion {

    @FunctionalInterface
    public interface Trabajo<T> {
        T ejecutar(Connection cx) throws SQLException;
    }

    private final DataSource origen;

    public Transaccion(DataSource origen) {
        this.origen = origen;
    }

    public <T> T ejecutar(Trabajo<T> trabajo) {
        try (Connection cx = origen.getConnection()) {
            boolean autoCommit = cx.getAutoCommit();
            cx.setAutoCommit(false);
            try {
                T resultado = trabajo.ejecutar(cx);
                cx.commit();
                return resultado;
            } catch (SQLException | RuntimeException e) {
                cx.rollback();
                throw e;
            } finally {
                cx.setAutoCommit(autoCommit);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Error de base de datos", e);
        }
    }
}

public record EventoDeSalida(long id, String tipo, String clave, String carga) { }

public final class BandejaDeSalida {

    public void guardar(Connection cx, String tipo, String clave, String carga) throws SQLException {
        try (PreparedStatement ps = cx.prepareStatement(
                "insert into bandeja_salida (tipo, clave, carga) values (?, ?, ?)")) {
            ps.setString(1, tipo);
            ps.setString(2, clave);
            ps.setString(3, carga);
            ps.executeUpdate();
        }
    }

    /** Reserva un lote sin bloquear a otras réplicas: las filas ya tomadas se saltan (SKIP LOCKED). */
    public List<EventoDeSalida> reservar(Connection cx, int maximo) throws SQLException {
        List<EventoDeSalida> lote = new ArrayList<>();
        try (PreparedStatement ps = cx.prepareStatement(
                "select id, tipo, clave, carga from bandeja_salida where publicado_en is null "
                        + "order by id limit ? for update skip locked")) {
            ps.setInt(1, maximo);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    lote.add(new EventoDeSalida(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4)));
                }
            }
        }
        return lote;
    }

    public void marcarPublicados(Connection cx, List<Long> ids) throws SQLException {
        if (ids.isEmpty()) {
            return;
        }
        try (PreparedStatement ps = cx.prepareStatement("update bandeja_salida set publicado_en = now() where id = ?")) {
            for (long id : ids) {
                ps.setLong(1, id);
                ps.addBatch();
            }
            ps.executeBatch();
        }
    }

    public long pendientes(Connection cx) throws SQLException {
        try (PreparedStatement ps = cx.prepareStatement("select count(*) from bandeja_salida where publicado_en is null");
             ResultSet rs = ps.executeQuery()) {
            rs.next();
            return rs.getLong(1);
        }
    }
}

public final class BandejaDeEntrada {

    /** true si el mensaje es nuevo; false si ya se había procesado. ON CONFLICT evita abortar la transacción en PostgreSQL. */
    public boolean registrarSiEsNuevo(Connection cx, String idMensaje) throws SQLException {
        try (PreparedStatement ps = cx.prepareStatement(
                "insert into mensajes_procesados (id_mensaje) values (?) on conflict do nothing")) {
            ps.setString(1, idMensaje);
            return ps.executeUpdate() == 1;
        }
    }
}
```

## 2. Los casos de uso: crear pedido, publicar y consumir sin repetir

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.json.JsonProviders;
import com.azure.json.JsonWriter;

import java.io.IOException;
import java.io.StringWriter;
import java.io.UncheckedIOException;
import java.math.BigDecimal;
import java.sql.PreparedStatement;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public interface Publicador {
    void publicar(EventoDeSalida evento);
}

public final class ServicioDePedidos {

    public record Item(String sku, int cantidad) { }

    private final Transaccion tx;
    private final BandejaDeSalida bandeja;

    public ServicioDePedidos(Transaccion tx, BandejaDeSalida bandeja) {
        this.tx = tx;
        this.bandeja = bandeja;
    }

    /** Guarda el pedido y su evento en UNA transacción: o quedan los dos o no queda ninguno. */
    public UUID crear(String clienteId, BigDecimal total, List<Item> items) {
        if (clienteId == null || clienteId.isBlank() || total == null || total.signum() < 0 || items == null || items.isEmpty()) {
            throw new IllegalArgumentException("Pedido inválido");
        }
        UUID id = UUID.randomUUID();
        String evento = jsonDelEvento(id, clienteId, total, items);
        tx.ejecutar(cx -> {
            try (PreparedStatement ps = cx.prepareStatement(
                    "insert into pedidos (id, cliente_id, total) values (?, ?, ?)")) {
                ps.setObject(1, id);
                ps.setString(2, clienteId);
                ps.setBigDecimal(3, total);
                ps.executeUpdate();
            }
            bandeja.guardar(cx, "pedido.creado", id.toString(), evento);
            return null;
        });
        return id;
    }

    private static String jsonDelEvento(UUID id, String clienteId, BigDecimal total, List<Item> items) {
        StringWriter salida = new StringWriter();
        try (JsonWriter json = JsonProviders.createWriter(salida)) {
            json.writeStartObject()
                    .writeStringField("tipo", "pedido.creado")
                    .writeIntField("version", 1)
                    .writeStringField("pedido_id", id.toString())
                    .writeStringField("cliente_id", clienteId)
                    .writeNumberField("total", total)
                    .writeStartArray("items");
            for (Item item : items) {
                json.writeStartObject().writeStringField("sku", item.sku()).writeIntField("cantidad", item.cantidad()).writeEndObject();
            }
            json.writeEndArray().writeEndObject().flush();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return salida.toString();
    }
}

public final class PublicadorDeBandeja {

    private final Transaccion tx;
    private final BandejaDeSalida bandeja;
    private final Publicador publicador;

    public PublicadorDeBandeja(Transaccion tx, BandejaDeSalida bandeja, Publicador publicador) {
        this.tx = tx;
        this.bandeja = bandeja;
        this.publicador = publicador;
    }

    /**
     * Publica un lote. Se detiene en el primer fallo para conservar el orden. Si el proceso muere entre publicar y
     * confirmar, el evento se publicará otra vez con el MISMO MessageId: la detección de duplicados lo descarta.
     * Mantén los lotes pequeños: la transacción está abierta mientras se publica.
     */
    public int publicarLote(int maximo) {
        return tx.ejecutar(cx -> {
            List<EventoDeSalida> lote = bandeja.reservar(cx, maximo);
            List<Long> publicados = new ArrayList<>();
            for (EventoDeSalida evento : lote) {
                try {
                    publicador.publicar(evento);
                    publicados.add(evento.id());
                } catch (RuntimeException e) {
                    break;
                }
            }
            bandeja.marcarPublicados(cx, publicados);
            return publicados.size();
        });
    }

    public long pendientes() {
        return tx.ejecutar(bandeja::pendientes);
    }
}

public final class ConsumidorIdempotente {

    private final Transaccion tx;
    private final BandejaDeEntrada entrada = new BandejaDeEntrada();

    public ConsumidorIdempotente(Transaccion tx) {
        this.tx = tx;
    }

    /** Ejecuta la lógica una sola vez por MessageId. El registro y la lógica comparten transacción. */
    public boolean procesar(String idMensaje, Transaccion.Trabajo<?> logica) {
        return tx.ejecutar(cx -> {
            if (!entrada.registrarSiEsNuevo(cx, idMensaje)) {
                return false;
            }
            logica.ejecutar(cx);
            return true;
        });
    }
}
```

## 3. El publicador hacia Service Bus
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusSenderClient;

public final class PublicadorServiceBus implements Publicador {

    private final ServiceBusSenderClient emisor;

    public PublicadorServiceBus(ServiceBusSenderClient emisor) {
        this.emisor = emisor;
    }

    @Override
    public void publicar(EventoDeSalida evento) {
        ServiceBusMessage mensaje = new ServiceBusMessage(evento.carga())
                .setMessageId("evt-" + evento.id())   // clave de la detección de duplicados
                .setSubject(evento.tipo())
                .setContentType("application/json");
        mensaje.getApplicationProperties().put("clave", evento.clave());
        emisor.sendMessage(mensaje);
    }
}
```

## 4. Spring Boot (MVC): configuración, publicador programado y controlador
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;

@Configuration
@EnableScheduling
class TiendaConfiguracion {

    @Bean
    Transaccion transaccion(DataSource origen) {
        return new Transaccion(origen);
    }

    @Bean
    ServiceBusSenderClient emisor(@Value("${servicebus.espacio}") String espacio, @Value("${servicebus.topico}") String topico) {
        // Identidad del pod (Workload Identity): sin cadenas de conexión ni claves
        return new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(espacio)
                .credential(new DefaultAzureCredentialBuilder().build())
                .sender().topicName(topico).buildClient();
    }

    @Bean
    ServicioDePedidos servicioDePedidos(Transaccion tx) {
        return new ServicioDePedidos(tx, new BandejaDeSalida());
    }

    @Bean
    PublicadorDeBandeja publicadorDeBandeja(Transaccion tx, ServiceBusSenderClient emisor) {
        return new PublicadorDeBandeja(tx, new BandejaDeSalida(), new PublicadorServiceBus(emisor));
    }
}

@Component
class TareaDePublicacion {

    private static final System.Logger LOG = System.getLogger("tienda.bandeja");

    private final PublicadorDeBandeja publicador;

    TareaDePublicacion(PublicadorDeBandeja publicador) {
        this.publicador = publicador;
    }

    @Scheduled(fixedDelayString = "${bandeja.intervalo-ms:1000}")
    void publicar() {
        try {
            int enviados = publicador.publicarLote(50);
            if (enviados > 0) {
                LOG.log(System.Logger.Level.DEBUG, "publicados {0}", enviados);
            }
            LOG.log(System.Logger.Level.INFO, "bandeja_salida.pendientes pendientes={0}", publicador.pendientes());
        } catch (RuntimeException e) {
            LOG.log(System.Logger.Level.WARNING, "No se pudo publicar el lote: {0}", e.getClass().getSimpleName());
        }
    }
}
```
```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/pedidos")
class PedidosControlador {

    record NuevoPedido(String clienteId, BigDecimal total, List<ServicioDePedidos.Item> items) { }

    private final ServicioDePedidos servicio;

    PedidosControlador(ServicioDePedidos servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    Map<String, String> crear(@RequestBody NuevoPedido pedido) {
        return Map.of("id", servicio.crear(pedido.clienteId(), pedido.total(), pedido.items()).toString());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ProblemDetail invalido(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }
}
```

## 5. Spring WebFlux (reactivo)
JDBC es **bloqueante**: se aísla con `boundedElastic`. Si el resto de tu pila es reactiva y la base de datos lo permite, R2DBC evita este paso, pero la bandeja de salida con `SKIP LOCKED` sigue siendo más simple con JDBC en un hilo propio.

```java
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/reactivo/api/pedidos")
class PedidosReactivoControlador {

    record NuevoPedido(String clienteId, BigDecimal total, List<ServicioDePedidos.Item> items) { }

    private final ServicioDePedidos servicio;

    PedidosReactivoControlador(ServicioDePedidos servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    Mono<Map<String, String>> crear(@RequestBody Mono<NuevoPedido> pedido) {
        return pedido
                .flatMap(p -> Mono.fromCallable(() -> servicio.crear(p.clienteId(), p.total(), p.items()))
                        .subscribeOn(Schedulers.boundedElastic()))
                .map(id -> Map.of("id", id.toString()))
                .onErrorMap(IllegalArgumentException.class, e -> new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()));
    }
}
```

## 6. Quarkus · imperativo
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import javax.sql.DataSource;

@ApplicationScoped
class TiendaProductores {

    @ConfigProperty(name = "servicebus.espacio")
    String espacio;

    @ConfigProperty(name = "servicebus.topico")
    String topico;

    @Produces
    @Singleton
    Transaccion transaccion(DataSource origen) {
        return new Transaccion(origen);
    }

    @Produces
    @Singleton
    ServiceBusSenderClient emisor() {
        return new ServiceBusClientBuilder()
                .fullyQualifiedNamespace(espacio)
                .credential(new DefaultAzureCredentialBuilder().build())
                .sender().topicName(topico).buildClient();
    }

    @Produces
    @Singleton
    ServicioDePedidos servicioDePedidos(Transaccion tx) {
        return new ServicioDePedidos(tx, new BandejaDeSalida());
    }

    @Produces
    @Singleton
    PublicadorDeBandeja publicadorDeBandeja(Transaccion tx, ServiceBusSenderClient emisor) {
        return new PublicadorDeBandeja(tx, new BandejaDeSalida(), new PublicadorServiceBus(emisor));
    }
}
```
```java
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@ApplicationScoped
class TareaDePublicacionQuarkus {

    private static final System.Logger LOG = System.getLogger("tienda.bandeja");

    @Inject
    PublicadorDeBandeja publicador;

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void publicar() {
        try {
            publicador.publicarLote(50);
            LOG.log(System.Logger.Level.INFO, "bandeja_salida.pendientes pendientes={0}", publicador.pendientes());
        } catch (RuntimeException e) {
            LOG.log(System.Logger.Level.WARNING, "No se pudo publicar el lote: {0}", e.getClass().getSimpleName());
        }
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@Path("/api/pedidos")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class PedidosRecurso {

    public record NuevoPedido(String clienteId, BigDecimal total, List<ServicioDePedidos.Item> items) { }

    @Inject
    ServicioDePedidos servicio;

    @POST
    public Response crear(NuevoPedido pedido) {
        try {
            String id = servicio.crear(pedido.clienteId(), pedido.total(), pedido.items()).toString();
            return Response.status(Response.Status.CREATED).entity(Map.of("id", id)).build();
        } catch (IllegalArgumentException e) {
            throw new BadRequestException(e.getMessage());
        }
    }
}
```

## 7. Quarkus · reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@Path("/reactivo/api/pedidos")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class PedidosRecursoReactivo {

    public record NuevoPedido(String clienteId, BigDecimal total, List<ServicioDePedidos.Item> items) { }

    @Inject
    ServicioDePedidos servicio;

    @POST
    public Uni<Response> crear(NuevoPedido pedido) {
        return Uni.createFrom().item(() -> servicio.crear(pedido.clienteId(), pedido.total(), pedido.items()))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool()) // JDBC bloquea: fuera del hilo de eventos
                .map(id -> Response.status(Response.Status.CREATED).entity(Map.of("id", id.toString())).build())
                .onFailure(IllegalArgumentException.class).transform(e -> new BadRequestException(e.getMessage()));
    }
}
```

## 8. El consumidor de facturación (idempotente)
Es el mismo en Spring y Quarkus: la lógica de facturación y el registro del `MessageId` van en **una** transacción.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.messaging.servicebus.ServiceBusReceivedMessage;

import java.sql.PreparedStatement;

public final class ManejadorDeFacturacion {

    private final ConsumidorIdempotente consumidor;

    public ManejadorDeFacturacion(ConsumidorIdempotente consumidor) {
        this.consumidor = consumidor;
    }

    /** true = se procesó; false = era un duplicado. Si lanza, el mensaje vuelve a la cola (y a la DLQ tras agotar reintentos). */
    public boolean manejar(ServiceBusReceivedMessage mensaje) {
        String pedido = String.valueOf(mensaje.getApplicationProperties().get("clave"));
        return consumidor.procesar(mensaje.getMessageId(), cx -> {
            try (PreparedStatement ps = cx.prepareStatement(
                    "update pedidos set estado = 'FACTURADO' where id = ?::uuid and estado = 'CREADO'")) {
                ps.setString(1, pedido);
                return ps.executeUpdate();
            }
        });
    }
}
```
Con el procesador de Service Bus (`ServiceBusProcessorClient`), llamas a `manejar` en el callback de mensaje; **solo cuando devuelve (verdadero o falso) se completa el mensaje**; si lanza una excepción, se abandona y se reintenta (ver el capítulo de [Service Bus](../../07-mensajeria/service-bus/uso-en-java.md)).

## 9. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Atomicidad pedido + evento** | Base en memoria; forzar un fallo después de insertar el pedido y comprobar que no quedó evento | La garantía central del patrón |
| **Publicador** | `Publicador` falso que falla en el 3.º evento: se publican 2, se marcan 2, el resto sigue pendiente | Orden conservado |
| **Dos réplicas** | Dos hilos publicando a la vez: ningún evento se publica dos veces en el mismo lote (`SKIP LOCKED`) | Necesita PostgreSQL real (Testcontainers) |
| **Idempotencia** | El mismo `MessageId` dos veces: la lógica corre una sola vez; si la lógica falla, el registro se deshace | Misma transacción |
| **Integración** | Service Bus de laboratorio con detección de duplicados | Comprueba el `MessageId` |

```java
// nocheck — requiere JUnit 5 y una base H2 en modo PostgreSQL
class BandejaTest {

    @Test
    void sinPedidoNoHayEvento() {
        var servicio = new ServicioDePedidos(tx, new BandejaDeSalida());

        assertThrows(IllegalArgumentException.class, () -> servicio.crear("cli-1", new BigDecimal("-1"), List.of()));

        assertEquals(0, contar("bandeja_salida"));
    }

    @Test
    void elMismoMensajeSeProcesaUnaVez() {
        var consumidor = new ConsumidorIdempotente(tx);
        var llamadas = new AtomicInteger();

        consumidor.procesar("evt-1", cx -> llamadas.incrementAndGet());
        consumidor.procesar("evt-1", cx -> llamadas.incrementAndGet());

        assertEquals(1, llamadas.get());
    }
}
```

## 10. Buenas prácticas de código
- **El evento nace con el dato:** misma transacción, o no hay garantía.
- **`MessageId` determinista** (`evt-<id>`): la detección de duplicados de Service Bus y tu bandeja de entrada trabajan juntas.
- **Consumidores idempotentes siempre:** «al menos una vez» es la regla de la mensajería.
- **Lotes pequeños y tiempos límite** al publicar: la transacción de la bandeja está abierta durante el envío.
- **Orden:** `SKIP LOCKED` con varias réplicas no garantiza el orden global; si necesitas orden por pedido, usa sesiones de Service Bus con `clave` como `SessionId` o una sola réplica del publicador.
- **Limpieza programada** de la bandeja y de los mensajes procesados.
- **Métrica y alerta** sobre `bandeja_salida.pendientes`: si crece, el publicador está atascado.
- **Sin secretos:** identidad del pod para Service Bus y Entra ID (o Key Vault) para SQL.
- En reactivo, **JDBC va fuera del hilo de eventos**; no mezcles `block()` en el hilo reactivo.
