# Oracle OCI · Mensajería · Streaming · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **productor de clickstream robusto** con la API nativa: la lógica pura arma lotes respetando el tamaño por mensaje y por lote y exige clave (la clave define partición y orden); el adaptador publica con `StreamClient.putMessages` y devuelve **solo las entradas fallidas** para reintentarlas, porque una respuesta 200 puede traer fallos parciales. Para clientes Kafka, ver `ejemplos/kafka/application.yml`.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
stream:
  id: ocid1.stream.oc1.sa-saopaulo-1.aaaa
  endpoint: https://cell-1.streaming.sa-saopaulo-1.oci.oraclecloud.com
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
stream.id=ocid1.stream.oc1.sa-saopaulo-1.aaaa
stream.endpoint=https://cell-1.streaming.sa-saopaulo-1.oci.oraclecloud.com
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

### 2.2 Armador de lotes (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Arma lotes para PutMessages respetando tamaño por mensaje y por lote. Puro. */
public class ArmadorDeLotes {

    public record Evento(String clave, String valor) { }

    private final int maxMensaje;
    private final int maxLote;
    private final int maxPorLote;

    public ArmadorDeLotes(int maxMensaje, int maxLote, int maxPorLote) {
        this.maxMensaje = maxMensaje;
        this.maxLote = maxLote;
        this.maxPorLote = maxPorLote;
    }

    public List<List<Evento>> armar(List<Evento> eventos) {
        var lotes = new ArrayList<List<Evento>>();
        var actual = new ArrayList<Evento>();
        int bytes = 0;
        for (Evento e : eventos) {
            if (e.clave() == null || e.clave().isBlank()) {
                throw new IllegalArgumentException("cada evento necesita clave (define partición y orden)");
            }
            int t = e.clave().getBytes(StandardCharsets.UTF_8).length + e.valor().getBytes(StandardCharsets.UTF_8).length;
            if (t > maxMensaje) {
                throw new IllegalArgumentException("evento de " + t + " bytes supera el máximo; usa claim check");
            }
            if (!actual.isEmpty() && (bytes + t > maxLote || actual.size() == maxPorLote)) {
                lotes.add(List.copyOf(actual));
                actual.clear();
                bytes = 0;
            }
            actual.add(e);
            bytes += t;
        }
        if (!actual.isEmpty()) {
            lotes.add(List.copyOf(actual));
        }
        return lotes;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.streaming.StreamClient;
import com.oracle.bmc.streaming.model.PutMessagesDetails;
import com.oracle.bmc.streaming.model.PutMessagesDetailsEntry;
import com.oracle.bmc.streaming.requests.PutMessagesRequest;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: publica un lote y devuelve SOLO los eventos que fallaron, para reintentarlos. */
public class StreamOci implements AutoCloseable {

    private final StreamClient cliente;
    private final String streamId;

    public StreamOci(StreamClient cliente, String streamId) {
        this.cliente = cliente;
        this.streamId = streamId;
    }

    public List<ArmadorDeLotes.Evento> publicar(List<ArmadorDeLotes.Evento> lote) {
        var entradas = lote.stream().map(e -> PutMessagesDetailsEntry.builder()
            .key(e.clave().getBytes(StandardCharsets.UTF_8))
            .value(e.valor().getBytes(StandardCharsets.UTF_8)).build()).toList();
        var r = cliente.putMessages(PutMessagesRequest.builder().streamId(streamId)
            .putMessagesDetails(PutMessagesDetails.builder().messages(entradas).build()).build()).getPutMessagesResult();
        var fallidos = new ArrayList<ArmadorDeLotes.Evento>();
        if (r.getFailures() != null && r.getFailures() > 0) {
            for (int i = 0; i < r.getEntries().size(); i++) {
                if (r.getEntries().get(i).getError() != null) {
                    fallidos.add(lote.get(i)); // las respuestas vienen en el mismo orden
                }
            }
        }
        return fallidos;
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
import java.util.List;

public class ServicioDeClickstream {

    public record Resultado(int enviados, int lotes, int fallidosFinales) { }

    private final StreamOci stream;
    private final ArmadorDeLotes armador = new ArmadorDeLotes(1_000_000, 1_000_000, 500);

    public ServicioDeClickstream(StreamOci stream) {
        this.stream = stream;
    }

    public Resultado publicar(List<ArmadorDeLotes.Evento> eventos) {
        var lotes = armador.armar(eventos);
        int fallidos = 0;
        for (var lote : lotes) {
            var pendientes = lote;
            for (int intento = 0; intento < 3 && !pendientes.isEmpty(); intento++) {
                if (intento > 0) {
                    dormir(200L << intento);
                }
                pendientes = stream.publicar(pendientes);
            }
            fallidos += pendientes.size(); // en producción: a una cola o archivo de rescate
        }
        return new Resultado(eventos.size() - fallidos, lotes.size(), fallidos);
    }

    private static void dormir(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.streaming.StreamClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ClickstreamConfiguracion {

    @Bean(destroyMethod = "close")
    StreamOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${stream.id}") String id, @Value("${stream.endpoint}") String endpoint) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new StreamOci(StreamClient.builder().endpoint(endpoint).build(auth), id);
    }

    @Bean
    ServicioDeClickstream servicio(StreamOci a) {
        return new ServicioDeClickstream(a);
    }
}

@RestController
@RequestMapping("/mensajeria/clickstream")
class ClickstreamControlador {

    private final ServicioDeClickstream s;

    ClickstreamControlador(ServicioDeClickstream s) {
        this.s = s;
    }

    @PostMapping("")
    ServicioDeClickstream.Resultado publicar(@RequestBody List<ArmadorDeLotes.Evento> eventos) {
        return s.publicar(eventos);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.streaming.StreamClient;
import java.util.List;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/mensajeria/clickstream")
class ClickstreamReactivoControlador {

    private final ServicioDeClickstream s;

    ClickstreamReactivoControlador(ServicioDeClickstream s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<ServicioDeClickstream.Resultado> publicar(@RequestBody List<ArmadorDeLotes.Evento> eventos) {
        return Mono.fromCallable(() -> s.publicar(eventos)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
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

    @jakarta.enterprise.inject.Produces
    @Singleton
    StreamOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new StreamOci(StreamClient.builder().endpoint(endpoint).build(auth), id);
    }

    void cerrar(@Disposes StreamOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeClickstream servicio(StreamOci a) {
        return new ServicioDeClickstream(a);
    }
}

@Path("/mensajeria/clickstream")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ClickstreamRecurso {

    @Inject
    ServicioDeClickstream s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeClickstream.Resultado publicar(List<ArmadorDeLotes.Evento> eventos) {
        return s.publicar(eventos);
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
import java.util.List;

@Path("/reactivo/mensajeria/clickstream")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ClickstreamRecursoReactivo {

    @Inject
    ServicioDeClickstream s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeClickstream.Resultado> publicar(List<ArmadorDeLotes.Evento> eventos) {
        return Uni.createFrom().item(() -> s.publicar(eventos)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Publicar | `Allow dynamic-group app-tienda to use stream-push in compartment tienda-prod where target.stream.id = '<ocid>'` |
| Consumir (otro servicio) | `Allow dynamic-group analitica to use stream-pull in compartment tienda-prod where target.stream.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No ignores `failures` en la respuesta de `putMessages`.
- No uses una clave constante: saturas una partición.
- No publiques mensaje por mensaje en tráfico alto: agrupa.
- No guardes el *auth token* de Kafka en `application.yml`: va en Vault o en una variable inyectada.
- No hagas commit del offset antes de procesar.
