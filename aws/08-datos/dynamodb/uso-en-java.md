# AWS · DynamoDB · Uso desde Java

DynamoDB se usa por HTTPS con el SDK, sin pool ni conexiones; lo difícil es **hacer bien lo que el motor no hace por ti**: claves que ordenan, paginación segura, idempotencia, lotes incompletos y conflictos de concurrencia. El núcleo común son cinco piezas pequeñas y probadas: **claves**, **cursor firmado**, **lotes con reintento**, **idempotencia** y **constructores de consultas**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56, `dynamodb` + `dynamodb-enhanced`).

## 1. Configuración
```yaml
# Spring Boot (application.yml) — el cliente toma región y credenciales de la cadena por defecto
app:
  tabla-pedidos: ${TABLA_PEDIDOS:prod-pedidos}
  tabla-idempotencia: ${TABLA_IDEMPOTENCIA:prod-idempotencia}
  cursor-secreto: ${CURSOR_SECRETO}        # ≥ 32 caracteres; viene de Secrets Manager, no del repositorio
```
```properties
# Quarkus (application.properties) — la extensión crea DynamoDbClient y DynamoDbAsyncClient
quarkus.dynamodb.aws.region=${AWS_REGION:us-east-1}
quarkus.dynamodb.aws.credentials.type=default
quarkus.dynamodb.sync-client.type=apache
quarkus.dynamodb.async-client.type=netty
# Desarrollo local con DynamoDB Local:
# %dev.quarkus.dynamodb.endpoint-override=http://localhost:8000
app.tabla-pedidos=${TABLA_PEDIDOS:prod-pedidos}
app.tabla-idempotencia=${TABLA_IDEMPOTENCIA:prod-idempotencia}
app.cursor-secreto=${CURSOR_SECRETO}
```
Dependencias: `software.amazon.awssdk:dynamodb` y `dynamodb-enhanced` (Spring); en Quarkus, `io.quarkiverse.amazonservices:quarkus-amazon-dynamodb` (y `quarkus-amazon-dynamodb-enhanced` si compilas a nativo).

## 2. Núcleo común

### 2.1 Claves que ordenan y reparten
Una clave bien hecha responde un patrón de acceso con un `Query`. Reglas: **prefijo de tipo** (`CLIENTE#`, `ORDEN#`), **separador `#` prohibido dentro de los componentes** y **fechas de ancho fijo** (si no, el orden de texto no es el cronológico).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.CRC32;

public final class ClavesDynamo {
    private static final DateTimeFormatter FECHA =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC);

    private ClavesDynamo() {}

    private static String limpio(String parte) {
        if (parte == null || parte.isBlank() || parte.indexOf('#') >= 0) {
            throw new IllegalArgumentException("componente de clave inválido: " + parte);
        }
        return parte;
    }

    public static String cliente(String id) {
        return "CLIENTE#" + limpio(id);
    }

    public static String prefijoOrdenes() {
        return "ORDEN#";
    }

    /** Ancho fijo: el orden alfabético de la clave de ordenación es el orden cronológico. */
    public static String orden(Instant cuando, String ordenId) {
        return prefijoOrdenes() + FECHA.format(cuando) + "#" + limpio(ordenId);
    }

    public static String estado(String estado) {
        return "ESTADO#" + limpio(estado);
    }

    /** El prefijo base sí puede llevar '#' (p. ej. FECHA#2026-11-27); solo se exige que no esté vacío. */
    private static String base(String base) {
        if (base == null || base.isBlank()) {
            throw new IllegalArgumentException("base de clave vacía");
        }
        return base;
    }

    /** Reparte una clave muy caliente en N fragmentos estables (mismo discriminador, mismo fragmento). */
    public static String fragmento(String base, String discriminador, int total) {
        if (total < 1) {
            throw new IllegalArgumentException("total debe ser >= 1");
        }
        CRC32 crc = new CRC32();
        crc.update(limpio(discriminador).getBytes(StandardCharsets.UTF_8));
        return base(base) + "#" + (crc.getValue() % total);
    }

    /** Para leer: se consulta cada fragmento (en paralelo) y se unen los resultados. */
    public static List<String> fragmentos(String base, int total) {
        List<String> lista = new ArrayList<>();
        for (int i = 0; i < total; i++) {
            lista.add(base(base) + "#" + i);
        }
        return lista;
    }
}
```

### 2.2 Cursor firmado
`LastEvaluatedKey` revela tu esquema y, si el cliente lo manipula, puede leer particiones ajenas. El cursor que sale a Internet va **firmado (HMAC), atado a un contexto (p. ej. el cliente consultado) y con vencimiento**.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.TreeMap;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class CursorFirmado {
    public static final class CursorInvalido extends RuntimeException {
        public CursorInvalido(String motivo) {
            super("cursor inválido: " + motivo);
        }
    }

    private final byte[] secreto;

    public CursorFirmado(byte[] secreto) {
        if (secreto.length < 32) {
            throw new IllegalArgumentException("el secreto debe tener al menos 32 bytes");
        }
        this.secreto = secreto.clone();
    }

    public String emitir(Map<String, String> clave, String contexto, Instant expira) {
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            try (DataOutputStream out = new DataOutputStream(bos)) {
                out.writeUTF(contexto);
                out.writeLong(expira.getEpochSecond());
                Map<String, String> ordenado = new TreeMap<>(clave);
                out.writeInt(ordenado.size());
                for (Map.Entry<String, String> e : ordenado.entrySet()) {
                    out.writeUTF(e.getKey());
                    out.writeUTF(e.getValue());
                }
            }
            byte[] cuerpo = bos.toByteArray();
            Base64.Encoder b64 = Base64.getUrlEncoder().withoutPadding();
            return b64.encodeToString(cuerpo) + "." + b64.encodeToString(firmar(cuerpo));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Map<String, String> leer(String cursor, String contexto, Instant ahora) {
        if (cursor == null) {
            throw new CursorInvalido("vacío");
        }
        int punto = cursor.indexOf('.');
        if (punto <= 0 || punto == cursor.length() - 1) {
            throw new CursorInvalido("formato");
        }
        byte[] cuerpo;
        byte[] firma;
        try {
            Base64.Decoder dec = Base64.getUrlDecoder();
            cuerpo = dec.decode(cursor.substring(0, punto));
            firma = dec.decode(cursor.substring(punto + 1));
        } catch (IllegalArgumentException e) {
            throw new CursorInvalido("formato");
        }
        if (!MessageDigest.isEqual(firma, firmar(cuerpo))) {
            throw new CursorInvalido("firma");
        }
        try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(cuerpo))) {
            if (!in.readUTF().equals(contexto)) {
                throw new CursorInvalido("contexto distinto");
            }
            if (ahora.getEpochSecond() > in.readLong()) {
                throw new CursorInvalido("vencido");
            }
            int n = in.readInt();
            Map<String, String> clave = new LinkedHashMap<>();
            for (int i = 0; i < n; i++) {
                clave.put(in.readUTF(), in.readUTF());
            }
            return clave;
        } catch (IOException e) {
            throw new CursorInvalido("contenido");
        }
    }

    private byte[] firmar(byte[] datos) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secreto, "HmacSHA256"));
            return mac.doFinal(datos);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }
}
```

### 2.3 Lotes con reintento de lo no procesado
`BatchWriteItem` puede responder «éxito» y devolver `UnprocessedItems`. Se reintenta **solo lo pendiente**, con espera creciente y azar; lo que sobreviva a los intentos se devuelve para que lo mandes a una cola de errores.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.function.DoubleSupplier;
import java.util.function.Function;
import java.util.function.LongConsumer;

public final class LoteDynamo {
    public static final int MAX_ESCRITURA = 25;
    public static final int MAX_LECTURA = 100;

    public record Resultado<T>(int enviados, List<T> pendientes) {}

    private LoteDynamo() {}

    /** @param envio manda un lote y devuelve los elementos que DynamoDB NO procesó */
    public static <T> Resultado<T> enviar(List<T> elementos, int tamanoLote, Function<List<T>, List<T>> envio,
                                          int maxIntentos, LongConsumer pausa, DoubleSupplier azar) {
        List<T> sinProcesar = new ArrayList<>();
        int enviados = 0;
        for (int i = 0; i < elementos.size(); i += tamanoLote) {
            List<T> pendientes = List.copyOf(elementos.subList(i, Math.min(i + tamanoLote, elementos.size())));
            int inicial = pendientes.size();
            for (int intento = 0; intento < maxIntentos && !pendientes.isEmpty(); intento++) {
                if (intento > 0) {
                    pausa.accept(espera(intento, azar));
                }
                pendientes = envio.apply(pendientes);
            }
            enviados += inicial - pendientes.size();
            sinProcesar.addAll(pendientes);
        }
        return new Resultado<>(enviados, sinProcesar);
    }

    /** Espera exponencial con tope de 5 s y «jitter completo». */
    static long espera(int intento, DoubleSupplier azar) {
        long tope = Math.min(5_000L, 50L << Math.min(intento, 10));
        return (long) (tope * azar.getAsDouble());
    }

    public static void dormir(long milisegundos) {
        try {
            Thread.sleep(milisegundos);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.WriteRequest;

public final class EscrituraLote {
    private EscrituraLote() {}

    public static LoteDynamo.Resultado<WriteRequest> escribir(DynamoDbClient dynamo, String tabla, List<WriteRequest> peticiones) {
        return LoteDynamo.enviar(
                peticiones,
                LoteDynamo.MAX_ESCRITURA,
                lote -> dynamo.batchWriteItem(b -> b.requestItems(Map.of(tabla, lote)))
                        .unprocessedItems().getOrDefault(tabla, List.of()),
                6,
                LoteDynamo::dormir,
                Math::random);
    }
}
```

### 2.4 Idempotencia con escritura condicional
**Reservar → hacer → completar; si falla, liberar.** La reserva es un `PutItem` condicional: pasa si la clave **no existe o ya venció** (TTL borra tarde, por eso se compara `expira_en`). Si el proceso muere a medias, la reserva corta caduca sola y el reintento puede continuar.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.util.function.Supplier;

public final class Idempotencia {
    public interface Almacen {
        /** true si se reservó; false si ya existe una reserva o resultado vigente. */
        boolean reservar(String clave, long expiraEpoch);

        void completar(String clave, long expiraEpoch);

        void liberar(String clave);
    }

    public record Resultado<T>(boolean duplicado, T valor) {}

    private final Almacen almacen;
    private final Clock reloj;
    private final Duration reserva;
    private final Duration retencion;

    /** @param reserva   un poco más que el tiempo máximo de la acción; @param retencion cuánto recordar el resultado */
    public Idempotencia(Almacen almacen, Clock reloj, Duration reserva, Duration retencion) {
        this.almacen = almacen;
        this.reloj = reloj;
        this.reserva = reserva;
        this.retencion = retencion;
    }

    public <T> Resultado<T> unaVez(String clave, Supplier<T> accion) {
        long ahora = reloj.instant().getEpochSecond();
        if (!almacen.reservar(clave, ahora + reserva.toSeconds())) {
            return new Resultado<>(true, null);
        }
        T valor;
        try {
            valor = accion.get();
        } catch (RuntimeException | Error e) {
            try {
                almacen.liberar(clave);
            } catch (RuntimeException ex) {
                e.addSuppressed(ex);
            }
            throw e;
        }
        almacen.completar(clave, reloj.instant().getEpochSecond() + retencion.toSeconds());
        return new Resultado<>(false, valor);
    }
}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.util.Map;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

/** Tabla de idempotencia: pk (texto) + expira_en (número, atributo TTL). */
public final class AlmacenDynamo implements Idempotencia.Almacen {
    private final DynamoDbClient dynamo;
    private final String tabla;
    private final Clock reloj;

    public AlmacenDynamo(DynamoDbClient dynamo, String tabla, Clock reloj) {
        this.dynamo = dynamo;
        this.tabla = tabla;
        this.reloj = reloj;
    }

    private static AttributeValue texto(String v) {
        return AttributeValue.builder().s(v).build();
    }

    private static AttributeValue numero(long v) {
        return AttributeValue.builder().n(Long.toString(v)).build();
    }

    @Override
    public boolean reservar(String clave, long expiraEpoch) {
        try {
            dynamo.putItem(PutItemRequest.builder()
                    .tableName(tabla)
                    .item(Map.of("pk", texto(clave), "estado", texto("PROCESANDO"), "expira_en", numero(expiraEpoch)))
                    .conditionExpression("attribute_not_exists(pk) OR expira_en < :ahora")
                    .expressionAttributeValues(Map.of(":ahora", numero(reloj.instant().getEpochSecond())))
                    .build());
            return true;
        } catch (ConditionalCheckFailedException e) {
            return false;
        }
    }

    @Override
    public void completar(String clave, long expiraEpoch) {
        dynamo.updateItem(UpdateItemRequest.builder()
                .tableName(tabla)
                .key(Map.of("pk", texto(clave)))
                .updateExpression("SET estado = :c, expira_en = :e")
                .expressionAttributeValues(Map.of(":c", texto("COMPLETADO"), ":e", numero(expiraEpoch)))
                .build());
    }

    @Override
    public void liberar(String clave) {
        dynamo.deleteItem(DeleteItemRequest.builder().tableName(tabla).key(Map.of("pk", texto(clave))).build());
    }
}
```

### 2.5 Constructores de consultas y modelo
Los pedidos de consulta son **funciones puras** (sin red): sirven igual al cliente síncrono y al asíncrono, y se prueban sin DynamoDB.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

public final class ConsultasPedidos {
    public record Pagina(List<Map<String, AttributeValue>> items, String siguiente) {}

    private ConsultasPedidos() {}

    private static AttributeValue texto(String v) {
        return AttributeValue.builder().s(v).build();
    }

    /** Órdenes de un cliente, las más recientes primero. */
    public static QueryRequest ordenesDeCliente(String tabla, String clienteId, int limite, Map<String, AttributeValue> desde) {
        QueryRequest.Builder b = QueryRequest.builder()
                .tableName(tabla)
                .keyConditionExpression("pk = :p AND begins_with(sk, :o)")
                .expressionAttributeValues(Map.of(
                        ":p", texto(ClavesDynamo.cliente(clienteId)),
                        ":o", texto(ClavesDynamo.prefijoOrdenes())))
                .scanIndexForward(false)
                .limit(Math.max(1, Math.min(limite, 100)));
        if (desde != null && !desde.isEmpty()) {
            b.exclusiveStartKey(desde);
        }
        return b.build();
    }

    /** Resta stock de forma atómica y solo si alcanza: sin leer antes, sin carrera. */
    public static UpdateItemRequest descontarStock(String tabla, String sku, int cantidad) {
        if (cantidad < 1) {
            throw new IllegalArgumentException("cantidad debe ser >= 1");
        }
        AttributeValue n = AttributeValue.builder().n(Integer.toString(cantidad)).build();
        return UpdateItemRequest.builder()
                .tableName(tabla)
                .key(Map.of("pk", texto("SKU#" + sku), "sk", texto("STOCK")))
                .updateExpression("SET cantidad = cantidad - :n")
                .conditionExpression("attribute_exists(pk) AND cantidad >= :n")
                .expressionAttributeValues(Map.of(":n", n))
                .build();
    }

    /** Clave de DynamoDB → texto con tipo ("S:abc", "N:42") para ir dentro del cursor. */
    public static Map<String, String> aTextos(Map<String, AttributeValue> clave) {
        Map<String, String> salida = new LinkedHashMap<>();
        clave.forEach((k, v) -> {
            if (v.s() != null) {
                salida.put(k, "S:" + v.s());
            } else if (v.n() != null) {
                salida.put(k, "N:" + v.n());
            } else {
                throw new IllegalArgumentException("tipo de clave no soportado en " + k);
            }
        });
        return salida;
    }

    public static Map<String, AttributeValue> aClave(Map<String, String> textos) {
        Map<String, AttributeValue> clave = new LinkedHashMap<>();
        textos.forEach((k, v) -> {
            String valor = v.substring(2);
            clave.put(k, v.startsWith("N:") ? AttributeValue.builder().n(valor).build()
                    : AttributeValue.builder().s(valor).build());
        });
        return clave;
    }

    /** Convierte la respuesta en una página con cursor firmado (null si ya no hay más). */
    public static Pagina pagina(QueryResponse r, CursorFirmado cursores, String contexto, Instant expira) {
        String siguiente = r.hasLastEvaluatedKey() && !r.lastEvaluatedKey().isEmpty()
                ? cursores.emitir(aTextos(r.lastEvaluatedKey()), contexto, expira)
                : null;
        return new Pagina(r.items(), siguiente);
    }
}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import software.amazon.awssdk.enhanced.dynamodb.extensions.annotations.DynamoDbVersionAttribute;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.DynamoDbBean;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.DynamoDbPartitionKey;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.DynamoDbSortKey;

/** Mapea TODOS los atributos del ítem: updateItem reemplaza lo que el bean no conoce. */
@DynamoDbBean
public class Pedido {
    private String pk;
    private String sk;
    private String gsi1pk;
    private String gsi1sk;
    private String estado;
    private BigDecimal total;
    private Long version;

    public Pedido() {}

    public static Pedido nuevo(String clienteId, UUID ordenId, Instant cuando, BigDecimal total) {
        Pedido p = new Pedido();
        p.pk = ClavesDynamo.cliente(clienteId);
        p.sk = ClavesDynamo.orden(cuando, ordenId.toString());
        p.gsi1pk = ClavesDynamo.estado("NUEVO");
        p.gsi1sk = p.sk.substring(ClavesDynamo.prefijoOrdenes().length());
        p.estado = "NUEVO";
        p.total = total;
        return p;
    }

    @DynamoDbPartitionKey
    public String getPk() { return pk; }
    public void setPk(String pk) { this.pk = pk; }

    @DynamoDbSortKey
    public String getSk() { return sk; }
    public void setSk(String sk) { this.sk = sk; }

    public String getGsi1pk() { return gsi1pk; }
    public void setGsi1pk(String gsi1pk) { this.gsi1pk = gsi1pk; }

    public String getGsi1sk() { return gsi1sk; }
    public void setGsi1sk(String gsi1sk) { this.gsi1sk = gsi1sk; }

    public String getEstado() { return estado; }
    public void setEstado(String estado) { this.estado = estado; }

    public BigDecimal getTotal() { return total; }
    public void setTotal(BigDecimal total) { this.total = total; }

    /** Bloqueo optimista: el cliente mejorado lo incrementa y exige que siga siendo el que leíste. */
    @DynamoDbVersionAttribute
    public Long getVersion() { return version; }
    public void setVersion(Long version) { this.version = version; }
}
```

## 3. Spring MVC (imperativo)
```java
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.Key;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.PutRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;
import software.amazon.awssdk.services.dynamodb.model.WriteRequest;

@Configuration
class DynamoConfig {
    @Bean(destroyMethod = "close")
    DynamoDbClient dynamo() {
        return DynamoDbClient.create();
    }

    @Bean
    DynamoDbEnhancedClient enhanced(DynamoDbClient dynamo) {
        return DynamoDbEnhancedClient.builder().dynamoDbClient(dynamo).build();
    }

    @Bean
    DynamoDbTable<Pedido> tablaPedidos(DynamoDbEnhancedClient enhanced, @Value("${app.tabla-pedidos}") String tabla) {
        return enhanced.table(tabla, TableSchema.fromBean(Pedido.class));
    }

    @Bean
    CursorFirmado cursores(@Value("${app.cursor-secreto}") String secreto) {
        return new CursorFirmado(secreto.getBytes(StandardCharsets.UTF_8));
    }

    @Bean
    Idempotencia idempotencia(DynamoDbClient dynamo, @Value("${app.tabla-idempotencia}") String tabla) {
        Clock reloj = Clock.systemUTC();
        return new Idempotencia(new AlmacenDynamo(dynamo, tabla, reloj), reloj, Duration.ofMinutes(5), Duration.ofDays(7));
    }
}

@Service
class PedidoServicio {
    enum Confirmacion { OK, NO_EXISTE, CONFLICTO }

    private static final TableSchema<Pedido> ESQUEMA = TableSchema.fromBean(Pedido.class);

    private final DynamoDbClient dynamo;
    private final DynamoDbTable<Pedido> pedidos;
    private final CursorFirmado cursores;
    private final Idempotencia idempotencia;
    private final String tabla;

    PedidoServicio(DynamoDbClient dynamo, DynamoDbTable<Pedido> pedidos, CursorFirmado cursores,
                   Idempotencia idempotencia, @Value("${app.tabla-pedidos}") String tabla) {
        this.dynamo = dynamo;
        this.pedidos = pedidos;
        this.cursores = cursores;
        this.idempotencia = idempotencia;
        this.tabla = tabla;
    }

    ConsultasPedidos.Pagina ordenes(String clienteId, int limite, String cursor) {
        String contexto = "ordenes:" + clienteId;
        Map<String, AttributeValue> desde = cursor == null ? Map.of()
                : ConsultasPedidos.aClave(cursores.leer(cursor, contexto, Instant.now()));
        QueryResponse r = dynamo.query(ConsultasPedidos.ordenesDeCliente(tabla, clienteId, limite, desde));
        return ConsultasPedidos.pagina(r, cursores, contexto, Instant.now().plus(Duration.ofMinutes(15)));
    }

    /** El id de la orden sale de la clave de idempotencia: un reintento responde con el mismo id. */
    Idempotencia.Resultado<UUID> crear(String clienteId, BigDecimal total, String claveIdem) {
        UUID ordenId = UUID.nameUUIDFromBytes((clienteId + ":" + claveIdem).getBytes(StandardCharsets.UTF_8));
        return idempotencia.unaVez("crear-orden:" + clienteId + ":" + claveIdem, () -> {
            pedidos.putItem(Pedido.nuevo(clienteId, ordenId, Instant.now(), total));
            return ordenId;
        });
    }

    /** Lee, cambia y escribe con bloqueo optimista: si alguien más lo cambió en medio, es un conflicto (409). */
    Confirmacion confirmar(String clienteId, String sk) {
        Pedido p = pedidos.getItem(Key.builder().partitionValue(ClavesDynamo.cliente(clienteId)).sortValue(sk).build());
        if (p == null) {
            return Confirmacion.NO_EXISTE;
        }
        p.setEstado("CONFIRMADO");
        p.setGsi1pk(ClavesDynamo.estado("CONFIRMADO"));
        try {
            pedidos.updateItem(p);
            return Confirmacion.OK;
        } catch (ConditionalCheckFailedException e) {
            return Confirmacion.CONFLICTO;
        }
    }

    boolean reservarStock(String sku, int cantidad) {
        try {
            dynamo.updateItem(ConsultasPedidos.descontarStock(tabla, sku, cantidad));
            return true;
        } catch (ConditionalCheckFailedException e) {
            return false;
        }
    }

    /** Carga masiva: BatchWriteItem no pasa por el bloqueo optimista, así que fijamos version=1 a mano. */
    LoteDynamo.Resultado<WriteRequest> importar(List<Pedido> lista) {
        List<WriteRequest> peticiones = lista.stream().map(p -> {
            Map<String, AttributeValue> item = new java.util.HashMap<>(ESQUEMA.itemToMap(p, true));
            item.put("version", AttributeValue.builder().n("1").build());
            return WriteRequest.builder().putRequest(PutRequest.builder().item(item).build()).build();
        }).toList();
        return EscrituraLote.escribir(dynamo, tabla, peticiones);
    }
}

@RestController
class PedidoController {
    record OrdenDto(String sk, String estado, String total) {}

    record PaginaDto(List<OrdenDto> items, String siguiente) {}

    record NuevaOrden(BigDecimal total) {}

    private final PedidoServicio servicio;

    PedidoController(PedidoServicio servicio) {
        this.servicio = servicio;
    }

    @GetMapping("/clientes/{id}/ordenes")
    ResponseEntity<PaginaDto> listar(@PathVariable String id, @RequestParam(defaultValue = "20") int limite,
                                     @RequestParam(required = false) String cursor) {
        try {
            ConsultasPedidos.Pagina p = servicio.ordenes(id, limite, cursor);
            List<OrdenDto> items = p.items().stream()
                    .map(i -> new OrdenDto(i.get("sk").s(), i.get("estado").s(), i.get("total").n()))
                    .toList();
            return ResponseEntity.ok(new PaginaDto(items, p.siguiente()));
        } catch (CursorFirmado.CursorInvalido e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @PostMapping("/clientes/{id}/ordenes")
    ResponseEntity<Map<String, Object>> crear(@PathVariable String id, @RequestBody NuevaOrden cuerpo,
                                              @RequestHeader("Idempotency-Key") String clave) {
        Idempotencia.Resultado<UUID> r = servicio.crear(id, cuerpo.total(), clave);
        UUID ordenId = UUID.nameUUIDFromBytes((id + ":" + clave).getBytes(StandardCharsets.UTF_8));
        return ResponseEntity.status(r.duplicado() ? HttpStatus.OK : HttpStatus.CREATED)
                .body(Map.of("ordenId", ordenId, "duplicado", r.duplicado()));
    }

    @PostMapping("/clientes/{id}/ordenes/confirmar")
    ResponseEntity<String> confirmar(@PathVariable String id, @RequestParam String sk) {
        return switch (servicio.confirmar(id, sk)) {
            case OK -> ResponseEntity.ok("confirmada");
            case NO_EXISTE -> ResponseEntity.notFound().build();
            case CONFLICTO -> ResponseEntity.status(HttpStatus.CONFLICT).body("la orden cambió; vuelve a leerla");
        };
    }

    @PostMapping("/stock/{sku}/descontar")
    ResponseEntity<String> descontar(@PathVariable String sku, @RequestParam int n) {
        return servicio.reservarStock(sku, n)
                ? ResponseEntity.ok("reservado")
                : ResponseEntity.status(HttpStatus.CONFLICT).body("sin stock suficiente");
    }
}
```

## 4. Spring WebFlux (reactivo)
El cliente asíncrono devuelve `CompletableFuture`; se convierte con `Mono.fromFuture`. Para recorrer **todas** las páginas hay un paginador que ya es un publicador reactivo.
```java
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.reactivestreams.Publisher;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import software.amazon.awssdk.services.dynamodb.DynamoDbAsyncClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

@Configuration
class DynamoReactivoConfig {
    @Bean(destroyMethod = "close")
    DynamoDbAsyncClient dynamoAsync() {
        return DynamoDbAsyncClient.create();
    }
}

@RestController
class OrdenesReactivoController {
    record OrdenDto(String sk, String estado, String total) {}

    record PaginaDto(List<OrdenDto> items, String siguiente) {}

    private final DynamoDbAsyncClient dynamo;
    private final CursorFirmado cursores;
    private final String tabla;

    OrdenesReactivoController(DynamoDbAsyncClient dynamo, CursorFirmado cursores, @Value("${app.tabla-pedidos}") String tabla) {
        this.dynamo = dynamo;
        this.cursores = cursores;
        this.tabla = tabla;
    }

    private static OrdenDto aDto(Map<String, AttributeValue> i) {
        return new OrdenDto(i.get("sk").s(), i.get("estado").s(), i.get("total").n());
    }

    @GetMapping("/r/clientes/{id}/ordenes")
    Mono<ResponseEntity<PaginaDto>> pagina(@PathVariable String id, @RequestParam(defaultValue = "20") int limite,
                                           @RequestParam(required = false) String cursor) {
        String contexto = "ordenes:" + id;
        return Mono.defer(() -> {
                    Map<String, AttributeValue> desde = cursor == null ? Map.of()
                            : ConsultasPedidos.aClave(cursores.leer(cursor, contexto, Instant.now()));
                    return Mono.fromFuture(() -> dynamo.query(ConsultasPedidos.ordenesDeCliente(tabla, id, limite, desde)));
                })
                .map((QueryResponse r) -> ConsultasPedidos.pagina(r, cursores, contexto, Instant.now().plus(Duration.ofMinutes(15))))
                .map(p -> ResponseEntity.ok(new PaginaDto(p.items().stream().map(OrdenesReactivoController::aDto).toList(), p.siguiente())))
                .onErrorResume(CursorFirmado.CursorInvalido.class, e -> Mono.just(ResponseEntity.badRequest().build()));
    }

    /** Recorre todas las páginas con el paginador del SDK; take(...) protege la memoria y el costo. */
    @GetMapping("/r/clientes/{id}/ordenes/todas")
    Flux<OrdenDto> todas(@PathVariable String id) {
        Publisher<QueryResponse> paginas = dynamo.queryPaginator(ConsultasPedidos.ordenesDeCliente(tabla, id, 100, Map.of()));
        return Flux.from(paginas)
                .concatMapIterable(QueryResponse::items)
                .map(OrdenesReactivoController::aDto)
                .take(1_000);
    }

    @PostMapping("/r/stock/{sku}/descontar")
    Mono<ResponseEntity<String>> descontar(@PathVariable String sku, @RequestParam int n) {
        return Mono.fromFuture(() -> dynamo.updateItem(ConsultasPedidos.descontarStock(tabla, sku, n)))
                .map(r -> ResponseEntity.ok("reservado"))
                .onErrorResume(ConditionalCheckFailedException.class,
                        e -> Mono.just(ResponseEntity.status(HttpStatus.CONFLICT).body("sin stock suficiente")));
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

@ApplicationScoped
class DynamoProductores {
    @Produces
    @Singleton
    DynamoDbEnhancedClient enhanced(DynamoDbClient dynamo) {
        return DynamoDbEnhancedClient.builder().dynamoDbClient(dynamo).build();
    }

    @Produces
    @Singleton
    CursorFirmado cursores(@ConfigProperty(name = "app.cursor-secreto") String secreto) {
        return new CursorFirmado(secreto.getBytes(StandardCharsets.UTF_8));
    }

    @Produces
    @Singleton
    Idempotencia idempotencia(DynamoDbClient dynamo, @ConfigProperty(name = "app.tabla-idempotencia") String tabla) {
        Clock reloj = Clock.systemUTC();
        return new Idempotencia(new AlmacenDynamo(dynamo, tabla, reloj), reloj, Duration.ofMinutes(5), Duration.ofDays(7));
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedClient;
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbTable;
import software.amazon.awssdk.enhanced.dynamodb.TableSchema;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

@Path("/clientes/{id}/ordenes")
@Produces(MediaType.APPLICATION_JSON)
class OrdenesRecurso {
    record NuevaOrden(BigDecimal total) {}

    @Inject
    DynamoDbClient dynamo;

    @Inject
    DynamoDbEnhancedClient enhanced;

    @Inject
    CursorFirmado cursores;

    @Inject
    Idempotencia idempotencia;

    @ConfigProperty(name = "app.tabla-pedidos")
    String tabla;

    @GET
    public Response listar(@PathParam("id") String id, @QueryParam("limite") @DefaultValue("20") int limite,
                           @QueryParam("cursor") String cursor) {
        String contexto = "ordenes:" + id;
        try {
            Map<String, AttributeValue> desde = cursor == null ? Map.of()
                    : ConsultasPedidos.aClave(cursores.leer(cursor, contexto, Instant.now()));
            QueryResponse r = dynamo.query(ConsultasPedidos.ordenesDeCliente(tabla, id, limite, desde));
            ConsultasPedidos.Pagina p = ConsultasPedidos.pagina(r, cursores, contexto, Instant.now().plus(Duration.ofMinutes(15)));
            var items = p.items().stream()
                    .map(i -> Map.of("sk", i.get("sk").s(), "estado", i.get("estado").s(), "total", i.get("total").n()))
                    .toList();
            return Response.ok(Map.of("items", items, "siguiente", p.siguiente() == null ? "" : p.siguiente())).build();
        } catch (CursorFirmado.CursorInvalido e) {
            return Response.status(Response.Status.BAD_REQUEST).entity(Map.of("error", e.getMessage())).build();
        }
    }

    @POST
    public Response crear(@PathParam("id") String id, NuevaOrden cuerpo, @HeaderParam("Idempotency-Key") String clave) {
        if (clave == null || clave.isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST).entity(Map.of("error", "falta Idempotency-Key")).build();
        }
        DynamoDbTable<Pedido> pedidos = enhanced.table(tabla, TableSchema.fromBean(Pedido.class));
        UUID ordenId = UUID.nameUUIDFromBytes((id + ":" + clave).getBytes(StandardCharsets.UTF_8));
        Idempotencia.Resultado<UUID> r = idempotencia.unaVez("crear-orden:" + id + ":" + clave, () -> {
            pedidos.putItem(Pedido.nuevo(id, ordenId, Clock.systemUTC().instant(), cuerpo.total()));
            return ordenId;
        });
        return Response.status(r.duplicado() ? Response.Status.OK : Response.Status.CREATED)
                .entity(Map.of("ordenId", ordenId, "duplicado", r.duplicado())).build();
    }

    @POST
    @Path("/stock/{sku}/descontar")
    public Response descontar(@PathParam("sku") String sku, @QueryParam("n") int n) {
        try {
            dynamo.updateItem(ConsultasPedidos.descontarStock(tabla, sku, n));
            return Response.ok(Map.of("estado", "reservado")).build();
        } catch (ConditionalCheckFailedException e) {
            return Response.status(Response.Status.CONFLICT).entity(Map.of("error", "sin stock suficiente")).build();
        }
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.reactivestreams.FlowAdapters;
import software.amazon.awssdk.services.dynamodb.DynamoDbAsyncClient;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.QueryResponse;

@Path("/m/clientes/{id}/ordenes")
class OrdenesMutinyRecurso {
    @Inject
    DynamoDbAsyncClient dynamo;

    @ConfigProperty(name = "app.tabla-pedidos")
    String tabla;

    /** Todas las órdenes (hasta 500) como flujo: el paginador del SDK pide la página siguiente cuando hace falta. */
    @GET
    @Path("/todas")
    @Produces(MediaType.APPLICATION_JSON)
    public Multi<String> todas(@PathParam("id") String id) {
        // El SDK entrega un Publisher de Reactive Streams; Mutiny espera el de java.util.concurrent.Flow: se adapta.
        return Multi.createFrom().publisher(FlowAdapters.toFlowPublisher(dynamo.queryPaginator(ConsultasPedidos.ordenesDeCliente(tabla, id, 100, Map.of()))))
                .onItem().transformToIterable(QueryResponse::items)
                .map(i -> i.get("sk").s())
                .select().first(500);
    }

    @POST
    @Path("/stock/{sku}/descontar")
    @Produces(MediaType.TEXT_PLAIN)
    public Uni<Response> descontar(@PathParam("sku") String sku, @QueryParam("n") int n) {
        return Uni.createFrom().completionStage(() -> dynamo.updateItem(ConsultasPedidos.descontarStock(tabla, sku, n)))
                .map(r -> Response.ok("reservado").build())
                .onFailure(e -> causaEs(e, ConditionalCheckFailedException.class))
                .recoverWithItem(Response.status(Response.Status.CONFLICT).entity("sin stock suficiente").build());
    }

    private static boolean causaEs(Throwable e, Class<? extends Throwable> tipo) {
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (tipo.isInstance(t)) {
                return true;
            }
        }
        return false;
    }
}
```

## 7. Permisos
El servicio necesita las acciones de datos sobre la **tabla y sus índices** (`table/<t>` y `table/<t>/index/*`) y, si usas clave propia, permisos KMS: lo genera `data.aws_iam_policy_document.servicio` en [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf). Para multi-inquilino por identidad, usa la condición `dynamodb:LeadingKeys` ([`ejemplos/json/politica-leading-keys.json`](ejemplos/json/politica-leading-keys.json)). La cuenta que crea tablas (pipeline) es **otra** identidad.

## 8. Qué NO hacer desde Java
- **No** uses `scan` para responder peticiones: es lectura de toda la tabla (§2.5 usa `query`).
- **No** devuelvas `LastEvaluatedKey` en crudo al cliente: firma el cursor y átalo a su contexto (§2.2).
- **No** hagas leer-modificar-escribir sin condición: usa `UpdateItem` condicional o versión (§2.5, `Pedido`).
- **No** ignores `UnprocessedItems`: reintenta solo lo pendiente (§2.3) y manda lo que sobreviva a una cola de errores.
- **No** mandes dos operaciones con la misma clave en un mismo `BatchWriteItem`: la petición completa se rechaza.
- **No** uses `updateItem(bean)` con un bean que no mapee todos los atributos: los que no conoce se pierden.
- **No** confíes en TTL como temporizador: compara `expira_en` (§2.4).
- **No** crees el cliente en cada petición: uno por proceso, con cierre ordenado (`destroyMethod`).
- **No** bloquees con el cliente síncrono dentro de un controlador reactivo: usa el asíncrono (§4, §6).
