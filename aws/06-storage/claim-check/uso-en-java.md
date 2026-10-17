# AWS · Claim Check · Uso desde Java

Se implementa a mano para controlar lo que importa: **orden** (subir, luego publicar), **integridad** (SHA-256 + `versionId`), **validación del ticket** (bucket/prefijo permitidos) e **idempotencia** (reserva atómica en DynamoDB). Versiones: Java 21, Spring Boot 4.1 (Spring Cloud AWS 4.2), Quarkus 3.40, AWS SDK v2 (BOM 2.56).

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
          max-concurrent-messages: 5
          max-messages-per-poll: 5
          poll-timeout: 20s
app:
  bucket: modalima-prod-claimcheck-111122223333-us-east-1
  prefijo: cc/pedidos/
  cola-url: https://sqs.us-east-1.amazonaws.com/111122223333/prod-claimcheck
  cola-nombre: prod-claimcheck
  tabla-idempotencia: claimcheck-procesados
  max-bytes: 1073741824
```
```properties
# Quarkus (application.properties)
quarkus.s3.aws.region=us-east-1
quarkus.sqs.aws.region=us-east-1
quarkus.dynamodb.aws.region=us-east-1
app.bucket=modalima-prod-claimcheck-111122223333-us-east-1
app.prefijo=cc/pedidos/
app.cola-url=https://sqs.us-east-1.amazonaws.com/111122223333/prod-claimcheck
app.tabla-idempotencia=claimcheck-procesados
app.max-bytes=1073741824
```

## 2. Núcleo común

### 2.1 El ticket (JSON plano, sin librerías)
Spring usa Jackson 3 y Quarkus Jackson 2: para que el mismo núcleo sirva en ambos, el ticket es un JSON plano de strings y números con un lector mínimo.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

public record Ticket(int version, String bucket, String clave, String versionId, long tamano, String sha256,
                     String contentType, String correlacion, Instant creado) {
    /** Identificador estable para idempotencia: el mismo objeto y versión = el mismo trabajo. */
    public String id() {
        return bucket + "/" + clave + "#" + versionId;
    }
}

final class TicketJson {
    private TicketJson() {}

    static String escribir(Ticket t) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("version", t.version());
        m.put("bucket", t.bucket());
        m.put("clave", t.clave());
        m.put("versionId", t.versionId());
        m.put("tamano", t.tamano());
        m.put("sha256", t.sha256());
        m.put("contentType", t.contentType());
        m.put("correlacion", t.correlacion());
        m.put("creado", t.creado().toString());
        StringBuilder sb = new StringBuilder("{");
        boolean primero = true;
        for (var e : m.entrySet()) {
            if (!primero) {
                sb.append(',');
            }
            primero = false;
            sb.append('"').append(e.getKey()).append("\":");
            if (e.getValue() instanceof Number) {
                sb.append(e.getValue());
            } else {
                sb.append('"').append(esc(String.valueOf(e.getValue()))).append('"');
            }
        }
        return sb.append('}').toString();
    }

    private static String esc(String s) {
        StringBuilder sb = new StringBuilder();
        for (char c : s.toCharArray()) {
            if (c == '"' || c == '\\') {
                sb.append('\\').append(c);
            } else if (c < 0x20) {
                sb.append(String.format("\\u%04x", (int) c));
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    static Ticket leer(String json) {
        Map<String, String> m = MiniJsonPlano.leer(json);
        try {
            return new Ticket(Integer.parseInt(req(m, "version")), req(m, "bucket"), req(m, "clave"),
                    req(m, "versionId"), Long.parseLong(req(m, "tamano")), req(m, "sha256"),
                    req(m, "contentType"), req(m, "correlacion"), Instant.parse(req(m, "creado")));
        } catch (NumberFormatException | java.time.format.DateTimeParseException e) {
            throw new TicketInvalidoException("campo con formato inválido: " + e.getMessage());
        }
    }

    private static String req(Map<String, String> m, String k) {
        String v = m.get(k);
        if (v == null || v.isBlank()) {
            throw new TicketInvalidoException("falta el campo '" + k + "'");
        }
        return v;
    }
}

/** Error permanente: reintentar no lo arregla (acabará en la DLQ). */
class TicketInvalidoException extends RuntimeException {
    TicketInvalidoException(String mensaje) {
        super(mensaje);
    }
}

/** Lector de un objeto JSON plano (valores string o literales; sin anidar). */
final class MiniJsonPlano {
    private final String s;
    private int i;

    private MiniJsonPlano(String s) {
        this.s = s;
    }

    static Map<String, String> leer(String texto) {
        if (texto == null) {
            throw new TicketInvalidoException("cuerpo vacío");
        }
        MiniJsonPlano p = new MiniJsonPlano(texto);
        return p.objeto();
    }

    private void espacios() {
        while (i < s.length() && Character.isWhitespace(s.charAt(i))) {
            i++;
        }
    }

    private void esperar(char c) {
        espacios();
        if (i >= s.length() || s.charAt(i) != c) {
            throw new TicketInvalidoException("JSON inválido: se esperaba '" + c + "' en la posición " + i);
        }
        i++;
    }

    private Map<String, String> objeto() {
        Map<String, String> r = new LinkedHashMap<>();
        esperar('{');
        espacios();
        if (i < s.length() && s.charAt(i) == '}') {
            i++;
            return r;
        }
        while (true) {
            espacios();
            String k = cadena();
            esperar(':');
            espacios();
            r.put(k, valor());
            espacios();
            if (i < s.length() && s.charAt(i) == ',') {
                i++;
                continue;
            }
            esperar('}');
            break;
        }
        espacios();
        if (i != s.length()) {
            throw new TicketInvalidoException("JSON inválido: texto después del objeto");
        }
        return r;
    }

    private String valor() {
        if (i < s.length() && s.charAt(i) == '"') {
            return cadena();
        }
        int ini = i;
        while (i < s.length() && ",}".indexOf(s.charAt(i)) < 0) {
            char c = s.charAt(i);
            if (c == '{' || c == '[') {
                throw new TicketInvalidoException("JSON anidado no permitido");
            }
            i++;
        }
        return s.substring(ini, i).trim();
    }

    private String cadena() {
        if (i >= s.length() || s.charAt(i) != '"') {
            throw new TicketInvalidoException("JSON inválido: se esperaba una cadena en la posición " + i);
        }
        i++;
        StringBuilder sb = new StringBuilder();
        while (i < s.length()) {
            char c = s.charAt(i++);
            if (c == '"') {
                return sb.toString();
            }
            if (c != '\\') {
                sb.append(c);
                continue;
            }
            if (i >= s.length()) {
                break;
            }
            char e = s.charAt(i++);
            switch (e) {
                case '"', '\\', '/' -> sb.append(e);
                case 'n' -> sb.append('\n');
                case 'r' -> sb.append('\r');
                case 't' -> sb.append('\t');
                case 'b' -> sb.append('\b');
                case 'f' -> sb.append('\f');
                case 'u' -> {
                    if (i + 4 > s.length()) {
                        throw new TicketInvalidoException("JSON inválido: escape \\u incompleto");
                    }
                    sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                    i += 4;
                }
                default -> throw new TicketInvalidoException("JSON inválido: escape \\" + e);
            }
        }
        throw new TicketInvalidoException("JSON inválido: cadena sin cerrar");
    }
}
```

### 2.2 Validar el ticket (entrada no confiable)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Set;
import java.util.regex.Pattern;

public final class ValidadorTicket {
    private static final Pattern CORRELACION = Pattern.compile("[A-Za-z0-9._:-]{1,100}");

    private final Set<String> bucketsPermitidos;
    private final String prefijo;
    private final long maxBytes;

    public ValidadorTicket(Set<String> bucketsPermitidos, String prefijo, long maxBytes) {
        this.bucketsPermitidos = Set.copyOf(bucketsPermitidos);
        this.prefijo = prefijo;
        this.maxBytes = maxBytes;
    }

    public void validar(Ticket t, Instant ahora) {
        if (t.version() != 1) {
            throw new TicketInvalidoException("versión de ticket no soportada: " + t.version());
        }
        if (!bucketsPermitidos.contains(t.bucket())) {
            throw new TicketInvalidoException("bucket no permitido");
        }
        if (!t.clave().startsWith(prefijo) || t.clave().contains("..") || t.clave().contains("//")) {
            throw new TicketInvalidoException("clave fuera del prefijo permitido");
        }
        if (t.tamano() < 1 || t.tamano() > maxBytes) {
            throw new TicketInvalidoException("tamaño fuera de rango");
        }
        try {
            if (Base64.getDecoder().decode(t.sha256()).length != 32) {
                throw new TicketInvalidoException("sha256 con longitud inválida");
            }
        } catch (IllegalArgumentException e) {
            throw new TicketInvalidoException("sha256 no es Base64");
        }
        if (!CORRELACION.matcher(t.correlacion()).matches()) {
            throw new TicketInvalidoException("correlación inválida");
        }
        if (t.creado().isAfter(ahora.plus(Duration.ofMinutes(5)))) {
            throw new TicketInvalidoException("ticket con fecha en el futuro");
        }
    }
}
```

### 2.3 Idempotencia: reserva atómica
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

public interface RegistroProcesados {
    /** true si este consumidor «ganó» el trabajo; false si ya está completado o lo tiene otro. */
    boolean reservar(String id, Duration plazo);

    void completar(String id);

    void liberar(String id);
}

/** Solo para pruebas o un único proceso. */
final class RegistroEnMemoria implements RegistroProcesados {
    private record Estado(boolean completado, Instant vence) {}

    private final ConcurrentHashMap<String, Estado> mapa = new ConcurrentHashMap<>();

    @Override
    public boolean reservar(String id, Duration plazo) {
        Instant ahora = Instant.now();
        boolean[] gano = {false};
        mapa.compute(id, (k, e) -> {
            if (e == null || (!e.completado() && e.vence().isBefore(ahora))) {
                gano[0] = true;
                return new Estado(false, ahora.plus(plazo));
            }
            return e;
        });
        return gano[0];
    }

    @Override
    public void completar(String id) {
        mapa.put(id, new Estado(true, Instant.MAX));
    }

    @Override
    public void liberar(String id) {
        mapa.computeIfPresent(id, (k, e) -> e.completado() ? e : null);
    }
}

/** Producción: escritura condicional en DynamoDB. La tabla usa "id" (S) como clave y "expira" como atributo TTL. */
final class RegistroDynamo implements RegistroProcesados {
    private final DynamoDbClient dynamo;
    private final String tabla;

    RegistroDynamo(DynamoDbClient dynamo, String tabla) {
        this.dynamo = dynamo;
        this.tabla = tabla;
    }

    @Override
    public boolean reservar(String id, Duration plazo) {
        long ahora = Instant.now().getEpochSecond();
        try {
            dynamo.putItem(PutItemRequest.builder().tableName(tabla)
                    .item(Map.of("id", AttributeValue.fromS(id),
                            "estado", AttributeValue.fromS("EN_PROCESO"),
                            "expira", AttributeValue.fromN(Long.toString(ahora + plazo.toSeconds()))))
                    .conditionExpression("attribute_not_exists(#id) OR (#st = :ep AND #ex < :ahora)")
                    .expressionAttributeNames(Map.of("#id", "id", "#st", "estado", "#ex", "expira"))
                    .expressionAttributeValues(Map.of(":ep", AttributeValue.fromS("EN_PROCESO"),
                            ":ahora", AttributeValue.fromN(Long.toString(ahora))))
                    .build());
            return true;
        } catch (ConditionalCheckFailedException e) {
            return false;
        }
    }

    @Override
    public void completar(String id) {
        long dias7 = Instant.now().plus(Duration.ofDays(7)).getEpochSecond();
        dynamo.updateItem(UpdateItemRequest.builder().tableName(tabla)
                .key(Map.of("id", AttributeValue.fromS(id)))
                .updateExpression("SET #st = :ok, #ex = :ttl")
                .expressionAttributeNames(Map.of("#st", "estado", "#ex", "expira"))
                .expressionAttributeValues(Map.of(":ok", AttributeValue.fromS("COMPLETADO"),
                        ":ttl", AttributeValue.fromN(Long.toString(dias7))))
                .build());
    }

    @Override
    public void liberar(String id) {
        try {
            dynamo.deleteItem(DeleteItemRequest.builder().tableName(tabla)
                    .key(Map.of("id", AttributeValue.fromS(id)))
                    .conditionExpression("#st = :ep")
                    .expressionAttributeNames(Map.of("#st", "estado"))
                    .expressionAttributeValues(Map.of(":ep", AttributeValue.fromS("EN_PROCESO")))
                    .build());
        } catch (ConditionalCheckFailedException ignorada) {
            // ya estaba completado: no se libera
        }
    }
}
```

### 2.4 Productor, consumidor y poller de SQS
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.io.OutputStream;
import java.io.InputStream;
import java.security.DigestOutputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.UUID;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.core.sync.ResponseTransformer;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ChecksumMode;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.DeleteMessageRequest;
import software.amazon.awssdk.services.sqs.model.Message;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

public final class ProductorClaimCheck {
    private static final DateTimeFormatter FECHA = DateTimeFormatter.ofPattern("yyyy/MM/dd").withZone(ZoneOffset.UTC);

    private final S3Client s3;
    private final SqsClient sqs;
    private final String bucket;
    private final String prefijo;
    private final String colaUrl;

    public ProductorClaimCheck(S3Client s3, SqsClient sqs, String bucket, String prefijo, String colaUrl) {
        this.s3 = s3;
        this.sqs = sqs;
        this.bucket = bucket;
        this.prefijo = prefijo;
        this.colaUrl = colaUrl;
    }

    static String sha256Base64(java.nio.file.Path archivo) throws IOException {
        try (InputStream in = java.nio.file.Files.newInputStream(archivo)) {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
            return Base64.getEncoder().encodeToString(md.digest());
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** 1) Sube con checksum (S3 lo verifica)  2) SOLO si subió, publica el ticket. */
    public Ticket publicar(java.nio.file.Path archivo, String contentType, String correlacion) throws IOException {
        long tamano = java.nio.file.Files.size(archivo);
        String sha = sha256Base64(archivo);
        String clave = prefijo + FECHA.format(Instant.now()) + "/" + UUID.randomUUID();
        PutObjectResponse r = s3.putObject(PutObjectRequest.builder().bucket(bucket).key(clave)
                .contentType(contentType).checksumSHA256(sha).build(), RequestBody.fromFile(archivo));
        if (r.versionId() == null) {
            throw new IllegalStateException("el bucket del Claim Check debe tener versionado activado");
        }
        Ticket t = new Ticket(1, bucket, clave, r.versionId(), tamano, sha, contentType, correlacion, Instant.now());
        sqs.sendMessage(SendMessageRequest.builder().queueUrl(colaUrl).messageBody(TicketJson.escribir(t)).build());
        return t;
    }
}

public final class ConsumidorClaimCheck {
    /** Lo que hace tu negocio con el archivo ya verificado. */
    public interface Procesador {
        void procesar(java.nio.file.Path archivo, Ticket ticket) throws Exception;
    }

    private final S3Client s3;
    private final ValidadorTicket validador;
    private final RegistroProcesados registro;
    private final Procesador procesador;
    private final Duration plazo;

    public ConsumidorClaimCheck(S3Client s3, ValidadorTicket validador, RegistroProcesados registro,
                                Procesador procesador, Duration plazo) {
        this.s3 = s3;
        this.validador = validador;
        this.registro = registro;
        this.procesador = procesador;
        this.plazo = plazo;
    }

    /** @return true si procesó; false si era un duplicado (ya hecho o en manos de otro consumidor). */
    public boolean procesar(String cuerpo) throws Exception {
        Ticket t = TicketJson.leer(cuerpo);
        validador.validar(t, Instant.now());
        String id = t.id();
        if (!registro.reservar(id, plazo)) {
            return false;
        }
        java.nio.file.Path tmp = java.nio.file.Files.createTempFile("cc-", ".tmp");
        try {
            descargarVerificado(t, tmp);
            procesador.procesar(tmp, t);
            registro.completar(id);
            return true;
        } catch (Exception e) {
            registro.liberar(id);          // permite el reintento (el mensaje reaparece tras el visibility timeout)
            throw e;
        } finally {
            java.nio.file.Files.deleteIfExists(tmp);
        }
    }

    private void descargarVerificado(Ticket t, java.nio.file.Path destino) throws IOException, NoSuchAlgorithmException {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        GetObjectRequest req = GetObjectRequest.builder().bucket(t.bucket()).key(t.clave())
                .versionId(t.versionId()).checksumMode(ChecksumMode.ENABLED).build();
        GetObjectResponse resp;
        try (OutputStream out = new DigestOutputStream(java.nio.file.Files.newOutputStream(destino), md)) {
            resp = s3.getObject(req, ResponseTransformer.toOutputStream(out));
        }
        if (resp.contentLength() != t.tamano()) {
            throw new IOException("tamaño distinto al del ticket: " + resp.contentLength() + " ≠ " + t.tamano());
        }
        String sha = Base64.getEncoder().encodeToString(md.digest());
        if (!sha.equals(t.sha256())) {
            throw new IOException("el SHA-256 del objeto no coincide con el del ticket");
        }
    }
}

public final class PollerSqs {
    private final SqsClient sqs;
    private final String colaUrl;
    private final ConsumidorClaimCheck consumidor;

    public PollerSqs(SqsClient sqs, String colaUrl, ConsumidorClaimCheck consumidor) {
        this.sqs = sqs;
        this.colaUrl = colaUrl;
        this.consumidor = consumidor;
    }

    /** Una pasada de long polling. Solo borra lo que se procesó (o era duplicado); el resto reaparece y acaba en la DLQ. */
    public int unaPasada() {
        var resp = sqs.receiveMessage(ReceiveMessageRequest.builder().queueUrl(colaUrl)
                .maxNumberOfMessages(10).waitTimeSeconds(20).build());
        int borrados = 0;
        for (Message m : resp.messages()) {
            try {
                consumidor.procesar(m.body());
                sqs.deleteMessage(DeleteMessageRequest.builder().queueUrl(colaUrl).receiptHandle(m.receiptHandle()).build());
                borrados++;
            } catch (Exception e) {
                // sin borrar: SQS lo reentrega tras el visibility timeout
            }
        }
        return borrados;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import java.io.IOException;
import java.nio.file.Files;
import java.time.Duration;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.sqs.SqsClient;

@Configuration
class ClaimCheckConfig {
    @Bean
    ProductorClaimCheck productor(S3Client s3, SqsClient sqs, @Value("${app.bucket}") String bucket,
                                  @Value("${app.prefijo}") String prefijo, @Value("${app.cola-url}") String cola) {
        return new ProductorClaimCheck(s3, sqs, bucket, prefijo, cola);
    }

    @Bean
    ConsumidorClaimCheck consumidor(S3Client s3, DynamoDbClient dynamo, @Value("${app.bucket}") String bucket,
                                    @Value("${app.prefijo}") String prefijo, @Value("${app.max-bytes}") long max,
                                    @Value("${app.tabla-idempotencia}") String tabla) {
        ConsumidorClaimCheck.Procesador negocio = (archivo, ticket) ->
                System.out.println("procesando " + ticket.correlacion() + " (" + Files.size(archivo) + " bytes)");
        return new ConsumidorClaimCheck(s3, new ValidadorTicket(Set.of(bucket), prefijo, max),
                new RegistroDynamo(dynamo, tabla), negocio, Duration.ofMinutes(10));
    }
}

@RestController
class DocumentosController {
    private final ProductorClaimCheck productor;

    DocumentosController(ProductorClaimCheck productor) {
        this.productor = productor;
    }

    /** El archivo llega al disco temporal y de ahí a S3; por la cola solo viaja el ticket. */
    @PostMapping("/documentos")
    Map<String, String> subir(@RequestParam("archivo") MultipartFile archivo,
                              @RequestParam("correlacion") String correlacion) throws IOException {
        var tmp = Files.createTempFile("doc-", ".tmp");
        try {
            archivo.transferTo(tmp);
            Ticket t = productor.publicar(tmp, archivo.getContentType(), correlacion);
            return Map.of("id", t.id(), "version", t.versionId());
        } finally {
            Files.deleteIfExists(tmp);
        }
    }
}

@org.springframework.stereotype.Component
class ColaListener {
    private final ConsumidorClaimCheck consumidor;

    ColaListener(ConsumidorClaimCheck consumidor) {
        this.consumidor = consumidor;
    }

    /** Si lanza excepción, Spring Cloud AWS NO borra el mensaje: reaparece y, tras N intentos, va a la DLQ. */
    @SqsListener("${app.cola-nombre}")
    void recibir(String cuerpo) throws Exception {
        consumidor.procesar(cuerpo);
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.springframework.http.MediaType;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class DocumentosReactivoController {
    private final ProductorClaimCheck productor;

    DocumentosReactivoController(ProductorClaimCheck productor) {
        this.productor = productor;
    }

    @PostMapping(value = "/documentos-r", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    Mono<Map<String, String>> subir(@RequestPart("archivo") FilePart parte) {
        return Mono.fromCallable(() -> java.nio.file.Files.createTempFile("doc-", ".tmp"))
                .subscribeOn(Schedulers.boundedElastic())
                .flatMap(tmp -> parte.transferTo(tmp)
                        .then(Mono.fromCallable(() -> productor.publicar(tmp, "application/pdf", "web"))
                                .subscribeOn(Schedulers.boundedElastic()))
                        .doFinally(s -> tmp.toFile().delete())
                        .map(t -> Map.of("id", t.id())));
    }
}

@Component
class ColaReactivaListener {
    private final ConsumidorClaimCheck consumidor;

    ColaReactivaListener(ConsumidorClaimCheck consumidor) {
        this.consumidor = consumidor;
    }

    /** Listener asíncrono: devuelve un CompletableFuture; el trabajo bloqueante va a boundedElastic. */
    @SqsListener("${app.cola-nombre}")
    CompletableFuture<Void> recibir(String cuerpo) {
        return Mono.fromCallable(() -> consumidor.procesar(cuerpo))
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
import java.time.Duration;
import java.util.Set;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.sqs.SqsClient;

@ApplicationScoped
class ClaimCheckProductores {
    @Produces
    @Singleton
    ProductorClaimCheck productor(S3Client s3, SqsClient sqs, @ConfigProperty(name = "app.bucket") String bucket,
                                  @ConfigProperty(name = "app.prefijo") String prefijo,
                                  @ConfigProperty(name = "app.cola-url") String cola) {
        return new ProductorClaimCheck(s3, sqs, bucket, prefijo, cola);
    }

    @Produces
    @Singleton
    ConsumidorClaimCheck consumidor(S3Client s3, DynamoDbClient dynamo, @ConfigProperty(name = "app.bucket") String bucket,
                                    @ConfigProperty(name = "app.prefijo") String prefijo,
                                    @ConfigProperty(name = "app.max-bytes") long max,
                                    @ConfigProperty(name = "app.tabla-idempotencia") String tabla) {
        ConsumidorClaimCheck.Procesador negocio = (archivo, ticket) ->
                System.out.println("procesando " + ticket.correlacion());
        return new ConsumidorClaimCheck(s3, new ValidadorTicket(Set.of(bucket), prefijo, max),
                new RegistroDynamo(dynamo, tabla), negocio, Duration.ofMinutes(10));
    }

    @Produces
    @Singleton
    PollerSqs poller(SqsClient sqs, @ConfigProperty(name = "app.cola-url") String cola, ConsumidorClaimCheck consumidor) {
        return new PollerSqs(sqs, cola, consumidor);
    }
}

/** Quarkus no trae @SqsListener: un planificador ejecuta el long polling sin solaparse. */
@ApplicationScoped
class ColaPlanificada {
    private final PollerSqs poller;

    ColaPlanificada(PollerSqs poller) {
        this.poller = poller;
    }

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void sondear() {
        poller.unaPasada();
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.io.IOException;
import java.util.Map;

@Path("/documentos")
class DocumentosRecurso {
    @Inject
    ProductorClaimCheck productor;

    /** Cuerpo binario crudo (application/pdf) guardado en un archivo temporal por el framework. */
    @POST
    @Consumes("application/pdf")
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, String> subir(java.io.File archivo, @QueryParam("correlacion") String correlacion) throws IOException {
        Ticket t = productor.publicar(archivo.toPath(), "application/pdf", correlacion);
        return Map.of("id", t.id(), "version", t.versionId());
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.time.Duration;

@ApplicationScoped
class ColaMutiny {
    private final PollerSqs poller;

    ColaMutiny(PollerSqs poller) {
        this.poller = poller;
    }

    /** Un sondeo cada 2 s sin solaparse: cada pasada es bloqueante, así que va al pool de trabajadores. */
    void iniciar(@Observes StartupEvent evento) {
        Multi.createFrom().ticks().every(Duration.ofSeconds(2))
                .onOverflow().drop()
                .onItem().transformToUniAndConcatenate(t ->
                        Uni.createFrom().item(poller::unaPasada).runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                                .onFailure().recoverWithItem(0))
                .subscribe().with(n -> { }, e -> { });
    }
}
```

## 7. Permisos
Productor: `s3:PutObject` (prefijo) y `sqs:SendMessage`. Consumidor: `s3:GetObject` + `s3:GetObjectVersion` (prefijo), `sqs:ReceiveMessage/DeleteMessage`, y `dynamodb:PutItem/UpdateItem/DeleteItem` sobre la tabla de idempotencia. Terraform en [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).

## 8. Qué NO hacer desde Java
- **No** publiques el ticket antes de que `putObject` termine.
- **No** confíes en el ticket: valida bucket, prefijo, tamaño y formato antes de tocar S3.
- **No** proceses sin comprobar tamaño y SHA-256 contra lo que dice el ticket.
- **No** marques como hecho antes de terminar: `completar` va después de `procesar`.
- **No** cargues el archivo entero en memoria: archivo temporal + streaming.
- **No** pongas URLs prefirmadas ni secretos en el ticket.
- **No** uses el `RegistroEnMemoria` en producción con más de una réplica.
