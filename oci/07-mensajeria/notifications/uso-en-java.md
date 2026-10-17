# Oracle OCI · Mensajería · Notifications · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **publicador de alertas sin tormentas**: la lógica pura agrupa alertas por clave en ventanas de 5 minutos (la primera sale, las demás se cuentan y se informan en la siguiente) y limpia títulos y cuerpos; el adaptador publica con `NotificationDataPlaneClient.publishMessage`.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
alertas:
  tema: ocid1.onstopic.oc1.sa-saopaulo-1.aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
alertas.tema=ocid1.onstopic.oc1.sa-saopaulo-1.aaaa
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

### 2.2 Agrupador de alertas (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/** Agrupa alertas repetidas por clave en ventanas: la primera sale, las demás se cuentan. Puro: reloj inyectado. */
public class AgrupadorDeAlertas {

    public record Alerta(String clave, String titulo, String detalle) { }

    public record Publicable(String titulo, String cuerpo) { }

    private record Ventana(Instant inicio, int suprimidas) { }

    private final Clock reloj;
    private final Duration ventana;
    private final Map<String, Ventana> abiertas = new ConcurrentHashMap<>();

    public AgrupadorDeAlertas(Clock reloj, Duration ventana) {
        this.reloj = reloj;
        this.ventana = ventana;
    }

    public Optional<Publicable> registrar(Alerta a) {
        Instant ahora = reloj.instant();
        var previa = abiertas.get(a.clave());
        if (previa != null && ahora.isBefore(previa.inicio().plus(ventana))) {
            abiertas.put(a.clave(), new Ventana(previa.inicio(), previa.suprimidas() + 1));
            return Optional.empty();
        }
        abiertas.put(a.clave(), new Ventana(ahora, 0));
        String extra = previa != null && previa.suprimidas() > 0
            ? "\n(+" + previa.suprimidas() + " repeticiones en la ventana anterior)" : "";
        return Optional.of(new Publicable(recortar(a.titulo(), 120), recortar(a.detalle(), 2000) + extra));
    }

    private static String recortar(String s, int max) {
        String limpio = s == null ? "" : s.replaceAll("[\\p{Cntrl}&&[^\\n]]", " ");
        return limpio.length() <= max ? limpio : limpio.substring(0, max - 1) + "…";
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.ons.NotificationDataPlaneClient;
import com.oracle.bmc.ons.model.MessageDetails;
import com.oracle.bmc.ons.requests.PublishMessageRequest;

/** Adaptador del SDK: publica en un tema. */
public class TemaOci implements AutoCloseable {

    private final NotificationDataPlaneClient cliente;
    private final String temaId;

    public TemaOci(NotificationDataPlaneClient cliente, String temaId) {
        this.cliente = cliente;
        this.temaId = temaId;
    }

    public String publicar(String titulo, String cuerpo) {
        return cliente.publishMessage(PublishMessageRequest.builder().topicId(temaId)
                .messageDetails(MessageDetails.builder().title(titulo).body(cuerpo).build()).build())
            .getPublishResult().getMessageId();
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
import java.time.Clock;
import java.time.Duration;

public class ServicioDeAlertas {

    public record Resultado(boolean publicada, String idMensaje) { }

    private final TemaOci tema;
    private final AgrupadorDeAlertas agrupador = new AgrupadorDeAlertas(Clock.systemUTC(), Duration.ofMinutes(5));

    public ServicioDeAlertas(TemaOci tema) {
        this.tema = tema;
    }

    public Resultado alertar(AgrupadorDeAlertas.Alerta a) {
        return agrupador.registrar(a)
            .map(p -> new Resultado(true, tema.publicar(p.titulo(), p.cuerpo())))
            .orElse(new Resultado(false, null));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.ons.NotificationDataPlaneClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class AlertasConfiguracion {

    @Bean(destroyMethod = "close")
    TemaOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${alertas.tema}") String tema) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new TemaOci(NotificationDataPlaneClient.builder().region(Region.fromRegionId(region)).build(auth), tema);
    }

    @Bean
    ServicioDeAlertas servicio(TemaOci a) {
        return new ServicioDeAlertas(a);
    }
}

@RestController
@RequestMapping("/mensajeria/alertas")
class AlertasControlador {

    private final ServicioDeAlertas s;

    AlertasControlador(ServicioDeAlertas s) {
        this.s = s;
    }

    @PostMapping("")
    ServicioDeAlertas.Resultado alertar(@RequestBody AgrupadorDeAlertas.Alerta a) {
        return s.alertar(a);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.ons.NotificationDataPlaneClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/mensajeria/alertas")
class AlertasReactivoControlador {

    private final ServicioDeAlertas s;

    AlertasReactivoControlador(ServicioDeAlertas s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<ServicioDeAlertas.Resultado> alertar(@RequestBody AgrupadorDeAlertas.Alerta a) {
        return Mono.fromCallable(() -> s.alertar(a)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.ons.NotificationDataPlaneClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AlertasProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "alertas.tema")
    String tema;

    @jakarta.enterprise.inject.Produces
    @Singleton
    TemaOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new TemaOci(NotificationDataPlaneClient.builder().region(Region.fromRegionId(region)).build(auth), tema);
    }

    void cerrar(@Disposes TemaOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeAlertas servicio(TemaOci a) {
        return new ServicioDeAlertas(a);
    }
}

@Path("/mensajeria/alertas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class AlertasRecurso {

    @Inject
    ServicioDeAlertas s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeAlertas.Resultado alertar(AgrupadorDeAlertas.Alerta a) {
        return s.alertar(a);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.ons.NotificationDataPlaneClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

@Path("/reactivo/mensajeria/alertas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class AlertasRecursoReactivo {

    @Inject
    ServicioDeAlertas s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeAlertas.Resultado> alertar(AgrupadorDeAlertas.Alerta a) {
        return Uni.createFrom().item(() -> s.alertar(a)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Publicar en el tema | `Allow dynamic-group app-tienda to use ons-topics in compartment tienda-prod where target.topic.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No publiques una alerta por cada error: agrupa.
- No incluyas datos personales, tokens ni *stack traces* completos.
- No uses Notifications como cola de trabajo con reintentos largos.
- No bloquees el hilo de eventos al publicar en WebFlux/Mutiny.
