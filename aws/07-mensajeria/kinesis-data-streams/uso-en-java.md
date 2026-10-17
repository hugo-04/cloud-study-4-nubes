# AWS · Kinesis Data Streams · Uso desde Java

Cuatro piezas puras o casi puras y una con KCL: un **simulador de reparto de claves** (para elegir bien la clave de partición *antes* de producción), **comparación correcta de números de secuencia** y filtro de duplicados, un **productor por lotes** con reintento por registro, un **lector sencillo** (diagnóstico) y el **consumidor de producción con KCL**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40 (`quarkus-amazon-kinesis`), AWS SDK v2 (BOM 2.56), KCL 3.x.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  stream-clics: prod-clics
  aplicacion-kcl: analitica-kcl
```
```properties
# Quarkus (application.properties)
quarkus.kinesis.aws.region=us-east-1
quarkus.dynamodb.aws.region=us-east-1
quarkus.cloudwatch.aws.region=us-east-1
app.stream-clics=prod-clics
app.aplicacion-kcl=analitica-kcl
```
> KCL usa tres clientes **asíncronos** (Kinesis, DynamoDB para los *leases* y CloudWatch para métricas). En Quarkus se inyectan desde sus extensiones (`quarkus-amazon-kinesis`, `-dynamodb`, `-cloudwatch`, más `netty-nio-client` para los clientes asíncronos); en Spring se crean con `create()`.

## 2. Núcleo común

### 2.1 Simulador de reparto de claves
Kinesis calcula `MD5(clave)` como número de 128 bits y lo asigna al shard cuyo rango lo contiene. Con shards uniformes, el rango de cada shard es `2^128 / N`. **Pasa tus claves reales por aquí para detectar shards calientes antes de producción** (tras dividir/combinar shards el reparto real puede variar).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Collection;

public final class ParticionKinesis {
    private ParticionKinesis() {}

    public record Reparto(int[] porShard, int total) {
        public int maximo() {
            int m = 0;
            for (int x : porShard) {
                m = Math.max(m, x);
            }
            return m;
        }

        /** 1.0 = reparto perfecto; 3.0 = el shard más cargado recibe el triple del promedio. */
        public double factorCalor() {
            return total == 0 ? 1.0 : maximo() / ((double) total / porShard.length);
        }

        public boolean hayShardCaliente(double umbral) {
            return factorCalor() > umbral;
        }
    }

    public static BigInteger hash(String clave) {
        try {
            byte[] d = MessageDigest.getInstance("MD5").digest(clave.getBytes(StandardCharsets.UTF_8));
            return new BigInteger(1, d);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public static int shardPara(String clave, int shards) {
        if (shards < 1) {
            throw new IllegalArgumentException("shards debe ser >= 1");
        }
        return hash(clave).multiply(BigInteger.valueOf(shards)).shiftRight(128).intValue();
    }

    public static Reparto simular(Collection<String> claves, int shards) {
        int[] c = new int[shards];
        for (String k : claves) {
            c[shardPara(k, shards)]++;
        }
        return new Reparto(c, claves.size());
    }
}
```

### 2.2 Números de secuencia y duplicados
Un número de secuencia es una cifra de hasta ~56 dígitos: se compara **como número**. Con registros agregados por la KPL, varios registros comparten secuencia y se distinguen por la *subsecuencia*.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigInteger;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

public final class SecuenciaKinesis {
    private SecuenciaKinesis() {}

    public static int comparar(String a, String b) {
        return new BigInteger(a).compareTo(new BigInteger(b));
    }

    /** Descarta lo ya visto en un shard tras un reinicio o una relectura. Es memoria de proceso: el checkpoint real lo guarda KCL. */
    public static final class FiltroDuplicados {
        private record Posicion(BigInteger secuencia, long sub) implements Comparable<Posicion> {
            @Override
            public int compareTo(Posicion o) {
                int c = secuencia.compareTo(o.secuencia);
                return c != 0 ? c : Long.compare(sub, o.sub);
            }
        }

        private final ConcurrentHashMap<String, Posicion> ultimo = new ConcurrentHashMap<>();

        /** @return true si la posición es nueva (mayor que la última vista en ese shard). */
        public boolean nuevo(String shardId, String secuencia, long subSecuencia) {
            Posicion p = new Posicion(new BigInteger(secuencia), subSecuencia);
            AtomicBoolean esNuevo = new AtomicBoolean(false);
            ultimo.compute(shardId, (k, anterior) -> {
                if (anterior == null || p.compareTo(anterior) > 0) {
                    esNuevo.set(true);
                    return p;
                }
                return anterior;
            });
            return esNuevo.get();
        }
    }
}
```

### 2.3 Productor por lotes con reintento por registro
`PutRecords` admite hasta 500 registros y 5 MiB por llamada; la respuesta trae un resultado **por registro**, en el mismo orden. Se reintentan solo los que fallaron por capacidad o error interno.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.function.LongConsumer;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.kinesis.KinesisClient;
import software.amazon.awssdk.services.kinesis.model.PutRecordsRequest;
import software.amazon.awssdk.services.kinesis.model.PutRecordsRequestEntry;
import software.amazon.awssdk.services.kinesis.model.PutRecordsResponse;
import software.amazon.awssdk.services.kinesis.model.PutRecordsResultEntry;

public final class ProductorKinesis {
    public record Registro(String clave, byte[] datos) {
        public static Registro texto(String clave, String json) {
            return new Registro(clave, json.getBytes(StandardCharsets.UTF_8));
        }
    }

    public static final class PublicacionParcialException extends RuntimeException {
        private final List<Registro> fallidos;

        PublicacionParcialException(List<Registro> fallidos) {
            super("no se pudieron publicar " + fallidos.size() + " registro(s)");
            this.fallidos = List.copyOf(fallidos);
        }

        public List<Registro> fallidos() {
            return fallidos;
        }
    }

    static final int MAX_REGISTROS = 500;
    static final long MAX_BYTES_LLAMADA = 5L * 1024 * 1024;
    static final long MAX_BYTES_REGISTRO = 1024L * 1024;   // verifica: límites mayores en configuraciones nuevas
    private static final Set<String> REINTENTABLES = Set.of("ProvisionedThroughputExceededException", "InternalFailure");

    private final KinesisClient kinesis;
    private final String stream;
    private final int reintentos;
    private final LongConsumer pausaMs;

    public ProductorKinesis(KinesisClient kinesis, String stream, int reintentos, LongConsumer pausaMs) {
        this.kinesis = kinesis;
        this.stream = stream;
        this.reintentos = reintentos;
        this.pausaMs = pausaMs;
    }

    public ProductorKinesis(KinesisClient kinesis, String stream) {
        this(kinesis, stream, 4, ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException(e);
            }
        });
    }

    static long bytes(Registro r) {
        return r.datos().length + r.clave().getBytes(StandardCharsets.UTF_8).length;
    }

    static List<List<Registro>> partir(List<Registro> registros) {
        List<List<Registro>> lotes = new ArrayList<>();
        List<Registro> actual = new ArrayList<>();
        long acumulado = 0;
        for (Registro r : registros) {
            long b = bytes(r);
            if (b > MAX_BYTES_REGISTRO) {
                throw new IllegalArgumentException("registro de " + b + " bytes supera el límite: usa Claim Check");
            }
            if (actual.size() == MAX_REGISTROS || acumulado + b > MAX_BYTES_LLAMADA) {
                lotes.add(actual);
                actual = new ArrayList<>();
                acumulado = 0;
            }
            actual.add(r);
            acumulado += b;
        }
        if (!actual.isEmpty()) {
            lotes.add(actual);
        }
        return lotes;
    }

    public void publicar(List<Registro> registros) {
        List<Registro> fallidos = new ArrayList<>();
        for (List<Registro> lote : partir(registros)) {
            List<Registro> pendientes = lote;
            for (int intento = 0; intento <= reintentos && !pendientes.isEmpty(); intento++) {
                if (intento > 0) {
                    pausaMs.accept(Math.min(5_000L, 100L << (intento - 1)));
                }
                PutRecordsResponse r = kinesis.putRecords(PutRecordsRequest.builder().streamName(stream)
                        .records(pendientes.stream().map(x -> PutRecordsRequestEntry.builder()
                                .partitionKey(x.clave()).data(SdkBytes.fromByteArray(x.datos())).build()).toList())
                        .build());
                int fallas = r.failedRecordCount() == null ? 0 : r.failedRecordCount();
                if (fallas == 0) {
                    pendientes = List.of();
                    break;
                }
                List<Registro> siguientes = new ArrayList<>();
                for (int i = 0; i < pendientes.size(); i++) {
                    PutRecordsResultEntry re = r.records().get(i);
                    if (re.errorCode() == null) {
                        continue;
                    }
                    if (REINTENTABLES.contains(re.errorCode())) {
                        siguientes.add(pendientes.get(i));
                    } else {
                        fallidos.add(pendientes.get(i));
                    }
                }
                pendientes = siguientes;
            }
            fallidos.addAll(pendientes);
        }
        if (!fallidos.isEmpty()) {
            throw new PublicacionParcialException(fallidos);
        }
    }
}
```

### 2.4 Lector sencillo (diagnóstico y herramientas)
Para inspeccionar un shard o hacer una lectura puntual. **En producción usa KCL (§2.5) o Lambda**: reparten shards, guardan *checkpoints* y manejan el resharding.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.List;
import software.amazon.awssdk.services.kinesis.KinesisClient;
import software.amazon.awssdk.services.kinesis.model.GetRecordsRequest;
import software.amazon.awssdk.services.kinesis.model.GetRecordsResponse;
import software.amazon.awssdk.services.kinesis.model.GetShardIteratorRequest;
import software.amazon.awssdk.services.kinesis.model.ShardIteratorType;

public final class LectorKinesis {
    public record Leido(String secuencia, String clave, byte[] datos, Instant llegada) {}

    public record Lectura(List<Leido> registros, String siguienteIterador, long atrasoMs) {
        public boolean alDia() {
            return atrasoMs == 0;
        }
    }

    private final KinesisClient kinesis;
    private final String stream;

    public LectorKinesis(KinesisClient kinesis, String stream) {
        this.kinesis = kinesis;
        this.stream = stream;
    }

    /** @param desde si es null, lee desde lo más antiguo (TRIM_HORIZON); si no, desde esa fecha. */
    public Lectura primera(String shardId, Instant desde, int limite) {
        var b = GetShardIteratorRequest.builder().streamName(stream).shardId(shardId);
        if (desde == null) {
            b.shardIteratorType(ShardIteratorType.TRIM_HORIZON);
        } else {
            b.shardIteratorType(ShardIteratorType.AT_TIMESTAMP).timestamp(desde);
        }
        return seguir(kinesis.getShardIterator(b.build()).shardIterator(), limite);
    }

    public Lectura seguir(String iterador, int limite) {
        GetRecordsResponse r = kinesis.getRecords(GetRecordsRequest.builder().shardIterator(iterador).limit(limite).build());
        List<Leido> lista = r.records().stream()
                .map(x -> new Leido(x.sequenceNumber(), x.partitionKey(), x.data().asByteArray(), x.approximateArrivalTimestamp()))
                .toList();
        return new Lectura(lista, r.nextShardIterator(), r.millisBehindLatest() == null ? 0 : r.millisBehindLatest());
    }
}
```

### 2.5 Consumidor de producción con KCL
KCL reparte los shards entre las instancias que comparten el mismo `aplicacion`, guarda *leases* y *checkpoints* en una tabla de DynamoDB y reacciona al resharding. **Ojo:** si `processRecords` lanza una excepción, KCL la registra y sigue con el siguiente lote; por eso el procesador reintenta, desvía lo irrecuperable (p. ej. a una cola DLQ) y hace `checkpoint` solo después.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.ByteBuffer;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import software.amazon.awssdk.services.cloudwatch.CloudWatchAsyncClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbAsyncClient;
import software.amazon.awssdk.services.kinesis.KinesisAsyncClient;
import software.amazon.kinesis.common.ConfigsBuilder;
import software.amazon.kinesis.common.InitialPositionInStream;
import software.amazon.kinesis.common.InitialPositionInStreamExtended;
import software.amazon.kinesis.coordinator.Scheduler;
import software.amazon.kinesis.lifecycle.events.InitializationInput;
import software.amazon.kinesis.lifecycle.events.LeaseLostInput;
import software.amazon.kinesis.lifecycle.events.ProcessRecordsInput;
import software.amazon.kinesis.lifecycle.events.ShardEndedInput;
import software.amazon.kinesis.lifecycle.events.ShutdownRequestedInput;
import software.amazon.kinesis.processor.ShardRecordProcessor;
import software.amazon.kinesis.retrieval.KinesisClientRecord;
import software.amazon.kinesis.retrieval.polling.PollingConfig;

public final class ConsumidorKcl {
    public interface Manejador {
        void procesar(String shardId, String clave, String secuencia, byte[] datos) throws Exception;
    }

    /** Qué hacer con un registro que no se pudo procesar tras los reintentos (p. ej. enviarlo a una cola de fallos). */
    public interface Desvio {
        void desviar(String shardId, String clave, String secuencia, byte[] datos, Exception causa);
    }

    private final Scheduler scheduler;
    private final String aplicacion;
    private Thread hilo;

    /**
     * @param fanOutMejorado true = consumidor con fan-out mejorado (registrado con el nombre de la aplicación);
     *                       false = sondeo compartido.
     * @param desde          null = solo lo nuevo (LATEST) la primera vez; con fecha = AT_TIMESTAMP (reproceso).
     */
    public ConsumidorKcl(String stream, String aplicacion, KinesisAsyncClient kinesis, DynamoDbAsyncClient dynamo,
                         CloudWatchAsyncClient cloudWatch, Manejador manejador, Desvio desvio,
                         boolean fanOutMejorado, Instant desde) {
        this.aplicacion = aplicacion;
        String trabajador = aplicacion + "-" + UUID.randomUUID();
        var cb = new ConfigsBuilder(stream, aplicacion, kinesis, dynamo, cloudWatch, trabajador,
                () -> new Procesador(manejador, desvio, 3));
        var recuperacion = cb.retrievalConfig();
        if (!fanOutMejorado) {
            recuperacion = recuperacion.retrievalSpecificConfig(new PollingConfig(stream, kinesis));
        }
        recuperacion = recuperacion.initialPositionInStreamExtended(desde == null
                ? InitialPositionInStreamExtended.newInitialPosition(InitialPositionInStream.LATEST)
                : InitialPositionInStreamExtended.newInitialPositionAtTimestamp(Date.from(desde)));
        this.scheduler = new Scheduler(cb.checkpointConfig(), cb.coordinatorConfig(), cb.leaseManagementConfig(),
                cb.lifecycleConfig(), cb.metricsConfig(), cb.processorConfig(), recuperacion);
    }

    public void iniciar() {
        hilo = new Thread(scheduler, "kcl-" + aplicacion);
        hilo.start();
    }

    public void detener() {
        detener(Duration.ofSeconds(30));
    }

    /** Cierre ordenado: suelta los leases y hace el último checkpoint. */
    public void detener(Duration espera) {
        try {
            scheduler.startGracefulShutdown().get(espera.toMillis(), TimeUnit.MILLISECONDS);
        } catch (Exception e) {
            if (e instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
        }
    }

    static final class Procesador implements ShardRecordProcessor {
        private final Manejador manejador;
        private final Desvio desvio;
        private final int intentos;
        private String shardId = "?";

        Procesador(Manejador manejador, Desvio desvio, int intentos) {
            this.manejador = manejador;
            this.desvio = desvio;
            this.intentos = intentos;
        }

        @Override
        public void initialize(InitializationInput entrada) {
            shardId = entrada.shardId();
        }

        @Override
        public void processRecords(ProcessRecordsInput entrada) {
            for (KinesisClientRecord r : entrada.records()) {
                ByteBuffer b = r.data().duplicate();
                byte[] datos = new byte[b.remaining()];
                b.get(datos);
                procesarConReintento(r.partitionKey(), r.sequenceNumber(), datos);
            }
            checkpoint(entrada.checkpointer());
        }

        private void procesarConReintento(String clave, String secuencia, byte[] datos) {
            Exception ultima = null;
            for (int i = 1; i <= intentos; i++) {
                try {
                    manejador.procesar(shardId, clave, secuencia, datos);
                    return;
                } catch (Exception e) {
                    ultima = e;
                    try {
                        Thread.sleep(100L * i);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
            desvio.desviar(shardId, clave, secuencia, datos, ultima);
        }

        private static void checkpoint(software.amazon.kinesis.processor.RecordProcessorCheckpointer c) {
            try {
                c.checkpoint();
            } catch (Exception e) {
                throw new IllegalStateException("checkpoint falló", e);
            }
        }

        @Override
        public void leaseLost(LeaseLostInput entrada) {
            // otra instancia tomó el shard: no hagas checkpoint
        }

        @Override
        public void shardEnded(ShardEndedInput entrada) {
            checkpoint(entrada.checkpointer());   // obligatorio para pasar a los shards hijos tras un resharding
        }

        @Override
        public void shutdownRequested(ShutdownRequestedInput entrada) {
            checkpoint(entrada.checkpointer());
        }
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.cloudwatch.CloudWatchAsyncClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbAsyncClient;
import software.amazon.awssdk.services.kinesis.KinesisAsyncClient;
import software.amazon.awssdk.services.kinesis.KinesisClient;
import tools.jackson.databind.json.JsonMapper;

@Configuration
class KinesisConfig {
    @Bean(destroyMethod = "close")
    KinesisClient kinesis() {
        return KinesisClient.create();
    }

    @Bean
    ProductorKinesis productor(KinesisClient kinesis, @Value("${app.stream-clics}") String stream) {
        return new ProductorKinesis(kinesis, stream);
    }

    /** KCL arranca con la aplicación y se cierra de forma ordenada al apagar (initMethod / destroyMethod). */
    @Bean(initMethod = "iniciar", destroyMethod = "detener")
    ConsumidorKcl consumidor(@Value("${app.stream-clics}") String stream, @Value("${app.aplicacion-kcl}") String app) {
        return new ConsumidorKcl(stream, app, KinesisAsyncClient.create(), DynamoDbAsyncClient.create(),
                CloudWatchAsyncClient.create(),
                (shard, clave, secuencia, datos) -> System.out.println(shard + " " + clave + " " + new String(datos)),   // tu negocio (idempotente)
                (shard, clave, secuencia, datos, causa) -> System.err.println("desviar " + secuencia + ": " + causa),   // envía a una DLQ
                false, null);
    }
}

record ClicDto(String idSesion, String tipo, String sku) {}

@RestController
class ClicsController {
    private final ProductorKinesis productor;
    private final JsonMapper json;

    ClicsController(ProductorKinesis productor, JsonMapper json) {
        this.productor = productor;
        this.json = json;
    }

    @PostMapping("/clics")
    Map<String, Object> publicar(@RequestBody List<ClicDto> clics) {
        var registros = clics.stream()
                .map(c -> new ProductorKinesis.Registro(c.idSesion(), json.writeValueAsBytes(c))).toList();
        productor.publicar(registros);
        return Map.of("publicados", registros.size());
    }

    /** ¿Mi clave reparte bien? Pasa claves reales y el número de shards. */
    @GetMapping("/kinesis/simular")
    Map<String, Object> simular(@RequestParam List<String> claves, @RequestParam int shards) {
        var r = ParticionKinesis.simular(claves, shards);
        return Map.of("porShard", r.porShard(), "factorCalor", r.factorCalor(), "caliente", r.hayShardCaliente(1.5));
    }

    @ExceptionHandler(ProductorKinesis.PublicacionParcialException.class)
    ResponseEntity<Map<String, Object>> parcial(ProductorKinesis.PublicacionParcialException e) {
        return ResponseEntity.status(207).body(Map.of("fallidos", e.fallidos().size()));
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

record ClicReactivoDto(String idSesion, String json) {}

@RestController
class ClicsReactivoController {
    private final ProductorKinesis productor;

    ClicsReactivoController(ProductorKinesis productor) {
        this.productor = productor;
    }

    /** El SDK síncrono bloquea (y el reintento duerme): se aísla en boundedElastic. */
    @PostMapping("/clics-r")
    Mono<Map<String, Object>> publicar(@RequestBody Mono<List<ClicReactivoDto>> cuerpo) {
        return cuerpo.flatMap(clics -> Mono.fromCallable(() -> {
            var registros = clics.stream().map(c -> ProductorKinesis.Registro.texto(c.idSesion(), c.json())).toList();
            productor.publicar(registros);
            return Map.<String, Object>of("publicados", registros.size());
        }).subscribeOn(Schedulers.boundedElastic()));
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.quarkus.runtime.ShutdownEvent;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.cloudwatch.CloudWatchAsyncClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbAsyncClient;
import software.amazon.awssdk.services.kinesis.KinesisAsyncClient;
import software.amazon.awssdk.services.kinesis.KinesisClient;

@ApplicationScoped
class KinesisProductores {
    @Produces
    @Singleton
    ProductorKinesis productor(KinesisClient kinesis, @ConfigProperty(name = "app.stream-clics") String stream) {
        return new ProductorKinesis(kinesis, stream);
    }

    @Produces
    @Singleton
    ConsumidorKcl consumidor(@ConfigProperty(name = "app.stream-clics") String stream,
                             @ConfigProperty(name = "app.aplicacion-kcl") String app,
                             KinesisAsyncClient kinesis, DynamoDbAsyncClient dynamo, CloudWatchAsyncClient cloudWatch) {
        return new ConsumidorKcl(stream, app, kinesis, dynamo, cloudWatch,
                (shard, clave, secuencia, datos) -> System.out.println(shard + " " + clave + " " + new String(datos)),   // tu negocio (idempotente)
                (shard, clave, secuencia, datos, causa) -> System.err.println("desviar " + secuencia + ": " + causa),
                false, null);
    }

    void alArrancar(@Observes StartupEvent ev, ConsumidorKcl consumidor) {
        consumidor.iniciar();
    }

    void alParar(@Observes ShutdownEvent ev, ConsumidorKcl consumidor) {
        consumidor.detener();
    }
}
```
```java
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Path("/clics")
class ClicsRecurso {
    public record ClicDto(String idSesion, String tipo, String sku) {}

    @Inject
    ProductorKinesis productor;

    @Inject
    ObjectMapper json;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response publicar(List<ClicDto> clics) throws Exception {
        var registros = new ArrayList<ProductorKinesis.Registro>();
        for (ClicDto c : clics) {
            registros.add(new ProductorKinesis.Registro(c.idSesion(), json.writeValueAsBytes(c)));
        }
        try {
            productor.publicar(registros);
            return Response.ok(Map.of("publicados", registros.size())).build();
        } catch (ProductorKinesis.PublicacionParcialException e) {
            return Response.status(207).entity(Map.of("fallidos", e.fallidos().size())).build();
        }
    }

    @GET
    @Path("/simular")
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, Object> simular(@QueryParam("claves") List<String> claves, @QueryParam("shards") int shards) {
        var r = ParticionKinesis.simular(claves, shards);
        return Map.of("porShard", r.porShard(), "factorCalor", r.factorCalor(), "caliente", r.hayShardCaliente(1.5));
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.kinesis.KinesisAsyncClient;
import software.amazon.awssdk.services.kinesis.model.PutRecordRequest;

@Path("/clics-r")
class ClicsMutinyRecurso {
    @Inject
    KinesisAsyncClient kinesis;

    @ConfigProperty(name = "app.stream-clics")
    String stream;

    /** Un registro con el cliente asíncrono: no bloquea el hilo de eventos. Para lotes, usa ProductorKinesis en un pool de trabajo. */
    @POST
    @Path("/{sesion}")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Map<String, String>> publicar(@jakarta.ws.rs.PathParam("sesion") String sesion, String json) {
        var rq = PutRecordRequest.builder().streamName(stream).partitionKey(sesion).data(SdkBytes.fromUtf8String(json)).build();
        return Uni.createFrom().completionStage(() -> kinesis.putRecord(rq))
                .map(r -> Map.of("shard", r.shardId(), "secuencia", r.sequenceNumber()));
    }
}
```

## 7. Permisos
Productor y consumidor: [`ejemplos/json/politica-productor.json`](ejemplos/json/politica-productor.json) y [`ejemplos/json/politica-consumidor-kcl.json`](ejemplos/json/politica-consumidor-kcl.json) (el consumidor KCL necesita además DynamoDB y CloudWatch).

## 8. Qué NO hacer desde Java
- **No** elijas la clave de partición sin simularla con datos reales.
- **No** asumas que `PutRecords` con 200 escribió todo: revisa `failedRecordCount` y reintenta solo los fallidos.
- **No** compares números de secuencia como texto.
- **No** hagas `checkpoint` antes de procesar.
- **No** dejes que una excepción escape de `processRecords` esperando un reintento automático: KCL sigue con el siguiente lote.
- **No** escribas tu propio reparto de shards con `GetRecords` en producción: usa KCL o Lambda.
- **No** olvides `detener()`: sin cierre ordenado, otra instancia espera a que expire el *lease*.
- **No** llames a `publicar` desde un hilo de eventos reactivo sin aislarlo.
