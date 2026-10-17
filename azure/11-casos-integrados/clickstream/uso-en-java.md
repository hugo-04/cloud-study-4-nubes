# Azure · Casos integrados · Clickstream · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-messaging-eventhubs`, `azure-messaging-eventhubs-checkpointstore-blob`, `azure-identity`, `azure-json`). Verifica las vigentes.

El capítulo de [Event Hubs](../../07-mensajeria/event-hubs-kafka/uso-en-java.md) ya explica el SDK, el cliente Kafka, los puntos de control y el *replay*. Este caso añade lo que une todo en una analítica de clics: **dimensionar, elegir la clave, recibir en lotes sin perder privacidad, agregar por ventanas y saber cuándo el resultado es aproximado**.

## El diseño

```
 Web/App ──POST lote (≤100 clics)──► Colector ──► Event Hubs «clics» (8 particiones, clave = cubeta de la sesión)
                                       │                  │                 │
                          valida, anonimiza        grupo «agregador»    CAPTURE (cada 5 min)
                                                         │                 │
                                          Agregador por minuto           Data Lake (Avro, crudo, para siempre)
                                          (ventanas + duplicados)              │
                                                         │               procesos por lotes (exactos)
                                              Redis / tabla de resúmenes ◄──── recalculan lo que el agregador estimó
```

**Dos caminos con distinta promesa:**

| Camino | Latencia | Exactitud | Para qué |
|---|---|---|---|
| **Agregador en línea** (este código) | Segundos | Aproximada: tras un reinicio una ventana abierta puede quedar incompleta | Tableros «en vivo», alertas de campaña |
| **Lago + proceso por lotes** (Capture) | Minutos–horas | Exacta, reproducible | Reportes, facturación, ciencia de datos |

Permisos (plano de datos): el **colector** solo *Azure Event Hubs Data Sender* en el event hub; el **agregador** *Data Receiver* en el event hub y datos de blob en el contenedor de puntos de control; **Capture** usa la identidad del espacio de nombres con *Storage Blob Data Contributor* en el lago. Terraform completo: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-eventhubs</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-eventhubs-checkpointstore-blob</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-json</artifactId></dependency>
```

## 1. Evento, planificador de capacidad, sesgo y privacidad (puro, sin red)

La capacidad se calcula, no se adivina. **Los valores por unidad son reglas prácticas del nivel Standard** (1 unidad ≈ 1 MB/s o 1 000 eventos/s de entrada y 2 MB/s de salida): verifica los vigentes en la doc oficial.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.json.JsonProviders;
import com.azure.json.JsonReader;
import com.azure.json.JsonToken;
import com.azure.json.JsonWriter;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.IOException;
import java.io.StringWriter;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

public record Clic(String eventId, String sesionId, String pagina, long marcaDeTiempo) { }

public final class ClicJson {

    private ClicJson() { }

    public static String aJson(Clic clic) {
        StringWriter salida = new StringWriter();
        try (JsonWriter json = JsonProviders.createWriter(salida)) {
            json.writeStartObject()
                    .writeStringField("eventId", clic.eventId())
                    .writeStringField("sesionId", clic.sesionId())
                    .writeStringField("pagina", clic.pagina())
                    .writeLongField("marcaDeTiempo", clic.marcaDeTiempo())
                    .writeEndObject().flush();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return salida.toString();
    }

    /** Lanza IllegalArgumentException si el JSON no es un clic válido: un mensaje malo no debe tumbar al procesador. */
    public static Clic deJson(String texto) {
        try (JsonReader lector = JsonProviders.createReader(texto)) {
            return lector.readObject(r -> {
                String id = null;
                String sesion = null;
                String pagina = null;
                long marca = 0;
                while (r.nextToken() != JsonToken.END_OBJECT) {
                    String campo = r.getFieldName();
                    r.nextToken();
                    switch (campo) {
                        case "eventId" -> id = r.getString();
                        case "sesionId" -> sesion = r.getString();
                        case "pagina" -> pagina = r.getString();
                        case "marcaDeTiempo" -> marca = r.getLong();
                        default -> r.skipChildren();
                    }
                }
                if (id == null || sesion == null || pagina == null) {
                    throw new IllegalArgumentException("Clic incompleto");
                }
                return new Clic(id, sesion, pagina, marca);
            });
        } catch (IOException | IllegalStateException e) {
            throw new IllegalArgumentException("Clic ilegible", e);
        }
    }
}

public final class PlanificadorDeCapacidad {

    public record Entrada(double eventosPorSegundoPico, int bytesPorEvento, double margen,
                          int lectoresIndependientes, int consumidoresEnParalelo, int diasDeRetencion) { }

    public record Plan(double entradaMBs, double salidaMBs, int unidades, int particiones, double retencionGB, List<String> avisos) { }

    // Reglas prácticas del nivel Standard (verifica en la doc oficial)
    private static final double MB_POR_UNIDAD_ENTRADA = 1.0;
    private static final double EVENTOS_POR_UNIDAD = 1000.0;
    private static final double MB_POR_UNIDAD_SALIDA = 2.0;

    private PlanificadorDeCapacidad() { }

    public static Plan calcular(Entrada e) {
        if (e.eventosPorSegundoPico() <= 0 || e.bytesPorEvento() <= 0 || e.margen() < 1 || e.lectoresIndependientes() < 1
                || e.consumidoresEnParalelo() < 1 || e.diasDeRetencion() < 1) {
            throw new IllegalArgumentException("Entrada inválida");
        }
        double eventos = e.eventosPorSegundoPico() * e.margen();
        double entrada = eventos * e.bytesPorEvento() / (1024.0 * 1024.0);
        double salida = entrada * e.lectoresIndependientes();
        int unidades = (int) Math.ceil(Math.max(entrada / MB_POR_UNIDAD_ENTRADA,
                Math.max(eventos / EVENTOS_POR_UNIDAD, salida / MB_POR_UNIDAD_SALIDA)));
        unidades = Math.max(unidades, 1);
        int particiones = Math.max(Math.max(e.consumidoresEnParalelo(), unidades), 2);
        if (particiones % 2 != 0) {
            particiones++;
        }
        // Almacenamiento del promedio (aprox.: la mitad del pico) durante la retención
        double retencionGB = entrada / 2 * 86_400.0 * e.diasDeRetencion() / 1024.0;
        List<String> avisos = new ArrayList<>();
        if (e.bytesPorEvento() > 100_000) {
            avisos.add("Eventos grandes: considera Claim Check (guardar el contenido en Blob y enviar la referencia)");
        }
        if (particiones > 32) {
            avisos.add("Más de 32 particiones: revisa el límite de tu nivel o usa un nivel dedicado");
        }
        if (e.lectoresIndependientes() > 5) {
            avisos.add("Muchos lectores independientes: la salida crece en proporción; considera una etapa intermedia");
        }
        return new Plan(entrada, salida, unidades, particiones, retencionGB, avisos);
    }
}

/** Mismo evento de sesión -> misma cubeta -> misma partición: se conserva el orden por sesión con pocas llaves distintas. */
public final class Cubetas {

    private Cubetas() { }

    public static String cubetaDe(String sesionId, int cubetas) {
        return "c" + Math.floorMod(sesionId.hashCode(), cubetas);
    }
}

public final class DetectorDeSesgo {

    public record Sesgo(String claveMasFrecuente, double participacionMaxima, double factorDeDesbalance, boolean caliente) { }

    private DetectorDeSesgo() { }

    /** Con una muestra de eventos por clave, mide cuánto se desbalancean las cubetas. 1.0 = parejo. */
    public static Sesgo analizar(Map<String, Long> eventosPorClave, int cubetas, double umbral) {
        long total = 0;
        long maximo = 0;
        String maxima = "";
        Map<String, Long> porCubeta = new HashMap<>();
        for (var entrada : eventosPorClave.entrySet()) {
            total += entrada.getValue();
            if (entrada.getValue() > maximo) {
                maximo = entrada.getValue();
                maxima = entrada.getKey();
            }
            porCubeta.merge(Cubetas.cubetaDe(entrada.getKey(), cubetas), entrada.getValue(), Long::sum);
        }
        if (total == 0) {
            return new Sesgo("", 0, 1, false);
        }
        long cubetaMayor = porCubeta.values().stream().mapToLong(Long::longValue).max().orElse(0);
        double promedio = (double) total / cubetas;
        double factor = cubetaMayor / promedio;
        return new Sesgo(maxima, (double) maximo / total, factor, factor > umbral);
    }
}

/** Seudónimo estable e irreversible sin la sal: sirve para contar sesiones sin guardar identificadores reales. */
public final class Anonimizador {

    private final byte[] sal;

    public Anonimizador(byte[] sal) {
        if (sal == null || sal.length < 16) {
            throw new IllegalArgumentException("La sal debe tener al menos 16 bytes");
        }
        this.sal = sal.clone();
    }

    public String seudonimo(String valor) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(sal, "HmacSHA256"));
            byte[] resumen = mac.doFinal(valor.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(resumen, 0, 8);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }
}
```

## 2. El colector y el agregador por ventanas (puro)

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Set;

public interface PublicadorDeClics {
    void publicar(List<Clic> clics);
}

public final class ColectorDeClics {

    public static final int MAXIMO_POR_LOTE = 100;

    public record Resultado(int aceptados, int descartados) { }

    private final PublicadorDeClics publicador;
    private final Anonimizador anonimizador;
    private final Clock reloj;

    public ColectorDeClics(PublicadorDeClics publicador, Anonimizador anonimizador, Clock reloj) {
        this.publicador = publicador;
        this.anonimizador = anonimizador;
        this.reloj = reloj;
    }

    public Resultado recibir(List<Clic> lote) {
        if (lote == null || lote.isEmpty() || lote.size() > MAXIMO_POR_LOTE) {
            throw new IllegalArgumentException("El lote debe tener entre 1 y " + MAXIMO_POR_LOTE + " clics");
        }
        long ahora = reloj.millis();
        List<Clic> validos = new ArrayList<>(lote.size());
        for (Clic c : lote) {
            if (esValido(c, ahora)) {
                // Se publica el seudónimo de la sesión, nunca el identificador original
                validos.add(new Clic(c.eventId(), anonimizador.seudonimo(c.sesionId()), c.pagina(), c.marcaDeTiempo()));
            }
        }
        if (!validos.isEmpty()) {
            publicador.publicar(validos);
        }
        return new Resultado(validos.size(), lote.size() - validos.size());
    }

    private static boolean esValido(Clic c, long ahora) {
        return c != null
                && c.eventId() != null && !c.eventId().isBlank() && c.eventId().length() <= 64
                && c.sesionId() != null && !c.sesionId().isBlank() && c.sesionId().length() <= 64
                && c.pagina() != null && c.pagina().startsWith("/") && c.pagina().length() <= 200
                && c.marcaDeTiempo() > ahora - Duration.ofHours(24).toMillis()
                && c.marcaDeTiempo() < ahora + Duration.ofMinutes(5).toMillis();
    }
}

public final class AgregadorDeVentanas {

    public enum Resultado { ACEPTADO, DUPLICADO, TARDIO }

    public record ResumenMinuto(Instant ventana, String pagina, long visitas, long sesionesUnicas) { }

    private record Clave(long inicioMs, String pagina) { }

    private static final class Acumulador {
        long visitas;
        final Set<String> sesiones = new HashSet<>();
    }

    private final Clock reloj;
    private final long ventanaMs;
    private final long toleranciaMs;
    private final Map<Clave, Acumulador> abiertas = new HashMap<>();
    private final Map<String, Boolean> vistos;
    private long tardios;

    public AgregadorDeVentanas(Clock reloj, Duration ventana, Duration toleranciaTardia, int maximoDeVistos) {
        this.reloj = reloj;
        this.ventanaMs = ventana.toMillis();
        this.toleranciaMs = toleranciaTardia.toMillis();
        // Memoria acotada: recuerda los últimos N identificadores para descartar repetidos
        this.vistos = new LinkedHashMap<>(16, 0.75f, false) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, Boolean> eldest) {
                return size() > maximoDeVistos;
            }
        };
    }

    /** Seguro entre hilos: el procesador llama desde varias particiones a la vez. */
    public synchronized Resultado aceptar(Clic clic) {
        long inicio = Math.floorDiv(clic.marcaDeTiempo(), ventanaMs) * ventanaMs;
        if (inicio + ventanaMs + toleranciaMs <= reloj.millis()) {
            tardios++;
            return Resultado.TARDIO;
        }
        if (vistos.put(clic.eventId(), Boolean.TRUE) != null) {
            return Resultado.DUPLICADO;
        }
        Acumulador a = abiertas.computeIfAbsent(new Clave(inicio, clic.pagina()), k -> new Acumulador());
        a.visitas++;
        a.sesiones.add(clic.sesionId());
        return Resultado.ACEPTADO;
    }

    /** Entrega y olvida las ventanas que ya no admiten eventos tardíos. */
    public synchronized List<ResumenMinuto> cerrarListas() {
        long ahora = reloj.millis();
        List<ResumenMinuto> listos = new ArrayList<>();
        var it = abiertas.entrySet().iterator();
        while (it.hasNext()) {
            var e = it.next();
            if (e.getKey().inicioMs() + ventanaMs + toleranciaMs <= ahora) {
                listos.add(new ResumenMinuto(Instant.ofEpochMilli(e.getKey().inicioMs()), e.getKey().pagina(),
                        e.getValue().visitas, e.getValue().sesiones.size()));
                it.remove();
            }
        }
        return listos;
    }

    public synchronized long tardios() {
        return tardios;
    }
}

/** Dónde se guardan los resúmenes: debe ser un UPSERT por (ventana, página), no un incremento. */
public interface DestinoDeResumenes {
    void guardar(List<AgregadorDeVentanas.ResumenMinuto> resumenes);
}
```

## 3. Publicar en Event Hubs: un lote por cubeta
Un lote del SDK admite **una sola clave de partición**. Si usaras una clave por sesión tendrías cientos de lotes diminutos; con **cubetas** (por ejemplo 64) hay a lo sumo 64 lotes por solicitud, y cada sesión sigue cayendo siempre en la misma partición.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.messaging.eventhubs.EventData;
import com.azure.messaging.eventhubs.EventDataBatch;
import com.azure.messaging.eventhubs.EventHubProducerClient;
import com.azure.messaging.eventhubs.models.CreateBatchOptions;

public final class PublicadorEventHubs implements PublicadorDeClics {

    private final EventHubProducerClient productor;
    private final int cubetas;

    public PublicadorEventHubs(EventHubProducerClient productor, int cubetas) {
        this.productor = productor;
        this.cubetas = cubetas;
    }

    @Override
    public void publicar(List<Clic> clics) {
        Map<String, List<Clic>> porCubeta = new HashMap<>();
        for (Clic c : clics) {
            porCubeta.computeIfAbsent(Cubetas.cubetaDe(c.sesionId(), cubetas), k -> new ArrayList<>()).add(c);
        }
        for (var grupo : porCubeta.entrySet()) {
            enviarGrupo(grupo.getKey(), grupo.getValue());
        }
    }

    private void enviarGrupo(String clave, List<Clic> clics) {
        EventDataBatch lote = productor.createBatch(new CreateBatchOptions().setPartitionKey(clave));
        for (Clic c : clics) {
            EventData evento = new EventData(ClicJson.aJson(c));
            evento.getProperties().put("tipo", "clic.v1");
            if (!lote.tryAdd(evento)) {
                productor.send(lote);
                lote = productor.createBatch(new CreateBatchOptions().setPartitionKey(clave));
                if (!lote.tryAdd(evento)) {
                    throw new IllegalStateException("Un clic no cabe en un lote vacío");
                }
            }
        }
        if (lote.getCount() > 0) {
            productor.send(lote);
        }
    }
}
```

## 4. Spring Boot (MVC): colector, procesador y cierre de ventanas

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventhubs.EventHubClientBuilder;
import com.azure.messaging.eventhubs.EventHubProducerClient;
import com.azure.messaging.eventhubs.EventProcessorClient;
import com.azure.messaging.eventhubs.EventProcessorClientBuilder;
import com.azure.messaging.eventhubs.checkpointstore.blob.BlobCheckpointStore;
import com.azure.storage.blob.BlobContainerClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Configuration
@EnableScheduling
class ClicsConfiguracion {

    private static final System.Logger LOG = System.getLogger("clics.procesador");

    @Bean
    EventHubProducerClient productor(@Value("${clics.espacio}") String espacio) {
        return new EventHubClientBuilder()
                .fullyQualifiedNamespace(espacio)
                .eventHubName("clics")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildProducerClient();
    }

    @Bean
    Anonimizador anonimizador(@Value("${clics.sal}") String sal) {
        return new Anonimizador(sal.getBytes(java.nio.charset.StandardCharsets.UTF_8)); // la sal viene de Key Vault, no del repositorio
    }

    @Bean
    ColectorDeClics colector(EventHubProducerClient productor, Anonimizador anonimizador) {
        return new ColectorDeClics(new PublicadorEventHubs(productor, 64), anonimizador, Clock.systemUTC());
    }

    @Bean
    AgregadorDeVentanas agregador() {
        return new AgregadorDeVentanas(Clock.systemUTC(), Duration.ofMinutes(1), Duration.ofMinutes(2), 200_000);
    }

    @Bean(initMethod = "start", destroyMethod = "stop")
    EventProcessorClient procesador(@Value("${clics.espacio}") String espacio, @Value("${clics.puntos}") String cuentaPuntos,
                                    AgregadorDeVentanas agregador) {
        var credencial = new DefaultAzureCredentialBuilder().build();
        var contenedor = new BlobContainerClientBuilder()
                .endpoint("https://" + cuentaPuntos + ".blob.core.windows.net")
                .containerName("puntos-de-control")
                .credential(credencial)
                .buildAsyncClient();
        ConcurrentHashMap<String, AtomicInteger> contadores = new ConcurrentHashMap<>();
        return new EventProcessorClientBuilder()
                .fullyQualifiedNamespace(espacio)
                .eventHubName("clics")
                .consumerGroup("agregador")
                .credential(credencial)
                .checkpointStore(new BlobCheckpointStore(contenedor))
                .processEvent(contexto -> {
                    try {
                        Clic clic = ClicJson.deJson(contexto.getEventData().getBodyAsString());
                        if (agregador.aceptar(clic) == AgregadorDeVentanas.Resultado.TARDIO) {
                            LOG.log(System.Logger.Level.DEBUG, "clics.tardio");
                        }
                    } catch (IllegalArgumentException e) {
                        LOG.log(System.Logger.Level.WARNING, "clics.ilegible"); // un mensaje malo no detiene la partición
                    }
                    String particion = contexto.getPartitionContext().getPartitionId();
                    if (contadores.computeIfAbsent(particion, k -> new AtomicInteger()).incrementAndGet() % 500 == 0) {
                        contexto.updateCheckpoint(); // punto de control por conteo: no por cada evento
                    }
                })
                .processError(error -> LOG.log(System.Logger.Level.ERROR, "clics.error particion={0}: {1}",
                        error.getPartitionContext().getPartitionId(), error.getThrowable().getClass().getSimpleName()))
                .buildEventProcessorClient();
    }
}

@Component
class CierreDeVentanas {

    private final AgregadorDeVentanas agregador;
    private final DestinoDeResumenes destino;

    CierreDeVentanas(AgregadorDeVentanas agregador, DestinoDeResumenes destino) {
        this.agregador = agregador;
        this.destino = destino;
    }

    @Scheduled(fixedDelay = 10_000)
    void cerrar() {
        var listos = agregador.cerrarListas();
        if (!listos.isEmpty()) {
            destino.guardar(listos);
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

import java.util.List;

@RestController
@RequestMapping("/api/clics")
class ClicsControlador {

    record Lote(List<Clic> clics) { }

    private final ColectorDeClics colector;

    ClicsControlador(ColectorDeClics colector) {
        this.colector = colector;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.ACCEPTED) // 202: se aceptó para procesar; no promete que ya se calculó nada
    ColectorDeClics.Resultado recibir(@RequestBody Lote lote) {
        return colector.recibir(lote.clics());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ProblemDetail invalido(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }
}
```

## 5. Spring WebFlux (reactivo)
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

import java.util.List;

@RestController
@RequestMapping("/reactivo/api/clics")
class ClicsReactivoControlador {

    record Lote(List<Clic> clics) { }

    private final ColectorDeClics colector;

    ClicsReactivoControlador(ColectorDeClics colector) {
        this.colector = colector;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.ACCEPTED)
    Mono<ColectorDeClics.Resultado> recibir(@RequestBody Mono<Lote> lote) {
        return lote
                .flatMap(l -> Mono.fromCallable(() -> colector.recibir(l.clics())).subscribeOn(Schedulers.boundedElastic()))
                .onErrorMap(IllegalArgumentException.class, e -> new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()));
    }
}
```

## 6. Quarkus · imperativo
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.messaging.eventhubs.EventHubClientBuilder;
import com.azure.messaging.eventhubs.EventHubProducerClient;
import com.azure.messaging.eventhubs.EventProcessorClient;
import com.azure.messaging.eventhubs.EventProcessorClientBuilder;
import com.azure.messaging.eventhubs.checkpointstore.blob.BlobCheckpointStore;
import com.azure.storage.blob.BlobContainerClientBuilder;
import io.quarkus.runtime.ShutdownEvent;
import io.quarkus.runtime.StartupEvent;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.time.Clock;
import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@ApplicationScoped
class ClicsProductores {

    @ConfigProperty(name = "clics.espacio")
    String espacio;

    @ConfigProperty(name = "clics.puntos")
    String cuentaPuntos;

    @ConfigProperty(name = "clics.sal")
    String sal;

    @Produces
    @Singleton
    EventHubProducerClient productor() {
        return new EventHubClientBuilder()
                .fullyQualifiedNamespace(espacio)
                .eventHubName("clics")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildProducerClient();
    }

    @Produces
    @Singleton
    ColectorDeClics colector(EventHubProducerClient productor) {
        return new ColectorDeClics(new PublicadorEventHubs(productor, 64),
                new Anonimizador(sal.getBytes(java.nio.charset.StandardCharsets.UTF_8)), Clock.systemUTC());
    }

    @Produces
    @Singleton
    AgregadorDeVentanas agregador() {
        return new AgregadorDeVentanas(Clock.systemUTC(), Duration.ofMinutes(1), Duration.ofMinutes(2), 200_000);
    }

    @Produces
    @Singleton
    EventProcessorClient procesador(AgregadorDeVentanas agregador) {
        var credencial = new DefaultAzureCredentialBuilder().build();
        var contenedor = new BlobContainerClientBuilder()
                .endpoint("https://" + cuentaPuntos + ".blob.core.windows.net")
                .containerName("puntos-de-control")
                .credential(credencial)
                .buildAsyncClient();
        ConcurrentHashMap<String, AtomicInteger> contadores = new ConcurrentHashMap<>();
        return new EventProcessorClientBuilder()
                .fullyQualifiedNamespace(espacio)
                .eventHubName("clics")
                .consumerGroup("agregador")
                .credential(credencial)
                .checkpointStore(new BlobCheckpointStore(contenedor))
                .processEvent(contexto -> {
                    try {
                        agregador.aceptar(ClicJson.deJson(contexto.getEventData().getBodyAsString()));
                    } catch (IllegalArgumentException e) {
                        // mensaje ilegible: se registra y se sigue
                    }
                    String particion = contexto.getPartitionContext().getPartitionId();
                    if (contadores.computeIfAbsent(particion, k -> new AtomicInteger()).incrementAndGet() % 500 == 0) {
                        contexto.updateCheckpoint();
                    }
                })
                .processError(error -> System.getLogger("clics.procesador").log(System.Logger.Level.ERROR,
                        "clics.error: {0}", error.getThrowable().getClass().getSimpleName()))
                .buildEventProcessorClient();
    }
}

@ApplicationScoped
class CicloDelProcesador {

    @Inject
    EventProcessorClient procesador;

    @Inject
    AgregadorDeVentanas agregador;

    @Inject
    DestinoDeResumenes destino;

    void alIniciar(@Observes StartupEvent evento) {
        procesador.start();
    }

    void alApagar(@Observes ShutdownEvent evento) {
        procesador.stop();
    }

    @Scheduled(every = "10s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void cerrarVentanas() {
        var listos = agregador.cerrarListas();
        if (!listos.isEmpty()) {
            destino.guardar(listos);
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

import java.util.List;

@Path("/api/clics")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class ClicsRecurso {

    public record Lote(List<Clic> clics) { }

    @Inject
    ColectorDeClics colector;

    @POST
    public Response recibir(Lote lote) {
        try {
            return Response.accepted(colector.recibir(lote.clics())).build();
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

import java.util.List;

@Path("/reactivo/api/clics")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class ClicsRecursoReactivo {

    public record Lote(List<Clic> clics) { }

    @Inject
    ColectorDeClics colector;

    @POST
    public Uni<Response> recibir(Lote lote) {
        return Uni.createFrom().item(() -> colector.recibir(lote.clics()))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(r -> Response.accepted(r).build())
                .onFailure(IllegalArgumentException.class).transform(e -> new BadRequestException(e.getMessage()));
    }
}
```

## 8. Pruebas

| Nivel | Qué se comprueba | Cómo |
|---|---|---|
| **Planificador** | 5 000 eventos/s de 400 B con margen 1,5 → unidades y particiones esperadas; avisos con eventos de 200 KB | Valores calculados a mano |
| **Sesgo** | Una sesión con el 60 % del tráfico marca `caliente`; sesiones parejas, no | Mapas de conteos sintéticos |
| **Cubetas** | La misma sesión da siempre la misma cubeta; la distribución es pareja | Miles de identificadores generados |
| **Colector** | Lote vacío o de 101 → error; fechas imposibles y páginas sin `/` se descartan; el identificador de sesión publicado es el seudónimo | Publicador falso |
| **Agregador** | Duplicado no suma; tardío se descarta; la ventana se cierra solo tras la tolerancia; sesiones únicas | Reloj controlado (`Clock.fixed`/mutable) |
| **Integración** | Publicar 10 000 clics y comprobar particiones usadas, Capture y retraso del agregador | Espacio de nombres de laboratorio |

## 9. Buenas prácticas de código
- **Calcula la capacidad** con el planificador y guarda el supuesto en el repositorio (cambia con el negocio).
- **Clave de partición = sesión (o cubeta de sesión)**, nunca página, país ni fecha: esas claves concentran el tráfico.
- **Lotes, no eventos sueltos**: un `send` por evento multiplica la latencia y el costo.
- **Identificadores seudónimos desde el borde**: el flujo y el lago nunca ven datos personales que no necesitan.
- **Memoria acotada** en todo lo que recuerda algo (duplicados, ventanas).
- **Destino idempotente (UPSERT por ventana y página)**, nunca «sumar al valor anterior».
- **Un mensaje ilegible se registra y se salta**; no detiene la partición.
- **El agregador en línea es aproximado**: lo exacto se recalcula del lago.
