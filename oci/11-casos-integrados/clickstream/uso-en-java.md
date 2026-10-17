# Oracle OCI · Caso integrado · Clickstream · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

El consumidor del tablero: un **agregador por ventanas fijas de 1 minuto según la hora del evento** con **marca de agua** (máximo visto − 30 s) que cierra ventanas solo cuando ya no se esperan eventos y cuenta los tardíos; y un **lector de grupo** con `StreamClient.createGroupCursor` sin commit automático, para confirmar solo después de escribir el resultado.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
stream:
  id: ocid1.stream.oc1.sa-saopaulo-1.aaaa
  endpoint: https://cell-1.streaming.sa-saopaulo-1.oci.oraclecloud.com
  instancia: tablero-1
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
stream.id=ocid1.stream.oc1.sa-saopaulo-1.aaaa
stream.endpoint=https://cell-1.streaming.sa-saopaulo-1.oci.oraclecloud.com
stream.instancia=tablero-1
```

## 2. Núcleo común

### 2.1 Autenticación según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
        }
    }
}
```

### 2.2 Agregador con marca de agua (lógica pura)
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

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.streaming.StreamClient;
import com.oracle.bmc.streaming.model.CreateGroupCursorDetails;
import com.oracle.bmc.streaming.requests.CreateGroupCursorRequest;
import com.oracle.bmc.streaming.requests.GetMessagesRequest;
import java.nio.charset.StandardCharsets;
import java.util.List;

/** Adaptador del SDK: lector de grupo de consumidores (sin commit automático). */
public class LectorDeGrupo implements AutoCloseable {

    private final StreamClient cliente;
    private final String streamId;
    private String cursor;

    public LectorDeGrupo(StreamClient cliente, String streamId, String grupo, String instancia) {
        this.cliente = cliente;
        this.streamId = streamId;
        this.cursor = cliente.createGroupCursor(CreateGroupCursorRequest.builder().streamId(streamId)
            .createGroupCursorDetails(CreateGroupCursorDetails.builder()
                .groupName(grupo).instanceName(instancia)
                .type(CreateGroupCursorDetails.Type.TrimHorizon).commitOnGet(false).build())
            .build()).getCursor().getValue();
    }

    /** Lee un lote y avanza el cursor; el commit se hace aparte, tras escribir el resultado. */
    public List<String> leer(int max) {
        var r = cliente.getMessages(GetMessagesRequest.builder().streamId(streamId).cursor(cursor).limit(max).build());
        cursor = r.getOpcNextCursor();
        return r.getItems().stream().map(m -> new String(m.getValue(), StandardCharsets.UTF_8)).toList();
    }

    public String cursorActual() {
        return cursor;
    }

    @Override
    public void close() {
        cliente.close();
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
        // aquí: escribir el top por ventana en OCI Cache y luego hacer commit del cursor del grupo
        return new Ciclo(mensajes.size(), cerradas, agregador.tardios());
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.streaming.StreamClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ClickstreamConfiguracion {

    @Bean(destroyMethod = "close")
    LectorDeGrupo adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${stream.id}") String id, @Value("${stream.endpoint}") String endpoint, @Value("${stream.instancia}") String instancia) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new LectorDeGrupo(StreamClient.builder().endpoint(endpoint).build(auth), id, "tablero", instancia);
    }

    @Bean
    ServicioDeClickstream servicio(LectorDeGrupo a) {
        return new ServicioDeClickstream(a);
    }
}

@RestController
@RequestMapping("/casos/clickstream")
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
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.streaming.StreamClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/casos/clickstream")
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
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.streaming.StreamClient;
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

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "stream.id")
    String id;

    @ConfigProperty(name = "stream.endpoint")
    String endpoint;

    @ConfigProperty(name = "stream.instancia")
    String instancia;

    @jakarta.enterprise.inject.Produces
    @Singleton
    LectorDeGrupo adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new LectorDeGrupo(StreamClient.builder().endpoint(endpoint).build(auth), id, "tablero", instancia);
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

@Path("/casos/clickstream")
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
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.streaming.StreamClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

@Path("/reactivo/casos/clickstream")
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
| Acción en Java | Política |
|---|---|
| Leer con grupo de consumidores | `Allow dynamic-group analitica to use stream-pull in compartment tienda-prod where target.stream.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No agregues por hora de llegada.
- No compartas un agregador entre hilos sin sincronizar (usa uno por partición o instancia).
- No hagas commit antes de escribir el resultado.
- No guardes identificadores personales en los eventos.
