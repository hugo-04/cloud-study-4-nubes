# Google Cloud · Caso integrado · Clickstream · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

El consumidor del tablero: un **agregador por ventanas fijas de 1 minuto según la hora del evento** con **marca de agua** (máximo visto − 30 s) que cierra ventanas solo cuando ya no se esperan eventos y cuenta los tardíos; y un **lector de grupo** de Managed Kafka con `KafkaConsumer` (OAUTHBEARER) **sin commit automático**, para confirmar con `commitSync` solo después de escribir el resultado. El tamaño del lote lo fija `max.poll.records`: `leer` nunca descarta registros, porque luego se confirmarían sin procesar.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
kafka:
  bootstrap: bootstrap.eventos-modalima.southamerica-west1.managedkafka.modalima-prod.cloud.goog:9092
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
kafka.bootstrap=bootstrap.eventos-modalima.southamerica-west1.managedkafka.modalima-prod.cloud.goog:9092
```

## 2. Núcleo común

### 2.1 Credenciales según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ImpersonatedCredentials;
import java.io.IOException;
import java.util.List;

public final class Credenciales {

    private static final List<String> ALCANCE = List.of("https://www.googleapis.com/auth/cloud-platform");

    private Credenciales() { }

    /**
     * ADC (Application Default Credentials): en la laptop, «gcloud auth application-default login»;
     * en GKE, Cloud Run, Functions o Compute Engine, la cuenta de servicio adjunta (sin llaves).
     * suplantar = correo de una cuenta de servicio para actuar como ella, o "ninguna".
     */
    public static GoogleCredentials crear(String suplantar) {
        try {
            var base = GoogleCredentials.getApplicationDefault().createScoped(ALCANCE);
            if (suplantar == null || suplantar.isBlank() || "ninguna".equals(suplantar)) {
                return base;
            }
            return ImpersonatedCredentials.create(base, suplantar, null, ALCANCE, 3600);
        } catch (IOException e) {
            throw new IllegalStateException("no hay credenciales ADC disponibles", e);
        }
    }
}
```

### 2.2 Agregador por ventanas (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;
import java.util.regex.Pattern;

/** Ventanas fijas por hora del evento con marca de agua. Puro (no es seguro entre hilos: un agregador por partición). */
public class AgregadorDeVentanas {

    public record Click(String tipo, String sku, Instant ts) {
        private static final Pattern P = Pattern.compile("\"(tipo|sku|ts)\"\\s*:\\s*\"([^\"]{1,64})\"");

        /** Lector mínimo del JSON del evento; descarta lo que no cumple. */
        public static Optional<Click> leer(String json) {
            Map<String, String> c = new TreeMap<>();
            var m = P.matcher(json);
            while (m.find()) {
                c.put(m.group(1), m.group(2));
            }
            try {
                return c.size() == 3 ? Optional.of(new Click(c.get("tipo"), c.get("sku"), Instant.parse(c.get("ts")))) : Optional.empty();
            } catch (RuntimeException e) {
                return Optional.empty();
            }
        }
    }

    public record Ventana(Instant inicio, Map<String, Integer> vistasPorSku) { }

    private final Duration tamano;
    private final Duration retraso;
    private final TreeMap<Instant, Map<String, Integer>> abiertas = new TreeMap<>();
    private Instant maxVisto = Instant.EPOCH;
    private long tardios;

    public AgregadorDeVentanas(Duration tamano, Duration retraso) {
        this.tamano = tamano;
        this.retraso = retraso;
    }

    public void registrar(Click c) {
        if (!"vista".equals(c.tipo())) {
            return;
        }
        Instant inicio = Instant.ofEpochMilli(c.ts().toEpochMilli() - Math.floorMod(c.ts().toEpochMilli(), tamano.toMillis()));
        if (inicio.plus(tamano).isBefore(marcaDeAgua())) {
            tardios++;
            return;
        }
        abiertas.computeIfAbsent(inicio, k -> new TreeMap<>()).merge(c.sku(), 1, Integer::sum);
        if (c.ts().isAfter(maxVisto)) {
            maxVisto = c.ts();
        }
    }

    public Instant marcaDeAgua() {
        return maxVisto.minus(retraso);
    }

    /** Devuelve y retira las ventanas cuyo fin quedó detrás de la marca de agua. */
    public List<Ventana> cerrar() {
        var out = new ArrayList<Ventana>();
        while (!abiertas.isEmpty() && !abiertas.firstKey().plus(tamano).isAfter(marcaDeAgua())) {
            var e = abiertas.pollFirstEntry();
            out.add(new Ventana(e.getKey(), Map.copyOf(e.getValue())));
        }
        return out;
    }

    public long tardios() {
        return tardios;
    }
}
```

### 2.3 Adaptador con kafka-clients
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.serialization.StringDeserializer;

/** Adaptador: consumidor del grupo sin commit automático (se confirma tras escribir el resultado). */
public class LectorDeGrupo implements AutoCloseable {

    private final KafkaConsumer<String, String> consumidor;

    public LectorDeGrupo(String bootstrap, String grupo, String tema) {
        Map<String, Object> p = new java.util.HashMap<>(Map.of(
            "bootstrap.servers", bootstrap,
            "security.protocol", "SASL_SSL",
            "sasl.mechanism", "OAUTHBEARER",
            "sasl.login.callback.handler.class", "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler",
            "sasl.jaas.config", "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;",
            "group.id", grupo,
            "enable.auto.commit", "false",
            "auto.offset.reset", "earliest",
            "max.poll.records", "500"));
        p.put("client.id", grupo + "-" + UUID.randomUUID());
        this.consumidor = new KafkaConsumer<>(p, new StringDeserializer(), new StringDeserializer());
        consumidor.subscribe(List.of(tema));
    }

    /** Devuelve todo el poll (el tope real es max.poll.records): descartar registros y luego confirmar los perdería. */
    public List<String> leer(int max) {
        var out = new ArrayList<String>();
        for (var r : consumidor.poll(Duration.ofMillis(500))) {
            out.add(r.value());
        }
        return out;
    }

    /** Confirma lo leído en el último poll (llamar solo después de escribir el resultado). */
    public void confirmar() {
        consumidor.commitSync();
    }

    @Override
    public void close() {
        consumidor.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.List;

public class ServicioDeClickstream {

    public record Ciclo(int leidos, List<AgregadorDeVentanas.Ventana> cerradas, long tardios) { }

    private final LectorDeGrupo lector;
    private final AgregadorDeVentanas agregador = new AgregadorDeVentanas(Duration.ofMinutes(1), Duration.ofSeconds(30));

    public ServicioDeClickstream(LectorDeGrupo lector) {
        this.lector = lector;
    }

    /** Un ciclo del consumidor del tablero; en producción corre en un bucle por instancia. */
    public synchronized Ciclo ciclo() {
        var mensajes = lector.leer(500);
        mensajes.forEach(json -> AgregadorDeVentanas.Click.leer(json).ifPresent(agregador::registrar));
        var cerradas = agregador.cerrar();
        // aquí: escribir el top por ventana en Memorystore (reemplazo idempotente) y, después, confirmar
        lector.confirmar();
        return new Ciclo(mensajes.size(), cerradas, agregador.tardios());
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ClickstreamConfiguracion {

    @Bean(destroyMethod = "close")
    LectorDeGrupo adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${kafka.bootstrap}") String bootstrap) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new LectorDeGrupo(bootstrap, "tablero", "clickstream");
    }

    @Bean
    ServicioDeClickstream servicio(LectorDeGrupo a) {
        return new ServicioDeClickstream(a);
    }
}

@RestController
@RequestMapping("/tienda/clickstream")
class ClickstreamControlador {

    private final ServicioDeClickstream s;

    ClickstreamControlador(ServicioDeClickstream s) {
        this.s = s;
    }

    @PostMapping("/ciclo")
    ServicioDeClickstream.Ciclo ciclo() {
        return s.ciclo();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/tienda/clickstream")
class ClickstreamReactivoControlador {

    private final ServicioDeClickstream s;

    ClickstreamReactivoControlador(ServicioDeClickstream s) {
        this.s = s;
    }

    @PostMapping("/ciclo")
    Mono<ServicioDeClickstream.Ciclo> ciclo() {
        return Mono.fromCallable(() -> s.ciclo()).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.google.auth.oauth2.GoogleCredentials;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ClickstreamProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "kafka.bootstrap")
    String bootstrap;

    @jakarta.enterprise.inject.Produces
    @Singleton
    LectorDeGrupo adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new LectorDeGrupo(bootstrap, "tablero", "clickstream");
    }

    void cerrar(@Disposes LectorDeGrupo a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeClickstream servicio(LectorDeGrupo a) {
        return new ServicioDeClickstream(a);
    }
}

@Path("/tienda/clickstream")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ClickstreamRecurso {

    @Inject
    ServicioDeClickstream s;

    @POST
    @Path("/ciclo")
    public ServicioDeClickstream.Ciclo ciclo() {
        return s.ciclo();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

@Path("/reactivo/tienda/clickstream")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ClickstreamRecursoReactivo {

    @Inject
    ServicioDeClickstream s;

    @POST
    @Path("/ciclo")
    public Uni<ServicioDeClickstream.Ciclo> ciclo() {
        return Uni.createFrom().item(() -> s.ciclo()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Consumir el tema | `roles/managedkafka.client` para `gke-tablero` (Workload Identity) |

## 8. Qué NO hacer desde Java
- No actives el commit automático.
- No confirmes antes de escribir el resultado.
- No agrupes por hora de llegada.
- No expongas `/ciclo` como API pública: en producción es un bucle interno.
