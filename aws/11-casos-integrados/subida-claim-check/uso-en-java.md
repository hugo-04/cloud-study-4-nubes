# AWS · Caso integrado · Subida con Claim Check · Uso desde Java

Se construye el corazón del caso: las **reglas de validación** (puras y fáciles de probar), la **máquina de estados**, el **validador idempotente** y el **reconciliador**. S3, DynamoDB y SQS quedan detrás de puertos con adaptadores finos.

| Pieza | Qué resuelve |
|---|---|
| `TipoArchivo`, `FirmaDeArchivo`, `ReglasDeSubida` | Qué se acepta, qué firma tiene cada formato, veredicto con motivo |
| `Estado` | Transiciones permitidas |
| `ServicioCargas` | Pedir subida (URL firmada), consultar estado, pedir descarga |
| `ValidadorDeCarga` + `ManejadorEventosS3` | Procesar el aviso de forma idempotente |
| `Reconciliador` | Reparar avisos perdidos y atascos |
| `FirmadorS3`, `AlmacenS3`, `RepositorioCargasDynamo` | Adaptadores del SDK |

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  task:
    scheduling:
      pool:
        size: 4
app:
  cargas:
    bucket-cuarentena: ${BUCKET_CUARENTENA}
    bucket-validadas: ${BUCKET_VALIDADAS}
    tabla: prod-cargas
    cola-validacion: ${COLA_VALIDACION}
```
```properties
# Quarkus (application.properties)
app.cargas.bucket-cuarentena=${BUCKET_CUARENTENA}
app.cargas.bucket-validadas=${BUCKET_VALIDADAS}
app.cargas.tabla=prod-cargas
app.cargas.cola-validacion=${COLA_VALIDACION}
quarkus.s3.sync-client.type=url-connection
quarkus.sqs.sync-client.type=url-connection
quarkus.dynamodb.sync-client.type=url-connection
```

## 2. Núcleo común

### 2.1 Modelo, estados y puertos
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

enum Estado {
    PENDIENTE, SUBIDO, VALIDADO, RECHAZADO, EXPIRADO;

    boolean puedePasarA(Estado destino) {
        return switch (this) {
            case PENDIENTE -> destino == SUBIDO || destino == EXPIRADO;
            case SUBIDO -> destino == VALIDADO || destino == RECHAZADO;
            default -> false;
        };
    }

    boolean esFinal() {
        return this == VALIDADO || this == RECHAZADO || this == EXPIRADO;
    }
}

record Carga(String id, String usuario, String nombre, String tipoDeclarado, long bytesDeclarados,
             Estado estado, Instant creada, Instant actualizada, String detalle) {}

record Cabecera(long bytes, String contentType) {}

enum Decision { BORRAR, DEJAR }

enum ResultadoValidacion { VALIDADA, RECHAZADA, YA_PROCESADA, DESCONOCIDA }

class CargaNoEncontrada extends RuntimeException {
    CargaNoEncontrada(String id) {
        super("carga no encontrada: " + id);
    }
}

interface RepositorioCargas {
    void crear(Carga carga);

    Optional<Carga> buscar(String id);

    /** Cambia el estado solo si sigue siendo «de». Devuelve false si otro proceso ya lo movió. */
    boolean transicionar(String id, Estado de, Estado a, String detalle, Instant ahora);

    List<Carga> porEstado(Estado estado, int max);
}

interface AlmacenObjetos {
    Optional<Cabecera> cabecera(String clave);

    byte[] primerosBytes(String clave, int n);

    /** Copia de cuarentena a validadas. Debe ser idempotente. */
    void copiarAValidadas(String claveCuarentena, String claveValidada);

    /** Borra de cuarentena; tolera que ya no exista. */
    void borrarDeCuarentena(String clave);
}

interface Firmador {
    String urlSubida(String clave, String contentType, long bytes, Duration validez);

    String urlDescarga(String clave, String nombreVisible, Duration validez);
}
```

### 2.2 Reglas de validación (puras)
La extensión y el `Content-Type` los elige quien sube; lo único que no miente (mucho) son los primeros bytes. Esto **no** es un antivirus: es un filtro de forma.
```java
// (clase reutilizada en los bloques siguientes, ambos)
enum TipoArchivo {
    PDF("application/pdf", 10L * 1024 * 1024),
    PNG("image/png", 5L * 1024 * 1024),
    JPEG("image/jpeg", 5L * 1024 * 1024),
    XLSX("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 10L * 1024 * 1024);

    final String mime;
    final long maxBytes;

    TipoArchivo(String mime, long maxBytes) {
        this.mime = mime;
        this.maxBytes = maxBytes;
    }

    static Optional<TipoArchivo> deMime(String mime) {
        for (var t : values()) {
            if (t.mime.equals(mime)) {
                return Optional.of(t);
            }
        }
        return Optional.empty();
    }
}

final class FirmaDeArchivo {
    private FirmaDeArchivo() {
    }

    static Optional<TipoArchivo> detectar(byte[] b) {
        if (empieza(b, '%', 'P', 'D', 'F', '-')) {
            return Optional.of(TipoArchivo.PDF);
        }
        if (empieza(b, 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A)) {
            return Optional.of(TipoArchivo.PNG);
        }
        if (empieza(b, 0xFF, 0xD8, 0xFF)) {
            return Optional.of(TipoArchivo.JPEG);
        }
        if (empieza(b, 'P', 'K', 0x03, 0x04)) {
            return Optional.of(TipoArchivo.XLSX); // todo ZIP empieza así: es un primer filtro, no una prueba
        }
        return Optional.empty();
    }

    private static boolean empieza(byte[] b, int... esperado) {
        if (b == null || b.length < esperado.length) {
            return false;
        }
        for (int i = 0; i < esperado.length; i++) {
            if ((b[i] & 0xFF) != esperado[i]) {
                return false;
            }
        }
        return true;
    }
}

record Veredicto(boolean aceptada, String motivo) {
    static Veredicto ok() {
        return new Veredicto(true, null);
    }

    static Veredicto rechazo(String motivo) {
        return new Veredicto(false, motivo);
    }
}

final class ReglasDeSubida {
    private ReglasDeSubida() {
    }

    static Veredicto evaluar(TipoArchivo declarado, long bytesReales, long bytesDeclarados, byte[] cabeza) {
        if (bytesReales <= 0) {
            return Veredicto.rechazo("VACIO");
        }
        if (bytesReales > declarado.maxBytes) {
            return Veredicto.rechazo("EXCEDE_TAMANO");
        }
        if (bytesReales != bytesDeclarados) {
            return Veredicto.rechazo("TAMANO_DISTINTO");
        }
        var detectado = FirmaDeArchivo.detectar(cabeza);
        if (detectado.isEmpty() || detectado.get() != declarado) {
            return Veredicto.rechazo("FIRMA_NO_COINCIDE");
        }
        return Veredicto.ok();
    }

    /** Nombre para mostrar: sin rutas, sin caracteres de control, acotado. Nunca se usa como clave del objeto. */
    static String nombreSeguro(String nombre) {
        String n = nombre == null ? "" : nombre;
        n = n.substring(Math.max(n.lastIndexOf('/'), n.lastIndexOf('\\')) + 1);
        n = n.replaceAll("[\\p{Cntrl}\"]", "").trim();
        if (n.length() > 100) {
            n = n.substring(n.length() - 100);
        }
        return n.isEmpty() ? "archivo" : n;
    }
}

final class Claves {
    private static final java.util.regex.Pattern ID = java.util.regex.Pattern.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    private Claves() {
    }

    static String cuarentena(String id) {
        return "entrada/" + id;
    }

    static String validada(String id) {
        return "archivos/" + id;
    }

    static Optional<String> idDe(String claveCuarentena) {
        if (!claveCuarentena.startsWith("entrada/")) {
            return Optional.empty();
        }
        String id = claveCuarentena.substring("entrada/".length());
        return ID.matcher(id).matches() ? Optional.of(id) : Optional.empty();
    }
}
```

### 2.3 Pedir subida, consultar y descargar
Se registra la carga **antes** de firmar: si firmar falla, queda una carga `PENDIENTE` que el reconciliador expirará. Al revés, habría una URL válida sin registro.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.util.UUID;
import java.util.function.Supplier;

record SolicitudSubida(String idCarga, String urlSubida, String contentType, Instant vence) {}

final class ServicioCargas {
    static final Duration VALIDEZ_URL = Duration.ofMinutes(5);

    private final RepositorioCargas repositorio;
    private final Firmador firmador;
    private final Clock reloj;
    private final Supplier<String> ids;

    ServicioCargas(RepositorioCargas repositorio, Firmador firmador, Clock reloj, Supplier<String> ids) {
        this.repositorio = repositorio;
        this.firmador = firmador;
        this.reloj = reloj;
        this.ids = ids;
    }

    ServicioCargas(RepositorioCargas repositorio, Firmador firmador) {
        this(repositorio, firmador, Clock.systemUTC(), () -> UUID.randomUUID().toString());
    }

    SolicitudSubida solicitar(String usuario, String nombre, String mime, long bytes) {
        var tipo = TipoArchivo.deMime(mime).orElseThrow(() -> new IllegalArgumentException("tipo no permitido: " + mime));
        if (bytes <= 0 || bytes > tipo.maxBytes) {
            throw new IllegalArgumentException("tamaño fuera de rango (máximo " + tipo.maxBytes + ")");
        }
        var ahora = reloj.instant();
        var id = ids.get();
        repositorio.crear(new Carga(id, usuario, ReglasDeSubida.nombreSeguro(nombre), mime, bytes, Estado.PENDIENTE, ahora, ahora, null));
        var url = firmador.urlSubida(Claves.cuarentena(id), mime, bytes, VALIDEZ_URL);
        return new SolicitudSubida(id, url, mime, ahora.plus(VALIDEZ_URL));
    }

    Carga estado(String usuario, String id) {
        return repositorio.buscar(id).filter(c -> c.usuario().equals(usuario)).orElseThrow(() -> new CargaNoEncontrada(id));
    }

    String urlDescarga(String usuario, String id) {
        var carga = estado(usuario, id);
        if (carga.estado() != Estado.VALIDADO) {
            throw new IllegalStateException("aún no disponible: " + carga.estado());
        }
        return firmador.urlDescarga(Claves.validada(id), carga.nombre(), VALIDEZ_URL);
    }
}
```

### 2.4 El validador (idempotente y reintentable)
Orden seguro: **copiar → transición condicional → borrar**. Si el proceso muere después de copiar, el reintento copia de nuevo (idempotente) y sigue. Si muere antes de borrar, la regla de ciclo de vida limpia la cuarentena.
```java
// (clase reutilizada en los bloques siguientes, ambos)
final class ValidadorDeCarga {
    private final RepositorioCargas repositorio;
    private final AlmacenObjetos almacen;
    private final Clock reloj;

    ValidadorDeCarga(RepositorioCargas repositorio, AlmacenObjetos almacen, Clock reloj) {
        this.repositorio = repositorio;
        this.almacen = almacen;
        this.reloj = reloj;
    }

    ResultadoValidacion procesar(String idCarga) {
        var carga = repositorio.buscar(idCarga).orElse(null);
        if (carga == null) {
            return ResultadoValidacion.DESCONOCIDA;
        }
        if (carga.estado().esFinal()) {
            return ResultadoValidacion.YA_PROCESADA;
        }
        if (carga.estado() == Estado.PENDIENTE && !repositorio.transicionar(idCarga, Estado.PENDIENTE, Estado.SUBIDO, null, reloj.instant())) {
            return ResultadoValidacion.YA_PROCESADA; // otro proceso se adelantó
        }
        String clave = Claves.cuarentena(idCarga);
        var cabecera = almacen.cabecera(clave).orElseThrow(() -> new IllegalStateException("el objeto aún no está en cuarentena: " + clave));
        var tipo = TipoArchivo.deMime(carga.tipoDeclarado()).orElseThrow();
        var veredicto = ReglasDeSubida.evaluar(tipo, cabecera.bytes(), carga.bytesDeclarados(), almacen.primerosBytes(clave, 16));
        if (veredicto.aceptada()) {
            almacen.copiarAValidadas(clave, Claves.validada(idCarga));
            if (!repositorio.transicionar(idCarga, Estado.SUBIDO, Estado.VALIDADO, null, reloj.instant())) {
                return ResultadoValidacion.YA_PROCESADA;
            }
            almacen.borrarDeCuarentena(clave);
            return ResultadoValidacion.VALIDADA;
        }
        if (!repositorio.transicionar(idCarga, Estado.SUBIDO, Estado.RECHAZADO, veredicto.motivo(), reloj.instant())) {
            return ResultadoValidacion.YA_PROCESADA;
        }
        almacen.borrarDeCuarentena(clave);
        return ResultadoValidacion.RECHAZADA;
    }
}
```

### 2.5 Leer el aviso de S3 y decidir
Lo ajeno al prefijo esperado se **borra** de la cola (no es para nosotros); lo ilegible o con error se **deja** para que SQS reintente y termine en la DLQ.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;

record ObjetoCreado(String bucket, String clave, long bytes) {}

final class LectorEventoS3 {
    private LectorEventoS3() {
    }

    static ObjetoCreado leer(String cuerpo) {
        try {
            JsonNode raiz = JsonNodeParser.create().parse(cuerpo);
            if (!raiz.isObject()) {
                throw new IllegalArgumentException("no es un objeto");
            }
            var o = raiz.asObject();
            if (!"aws.s3".equals(texto(o, "source")) || !"Object Created".equals(texto(o, "detail-type"))) {
                throw new IllegalArgumentException("no es un 'Object Created' de S3");
            }
            var d = objeto(o, "detail");
            var bucket = texto(objeto(d, "bucket"), "name");
            var obj = objeto(d, "object");
            return new ObjetoCreado(bucket, texto(obj, "key"), Long.parseLong(numero(obj, "size")));
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("evento ilegible", e);
        }
    }

    private static Map<String, JsonNode> objeto(Map<String, JsonNode> m, String clave) {
        JsonNode n = m.get(clave);
        if (n == null || !n.isObject()) {
            throw new IllegalArgumentException("falta " + clave);
        }
        return n.asObject();
    }

    private static String texto(Map<String, JsonNode> m, String clave) {
        JsonNode n = m.get(clave);
        if (n == null || !n.isString()) {
            throw new IllegalArgumentException("falta texto " + clave);
        }
        return n.asString();
    }

    private static String numero(Map<String, JsonNode> m, String clave) {
        JsonNode n = m.get(clave);
        if (n == null || !n.isNumber()) {
            throw new IllegalArgumentException("falta número " + clave);
        }
        return n.asNumber();
    }
}

final class ManejadorEventosS3 {
    private final ValidadorDeCarga validador;
    private final String bucketEsperado;

    ManejadorEventosS3(ValidadorDeCarga validador, String bucketEsperado) {
        this.validador = validador;
        this.bucketEsperado = bucketEsperado;
    }

    Decision manejar(String cuerpo) {
        ObjetoCreado evento;
        try {
            evento = LectorEventoS3.leer(cuerpo);
        } catch (IllegalArgumentException e) {
            return Decision.DEJAR;
        }
        if (!bucketEsperado.equals(evento.bucket())) {
            return Decision.BORRAR;
        }
        var id = Claves.idDe(evento.clave());
        if (id.isEmpty()) {
            return Decision.BORRAR;
        }
        try {
            validador.procesar(id.get());
            return Decision.BORRAR;
        } catch (RuntimeException e) {
            return Decision.DEJAR;
        }
    }
}
```

### 2.6 El reconciliador
Los eventos son **avisos**, no la verdad. Cada minuto: las `PENDIENTE` cuya URL ya venció se contrastan con S3 (si el objeto está, se revalida; si no, `EXPIRADO`) y las `SUBIDO` atascadas se reprocesan.
```java
// (clase reutilizada en los bloques siguientes, ambos)
record ResumenReconciliacion(int expiradas, int revalidadas, int errores) {}

final class Reconciliador {
    private final RepositorioCargas repositorio;
    private final AlmacenObjetos almacen;
    private final ValidadorDeCarga validador;
    private final Clock reloj;
    private final Duration gracia;

    Reconciliador(RepositorioCargas repositorio, AlmacenObjetos almacen, ValidadorDeCarga validador, Clock reloj, Duration gracia) {
        this.repositorio = repositorio;
        this.almacen = almacen;
        this.validador = validador;
        this.reloj = reloj;
        this.gracia = gracia;
    }

    ResumenReconciliacion ejecutar() {
        var ahora = reloj.instant();
        int expiradas = 0;
        int revalidadas = 0;
        int errores = 0;
        for (var c : repositorio.porEstado(Estado.PENDIENTE, 100)) {
            if (c.creada().plus(ServicioCargas.VALIDEZ_URL).plus(gracia).isAfter(ahora)) {
                continue;
            }
            try {
                if (almacen.cabecera(Claves.cuarentena(c.id())).isPresent()) {
                    validador.procesar(c.id());
                    revalidadas++;
                } else if (repositorio.transicionar(c.id(), Estado.PENDIENTE, Estado.EXPIRADO, "URL vencida sin subida", ahora)) {
                    expiradas++;
                }
            } catch (RuntimeException e) {
                errores++;
            }
        }
        for (var c : repositorio.porEstado(Estado.SUBIDO, 100)) {
            if (c.actualizada().plus(gracia).isAfter(ahora)) {
                continue;
            }
            try {
                validador.procesar(c.id());
                revalidadas++;
            } catch (RuntimeException e) {
                errores++;
            }
        }
        return new ResumenReconciliacion(expiradas, revalidadas, errores);
    }
}
```

### 2.7 Adaptadores del SDK
El `Content-Length` y el `Content-Type` van dentro de la solicitud que se firma: son cabeceras firmadas, y S3 rechaza la subida si no coinciden. El rango `bytes=0-15` evita descargar el archivo entero para mirar su firma.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.dynamodb.model.QueryRequest;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CopyObjectRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

final class FirmadorS3 implements Firmador {
    private final S3Presigner presigner;
    private final String bucketCuarentena;
    private final String bucketValidadas;

    FirmadorS3(S3Presigner presigner, String bucketCuarentena, String bucketValidadas) {
        this.presigner = presigner;
        this.bucketCuarentena = bucketCuarentena;
        this.bucketValidadas = bucketValidadas;
    }

    @Override
    public String urlSubida(String clave, String contentType, long bytes, Duration validez) {
        var put = PutObjectRequest.builder().bucket(bucketCuarentena).key(clave).contentType(contentType).contentLength(bytes).build();
        return presigner.presignPutObject(PutObjectPresignRequest.builder().signatureDuration(validez).putObjectRequest(put).build())
                .url().toString();
    }

    @Override
    public String urlDescarga(String clave, String nombreVisible, Duration validez) {
        var get = GetObjectRequest.builder().bucket(bucketValidadas).key(clave)
                .responseContentDisposition("attachment; filename=\"" + nombreVisible + "\"").build();
        return presigner.presignGetObject(GetObjectPresignRequest.builder().signatureDuration(validez).getObjectRequest(get).build())
                .url().toString();
    }
}

final class AlmacenS3 implements AlmacenObjetos {
    private final S3Client s3;
    private final String cuarentena;
    private final String validadas;

    AlmacenS3(S3Client s3, String cuarentena, String validadas) {
        this.s3 = s3;
        this.cuarentena = cuarentena;
        this.validadas = validadas;
    }

    @Override
    public Optional<Cabecera> cabecera(String clave) {
        try {
            var h = s3.headObject(HeadObjectRequest.builder().bucket(cuarentena).key(clave).build());
            return Optional.of(new Cabecera(h.contentLength(), h.contentType()));
        } catch (S3Exception e) {
            if (e.statusCode() == 404) {
                return Optional.empty();
            }
            throw e;
        }
    }

    @Override
    public byte[] primerosBytes(String clave, int n) {
        return s3.getObjectAsBytes(GetObjectRequest.builder().bucket(cuarentena).key(clave).range("bytes=0-" + (n - 1)).build()).asByteArray();
    }

    @Override
    public void copiarAValidadas(String claveCuarentena, String claveValidada) {
        s3.copyObject(CopyObjectRequest.builder()
                .sourceBucket(cuarentena).sourceKey(claveCuarentena)
                .destinationBucket(validadas).destinationKey(claveValidada).build());
    }

    @Override
    public void borrarDeCuarentena(String clave) {
        s3.deleteObject(DeleteObjectRequest.builder().bucket(cuarentena).key(clave).build());
    }
}

final class RepositorioCargasDynamo implements RepositorioCargas {
    private final DynamoDbClient dynamo;
    private final String tabla;

    RepositorioCargasDynamo(DynamoDbClient dynamo, String tabla) {
        this.dynamo = dynamo;
        this.tabla = tabla;
    }

    @Override
    public void crear(Carga c) {
        var item = new java.util.HashMap<String, AttributeValue>();
        item.put("id", s(c.id()));
        item.put("usuario", s(c.usuario()));
        item.put("nombre", s(c.nombre()));
        item.put("tipo", s(c.tipoDeclarado()));
        item.put("bytes", AttributeValue.builder().n(Long.toString(c.bytesDeclarados())).build());
        item.put("estado", s(c.estado().name()));
        item.put("creada", s(c.creada().toString()));
        item.put("actualizada", s(c.actualizada().toString()));
        dynamo.putItem(PutItemRequest.builder().tableName(tabla).item(item).conditionExpression("attribute_not_exists(id)").build());
    }

    @Override
    public Optional<Carga> buscar(String id) {
        var r = dynamo.getItem(GetItemRequest.builder().tableName(tabla).key(Map.of("id", s(id))).consistentRead(true).build());
        return r.hasItem() && !r.item().isEmpty() ? Optional.of(aCarga(r.item())) : Optional.empty();
    }

    @Override
    public boolean transicionar(String id, Estado de, Estado a, String detalle, Instant ahora) {
        if (!de.puedePasarA(a)) {
            throw new IllegalArgumentException("transición no permitida: " + de + " → " + a);
        }
        var valores = new java.util.HashMap<String, AttributeValue>();
        valores.put(":de", s(de.name()));
        valores.put(":a", s(a.name()));
        valores.put(":ahora", s(ahora.toString()));
        String expresion = "SET estado = :a, actualizada = :ahora";
        if (detalle != null) {
            expresion += ", detalle = :detalle";
            valores.put(":detalle", s(detalle));
        }
        if (a.esFinal()) {
            expresion += ", expira = :expira";
            valores.put(":expira", AttributeValue.builder().n(Long.toString(ahora.plus(Duration.ofDays(90)).getEpochSecond())).build());
        }
        try {
            dynamo.updateItem(UpdateItemRequest.builder().tableName(tabla).key(Map.of("id", s(id)))
                    .conditionExpression("estado = :de").updateExpression(expresion).expressionAttributeValues(valores).build());
            return true;
        } catch (ConditionalCheckFailedException e) {
            return false;
        }
    }

    @Override
    public List<Carga> porEstado(Estado estado, int max) {
        var r = dynamo.query(QueryRequest.builder().tableName(tabla).indexName("por-estado")
                .keyConditionExpression("estado = :e").expressionAttributeValues(Map.of(":e", s(estado.name()))).limit(max).build());
        return r.items().stream().map(RepositorioCargasDynamo::aCarga).toList();
    }

    private static Carga aCarga(Map<String, AttributeValue> i) {
        return new Carga(i.get("id").s(), i.get("usuario").s(), i.get("nombre").s(), i.get("tipo").s(), Long.parseLong(i.get("bytes").n()),
                Estado.valueOf(i.get("estado").s()), Instant.parse(i.get("creada").s()), Instant.parse(i.get("actualizada").s()),
                i.containsKey("detalle") ? i.get("detalle").s() : null);
    }

    private static AttributeValue s(String v) {
        return AttributeValue.builder().s(v).build();
    }
}
```

### 2.8 Sondeo de SQS
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.function.Function;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.DeleteMessageBatchRequest;
import software.amazon.awssdk.services.sqs.model.DeleteMessageBatchRequestEntry;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;

final class SondeoSqs {
    private final SqsClient sqs;
    private final String urlCola;
    private final Function<String, Decision> manejador;

    SondeoSqs(SqsClient sqs, String urlCola, Function<String, Decision> manejador) {
        this.sqs = sqs;
        this.urlCola = urlCola;
        this.manejador = manejador;
    }

    /** Una vuelta de sondeo largo; devuelve cuántos mensajes se borraron. */
    int sondear() {
        var mensajes = sqs.receiveMessage(ReceiveMessageRequest.builder().queueUrl(urlCola).maxNumberOfMessages(10).waitTimeSeconds(20).build()).messages();
        var aBorrar = new ArrayList<DeleteMessageBatchRequestEntry>();
        for (int i = 0; i < mensajes.size(); i++) {
            if (manejador.apply(mensajes.get(i).body()) == Decision.BORRAR) {
                aBorrar.add(DeleteMessageBatchRequestEntry.builder().id("m" + i).receiptHandle(mensajes.get(i).receiptHandle()).build());
            }
        }
        if (!aBorrar.isEmpty()) {
            sqs.deleteMessageBatch(DeleteMessageBatchRequest.builder().queueUrl(urlCola).entries(aBorrar).build());
        }
        return aBorrar.size();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.security.Principal;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
@EnableScheduling
class CargasConfig {
    @Bean(destroyMethod = "close")
    S3Client s3() {
        return S3Client.create();
    }

    @Bean(destroyMethod = "close")
    S3Presigner presigner() {
        return S3Presigner.create();
    }

    @Bean(destroyMethod = "close")
    DynamoDbClient dynamo() {
        return DynamoDbClient.create();
    }

    @Bean(destroyMethod = "close")
    SqsClient sqs() {
        return SqsClient.create();
    }

    @Bean
    RepositorioCargas repositorio(DynamoDbClient dynamo, @Value("${app.cargas.tabla}") String tabla) {
        return new RepositorioCargasDynamo(dynamo, tabla);
    }

    @Bean
    AlmacenObjetos almacen(S3Client s3, @Value("${app.cargas.bucket-cuarentena}") String c, @Value("${app.cargas.bucket-validadas}") String v) {
        return new AlmacenS3(s3, c, v);
    }

    @Bean
    ServicioCargas servicio(RepositorioCargas repo, S3Presigner presigner, @Value("${app.cargas.bucket-cuarentena}") String c,
                            @Value("${app.cargas.bucket-validadas}") String v) {
        return new ServicioCargas(repo, new FirmadorS3(presigner, c, v));
    }

    @Bean
    ValidadorDeCarga validador(RepositorioCargas repo, AlmacenObjetos almacen) {
        return new ValidadorDeCarga(repo, almacen, Clock.systemUTC());
    }

    @Bean
    Reconciliador reconciliador(RepositorioCargas repo, AlmacenObjetos almacen, ValidadorDeCarga validador) {
        return new Reconciliador(repo, almacen, validador, Clock.systemUTC(), Duration.ofMinutes(2));
    }

    @Bean
    SondeoSqs sondeo(SqsClient sqs, ValidadorDeCarga validador, @Value("${app.cargas.cola-validacion}") String cola,
                     @Value("${app.cargas.bucket-cuarentena}") String bucket) {
        return new SondeoSqs(sqs, cola, new ManejadorEventosS3(validador, bucket)::manejar);
    }
}

record PeticionSubida(String nombre, String tipo, long bytes) {}

@RestController
@RequestMapping("/cargas")
class CargasController {
    private final ServicioCargas servicio;

    CargasController(ServicioCargas servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    ResponseEntity<SolicitudSubida> pedir(Principal usuario, @RequestBody PeticionSubida p) {
        return ResponseEntity.status(201).body(servicio.solicitar(usuario.getName(), p.nombre(), p.tipo(), p.bytes()));
    }

    @GetMapping("/{id}")
    Map<String, String> estado(Principal usuario, @PathVariable String id) {
        var c = servicio.estado(usuario.getName(), id);
        return Map.of("estado", c.estado().name(), "detalle", c.detalle() == null ? "" : c.detalle());
    }

    @GetMapping("/{id}/descarga")
    Map<String, String> descarga(Principal usuario, @PathVariable String id) {
        return Map.of("url", servicio.urlDescarga(usuario.getName(), id));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> invalido(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(CargaNoEncontrada.class)
    ResponseEntity<Void> noEncontrada() {
        return ResponseEntity.notFound().build();
    }

    @ExceptionHandler(IllegalStateException.class)
    ResponseEntity<Map<String, String>> noDisponible(IllegalStateException e) {
        return ResponseEntity.status(409).body(Map.of("error", e.getMessage()));
    }
}

@Component
class TareasDeCargas {
    private final SondeoSqs sondeo;
    private final Reconciliador reconciliador;

    TareasDeCargas(SondeoSqs sondeo, Reconciliador reconciliador) {
        this.sondeo = sondeo;
        this.reconciliador = reconciliador;
    }

    @Scheduled(fixedDelay = 100)
    void validar() {
        sondeo.sondear();
    }

    @Scheduled(fixedDelay = 60_000)
    void reconciliar() {
        reconciliador.ejecutar();
    }
}
```

## 4. Spring WebFlux (reactivo)
Las llamadas al SDK síncrono y DynamoDB van a `boundedElastic`. Firmar una URL es cálculo local, pero el registro en DynamoDB es red: todo el servicio se envuelve.
```java
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.security.Principal;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.Disposable;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

record PeticionSubidaV2(String nombre, String tipo, long bytes) {}

@RestController
@RequestMapping("/v2/cargas")
class CargasReactivoController {
    private final ServicioCargas servicio;

    CargasReactivoController(ServicioCargas servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    Mono<ResponseEntity<Object>> pedir(Principal usuario, @RequestBody PeticionSubidaV2 p) {
        return Mono.fromCallable(() -> servicio.solicitar(usuario.getName(), p.nombre(), p.tipo(), p.bytes()))
                .subscribeOn(Schedulers.boundedElastic())
                .<ResponseEntity<Object>>map(s -> ResponseEntity.status(201).body(s))
                .onErrorResume(IllegalArgumentException.class, e -> Mono.just(ResponseEntity.badRequest().body(Map.of("error", e.getMessage()))));
    }

    @GetMapping("/{id}/descarga")
    Mono<ResponseEntity<Object>> descarga(Principal usuario, @PathVariable String id) {
        return Mono.fromCallable(() -> servicio.urlDescarga(usuario.getName(), id))
                .subscribeOn(Schedulers.boundedElastic())
                .<ResponseEntity<Object>>map(url -> ResponseEntity.ok(Map.of("url", url)))
                .onErrorResume(CargaNoEncontrada.class, e -> Mono.just(ResponseEntity.notFound().build()))
                .onErrorResume(IllegalStateException.class, e -> Mono.just(ResponseEntity.status(409).body(Map.of("error", e.getMessage()))));
    }
}

@Component
class BucleReactivoDeCargas {
    private final SondeoSqs sondeo;
    private final Reconciliador reconciliador;
    private Disposable validacion;
    private Disposable reconciliacion;

    BucleReactivoDeCargas(SondeoSqs sondeo, Reconciliador reconciliador) {
        this.sondeo = sondeo;
        this.reconciliador = reconciliador;
    }

    @PostConstruct
    void iniciar() {
        validacion = Mono.fromCallable(sondeo::sondear)
                .subscribeOn(Schedulers.boundedElastic())
                .onErrorResume(e -> Mono.delay(java.time.Duration.ofSeconds(2)).thenReturn(0))
                .repeat()
                .subscribe();
        reconciliacion = Flux.interval(java.time.Duration.ofMinutes(1))
                .onBackpressureDrop()
                .concatMap(t -> Mono.fromCallable(reconciliador::ejecutar).subscribeOn(Schedulers.boundedElastic()).onErrorResume(e -> Mono.empty()), 1)
                .subscribe();
    }

    @PreDestroy
    void detener() {
        validacion.dispose();
        reconciliacion.dispose();
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class CargasProductores {
    @jakarta.enterprise.inject.Produces
    @Singleton
    S3Presigner presigner() {
        return S3Presigner.create();
    }

    void cerrar(@Disposes S3Presigner presigner) {
        presigner.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    RepositorioCargas repositorio(DynamoDbClient dynamo, @ConfigProperty(name = "app.cargas.tabla") String tabla) {
        return new RepositorioCargasDynamo(dynamo, tabla);
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    AlmacenObjetos almacen(S3Client s3, @ConfigProperty(name = "app.cargas.bucket-cuarentena") String c,
                           @ConfigProperty(name = "app.cargas.bucket-validadas") String v) {
        return new AlmacenS3(s3, c, v);
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioCargas servicio(RepositorioCargas repo, S3Presigner presigner, @ConfigProperty(name = "app.cargas.bucket-cuarentena") String c,
                            @ConfigProperty(name = "app.cargas.bucket-validadas") String v) {
        return new ServicioCargas(repo, new FirmadorS3(presigner, c, v));
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ValidadorDeCarga validador(RepositorioCargas repo, AlmacenObjetos almacen) {
        return new ValidadorDeCarga(repo, almacen, Clock.systemUTC());
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    Reconciliador reconciliador(RepositorioCargas repo, AlmacenObjetos almacen, ValidadorDeCarga validador) {
        return new Reconciliador(repo, almacen, validador, Clock.systemUTC(), Duration.ofMinutes(2));
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    SondeoSqs sondeo(SqsClient sqs, ValidadorDeCarga validador, @ConfigProperty(name = "app.cargas.cola-validacion") String cola,
                     @ConfigProperty(name = "app.cargas.bucket-cuarentena") String bucket) {
        return new SondeoSqs(sqs, cola, new ManejadorEventosS3(validador, bucket)::manejar);
    }
}
```
```java
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.SecurityContext;

record PeticionSubidaQ(String nombre, String tipo, long bytes) {}

@Path("/cargas")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class CargasResource {
    @Inject
    ServicioCargas servicio;

    @POST
    public Response pedir(@Context SecurityContext sc, PeticionSubidaQ p) {
        try {
            return Response.status(201).entity(servicio.solicitar(sc.getUserPrincipal().getName(), p.nombre(), p.tipo(), p.bytes())).build();
        } catch (IllegalArgumentException e) {
            return Response.status(400).entity(Map.of("error", e.getMessage())).build();
        }
    }

    @GET
    @Path("/{id}/descarga")
    public Response descarga(@Context SecurityContext sc, @PathParam("id") String id) {
        try {
            return Response.ok(Map.of("url", servicio.urlDescarga(sc.getUserPrincipal().getName(), id))).build();
        } catch (CargaNoEncontrada e) {
            return Response.status(404).build();
        } catch (IllegalStateException e) {
            return Response.status(409).entity(Map.of("error", e.getMessage())).build();
        }
    }
}

@ApplicationScoped
class TareasQuarkusCargas {
    @Inject
    SondeoSqs sondeo;
    @Inject
    Reconciliador reconciliador;

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void validar() {
        sondeo.sondear();
    }

    @Scheduled(every = "60s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void reconciliar() {
        reconciliador.ejecutar();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.quarkus.scheduler.Scheduled;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.SecurityContext;

record PeticionSubidaM(String nombre, String tipo, long bytes) {}

@Path("/v2/cargas")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class CargasMutinyResource {
    @Inject
    ServicioCargas servicio;

    @POST
    public Uni<Response> pedir(@Context SecurityContext sc, PeticionSubidaM p) {
        String usuario = sc.getUserPrincipal().getName();
        return Uni.createFrom().item(() -> servicio.solicitar(usuario, p.nombre(), p.tipo(), p.bytes()))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(s -> Response.status(201).entity(s).build())
                .onFailure(IllegalArgumentException.class).recoverWithItem(e -> Response.status(400).entity(Map.of("error", e.getMessage())).build());
    }

    @GET
    @Path("/{id}/descarga")
    public Uni<Response> descarga(@Context SecurityContext sc, @PathParam("id") String id) {
        String usuario = sc.getUserPrincipal().getName();
        return Uni.createFrom().item(() -> servicio.urlDescarga(usuario, id))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(url -> Response.ok(Map.of("url", url)).build())
                .onFailure(CargaNoEncontrada.class).recoverWithItem(e -> Response.status(404).build())
                .onFailure(IllegalStateException.class).recoverWithItem(e -> Response.status(409).entity(Map.of("error", e.getMessage())).build());
    }
}

@ApplicationScoped
class TareasMutinyCargas {
    @Inject
    SondeoSqs sondeo;
    @Inject
    Reconciliador reconciliador;

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    Uni<Void> validar() {
        return Uni.createFrom().item(sondeo::sondear).runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .onFailure().recoverWithItem(0).replaceWithVoid();
    }

    @Scheduled(every = "60s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    Uni<Void> reconciliar() {
        return Uni.createFrom().item(reconciliador::ejecutar).runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .onFailure().recoverWithItem(new ResumenReconciliacion(0, 0, 1)).replaceWithVoid();
    }
}
```

## 7. Permisos
| Servicio | Acciones | Recurso |
|---|---|---|
| API de solicitudes | `s3:PutObject` (para firmar) | `…cuarentena/entrada/*` |
| API de solicitudes | `s3:GetObject` (para firmar) | `…validadas/archivos/*` |
| API de solicitudes | `dynamodb:PutItem`, `GetItem` | tabla `prod-cargas` |
| Validador | `s3:GetObject`, `s3:DeleteObject` | `…cuarentena/entrada/*` |
| Validador | `s3:PutObject` | `…validadas/archivos/*` |
| Validador | `sqs:ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility` | cola `prod-validacion` |
| Validador | `dynamodb:GetItem`, `UpdateItem`, `Query` | tabla y índice `por-estado` |

Importante: una URL prefirmada **hereda** los permisos de quien la firmó; por eso el rol de la API tiene `PutObject` solo en `entrada/*` y las credenciales de corta vida (rol de tarea) limitan la vida real de la URL.

## 8. Qué NO hacer desde Java
- No uses el nombre del archivo del cliente como clave del objeto.
- No confíes en `Content-Type` ni en la extensión; mira los primeros bytes (y usa un escáner si el riesgo lo exige).
- No borres de cuarentena antes de la transición de estado.
- No firmes URLs de larga vida ni las guardes en la base: se generan bajo demanda.
- No dejes que un id ajeno revele si existe: responde 404.
- No hagas `Scan` de la tabla para el reconciliador: usa el índice `por-estado`.
- No ejecutes el SDK síncrono en el bucle de eventos de WebFlux/Vert.x.
