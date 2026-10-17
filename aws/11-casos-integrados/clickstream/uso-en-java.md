# AWS · Caso integrado · Clickstream · Uso desde Java

Se construye lo que Kinesis **no** hace por ti: dimensionar, elegir bien la clave, validar y seudonimizar en la puerta, escribir por lotes con reintento parcial, y leer con **ventanas, marca de agua y checkpoint seguro**. Todo el núcleo es puro y se prueba sin red.

| Pieza | Qué resuelve |
|---|---|
| `DimensionadorDeStream`, `RepartoDeClaves` | Cuántos shards y si la clave reparte parejo |
| `Seudonimizador`, `CodificadorDeClics`, `ServicioDeIngesta` | Validar, recortar el reloj del cliente, seudonimizar y enviar |
| `ProductorDeClics` | `PutRecords` por lotes (500 / 5 MiB) reintentando solo los fallidos |
| `AgregadorDeVentanas`, `ProcesadorDeLote` | Ventanas por hora del evento, duplicados, tardíos, punto seguro |
| `LectorDeShards`, `CheckpointsDynamo`, `RepositorioMetricasDynamo`, `TrabajadorDeClics` | Leer, escribir métricas idempotentes y hacer checkpoint |

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  task:
    scheduling:
      pool:
        size: 2
app:
  clics:
    stream: prod-clics
    tabla-metricas: prod-metricas-clics
    tabla-checkpoints: prod-checkpoints-clics
    secreto: ${SECRETO_SESION}      # inyectado desde Secrets Manager por la definición de tarea
```
```properties
# Quarkus (application.properties)
app.clics.stream=prod-clics
app.clics.tabla-metricas=prod-metricas-clics
app.clics.tabla-checkpoints=prod-checkpoints-clics
app.clics.secreto=${SECRETO_SESION}
quarkus.kinesis.sync-client.type=url-connection
quarkus.dynamodb.sync-client.type=url-connection
```

## 2. Núcleo común

### 2.1 Modelo y puertos
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.List;
import java.util.Optional;

record Clic(String idEvento, String idSesion, String pagina, String tipo, Instant instante) {}

record Registro(String secuencia, byte[] datos) {}

record MetricaVentana(Instant inicio, String pagina, String tipo, long clics, long sesionesUnicas) {}

record ResumenLote(int procesados, int invalidos, int duplicados, int tardios, List<MetricaVentana> cerradas) {}

record ResultadoEnvio(int enviados, List<Clic> fallidos) {}

record LoteLeido(List<Registro> registros, long milisDetras) {}

interface PuertoEnvio {
    ResultadoEnvio enviar(List<Clic> clics);
}

interface Checkpoints {
    Optional<String> ultimo(String shard);

    void guardar(String shard, String secuencia);
}

interface RepositorioMetricas {
    void guardar(String shard, List<MetricaVentana> metricas);
}

interface Pausa {
    void esperar(long millis);
}
```

### 2.2 Dimensionar y comprobar el reparto de claves
Un shard admite ~1 MiB/s **o** 1000 registros/s de escritura y ~2 MiB/s de lectura **compartida** entre los consumidores clásicos. El número de shards es el mayor de los tres límites, con margen. Aparte, una buena cantidad total no sirve si la clave concentra el tráfico: `RepartoDeClaves` aplica el mismo MD5 que usa Kinesis para ver el desbalance **antes** de producción.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

record PerfilDeCarga(double registrosPorSegundo, int bytesPorRegistro, int consumidoresCompartidos) {}

record Dimension(int shards, String limitante, double escrituraMiBs, double lecturaMiBs) {}

final class DimensionadorDeStream {
    static final double ESCRITURA_MIB_POR_SHARD = 1.0;
    static final double REGISTROS_POR_SHARD = 1000;
    static final double LECTURA_MIB_POR_SHARD = 2.0;

    private DimensionadorDeStream() {
    }

    static Dimension calcular(PerfilDeCarga p, double margen) {
        if (p.registrosPorSegundo() <= 0 || p.bytesPorRegistro() <= 0 || p.consumidoresCompartidos() < 0 || margen < 1) {
            throw new IllegalArgumentException("perfil inválido");
        }
        double escritura = p.registrosPorSegundo() * p.bytesPorRegistro() / 1_048_576.0;
        double lectura = escritura * p.consumidoresCompartidos();
        int porBytes = (int) Math.ceil(escritura * margen / ESCRITURA_MIB_POR_SHARD);
        int porRegistros = (int) Math.ceil(p.registrosPorSegundo() * margen / REGISTROS_POR_SHARD);
        int porLectura = (int) Math.ceil(lectura * margen / LECTURA_MIB_POR_SHARD);
        int shards = Math.max(1, Math.max(porBytes, Math.max(porRegistros, porLectura)));
        String limitante = shards == porRegistros ? "registros/s" : shards == porBytes ? "escritura MiB/s" : "lectura compartida MiB/s";
        return new Dimension(shards, limitante, escritura, lectura);
    }

    /** Bajo demanda si el pico supera 3 veces el promedio o la carga no se conoce; provisionado si es estable y medida. */
    static String recomendarModo(double picoSobrePromedio, boolean cargaConocida) {
        return !cargaConocida || picoSobrePromedio > 3 ? "ON_DEMAND" : "PROVISIONED";
    }
}

final class RepartoDeClaves {
    private RepartoDeClaves() {
    }

    static int[] repartir(List<String> claves, int shards) {
        try {
            var md5 = MessageDigest.getInstance("MD5");
            var rango = BigInteger.TWO.pow(128).divide(BigInteger.valueOf(shards));
            var conteo = new int[shards];
            for (String c : claves) {
                var hash = new BigInteger(1, md5.digest(c.getBytes(StandardCharsets.UTF_8)));
                conteo[Math.min(shards - 1, hash.divide(rango).intValue())]++;
            }
            return conteo;
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** 1.0 = reparto perfecto; 4.0 = el shard más cargado recibe 4 veces el promedio. */
    static double desbalance(int[] conteo) {
        int total = 0;
        int maximo = 0;
        for (int c : conteo) {
            total += c;
            maximo = Math.max(maximo, c);
        }
        return total == 0 ? 1.0 : maximo / ((double) total / conteo.length);
    }
}
```

### 2.3 Validar, seudonimizar y codificar
El identificador de sesión del navegador **nunca** entra tal cual: se transforma con HMAC-SHA256 y un secreto del servidor. La hora del cliente solo se acepta si es verosímil (±5 min); si no, se usa la del servidor.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.security.GeneralSecurityException;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.Set;
import java.util.regex.Pattern;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;

final class Seudonimizador {
    private final SecretKeySpec clave;

    Seudonimizador(byte[] secreto) {
        if (secreto == null || secreto.length < 16) {
            throw new IllegalArgumentException("el secreto debe tener al menos 16 bytes");
        }
        this.clave = new SecretKeySpec(secreto, "HmacSHA256");
    }

    String sesion(String idCrudo) {
        try {
            var mac = Mac.getInstance("HmacSHA256");
            mac.init(clave);
            return HexFormat.of().formatHex(mac.doFinal(idCrudo.getBytes(StandardCharsets.UTF_8))).substring(0, 32);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }
}

final class CodificadorDeClics {
    static final Pattern PAGINA = Pattern.compile("/[a-z0-9/_-]{0,80}");
    static final Pattern ID_EVENTO = Pattern.compile("[A-Za-z0-9-]{8,64}");
    static final Pattern ID_SESION = Pattern.compile("[0-9a-f]{32}");
    static final Set<String> TIPOS = Set.of("vista", "clic", "compra");

    private CodificadorDeClics() {
    }

    static boolean valido(String idEvento, String pagina, String tipo) {
        return idEvento != null && ID_EVENTO.matcher(idEvento).matches()
                && pagina != null && PAGINA.matcher(pagina).matches() && tipo != null && TIPOS.contains(tipo);
    }

    static byte[] aJson(Clic c) {
        String json = "{\"idEvento\":\"" + c.idEvento() + "\",\"idSesion\":\"" + c.idSesion() + "\",\"pagina\":\"" + c.pagina()
                + "\",\"tipo\":\"" + c.tipo() + "\",\"instante\":\"" + c.instante() + "\"}";
        return json.getBytes(StandardCharsets.UTF_8);
    }

    /** Devuelve vacío ante cualquier problema: un registro malo nunca debe detener al lector. */
    static Optional<Clic> leer(byte[] datos) {
        try {
            JsonNode raiz = JsonNodeParser.create().parse(new String(datos, StandardCharsets.UTF_8));
            if (!raiz.isObject()) {
                return Optional.empty();
            }
            var o = raiz.asObject();
            String idEvento = texto(o.get("idEvento"));
            String idSesion = texto(o.get("idSesion"));
            String pagina = texto(o.get("pagina"));
            String tipo = texto(o.get("tipo"));
            String instante = texto(o.get("instante"));
            if (!valido(idEvento, pagina, tipo) || idSesion == null || !ID_SESION.matcher(idSesion).matches() || instante == null) {
                return Optional.empty();
            }
            return Optional.of(new Clic(idEvento, idSesion, pagina, tipo, Instant.parse(instante)));
        } catch (RuntimeException e) {
            return Optional.empty();
        }
    }

    private static String texto(JsonNode n) {
        return n != null && n.isString() ? n.asString() : null;
    }
}

record ClicEntrante(String idEvento, String pagina, String tipo, Instant instante) {}

record ResultadoIngesta(int aceptados, int descartados, int fallidos) {}

final class ServicioDeIngesta {
    static final int MAX_LOTE = 50;
    static final Duration TOLERANCIA = Duration.ofMinutes(5);

    private final PuertoEnvio envio;
    private final Seudonimizador seudonimizador;
    private final Clock reloj;

    ServicioDeIngesta(PuertoEnvio envio, Seudonimizador seudonimizador, Clock reloj) {
        this.envio = envio;
        this.seudonimizador = seudonimizador;
        this.reloj = reloj;
    }

    ResultadoIngesta registrar(String sesionCruda, List<ClicEntrante> entrantes) {
        if (sesionCruda == null || sesionCruda.isBlank() || sesionCruda.length() > 200) {
            throw new IllegalArgumentException("sesión inválida");
        }
        if (entrantes == null || entrantes.isEmpty() || entrantes.size() > MAX_LOTE) {
            throw new IllegalArgumentException("el lote debe tener entre 1 y " + MAX_LOTE + " clics");
        }
        String sesion = seudonimizador.sesion(sesionCruda);
        Instant ahora = reloj.instant();
        var validos = new ArrayList<Clic>();
        for (var e : entrantes) {
            if (e == null || !CodificadorDeClics.valido(e.idEvento(), e.pagina(), e.tipo())) {
                continue;
            }
            boolean verosimil = e.instante() != null && Duration.between(e.instante(), ahora).abs().compareTo(TOLERANCIA) <= 0;
            validos.add(new Clic(e.idEvento(), sesion, e.pagina(), e.tipo(), verosimil ? e.instante() : ahora));
        }
        int descartados = entrantes.size() - validos.size();
        if (validos.isEmpty()) {
            return new ResultadoIngesta(0, descartados, 0);
        }
        try {
            var r = envio.enviar(validos);
            return new ResultadoIngesta(r.enviados(), descartados, r.fallidos().size());
        } catch (RuntimeException e) {
            return new ResultadoIngesta(0, descartados, validos.size());
        }
    }
}
```

### 2.4 El productor por lotes
`PutRecords` responde `200` aunque algunos registros fallen: la respuesta trae un resultado **por registro**, en el mismo orden. Se reintenta **solo** lo fallido, con espera creciente, y lo que no se logra se devuelve a quien llamó.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.kinesis.KinesisClient;
import software.amazon.awssdk.services.kinesis.model.PutRecordsRequest;
import software.amazon.awssdk.services.kinesis.model.PutRecordsRequestEntry;

final class ProductorDeClics implements PuertoEnvio {
    static final int MAX_REGISTROS = 500;
    static final int MAX_BYTES = 5 * 1024 * 1024;

    private final KinesisClient kinesis;
    private final String stream;
    private final Pausa pausa;
    private final int intentos;

    ProductorDeClics(KinesisClient kinesis, String stream, Pausa pausa, int intentos) {
        this.kinesis = kinesis;
        this.stream = stream;
        this.pausa = pausa;
        this.intentos = intentos;
    }

    @Override
    public ResultadoEnvio enviar(List<Clic> clics) {
        List<Clic> pendientes = new ArrayList<>(clics);
        int enviados = 0;
        for (int intento = 1; intento <= intentos && !pendientes.isEmpty(); intento++) {
            if (intento > 1) {
                pausa.esperar(Math.min(1000L, 50L << (intento - 2)));
            }
            var siguientes = new ArrayList<Clic>();
            for (var lote : partir(pendientes)) {
                var respuesta = kinesis.putRecords(solicitud(stream, lote));
                if (respuesta.records().size() != lote.size()) {
                    throw new IllegalStateException("respuesta de PutRecords incompleta");
                }
                for (int i = 0; i < lote.size(); i++) {
                    if (respuesta.records().get(i).errorCode() == null) {
                        enviados++;
                    } else {
                        siguientes.add(lote.get(i));
                    }
                }
            }
            pendientes = siguientes;
        }
        return new ResultadoEnvio(enviados, pendientes);
    }

    static List<List<Clic>> partir(List<Clic> clics) {
        var lotes = new ArrayList<List<Clic>>();
        var actual = new ArrayList<Clic>();
        int bytes = 0;
        for (var c : clics) {
            int tam = CodificadorDeClics.aJson(c).length + c.idSesion().length();
            if (!actual.isEmpty() && (actual.size() == MAX_REGISTROS || bytes + tam > MAX_BYTES)) {
                lotes.add(actual);
                actual = new ArrayList<>();
                bytes = 0;
            }
            actual.add(c);
            bytes += tam;
        }
        if (!actual.isEmpty()) {
            lotes.add(actual);
        }
        return lotes;
    }

    static PutRecordsRequest solicitud(String stream, List<Clic> lote) {
        var entradas = lote.stream()
                .map(c -> PutRecordsRequestEntry.builder()
                        .partitionKey(c.idSesion())
                        .data(SdkBytes.fromByteArray(CodificadorDeClics.aJson(c)))
                        .build())
                .toList();
        return PutRecordsRequest.builder().streamName(stream).records(entradas).build();
    }
}
```

### 2.5 Ventanas, marca de agua y punto seguro
Cada ventana de 1 minuto se identifica por `(inicio, página, tipo)`. La **marca de agua** es «el evento más reciente menos la tardanza permitida»: cuando pasa el fin de una ventana, esta se cierra y sale. Un evento cuya ventana ya cerró es **tardío** y se cuenta aparte (la corrección nocturna lo recupera). Cada ventana recuerda el registro **anterior** a su primer evento: el *punto seguro* del checkpoint es el más antiguo de ellos, de modo que tras un reinicio se relee lo necesario y los duplicados se descartan por `idEvento`.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;

enum ResultadoAceptar { ACEPTADO, DUPLICADO, TARDIO }

final class AgregadorDeVentanas {
    private record ClaveVentana(Instant inicio, String pagina, String tipo) {}

    private static final class Acumulado {
        long clics;
        final Set<String> sesiones = new HashSet<>();
        final Set<String> ids = new HashSet<>();
        final String previa;

        Acumulado(String previa) {
            this.previa = previa;
        }
    }

    private final Map<ClaveVentana, Acumulado> abiertas = new HashMap<>();
    private final long ventanaSegundos;
    private final Duration tardanza;
    private Instant maxEvento = Instant.EPOCH;
    private Instant marcaDeAgua = Instant.EPOCH;
    private String ultimaSecuencia;

    AgregadorDeVentanas(Duration ventana, Duration tardanza, String desdeDespuesDe) {
        this.ventanaSegundos = ventana.toSeconds();
        this.tardanza = tardanza;
        this.ultimaSecuencia = desdeDespuesDe;
    }

    ResultadoAceptar aceptar(Clic c) {
        Instant inicio = Instant.ofEpochSecond(Math.floorDiv(c.instante().getEpochSecond(), ventanaSegundos) * ventanaSegundos);
        if (!inicio.plusSeconds(ventanaSegundos).isAfter(marcaDeAgua)) {
            return ResultadoAceptar.TARDIO;
        }
        var acu = abiertas.computeIfAbsent(new ClaveVentana(inicio, c.pagina(), c.tipo()), k -> new Acumulado(ultimaSecuencia));
        if (!acu.ids.add(c.idEvento())) {
            return ResultadoAceptar.DUPLICADO;
        }
        acu.clics++;
        acu.sesiones.add(c.idSesion());
        if (c.instante().isAfter(maxEvento)) {
            maxEvento = c.instante();
            marcaDeAgua = maxEvento.minus(tardanza).isAfter(marcaDeAgua) ? maxEvento.minus(tardanza) : marcaDeAgua;
        }
        return ResultadoAceptar.ACEPTADO;
    }

    /** Se llama con CADA registro leído (válido o no), después de procesarlo. */
    void leido(String secuencia) {
        ultimaSecuencia = secuencia;
    }

    /** Con el lector al día y sin tráfico, el reloj también cierra ventanas. */
    void avanzarPorReloj(Instant ahora) {
        Instant candidata = ahora.minus(tardanza);
        if (candidata.isAfter(marcaDeAgua)) {
            marcaDeAgua = candidata;
        }
    }

    List<MetricaVentana> cerrar() {
        var cerradas = new ArrayList<MetricaVentana>();
        var it = abiertas.entrySet().iterator();
        while (it.hasNext()) {
            var e = it.next();
            if (!e.getKey().inicio().plusSeconds(ventanaSegundos).isAfter(marcaDeAgua)) {
                cerradas.add(new MetricaVentana(e.getKey().inicio(), e.getKey().pagina(), e.getKey().tipo(), e.getValue().clics, e.getValue().sesiones.size()));
                it.remove();
            }
        }
        cerradas.sort(java.util.Comparator.comparing(MetricaVentana::inicio).thenComparing(MetricaVentana::pagina).thenComparing(MetricaVentana::tipo));
        return cerradas;
    }

    /** Hasta dónde se puede hacer checkpoint sin perder nada de lo que aún está en memoria. */
    Optional<String> puntoSeguro() {
        if (abiertas.isEmpty()) {
            return Optional.ofNullable(ultimaSecuencia);
        }
        BigInteger minimo = null;
        for (var acu : abiertas.values()) {
            if (acu.previa == null) {
                return Optional.empty();
            }
            var v = new BigInteger(acu.previa);
            if (minimo == null || v.compareTo(minimo) < 0) {
                minimo = v;
            }
        }
        return Optional.of(minimo.toString());
    }

    int ventanasAbiertas() {
        return abiertas.size();
    }
}

final class ProcesadorDeLote {
    private static final Duration FUTURO_MAXIMO = Duration.ofMinutes(5);

    private final AgregadorDeVentanas agregador;
    private final Clock reloj;

    ProcesadorDeLote(AgregadorDeVentanas agregador, Clock reloj) {
        this.agregador = agregador;
        this.reloj = reloj;
    }

    ResumenLote procesar(List<Registro> registros, boolean alDia) {
        int ok = 0;
        int invalidos = 0;
        int duplicados = 0;
        int tardios = 0;
        Instant ahora = reloj.instant();
        for (var r : registros) {
            var clic = CodificadorDeClics.leer(r.datos());
            if (clic.isEmpty() || clic.get().instante().isAfter(ahora.plus(FUTURO_MAXIMO))) {
                invalidos++;
            } else {
                switch (agregador.aceptar(clic.get())) {
                    case ACEPTADO -> ok++;
                    case DUPLICADO -> duplicados++;
                    case TARDIO -> tardios++;
                }
            }
            agregador.leido(r.secuencia());
        }
        if (alDia) {
            agregador.avanzarPorReloj(ahora);
        }
        return new ResumenLote(ok, invalidos, duplicados, tardios, agregador.cerrar());
    }

    Optional<String> puntoSeguro() {
        return agregador.puntoSeguro();
    }
}
```

### 2.6 Leer shards, guardar métricas y hacer checkpoint
Orden obligatorio: **primero la salida, después el checkpoint**. Si el proceso muere en medio, se repite trabajo (inocuo: la salida es idempotente) pero nunca se pierde. Las filas de métricas llevan el `shard` en la clave: así dos lectores no se pisan, y como la clave de partición es la sesión, las sesiones únicas de todos los shards **se suman sin doble conteo**.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.function.Supplier;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.kinesis.model.ExpiredIteratorException;
import software.amazon.awssdk.services.kinesis.model.GetRecordsRequest;
import software.amazon.awssdk.services.kinesis.model.GetRecordsResponse;
import software.amazon.awssdk.services.kinesis.model.GetShardIteratorRequest;
import software.amazon.awssdk.services.kinesis.model.ListShardsRequest;
import software.amazon.awssdk.services.kinesis.model.Shard;
import software.amazon.awssdk.services.kinesis.model.ShardIteratorType;

final class LectorDeShards {
    private final KinesisClient kinesis;
    private final String stream;
    private final Map<String, String> iteradores = new HashMap<>();

    LectorDeShards(KinesisClient kinesis, String stream) {
        this.kinesis = kinesis;
        this.stream = stream;
    }

    List<String> shards() {
        var ids = new ArrayList<String>();
        String token = null;
        do { // ListShards no trae paginador en el SDK: se pagina a mano con nextToken
            var pedido = token == null ? ListShardsRequest.builder().streamName(stream).build() : ListShardsRequest.builder().nextToken(token).build();
            var r = kinesis.listShards(pedido);
            for (Shard s : r.shards()) {
                if (s.sequenceNumberRange().endingSequenceNumber() == null) {
                    ids.add(s.shardId()); // solo shards abiertos
                }
            }
            token = r.nextToken();
        } while (token != null);
        return ids;
    }

    LoteLeido leer(String shard, Supplier<Optional<String>> desdeDespuesDe, int limite) {
        String iterador = iteradores.get(shard);
        if (iterador == null) {
            iterador = nuevoIterador(shard, desdeDespuesDe.get());
        }
        GetRecordsResponse r;
        try {
            r = kinesis.getRecords(GetRecordsRequest.builder().shardIterator(iterador).limit(limite).build());
        } catch (ExpiredIteratorException e) {
            r = kinesis.getRecords(GetRecordsRequest.builder().shardIterator(nuevoIterador(shard, desdeDespuesDe.get())).limit(limite).build());
        }
        if (r.nextShardIterator() == null) {
            iteradores.remove(shard);
        } else {
            iteradores.put(shard, r.nextShardIterator());
        }
        var registros = r.records().stream().map(x -> new Registro(x.sequenceNumber(), x.data().asByteArray())).toList();
        return new LoteLeido(registros, r.millisBehindLatest() == null ? 0 : r.millisBehindLatest());
    }

    private String nuevoIterador(String shard, Optional<String> despuesDe) {
        var b = GetShardIteratorRequest.builder().streamName(stream).shardId(shard);
        if (despuesDe.isPresent()) {
            b.shardIteratorType(ShardIteratorType.AFTER_SEQUENCE_NUMBER).startingSequenceNumber(despuesDe.get());
        } else {
            b.shardIteratorType(ShardIteratorType.TRIM_HORIZON);
        }
        return kinesis.getShardIterator(b.build()).shardIterator();
    }
}

final class CheckpointsDynamo implements Checkpoints {
    private final DynamoDbClient dynamo;
    private final String tabla;

    CheckpointsDynamo(DynamoDbClient dynamo, String tabla) {
        this.dynamo = dynamo;
        this.tabla = tabla;
    }

    @Override
    public Optional<String> ultimo(String shard) {
        var r = dynamo.getItem(GetItemRequest.builder().tableName(tabla).key(Map.of("shard", s(shard))).consistentRead(true).build());
        return r.hasItem() && r.item().containsKey("secuencia") ? Optional.of(r.item().get("secuencia").s()) : Optional.empty();
    }

    @Override
    public void guardar(String shard, String secuencia) {
        dynamo.putItem(PutItemRequest.builder().tableName(tabla).item(Map.of("shard", s(shard), "secuencia", s(secuencia))).build());
    }

    private static AttributeValue s(String v) {
        return AttributeValue.builder().s(v).build();
    }
}

final class RepositorioMetricasDynamo implements RepositorioMetricas {
    private final DynamoDbClient dynamo;
    private final String tabla;
    private final Clock reloj;

    RepositorioMetricasDynamo(DynamoDbClient dynamo, String tabla, Clock reloj) {
        this.dynamo = dynamo;
        this.tabla = tabla;
        this.reloj = reloj;
    }

    @Override
    public void guardar(String shard, List<MetricaVentana> metricas) {
        long expira = reloj.instant().plus(Duration.ofDays(7)).getEpochSecond();
        for (var m : metricas) {
            dynamo.putItem(PutItemRequest.builder().tableName(tabla).item(Map.of(
                    "pagina", AttributeValue.builder().s(m.pagina()).build(),
                    "ventana", AttributeValue.builder().s(m.inicio() + "#" + m.tipo() + "#" + shard).build(),
                    "clics", AttributeValue.builder().n(Long.toString(m.clics())).build(),
                    "sesiones", AttributeValue.builder().n(Long.toString(m.sesionesUnicas())).build(),
                    "expira", AttributeValue.builder().n(Long.toString(expira)).build())).build());
        }
    }
}

final class TrabajadorDeClics {
    private final LectorDeShards lector;
    private final Checkpoints checkpoints;
    private final RepositorioMetricas metricas;
    private final Clock reloj;
    private final Map<String, ProcesadorDeLote> procesadores = new HashMap<>();
    private final Map<String, String> guardados = new HashMap<>();

    TrabajadorDeClics(LectorDeShards lector, Checkpoints checkpoints, RepositorioMetricas metricas, Clock reloj) {
        this.lector = lector;
        this.checkpoints = checkpoints;
        this.metricas = metricas;
        this.reloj = reloj;
    }

    /** Una vuelta por todos los shards. Devuelve cuántos registros se leyeron. */
    int ciclo() {
        int total = 0;
        for (String shard : lector.shards()) {
            var proc = procesadores.computeIfAbsent(shard, s -> new ProcesadorDeLote(
                    new AgregadorDeVentanas(Duration.ofMinutes(1), Duration.ofMinutes(2), checkpoints.ultimo(s).orElse(null)), reloj));
            var lote = lector.leer(shard, () -> checkpoints.ultimo(shard), 1000);
            var resumen = proc.procesar(lote.registros(), lote.milisDetras() < 5000);
            if (!resumen.cerradas().isEmpty()) {
                metricas.guardar(shard, resumen.cerradas());          // 1.º la salida (idempotente)
            }
            proc.puntoSeguro().ifPresent(seq -> {                       // 2.º el checkpoint
                if (!seq.equals(guardados.get(shard))) {
                    checkpoints.guardar(shard, seq);
                    guardados.put(shard, seq);
                }
            });
            total += lote.registros().size();
        }
        return total;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.time.Clock;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.CookieValue;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
@EnableScheduling
class ClicsConfig {
    @Bean(destroyMethod = "close")
    KinesisClient kinesis() {
        return KinesisClient.create();
    }

    @Bean(destroyMethod = "close")
    DynamoDbClient dynamo() {
        return DynamoDbClient.create();
    }

    @Bean
    ServicioDeIngesta ingesta(KinesisClient kinesis, @Value("${app.clics.stream}") String stream, @Value("${app.clics.secreto}") String secreto) {
        Pausa pausa = ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        };
        return new ServicioDeIngesta(new ProductorDeClics(kinesis, stream, pausa, 3),
                new Seudonimizador(secreto.getBytes(StandardCharsets.UTF_8)), Clock.systemUTC());
    }

    @Bean
    TrabajadorDeClics trabajador(KinesisClient kinesis, DynamoDbClient dynamo, @Value("${app.clics.stream}") String stream,
                                 @Value("${app.clics.tabla-metricas}") String metricas, @Value("${app.clics.tabla-checkpoints}") String cps) {
        return new TrabajadorDeClics(new LectorDeShards(kinesis, stream), new CheckpointsDynamo(dynamo, cps),
                new RepositorioMetricasDynamo(dynamo, metricas, Clock.systemUTC()), Clock.systemUTC());
    }
}

record LoteDeClics(List<ClicEntrante> clics) {}

@RestController
@RequestMapping("/clics")
class ClicsController {
    private final ServicioDeIngesta ingesta;

    ClicsController(ServicioDeIngesta ingesta) {
        this.ingesta = ingesta;
    }

    @PostMapping
    ResponseEntity<ResultadoIngesta> recibir(@CookieValue("sid") String sesion, @RequestBody LoteDeClics lote) {
        var r = ingesta.registrar(sesion, lote.clics());
        return r.fallidos() > 0 ? ResponseEntity.status(503).header("Retry-After", "2").body(r) : ResponseEntity.accepted().body(r);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> invalido(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
}

@Component
class TareaDeMetricas {
    private final TrabajadorDeClics trabajador;

    TareaDeMetricas(TrabajadorDeClics trabajador) {
        this.trabajador = trabajador;
    }

    @Scheduled(fixedDelay = 1000)
    void leer() {
        trabajador.ciclo();
    }
}
```

## 4. Spring WebFlux (reactivo)
La ingesta usa el SDK síncrono: va a `boundedElastic`. El trabajador se ejecuta en un bucle `Flux.interval` con `concatMap(…, 1)` (jamás dos vueltas a la vez) y los errores de una vuelta no matan el bucle.
```java
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.CookieValue;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.Disposable;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

record LoteDeClicsV2(List<ClicEntrante> clics) {}

@RestController
@RequestMapping("/v2/clics")
class ClicsReactivoController {
    private final ServicioDeIngesta ingesta;

    ClicsReactivoController(ServicioDeIngesta ingesta) {
        this.ingesta = ingesta;
    }

    @PostMapping
    Mono<ResponseEntity<Object>> recibir(@CookieValue("sid") String sesion, @RequestBody LoteDeClicsV2 lote) {
        return Mono.fromCallable(() -> ingesta.registrar(sesion, lote.clics()))
                .subscribeOn(Schedulers.boundedElastic())
                .<ResponseEntity<Object>>map(r -> r.fallidos() > 0 ? ResponseEntity.status(503).header("Retry-After", "2").body(r) : ResponseEntity.accepted().body(r))
                .onErrorResume(IllegalArgumentException.class, e -> Mono.just(ResponseEntity.badRequest().body(Map.of("error", e.getMessage()))));
    }
}

@Component
class BucleReactivoDeMetricas {
    private final TrabajadorDeClics trabajador;
    private Disposable bucle;

    BucleReactivoDeMetricas(TrabajadorDeClics trabajador) {
        this.trabajador = trabajador;
    }

    @PostConstruct
    void iniciar() {
        bucle = Flux.interval(java.time.Duration.ofSeconds(1))
                .onBackpressureDrop()
                .concatMap(t -> Mono.fromCallable(trabajador::ciclo).subscribeOn(Schedulers.boundedElastic()).onErrorResume(e -> Mono.empty()), 1)
                .subscribe();
    }

    @PreDestroy
    void detener() {
        bucle.dispose();
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ClicsProductores {
    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeIngesta ingesta(KinesisClient kinesis, @ConfigProperty(name = "app.clics.stream") String stream,
                              @ConfigProperty(name = "app.clics.secreto") String secreto) {
        Pausa pausa = ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        };
        return new ServicioDeIngesta(new ProductorDeClics(kinesis, stream, pausa, 3),
                new Seudonimizador(secreto.getBytes(StandardCharsets.UTF_8)), Clock.systemUTC());
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    TrabajadorDeClics trabajador(KinesisClient kinesis, DynamoDbClient dynamo, @ConfigProperty(name = "app.clics.stream") String stream,
                                 @ConfigProperty(name = "app.clics.tabla-metricas") String metricas,
                                 @ConfigProperty(name = "app.clics.tabla-checkpoints") String cps) {
        return new TrabajadorDeClics(new LectorDeShards(kinesis, stream), new CheckpointsDynamo(dynamo, cps),
                new RepositorioMetricasDynamo(dynamo, metricas, Clock.systemUTC()), Clock.systemUTC());
    }
}
```
```java
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.CookieParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

record LoteDeClicsQ(List<ClicEntrante> clics) {}

@Path("/clics")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class ClicsResource {
    @Inject
    ServicioDeIngesta ingesta;

    @POST
    public Response recibir(@CookieParam("sid") String sesion, LoteDeClicsQ lote) {
        try {
            var r = ingesta.registrar(sesion, lote.clics());
            return r.fallidos() > 0 ? Response.status(503).header("Retry-After", "2").entity(r).build() : Response.accepted(r).build();
        } catch (IllegalArgumentException e) {
            return Response.status(400).entity(Map.of("error", e.getMessage())).build();
        }
    }
}

@ApplicationScoped
class TareaQuarkusDeMetricas {
    @Inject
    TrabajadorDeClics trabajador;

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void leer() {
        trabajador.ciclo();
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
import jakarta.ws.rs.CookieParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

record LoteDeClicsM(List<ClicEntrante> clics) {}

@Path("/v2/clics")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class ClicsMutinyResource {
    @Inject
    ServicioDeIngesta ingesta;

    @POST
    public Uni<Response> recibir(@CookieParam("sid") String sesion, LoteDeClicsM lote) {
        return Uni.createFrom().item(() -> ingesta.registrar(sesion, lote.clics()))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(r -> r.fallidos() > 0 ? Response.status(503).header("Retry-After", "2").entity(r).build() : Response.accepted(r).build())
                .onFailure(IllegalArgumentException.class).recoverWithItem(e -> Response.status(400).entity(Map.of("error", e.getMessage())).build());
    }
}

@ApplicationScoped
class TareaMutinyDeMetricas {
    @Inject
    TrabajadorDeClics trabajador;

    @Scheduled(every = "1s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    Uni<Void> leer() {
        return Uni.createFrom().item(trabajador::ciclo)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .onFailure().recoverWithItem(0)
                .replaceWithVoid();
    }
}
```

## 7. Permisos
| Servicio | Acciones | Recurso |
|---|---|---|
| API de ingesta | `kinesis:PutRecords` | Stream `prod-clics` |
| Consumidor | `kinesis:ListShards`, `GetShardIterator`, `GetRecords` | Stream `prod-clics` |
| Consumidor | `dynamodb:PutItem`, `GetItem` | Tablas `prod-metricas-clics` y `prod-checkpoints-clics` |
| Ambos | `secretsmanager:GetSecretValue` (vía definición de tarea) | Secreto de seudonimización |

## 8. Qué NO hacer desde Java
- No uses `pagina`, `pais` ni nada con pocos valores como clave de partición.
- No lances excepciones por un registro inválido: cuéntalo y sigue.
- No hagas checkpoint antes de escribir la salida, ni más allá del punto seguro.
- No uses `ADD` en DynamoDB para métricas que puedes recalcular: `PutItem` por clave.
- No ejecutes **este** trabajador en varias réplicas sin coordinación: leerían los mismos shards. Para escalar, usa la Kinesis Client Library (arrendamientos de shards, ver capítulo 07) o asigna shards por réplica.
- No metas correo, nombre ni IP en el stream; seudonimiza en la puerta.
- No cuentes con la hora del cliente: acótala contra la del servidor.
- No lo uses para un flujo de unos cientos de eventos al día: SQS/EventBridge son más simples.
