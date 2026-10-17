# AWS · Caso integrado · Tienda online · Uso desde Java

Aquí se construye lo que **no** viene hecho en ningún SDK: la lógica que une los servicios. Un **núcleo común** (reglas puras, sin red), **puertos** (interfaces) y adaptadores finos: JDBC para Aurora, el SDK para EventBridge, SQS y DynamoDB. Los mismos bloques sirven a Spring MVC, WebFlux, Quarkus imperativo y Quarkus Mutiny.

| Pieza | Qué resuelve |
|---|---|
| `ServicioPedidos` + `RepositorioPedidosJdbc` | Pedido y evento en **una** transacción; idempotencia por `Idempotency-Key` |
| `LoteadorEventos` + `CicloPublicacion` + `PublicadorEventBridge` | Publicar por lotes (10 entradas / 256 KB) y reintentar solo las fallidas |
| `BandejaSalidaJdbc` | `FOR UPDATE SKIP LOCKED` para varias réplicas |
| `BandejaEntradaDynamo` + `ProcesadorIdempotente` | Consumidor que no procesa dos veces ni pierde mensajes |
| `LectorDeEvento` + `ManejadorDeMensajes` + `ConsumidorSqs` | Leer el sobre de EventBridge, decidir borrar o dejar |

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST}:5432/tienda
    username: ${DB_USER}
    password: ${DB_PASSWORD}          # viene de Secrets Manager, nunca del repositorio
  task:
    scheduling:
      pool:
        size: 4                        # publicador y consumidor no deben bloquearse entre sí
app:
  eventos:
    bus: prod-ordenes
    intervalo-ms: 1000
  cola-facturacion: ${COLA_FACTURACION}
  bandeja-entrada: prod-bandeja-entrada
```
```properties
# Quarkus (application.properties)
quarkus.datasource.db-kind=postgresql
quarkus.datasource.jdbc.url=jdbc:postgresql://${DB_HOST}:5432/tienda
quarkus.datasource.username=${DB_USER}
quarkus.datasource.password=${DB_PASSWORD}
quarkus.eventbridge.sync-client.type=url-connection
quarkus.sqs.sync-client.type=url-connection
quarkus.dynamodb.sync-client.type=url-connection
app.eventos.bus=prod-ordenes
app.cola-facturacion=${COLA_FACTURACION}
app.bandeja-entrada=prod-bandeja-entrada
```

## 2. Núcleo común

### 2.1 Modelo y puertos
Records inmutables e interfaces. El resto del código depende de estos puertos, no de JDBC ni del SDK.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Map;
import java.util.function.Function;

record LineaPedido(String sku, int cantidad) {}

record Pedido(String id, String clienteId, long totalCentimos, String moneda, String envio, List<LineaPedido> lineas) {}

record EventoSalida(String id, String tipo, String detalleJson) {}

record ResultadoCreacion(boolean creado, String idPedido) {}

record ResultadoPublicacion(List<String> publicados, Map<String, String> fallidos) {}

enum Reserva { NUEVA, YA_HECHA, EN_CURSO }

enum Resultado { PROCESADO, DUPLICADO, OCUPADO }

/** Guarda pedido + evento en UNA transacción. Si la clave ya existe, devuelve el pedido original. */
interface RepositorioPedidos {
    ResultadoCreacion guardar(String claveIdempotencia, Pedido pedido, EventoSalida evento);
}

interface PuertoPublicacion {
    ResultadoPublicacion publicar(List<EventoSalida> lote);
}

/** Toma pendientes con bloqueo, llama a la función y confirma el resultado. Devuelve cuántos se publicaron. */
interface BandejaSalida {
    int procesarLote(int max, Function<List<EventoSalida>, ResultadoPublicacion> publicar);
}

interface BandejaEntrada {
    Reserva reservar(String idMensaje);

    void completar(String idMensaje);
}
```

### 2.2 Crear el pedido y su evento
El evento se arma sin Jackson (un escritor mínimo) para que el contrato sea explícito y estable. El dinero viaja en céntimos enteros.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;

final class ConstructorEventos {
    static final String FUENTE = "modalima.pedidos";
    static final String TIPO = "PedidoCreado";

    private ConstructorEventos() {
    }

    static EventoSalida pedidoCreado(String idEvento, Pedido p) {
        var sb = new StringBuilder(200);
        sb.append("{\"version\":1,\"idEvento\":").append(texto(idEvento))
                .append(",\"idPedido\":").append(texto(p.id()))
                .append(",\"idCliente\":").append(texto(p.clienteId()))
                .append(",\"total\":").append(decimal(p.totalCentimos()))
                .append(",\"moneda\":").append(texto(p.moneda()))
                .append(",\"envio\":").append(texto(p.envio()))
                .append(",\"lineas\":[");
        for (int i = 0; i < p.lineas().size(); i++) {
            var l = p.lineas().get(i);
            if (i > 0) {
                sb.append(',');
            }
            sb.append("{\"sku\":").append(texto(l.sku())).append(",\"cantidad\":").append(l.cantidad()).append('}');
        }
        return new EventoSalida(idEvento, TIPO, sb.append("]}").toString());
    }

    static String decimal(long centimos) {
        return (centimos / 100) + "." + String.format("%02d", centimos % 100);
    }

    static String texto(String s) {
        var sb = new StringBuilder(s.length() + 2).append('"');
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        return sb.append('"').toString();
    }
}

final class ServicioPedidos {
    private static final Set<String> ENVIOS = Set.of("domicilio", "tienda");

    private final RepositorioPedidos repositorio;
    private final Supplier<String> ids;

    ServicioPedidos(RepositorioPedidos repositorio, Supplier<String> ids) {
        this.repositorio = repositorio;
        this.ids = ids;
    }

    ServicioPedidos(RepositorioPedidos repositorio) {
        this(repositorio, () -> UUID.randomUUID().toString());
    }

    ResultadoCreacion crear(String clave, String clienteId, String envio, long totalCentimos, List<LineaPedido> lineas) {
        if (clave == null || clave.isBlank() || clave.length() > 100) {
            throw new IllegalArgumentException("Idempotency-Key obligatoria (hasta 100 caracteres)");
        }
        if (clienteId == null || clienteId.isBlank()) {
            throw new IllegalArgumentException("cliente obligatorio");
        }
        if (!ENVIOS.contains(envio)) {
            throw new IllegalArgumentException("envío no válido: " + envio);
        }
        if (totalCentimos <= 0) {
            throw new IllegalArgumentException("total debe ser positivo");
        }
        if (lineas == null || lineas.isEmpty() || lineas.stream().anyMatch(l -> l.cantidad() <= 0)) {
            throw new IllegalArgumentException("líneas inválidas");
        }
        var pedido = new Pedido(ids.get(), clienteId, totalCentimos, "PEN", envio, List.copyOf(lineas));
        var evento = ConstructorEventos.pedidoCreado(ids.get(), pedido);
        return repositorio.guardar(clave, pedido, evento);
    }
}
```

### 2.3 Publicar por lotes
`PutEvents` admite hasta 10 entradas y 256 KB por llamada. `LoteadorEventos` parte la lista respetando **ambos** límites y aparta lo que nunca cabría; `CicloPublicacion` publica lote a lote y **no** pierde las entradas que fallen.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;

record Lotes(List<List<EventoSalida>> lotes, List<EventoSalida> excedidos) {}

final class LoteadorEventos {
    static final int MAX_ENTRADAS = 10;
    static final int MAX_BYTES = 256 * 1024;
    private static final int TIEMPO = 14;

    private LoteadorEventos() {
    }

    static int tamano(EventoSalida e) {
        return TIEMPO + bytes(ConstructorEventos.FUENTE) + bytes(e.tipo()) + bytes(e.detalleJson());
    }

    static Lotes partir(List<EventoSalida> eventos) {
        var lotes = new ArrayList<List<EventoSalida>>();
        var excedidos = new ArrayList<EventoSalida>();
        var actual = new ArrayList<EventoSalida>();
        int bytesActual = 0;
        for (var e : eventos) {
            int t = tamano(e);
            if (t > MAX_BYTES) {
                excedidos.add(e);
                continue;
            }
            if (actual.size() == MAX_ENTRADAS || bytesActual + t > MAX_BYTES) {
                lotes.add(actual);
                actual = new ArrayList<>();
                bytesActual = 0;
            }
            actual.add(e);
            bytesActual += t;
        }
        if (!actual.isEmpty()) {
            lotes.add(actual);
        }
        return new Lotes(lotes, excedidos);
    }

    private static int bytes(String s) {
        return s.getBytes(StandardCharsets.UTF_8).length;
    }
}

final class CicloPublicacion {
    private final BandejaSalida bandeja;
    private final PuertoPublicacion puerto;
    private final int maxPorCiclo;

    CicloPublicacion(BandejaSalida bandeja, PuertoPublicacion puerto, int maxPorCiclo) {
        this.bandeja = bandeja;
        this.puerto = puerto;
        this.maxPorCiclo = maxPorCiclo;
    }

    int ejecutar() {
        return bandeja.procesarLote(maxPorCiclo, this::publicarTodo);
    }

    ResultadoPublicacion publicarTodo(List<EventoSalida> eventos) {
        var partido = LoteadorEventos.partir(eventos);
        var ok = new ArrayList<String>();
        var mal = new LinkedHashMap<String, String>();
        partido.excedidos().forEach(e -> mal.put(e.id(), "EXCEDE_256KB"));
        for (var lote : partido.lotes()) {
            try {
                var r = puerto.publicar(lote);
                ok.addAll(r.publicados());
                mal.putAll(r.fallidos());
            } catch (RuntimeException ex) {
                lote.forEach(e -> mal.put(e.id(), ex.getClass().getSimpleName()));
            }
        }
        return new ResultadoPublicacion(ok, mal);
    }
}
```

### 2.4 El adaptador de EventBridge
El `200` de `PutEvents` no significa «todo entregado»: la respuesta trae **una entrada por evento**, en el mismo orden. Un `eventId` presente es éxito; si no, hay `errorCode`.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import software.amazon.awssdk.services.eventbridge.EventBridgeClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;
import software.amazon.awssdk.services.eventbridge.model.PutEventsResultEntry;

final class PublicadorEventBridge implements PuertoPublicacion {
    private final EventBridgeClient eventBridge;
    private final String bus;

    PublicadorEventBridge(EventBridgeClient eventBridge, String bus) {
        this.eventBridge = eventBridge;
        this.bus = bus;
    }

    @Override
    public ResultadoPublicacion publicar(List<EventoSalida> lote) {
        return interpretar(lote, eventBridge.putEvents(solicitud(bus, lote)).entries());
    }

    static PutEventsRequest solicitud(String bus, List<EventoSalida> lote) {
        var entradas = lote.stream()
                .map(e -> PutEventsRequestEntry.builder()
                        .eventBusName(bus)
                        .source(ConstructorEventos.FUENTE)
                        .detailType(e.tipo())
                        .detail(e.detalleJson())
                        .build())
                .toList();
        return PutEventsRequest.builder().entries(entradas).build();
    }

    static ResultadoPublicacion interpretar(List<EventoSalida> lote, List<PutEventsResultEntry> entradas) {
        if (entradas.size() != lote.size()) {
            throw new IllegalStateException("respuesta de PutEvents incompleta");
        }
        var ok = new ArrayList<String>();
        var mal = new LinkedHashMap<String, String>();
        for (int i = 0; i < lote.size(); i++) {
            var r = entradas.get(i);
            if (r.eventId() != null && r.errorCode() == null) {
                ok.add(lote.get(i).id());
            } else {
                mal.put(lote.get(i).id(), r.errorCode() + ": " + r.errorMessage());
            }
        }
        return new ResultadoPublicacion(ok, mal);
    }
}
```

### 2.5 La bandeja de entrada (idempotencia sin perder mensajes)
Registrar «ya lo procesé» **antes** del efecto pierde mensajes si el proceso muere en medio; registrarlo **después** deja pasar duplicados concurrentes. La solución es un *arrendamiento*: se reserva como `EN_CURSO` con vencimiento, se ejecuta el efecto y se marca `HECHO`. Un duplicado que llega con el original `EN_CURSO` **no se borra** (vuelve a aparecer); uno con `HECHO` sí.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.ReturnValuesOnConditionCheckFailure;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

final class BandejaEntradaDynamo implements BandejaEntrada {
    private final DynamoDbClient dynamo;
    private final String tabla;
    private final Duration lease;
    private final Duration retencion;
    private final Clock reloj;

    BandejaEntradaDynamo(DynamoDbClient dynamo, String tabla, Duration lease, Duration retencion, Clock reloj) {
        this.dynamo = dynamo;
        this.tabla = tabla;
        this.lease = lease;
        this.retencion = retencion;
        this.reloj = reloj;
    }

    @Override
    public Reserva reservar(String idMensaje) {
        long ahora = reloj.instant().getEpochSecond();
        try {
            dynamo.putItem(PutItemRequest.builder()
                    .tableName(tabla)
                    .item(Map.of(
                            "idMensaje", s(idMensaje),
                            "estado", s("EN_CURSO"),
                            "lease", n(ahora + lease.toSeconds()),
                            "expira", n(ahora + retencion.toSeconds())))
                    .conditionExpression("attribute_not_exists(idMensaje) OR (estado = :curso AND lease < :ahora)")
                    .expressionAttributeValues(Map.of(":curso", s("EN_CURSO"), ":ahora", n(ahora)))
                    .returnValuesOnConditionCheckFailure(ReturnValuesOnConditionCheckFailure.ALL_OLD)
                    .build());
            return Reserva.NUEVA;
        } catch (ConditionalCheckFailedException e) {
            var previo = e.hasItem() ? e.item().get("estado") : null;
            return previo != null && "HECHO".equals(previo.s()) ? Reserva.YA_HECHA : Reserva.EN_CURSO;
        }
    }

    @Override
    public void completar(String idMensaje) {
        dynamo.updateItem(UpdateItemRequest.builder()
                .tableName(tabla)
                .key(Map.of("idMensaje", s(idMensaje)))
                .updateExpression("SET estado = :hecho")
                .expressionAttributeValues(Map.of(":hecho", s("HECHO")))
                .build());
    }

    private static AttributeValue s(String v) {
        return AttributeValue.builder().s(v).build();
    }

    private static AttributeValue n(long v) {
        return AttributeValue.builder().n(Long.toString(v)).build();
    }
}

final class ProcesadorIdempotente {
    private final BandejaEntrada bandeja;

    ProcesadorIdempotente(BandejaEntrada bandeja) {
        this.bandeja = bandeja;
    }

    Resultado procesar(String idMensaje, Runnable efecto) {
        return switch (bandeja.reservar(idMensaje)) {
            case YA_HECHA -> Resultado.DUPLICADO;
            case EN_CURSO -> Resultado.OCUPADO;
            case NUEVA -> {
                efecto.run();
                bandeja.completar(idMensaje);
                yield Resultado.PROCESADO;
            }
        };
    }
}
```

### 2.6 Leer el mensaje y consumir la cola
Lo que llega a SQS desde una regla de EventBridge es el **evento completo** (con `source`, `detail-type` y `detail`). Se valida la fuente y la versión antes de confiar en nada. Lo ilegible **no se borra**: tras `maxReceiveCount` intentos pasa a la DLQ, donde una persona lo revisa.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.DeleteMessageBatchRequest;
import software.amazon.awssdk.services.sqs.model.DeleteMessageBatchRequestEntry;
import software.amazon.awssdk.services.sqs.model.Message;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;

record PedidoCreadoEvt(String idEvento, String idPedido, String idCliente, long totalCentimos, String envio) {}

enum Decision { BORRAR, DEJAR }

interface Facturador {
    void facturar(PedidoCreadoEvt evento);
}

final class LectorDeEvento {
    private LectorDeEvento() {
    }

    static PedidoCreadoEvt leer(String cuerpo) {
        try {
            JsonNode raiz = JsonNodeParser.create().parse(cuerpo);
            if (!raiz.isObject()) {
                throw new IllegalArgumentException("el mensaje no es un objeto");
            }
            var o = raiz.asObject();
            exigir(texto(o, "source"), ConstructorEventos.FUENTE, "source");
            exigir(texto(o, "detail-type"), ConstructorEventos.TIPO, "detail-type");
            JsonNode nodo = o.get("detail");
            if (nodo == null || !nodo.isObject()) {
                throw new IllegalArgumentException("falta detail");
            }
            var d = nodo.asObject();
            if (Integer.parseInt(numero(d, "version")) != 1) {
                throw new IllegalArgumentException("versión de contrato no soportada");
            }
            long centimos = new BigDecimal(numero(d, "total")).movePointRight(2).longValueExact();
            return new PedidoCreadoEvt(texto(d, "idEvento"), texto(d, "idPedido"), texto(d, "idCliente"), centimos, texto(d, "envio"));
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("mensaje ilegible: " + e.getClass().getSimpleName(), e);
        }
    }

    private static void exigir(String real, String esperado, String campo) {
        if (!esperado.equals(real)) {
            throw new IllegalArgumentException(campo + " inesperado: " + real);
        }
    }

    private static String texto(Map<String, JsonNode> o, String clave) {
        JsonNode n = o.get(clave);
        if (n == null || !n.isString()) {
            throw new IllegalArgumentException("falta texto " + clave);
        }
        return n.asString();
    }

    private static String numero(Map<String, JsonNode> o, String clave) {
        JsonNode n = o.get(clave);
        if (n == null || !n.isNumber()) {
            throw new IllegalArgumentException("falta número " + clave);
        }
        return n.asNumber();
    }
}

final class ManejadorDeMensajes {
    private final ProcesadorIdempotente procesador;
    private final Facturador facturador;

    ManejadorDeMensajes(ProcesadorIdempotente procesador, Facturador facturador) {
        this.procesador = procesador;
        this.facturador = facturador;
    }

    Decision manejar(String cuerpo) {
        PedidoCreadoEvt evento;
        try {
            evento = LectorDeEvento.leer(cuerpo);
        } catch (IllegalArgumentException e) {
            return Decision.DEJAR;
        }
        try {
            return switch (procesador.procesar(evento.idEvento(), () -> facturador.facturar(evento))) {
                case PROCESADO, DUPLICADO -> Decision.BORRAR;
                case OCUPADO -> Decision.DEJAR;
            };
        } catch (RuntimeException e) {
            return Decision.DEJAR;
        }
    }
}

final class ConsumidorSqs {
    private final SqsClient sqs;
    private final String urlCola;
    private final ManejadorDeMensajes manejador;
    private final int esperaSegundos;

    ConsumidorSqs(SqsClient sqs, String urlCola, ManejadorDeMensajes manejador, int esperaSegundos) {
        this.sqs = sqs;
        this.urlCola = urlCola;
        this.manejador = manejador;
        this.esperaSegundos = esperaSegundos;
    }

    /** Una vuelta de sondeo largo. Devuelve cuántos mensajes se borraron. */
    int sondear() {
        var respuesta = sqs.receiveMessage(ReceiveMessageRequest.builder()
                .queueUrl(urlCola)
                .maxNumberOfMessages(10)
                .waitTimeSeconds(esperaSegundos)
                .build());
        var aBorrar = new ArrayList<DeleteMessageBatchRequestEntry>();
        int i = 0;
        for (Message m : respuesta.messages()) {
            if (manejador.manejar(m.body()) == Decision.BORRAR) {
                aBorrar.add(DeleteMessageBatchRequestEntry.builder().id("m" + i).receiptHandle(m.receiptHandle()).build());
            }
            i++;
        }
        if (!aBorrar.isEmpty()) {
            // Si algún borrado falla, el mensaje vuelve: la bandeja de entrada lo descartará como duplicado.
            sqs.deleteMessageBatch(DeleteMessageBatchRequest.builder().queueUrl(urlCola).entries(aBorrar).build());
        }
        return aBorrar.size();
    }
}
```

### 2.7 Adaptadores JDBC (Aurora)
JDBC puro y transacciones explícitas: funciona igual en Spring y en Quarkus. `ON CONFLICT DO NOTHING` + índice único convierte el reintento del cliente en una lectura del pedido original. `FOR UPDATE SKIP LOCKED` permite varias réplicas del publicador sin pisarse.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.UUID;
import javax.sql.DataSource;

final class RepositorioPedidosJdbc implements RepositorioPedidos {
    private final DataSource ds;

    RepositorioPedidosJdbc(DataSource ds) {
        this.ds = ds;
    }

    @Override
    public ResultadoCreacion guardar(String clave, Pedido p, EventoSalida e) {
        try (Connection c = ds.getConnection()) {
            c.setAutoCommit(false);
            try {
                try (PreparedStatement ps = c.prepareStatement(
                        "INSERT INTO pedidos (id, cliente_id, total, envio, clave_idempotencia) VALUES (?::uuid, ?, ?, ?, ?) "
                                + "ON CONFLICT (cliente_id, clave_idempotencia) DO NOTHING")) {
                    ps.setString(1, p.id());
                    ps.setString(2, p.clienteId());
                    ps.setBigDecimal(3, new BigDecimal(ConstructorEventos.decimal(p.totalCentimos())));
                    ps.setString(4, p.envio());
                    ps.setString(5, clave);
                    if (ps.executeUpdate() == 0) {
                        c.rollback();
                        return new ResultadoCreacion(false, existente(c, p.clienteId(), clave));
                    }
                }
                try (PreparedStatement ps = c.prepareStatement(
                        "INSERT INTO bandeja_salida (id, tipo, agregado_id, carga) VALUES (?::uuid, ?, ?::uuid, ?::jsonb)")) {
                    ps.setString(1, e.id());
                    ps.setString(2, e.tipo());
                    ps.setString(3, p.id());
                    ps.setString(4, e.detalleJson());
                    ps.executeUpdate();
                }
                c.commit();
                return new ResultadoCreacion(true, p.id());
            } catch (SQLException | RuntimeException ex) {
                c.rollback();
                throw ex;
            }
        } catch (SQLException ex) {
            throw new IllegalStateException("no se pudo guardar el pedido", ex);
        }
    }

    private static String existente(Connection c, String clienteId, String clave) throws SQLException {
        try (PreparedStatement ps = c.prepareStatement(
                "SELECT id::text FROM pedidos WHERE cliente_id = ? AND clave_idempotencia = ?")) {
            ps.setString(1, clienteId);
            ps.setString(2, clave);
            try (var rs = ps.executeQuery()) {
                if (!rs.next()) {
                    throw new IllegalStateException("conflicto sin pedido original");
                }
                return rs.getString(1);
            }
        }
    }
}

final class BandejaSalidaJdbc implements BandejaSalida {
    private final DataSource ds;

    BandejaSalidaJdbc(DataSource ds) {
        this.ds = ds;
    }

    @Override
    public int procesarLote(int max, Function<List<EventoSalida>, ResultadoPublicacion> publicar) {
        try (Connection c = ds.getConnection()) {
            c.setAutoCommit(false);
            try {
                var pendientes = new ArrayList<EventoSalida>();
                try (PreparedStatement ps = c.prepareStatement(
                        "SELECT id::text, tipo, carga::text FROM bandeja_salida WHERE publicado IS NULL "
                                + "ORDER BY creado LIMIT ? FOR UPDATE SKIP LOCKED")) {
                    ps.setInt(1, max);
                    try (var rs = ps.executeQuery()) {
                        while (rs.next()) {
                            pendientes.add(new EventoSalida(rs.getString(1), rs.getString(2), rs.getString(3)));
                        }
                    }
                }
                if (pendientes.isEmpty()) {
                    c.commit();
                    return 0;
                }
                var resultado = publicar.apply(pendientes);
                marcar(c, "UPDATE bandeja_salida SET publicado = now() WHERE id = ANY (?::uuid[])", resultado.publicados());
                marcar(c, "UPDATE bandeja_salida SET intentos = intentos + 1 WHERE id = ANY (?::uuid[])",
                        List.copyOf(resultado.fallidos().keySet()));
                c.commit();
                return resultado.publicados().size();
            } catch (SQLException | RuntimeException ex) {
                c.rollback();
                throw ex;
            }
        } catch (SQLException ex) {
            throw new IllegalStateException("fallo en la bandeja de salida", ex);
        }
    }

    private static void marcar(Connection c, String sql, List<String> ids) throws SQLException {
        if (ids.isEmpty()) {
            return;
        }
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setArray(1, c.createArrayOf("text", ids.toArray()));
            ps.executeUpdate();
        }
    }
}
```

## 3. Spring MVC (imperativo)
Los clientes del SDK se crean una vez y se cierran con el contexto. El publicador y el consumidor son tareas programadas (con el *pool* de la sección 1).
```java
import java.time.Clock;
import java.time.Duration;
import javax.sql.DataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
@EnableScheduling
class TiendaConfig {
    @Bean(destroyMethod = "close")
    EventBridgeClient eventBridge() {
        return EventBridgeClient.create();
    }

    @Bean(destroyMethod = "close")
    SqsClient sqs() {
        return SqsClient.create();
    }

    @Bean(destroyMethod = "close")
    DynamoDbClient dynamo() {
        return DynamoDbClient.create();
    }

    @Bean
    ServicioPedidos servicioPedidos(DataSource ds) {
        return new ServicioPedidos(new RepositorioPedidosJdbc(ds));
    }

    @Bean
    CicloPublicacion ciclo(DataSource ds, EventBridgeClient eb, @Value("${app.eventos.bus}") String bus) {
        return new CicloPublicacion(new BandejaSalidaJdbc(ds), new PublicadorEventBridge(eb, bus), 50);
    }

    @Bean
    Facturador facturador() {
        return evento -> {
            // Aquí va la lógica real: crear la factura, guardar el PDF en S3 (Claim Check), etc.
        };
    }

    @Bean
    ConsumidorSqs consumidor(SqsClient sqs, DynamoDbClient dynamo, Facturador facturador,
                             @Value("${app.cola-facturacion}") String cola, @Value("${app.bandeja-entrada}") String tabla) {
        var bandeja = new BandejaEntradaDynamo(dynamo, tabla, Duration.ofSeconds(120), Duration.ofDays(14), Clock.systemUTC());
        return new ConsumidorSqs(sqs, cola, new ManejadorDeMensajes(new ProcesadorIdempotente(bandeja), facturador), 20);
    }
}

record SolicitudPedido(String clienteId, String envio, long totalCentimos, List<LineaPedido> lineas) {}

@RestController
@RequestMapping("/pedidos")
class PedidosController {
    private final ServicioPedidos servicio;

    PedidosController(ServicioPedidos servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    ResponseEntity<Map<String, String>> crear(@RequestHeader("Idempotency-Key") String clave, @RequestBody SolicitudPedido s) {
        var r = servicio.crear(clave, s.clienteId(), s.envio(), s.totalCentimos(), s.lineas());
        var cuerpo = Map.of("idPedido", r.idPedido());
        return r.creado() ? ResponseEntity.status(201).body(cuerpo) : ResponseEntity.ok(cuerpo);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> invalido(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
}

@Component
class TareasDeEventos {
    private final CicloPublicacion ciclo;
    private final ConsumidorSqs consumidor;

    TareasDeEventos(CicloPublicacion ciclo, ConsumidorSqs consumidor) {
        this.ciclo = ciclo;
        this.consumidor = consumidor;
    }

    @Scheduled(fixedDelayString = "${app.eventos.intervalo-ms}")
    void publicar() {
        ciclo.ejecutar();
    }

    @Scheduled(fixedDelay = 100)
    void consumir() {
        consumidor.sondear();
    }
}
```

## 4. Spring WebFlux (reactivo)
JDBC **bloquea**: nunca en el hilo del bucle de eventos. Cada llamada va a `boundedElastic`. Si más adelante usas R2DBC, solo cambias el adaptador del puerto. El publicador es un `Flux.interval` con `concatMap(…, 1)` (nunca dos ciclos a la vez) y sin que un error mate el bucle.
```java
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.Disposable;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/v2/pedidos")
class PedidosReactivoController {
    private final ServicioPedidos servicio;

    PedidosReactivoController(ServicioPedidos servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    Mono<ResponseEntity<Map<String, String>>> crear(@RequestHeader("Idempotency-Key") String clave, @RequestBody SolicitudPedidoV2 s) {
        return Mono.fromCallable(() -> servicio.crear(clave, s.clienteId(), s.envio(), s.totalCentimos(), s.lineas()))
                .subscribeOn(Schedulers.boundedElastic())
                .map(r -> r.creado()
                        ? ResponseEntity.status(201).body(Map.of("idPedido", r.idPedido()))
                        : ResponseEntity.ok(Map.of("idPedido", r.idPedido())))
                .onErrorResume(IllegalArgumentException.class,
                        e -> Mono.just(ResponseEntity.badRequest().body(Map.of("error", String.valueOf(e.getMessage())))));
    }
}

record SolicitudPedidoV2(String clienteId, String envio, long totalCentimos, List<LineaPedido> lineas) {}

@Component
class BucleReactivoDeEventos {
    private final CicloPublicacion ciclo;
    private final ConsumidorSqs consumidor;
    private Disposable publicador;
    private Disposable lector;

    BucleReactivoDeEventos(CicloPublicacion ciclo, ConsumidorSqs consumidor) {
        this.ciclo = ciclo;
        this.consumidor = consumidor;
    }

    @PostConstruct
    void iniciar() {
        publicador = Flux.interval(Duration.ofSeconds(1))
                .onBackpressureDrop()
                .concatMap(t -> Mono.fromCallable(ciclo::ejecutar)
                        .subscribeOn(Schedulers.boundedElastic())
                        .onErrorResume(e -> Mono.empty()), 1)
                .subscribe();
        lector = Mono.fromCallable(consumidor::sondear)
                .subscribeOn(Schedulers.boundedElastic())
                .onErrorResume(e -> Mono.delay(Duration.ofSeconds(2)).thenReturn(0))
                .repeat()
                .subscribe();
    }

    @PreDestroy
    void detener() {
        publicador.dispose();
        lector.dispose();
    }
}
```

## 5. Quarkus (imperativo)
Con las extensiones `quarkus-amazon-*` los clientes (`EventBridgeClient`, `SqsClient`, `DynamoDbClient`) se **inyectan** ya configurados; solo se producen los objetos del dominio. El `@Scheduled` con `SKIP` evita ciclos solapados.
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Singleton;
import java.time.Clock;
import java.time.Duration;
import javax.sql.DataSource;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class TiendaProductores {
    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioPedidos servicioPedidos(DataSource ds) {
        return new ServicioPedidos(new RepositorioPedidosJdbc(ds));
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    CicloPublicacion ciclo(DataSource ds, EventBridgeClient eb, @ConfigProperty(name = "app.eventos.bus") String bus) {
        return new CicloPublicacion(new BandejaSalidaJdbc(ds), new PublicadorEventBridge(eb, bus), 50);
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ConsumidorSqs consumidor(SqsClient sqs, DynamoDbClient dynamo, @ConfigProperty(name = "app.cola-facturacion") String cola,
                             @ConfigProperty(name = "app.bandeja-entrada") String tabla) {
        Facturador facturador = evento -> {
            // Lógica real de facturación.
        };
        var bandeja = new BandejaEntradaDynamo(dynamo, tabla, Duration.ofSeconds(120), Duration.ofDays(14), Clock.systemUTC());
        return new ConsumidorSqs(sqs, cola, new ManejadorDeMensajes(new ProcesadorIdempotente(bandeja), facturador), 20);
    }
}
```
```java
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

record SolicitudPedidoQ(String clienteId, String envio, long totalCentimos, List<LineaPedido> lineas) {}

@Path("/pedidos")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class PedidosResource {
    @Inject
    ServicioPedidos servicio;

    @POST
    public Response crear(@HeaderParam("Idempotency-Key") String clave, SolicitudPedidoQ s) {
        try {
            var r = servicio.crear(clave, s.clienteId(), s.envio(), s.totalCentimos(), s.lineas());
            return Response.status(r.creado() ? 201 : 200).entity(Map.of("idPedido", r.idPedido())).build();
        } catch (IllegalArgumentException e) {
            return Response.status(400).entity(Map.of("error", String.valueOf(e.getMessage()))).build();
        }
    }
}

@ApplicationScoped
class TareasQuarkus {
    @Inject
    CicloPublicacion ciclo;
    @Inject
    ConsumidorSqs consumidor;

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void publicar() {
        ciclo.ejecutar();
    }

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void consumir() {
        consumidor.sondear();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
Mismo núcleo bloqueante, movido al *pool* de trabajo para no tocar el hilo de E/S. Un método `@Scheduled` puede devolver `Uni<Void>`: Quarkus se suscribe y no lanza otro ciclo mientras el anterior no termina.
```java
import io.quarkus.scheduler.Scheduled;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

record SolicitudPedidoM(String clienteId, String envio, long totalCentimos, List<LineaPedido> lineas) {}

@Path("/v2/pedidos")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class PedidosMutinyResource {
    @Inject
    ServicioPedidos servicio;

    @POST
    public Uni<Response> crear(@HeaderParam("Idempotency-Key") String clave, SolicitudPedidoM s) {
        return Uni.createFrom().item(() -> servicio.crear(clave, s.clienteId(), s.envio(), s.totalCentimos(), s.lineas()))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(r -> Response.status(r.creado() ? 201 : 200).entity(Map.of("idPedido", r.idPedido())).build())
                .onFailure(IllegalArgumentException.class)
                .recoverWithItem(e -> Response.status(400).entity(Map.of("error", String.valueOf(e.getMessage()))).build());
    }
}

@ApplicationScoped
class TareasMutiny {
    @Inject
    CicloPublicacion ciclo;
    @Inject
    ConsumidorSqs consumidor;

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    Uni<Void> publicar() {
        return Uni.createFrom().item(ciclo::ejecutar)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .onFailure().recoverWithItem(0)
                .replaceWithVoid();
    }

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    Uni<Void> consumir() {
        return Uni.createFrom().item(consumidor::sondear)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .onFailure().recoverWithItem(0)
                .replaceWithVoid();
    }
}
```

## 7. Permisos
| Servicio (rol de tarea) | Acciones | Recurso |
|---|---|---|
| `pedidos` | — (solo Aurora por red y secreto) | `secretsmanager:GetSecretValue` del secreto de la base |
| `publicador` | `events:PutEvents` | ARN del bus `prod-ordenes` |
| `facturacion` | `sqs:ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility`, `GetQueueAttributes` | Solo **su** cola |
| `facturacion` | `dynamodb:PutItem`, `dynamodb:UpdateItem` | Tabla `prod-bandeja-entrada` |
| `comprobantes` | `s3:PutObject` | `arn:aws:s3:::modalima-comprobantes/facturas/*` |

Las políticas reales salen de [`ejemplos/terraform`](ejemplos/terraform/main.tf).

## 8. Qué NO hacer desde Java
- No llames a `PutEvents` dentro de la transacción del pedido «porque es rápido»: la base y EventBridge no comparten transacción.
- No marques como publicado un evento sin mirar su entrada en la respuesta.
- No borres el mensaje antes de terminar el efecto; ni borres lo ilegible (va a la DLQ).
- No uses `@Scheduled` con un solo hilo para publicar y consumir a la vez.
- No pongas datos personales en `detailType`, atributos ni nombres de cola.
- No ejecutes JDBC en el bucle de eventos de WebFlux/Vert.x.
- No guardes en la bandeja de entrada solo «ya lo vi» antes del efecto: usa reserva con vencimiento.
