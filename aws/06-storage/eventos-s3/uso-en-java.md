# AWS · Eventos de S3 · Uso desde Java

Un consumidor de eventos de S3 hace siempre lo mismo: **leer** el cuerpo (notificación, EventBridge o SNS), **decodificar la clave**, **filtrar** (evitar recursión), **deduplicar / ordenar** y **verificar** el objeto antes de procesarlo. Ese trabajo es puro y se comparte en los dos frameworks. Versiones: Java 21, Spring Boot 4.1 (Spring Cloud AWS 4.2), Quarkus 3.40, AWS SDK v2 (BOM 2.56), `aws-lambda-java-events` 3.16.

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
          max-concurrent-messages: 10
app:
  bucket: modalima-prod-datos-111122223333-us-east-1
  cola-eventos: prod-eventos-s3-entrada
  prefijo-entrada: entrada/
```
```properties
# Quarkus (application.properties)
quarkus.s3.aws.region=us-east-1
quarkus.lambda.handler=s3-eventos
app.bucket=modalima-prod-datos-111122223333-us-east-1
app.prefijo-entrada=entrada/
```

## 2. Núcleo común

### 2.1 Lector de JSON mínimo (sin Jackson)
Spring usa Jackson 3 y Quarkus Jackson 2; un manejador de Lambda no trae ninguno. Un lector pequeño devuelve `Map`/`List`/`String`/`Long`/`Double`/`Boolean`/`null` y sirve en los tres sitios.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class JsonLector {
    private static final int PROFUNDIDAD_MAX = 32;
    private final String s;
    private int i;

    private JsonLector(String s) {
        this.s = s;
    }

    public static Object leer(String texto) {
        if (texto == null) {
            throw new IllegalArgumentException("JSON nulo");
        }
        JsonLector p = new JsonLector(texto);
        Object v = p.valor(0);
        p.espacios();
        if (p.i != texto.length()) {
            throw new IllegalArgumentException("JSON inválido: texto sobrante en " + p.i);
        }
        return v;
    }

    private void espacios() {
        while (i < s.length() && Character.isWhitespace(s.charAt(i))) {
            i++;
        }
    }

    private IllegalArgumentException error(String m) {
        return new IllegalArgumentException("JSON inválido: " + m + " (posición " + i + ")");
    }

    private Object valor(int nivel) {
        if (nivel > PROFUNDIDAD_MAX) {
            throw error("demasiado anidado");
        }
        espacios();
        if (i >= s.length()) {
            throw error("fin inesperado");
        }
        char c = s.charAt(i);
        if (c == '{') {
            return objeto(nivel);
        }
        if (c == '[') {
            return lista(nivel);
        }
        if (c == '"') {
            return cadena();
        }
        return literal();
    }

    private Map<String, Object> objeto(int nivel) {
        Map<String, Object> r = new LinkedHashMap<>();
        i++;
        espacios();
        if (i < s.length() && s.charAt(i) == '}') {
            i++;
            return r;
        }
        while (true) {
            espacios();
            String k = cadena();
            espacios();
            if (i >= s.length() || s.charAt(i++) != ':') {
                throw error("se esperaba ':'");
            }
            r.put(k, valor(nivel + 1));
            espacios();
            if (i < s.length() && s.charAt(i) == ',') {
                i++;
                continue;
            }
            if (i < s.length() && s.charAt(i) == '}') {
                i++;
                return r;
            }
            throw error("se esperaba ',' o '}'");
        }
    }

    private List<Object> lista(int nivel) {
        List<Object> r = new ArrayList<>();
        i++;
        espacios();
        if (i < s.length() && s.charAt(i) == ']') {
            i++;
            return r;
        }
        while (true) {
            r.add(valor(nivel + 1));
            espacios();
            if (i < s.length() && s.charAt(i) == ',') {
                i++;
                continue;
            }
            if (i < s.length() && s.charAt(i) == ']') {
                i++;
                return r;
            }
            throw error("se esperaba ',' o ']'");
        }
    }

    private String cadena() {
        if (i >= s.length() || s.charAt(i) != '"') {
            throw error("se esperaba una cadena");
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
                        throw error("escape \\u incompleto");
                    }
                    sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                    i += 4;
                }
                default -> throw error("escape inválido \\" + e);
            }
        }
        throw error("cadena sin cerrar");
    }

    private Object literal() {
        int ini = i;
        while (i < s.length() && ",]} \t\r\n".indexOf(s.charAt(i)) < 0) {
            i++;
        }
        String t = s.substring(ini, i);
        switch (t) {
            case "true":
                return Boolean.TRUE;
            case "false":
                return Boolean.FALSE;
            case "null":
                return null;
            default:
                try {
                    if (t.contains(".") || t.contains("e") || t.contains("E")) {
                        return Double.parseDouble(t);
                    }
                    return Long.parseLong(t);
                } catch (NumberFormatException e) {
                    i = ini;
                    throw error("literal inválido '" + t + "'");
                }
        }
    }
}
```

### 2.2 Eventos de S3 normalizados (notificación, EventBridge y SNS)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public record EventoS3(String origen, String tipo, String bucket, String clave, long tamano, String etag,
                       String versionId, String sequencer, String region, String momento) {

    public boolean esCreacion() {
        return tipo.startsWith("ObjectCreated") || tipo.startsWith("Object Created");
    }
}

final class LectorEventosS3 {
    private LectorEventosS3() {}

    static List<EventoS3> desdeCuerpo(String json) {
        Object o = JsonLector.leer(json);
        if (!(o instanceof Map<?, ?> m)) {
            throw new IllegalArgumentException("el cuerpo no es un objeto JSON");
        }
        return desdeMapa(castMapa(m));
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMapa(Object o) {
        return o instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    private static List<Object> lista(Object o) {
        return o instanceof List<?> l ? new ArrayList<>(l) : List.of();
    }

    private static String texto(Object o) {
        return o == null ? "" : String.valueOf(o);
    }

    private static long numero(Object o) {
        return o instanceof Number n ? n.longValue() : 0L;
    }

    static List<EventoS3> desdeMapa(Map<String, Object> m) {
        if ("s3:TestEvent".equals(m.get("Event"))) {
            return List.of();                                          // prueba de configuración
        }
        if ("Notification".equals(m.get("Type")) && m.get("Message") instanceof String interno) {
            return desdeCuerpo(interno);                               // S3 → SNS → SQS: el evento viene dentro de "Message"
        }
        if (m.containsKey("Records")) {
            List<EventoS3> r = new ArrayList<>();
            for (Object reg : lista(m.get("Records"))) {
                Map<String, Object> rec = castMapa(reg);
                Map<String, Object> s3 = castMapa(rec.get("s3"));
                Map<String, Object> obj = castMapa(s3.get("object"));
                String claveCodificada = texto(obj.get("key"));
                r.add(new EventoS3("notificacion", texto(rec.get("eventName")),
                        texto(castMapa(s3.get("bucket")).get("name")),
                        URLDecoder.decode(claveCodificada, StandardCharsets.UTF_8),   // '+' → espacio, %XX → byte
                        numero(obj.get("size")), texto(obj.get("eTag")), texto(obj.get("versionId")),
                        texto(obj.get("sequencer")), texto(rec.get("awsRegion")), texto(rec.get("eventTime"))));
            }
            return r;
        }
        if ("aws.s3".equals(m.get("source")) && m.containsKey("detail-type")) {
            Map<String, Object> d = castMapa(m.get("detail"));
            Map<String, Object> obj = castMapa(d.get("object"));
            String motivo = texto(d.get("reason"));
            String tipo = texto(m.get("detail-type")) + (motivo.isEmpty() ? "" : ":" + motivo);
            return List.of(new EventoS3("eventbridge", tipo,
                    texto(castMapa(d.get("bucket")).get("name")),
                    texto(obj.get("key")),                              // en EventBridge la clave NO viene codificada
                    numero(obj.get("size")), texto(obj.get("etag")), texto(obj.get("version-id")),
                    texto(obj.get("sequencer")), texto(m.get("region")), texto(m.get("time"))));
        }
        throw new IllegalArgumentException("formato de evento no reconocido");
    }
}
```

### 2.3 Filtro anti-recursión, deduplicación y orden
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class FiltroEventos {
    private final String prefijoEntrada;
    private final Set<String> sufijos;
    private final Set<String> prefijosIgnorados;

    public FiltroEventos(String prefijoEntrada, Set<String> sufijos, Set<String> prefijosIgnorados) {
        this.prefijoEntrada = prefijoEntrada;
        this.sufijos = sufijos;
        this.prefijosIgnorados = prefijosIgnorados;
    }

    /** Solo creaciones reales, dentro del prefijo de entrada, no vacías, con extensión esperada y fuera de las salidas. */
    public boolean aceptar(EventoS3 e) {
        if (!e.esCreacion() || !e.clave().startsWith(prefijoEntrada) || e.clave().endsWith("/") || e.tamano() <= 0) {
            return false;
        }
        for (String ignorado : prefijosIgnorados) {
            if (e.clave().startsWith(ignorado)) {
                return false;
            }
        }
        String minus = e.clave().toLowerCase(Locale.ROOT);
        return sufijos.isEmpty() || sufijos.stream().anyMatch(minus::endsWith);
    }
}

public final class Deduplicador {
    private final int capacidad;
    private final Duration ttl;
    private final Map<String, Instant> vistos;
    private final Map<String, String> ultimoSequencer;

    public Deduplicador(int capacidad, Duration ttl) {
        this.capacidad = capacidad;
        this.ttl = ttl;
        this.vistos = new LinkedHashMap<>();
        this.ultimoSequencer = new LinkedHashMap<>();
    }

    /** Compara dos sequencers de la MISMA clave: se rellena con ceros a la derecha el más corto. */
    public static int compararSequencer(String a, String b) {
        int n = Math.max(a.length(), b.length());
        String x = (a + "0".repeat(n - a.length())).toUpperCase(Locale.ROOT);
        String y = (b + "0".repeat(n - b.length())).toUpperCase(Locale.ROOT);
        return x.compareTo(y);
    }

    private static String id(EventoS3 e) {
        return e.bucket() + "|" + e.clave() + "|" + e.versionId() + "|" + e.sequencer() + "|" + e.tipo();
    }

    public synchronized boolean yaProcesado(EventoS3 e) {
        Instant t = vistos.get(id(e));
        return t != null && t.isAfter(Instant.now());
    }

    /** Llamar SOLO cuando el trabajo terminó bien: si falla, el reintento no debe parecer duplicado. */
    public synchronized void marcar(EventoS3 e) {
        vistos.put(id(e), Instant.now().plus(ttl));
        if (vistos.size() > capacidad) {
            var it = vistos.entrySet().iterator();
            it.next();
            it.remove();
        }
    }

    /** ¿Este evento es más nuevo que el último que vimos para la misma clave? Registra el más nuevo. */
    public synchronized boolean esVigente(EventoS3 e) {
        String k = e.bucket() + "|" + e.clave();
        String previo = ultimoSequencer.get(k);
        if (previo != null && compararSequencer(e.sequencer(), previo) <= 0) {
            return false;
        }
        ultimoSequencer.put(k, e.sequencer());
        if (ultimoSequencer.size() > capacidad) {
            var it = ultimoSequencer.entrySet().iterator();
            it.next();
            it.remove();
        }
        return true;
    }
}
```

### 2.4 Verificar el objeto y manejador de Lambda (SQS con fallos parciales)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import java.util.ArrayList;
import java.util.Optional;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

public final class VerificadorObjeto {
    public record Metadatos(long tamano, String contentType, String etag) {}

    private final S3Client s3;

    public VerificadorObjeto(S3Client s3) {
        this.s3 = s3;
    }

    /** HEAD con el versionId del evento. Vacío si el objeto ya no existe (borrado antes de procesar). */
    public Optional<Metadatos> metadatos(EventoS3 e) {
        HeadObjectRequest.Builder b = HeadObjectRequest.builder().bucket(e.bucket()).key(e.clave());
        if (!e.versionId().isEmpty()) {
            b.versionId(e.versionId());
        }
        try {
            HeadObjectResponse r = s3.headObject(b.build());
            return Optional.of(new Metadatos(r.contentLength(), r.contentType(), r.eTag()));
        } catch (NoSuchKeyException ex) {
            return Optional.empty();
        }
    }
}

public final class ManejadorEventosS3 implements RequestHandler<SQSEvent, SQSBatchResponse> {
    /** Lo que hace tu negocio con cada evento válido. */
    public interface Accion {
        void aplicar(EventoS3 evento) throws Exception;
    }

    private final FiltroEventos filtro;
    private final Deduplicador dedup;
    private final Accion accion;

    public ManejadorEventosS3(FiltroEventos filtro, Deduplicador dedup, Accion accion) {
        this.filtro = filtro;
        this.dedup = dedup;
        this.accion = accion;
    }

    @Override
    public SQSBatchResponse handleRequest(SQSEvent evento, Context contexto) {
        List<SQSBatchResponse.BatchItemFailure> fallos = new ArrayList<>();
        for (SQSEvent.SQSMessage mensaje : evento.getRecords()) {
            try {
                for (EventoS3 e : LectorEventosS3.desdeCuerpo(mensaje.getBody())) {
                    if (!filtro.aceptar(e) || dedup.yaProcesado(e) || !dedup.esVigente(e)) {
                        continue;
                    }
                    accion.aplicar(e);
                    dedup.marcar(e);
                }
            } catch (Exception ex) {
                fallos.add(new SQSBatchResponse.BatchItemFailure(mensaje.getMessageId()));   // solo este mensaje se reintenta
            }
        }
        return SQSBatchResponse.builder().withBatchItemFailures(fallos).build();
    }
}
```
> `Deduplicador` en memoria cubre un contenedor de Lambda o un proceso. Para exactitud entre réplicas usa la **reserva atómica en DynamoDB** del [Claim Check](../claim-check/uso-en-java.md).

## 3. Spring MVC (imperativo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
class EventosConfig {
    @Bean
    FiltroEventos filtro(@Value("${app.prefijo-entrada}") String entrada) {
        return new FiltroEventos(entrada, Set.of(".csv"), Set.of("procesados/", "errores/"));
    }

    @Bean
    Deduplicador deduplicador() {
        return new Deduplicador(10_000, Duration.ofHours(1));
    }

    @Bean
    VerificadorObjeto verificador(S3Client s3) {
        return new VerificadorObjeto(s3);
    }
}

@Component
class EventosS3Listener {
    private final FiltroEventos filtro;
    private final Deduplicador dedup;
    private final VerificadorObjeto verificador;
    private final String bucketEsperado;

    EventosS3Listener(FiltroEventos filtro, Deduplicador dedup, VerificadorObjeto verificador,
                      @Value("${app.bucket}") String bucketEsperado) {
        this.filtro = filtro;
        this.dedup = dedup;
        this.verificador = verificador;
        this.bucketEsperado = bucketEsperado;
    }

    /** Si lanza excepción, el mensaje NO se borra: reaparece y, tras N intentos, va a la DLQ. */
    @SqsListener("${app.cola-eventos}")
    void recibir(String cuerpo) {
        for (EventoS3 e : LectorEventosS3.desdeCuerpo(cuerpo)) {
            if (!e.bucket().equals(bucketEsperado)) {
                throw new IllegalStateException("evento de un bucket inesperado: " + e.bucket());
            }
            if (!filtro.aceptar(e) || dedup.yaProcesado(e) || !dedup.esVigente(e)) {
                continue;
            }
            verificador.metadatos(e).ifPresent(m ->
                    System.out.println("procesando " + e.clave() + " (" + m.tamano() + " bytes)"));   // tu negocio
            dedup.marcar(e);
        }
    }
}

@RestController
class SimuladorEventosController {
    /** Para pruebas locales: pega aquí un evento real y ve cómo lo interpreta el lector. */
    @PostMapping("/interno/eventos/leer")
    List<EventoS3> leer(@RequestBody String json) {
        return LectorEventosS3.desdeCuerpo(json);
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@Component
class EventosReactivosListener {
    private final FiltroEventos filtro;
    private final Deduplicador dedup;
    private final VerificadorObjeto verificador;

    EventosReactivosListener(FiltroEventos filtro, Deduplicador dedup, VerificadorObjeto verificador) {
        this.filtro = filtro;
        this.dedup = dedup;
        this.verificador = verificador;
    }

    /** Verificaciones HEAD en paralelo (máx. 8) sobre boundedElastic, porque el SDK síncrono bloquea. */
    @SqsListener("${app.cola-eventos}")
    CompletableFuture<Void> recibir(String cuerpo) {
        return Flux.fromIterable(LectorEventosS3.desdeCuerpo(cuerpo))
                .filter(e -> filtro.aceptar(e) && !dedup.yaProcesado(e) && dedup.esVigente(e))
                .flatMap(e -> Mono.fromCallable(() -> verificador.metadatos(e))
                        .subscribeOn(Schedulers.boundedElastic())
                        .doOnNext(m -> m.ifPresent(x -> System.out.println("procesando " + e.clave())))
                        .doOnSuccess(m -> dedup.marcar(e)), 8)
                .then()
                .toFuture();
    }
}

@RestController
class SimuladorEventosReactivoController {
    @PostMapping("/interno/eventos/leer-r")
    Mono<List<EventoS3>> leer(@RequestBody Mono<String> json) {
        return json.map(LectorEventosS3::desdeCuerpo);
    }
}
```

## 5. Quarkus (imperativo): Lambda con SQS
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import java.time.Duration;
import java.util.Set;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;

/** Con quarkus-amazon-lambda: quarkus.lambda.handler=s3-eventos selecciona este manejador. */
@Named("s3-eventos")
@ApplicationScoped
class S3EventosLambda implements RequestHandler<SQSEvent, SQSBatchResponse> {
    private final ManejadorEventosS3 manejador;

    @Inject
    S3EventosLambda(@ConfigProperty(name = "app.prefijo-entrada") String entrada) {
        this.manejador = new ManejadorEventosS3(
                new FiltroEventos(entrada, Set.of(".csv"), Set.of("procesados/", "errores/")),
                new Deduplicador(5_000, Duration.ofMinutes(30)),
                e -> System.out.println("procesando " + e.clave()));          // tu negocio
    }

    @Override
    public SQSBatchResponse handleRequest(SQSEvent evento, Context contexto) {
        return manejador.handleRequest(evento, contexto);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.s3.S3AsyncClient;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;

@Path("/interno/eventos")
class EventosMutinyRecurso {
    @Inject
    S3AsyncClient s3;

    /** Recibe un evento (cuerpo JSON), lo normaliza y verifica cada objeto con HEAD asíncrono, 8 a la vez. */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<List<Map<String, Object>>> verificar(String cuerpo) {
        return Multi.createFrom().iterable(LectorEventosS3.desdeCuerpo(cuerpo))
                .onItem().transformToUniAndMerge(e ->
                        Uni.createFrom().completionStage(() -> s3.headObject(
                                        HeadObjectRequest.builder().bucket(e.bucket()).key(e.clave()).build()))
                                .map(h -> Map.<String, Object>of("clave", e.clave(), "existe", true, "tamano", h.contentLength()))
                                .onFailure().recoverWithItem(Map.<String, Object>of("clave", e.clave(), "existe", false)))
                .collect().asList();
    }
}
```

## 7. Permisos
Consumidor: `sqs:ReceiveMessage`, `sqs:DeleteMessage` sobre la cola; `s3:GetObject` (y `s3:GetObjectVersion` si verificas versiones) sobre el prefijo de entrada. La **cola** debe autorizar a `s3.amazonaws.com` con `aws:SourceArn` y `aws:SourceAccount` ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)).

## 8. Qué NO hacer desde Java
- **No** uses la clave de una notificación sin decodificarla; en EventBridge **no** la decodifiques otra vez.
- **No** escribas el resultado en el prefijo de entrada (bucle infinito).
- **No** marques como procesado antes de terminar el trabajo.
- **No** asumas orden: compara `sequencer` por clave.
- **No** ejecutes nada con una clave sin validar bucket y prefijo.
- **No** devuelvas error de todo el lote en Lambda si solo falló un mensaje: usa `batchItemFailures`.
- **No** pongas lógica pesada en el manejador del evento: delega a una cola o a un trabajo con tiempo propio.
