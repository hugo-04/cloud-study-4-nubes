# Google Cloud · Mensajería · Managed Kafka · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Con Managed Kafka se usan los **clientes Kafka estándar**; lo propio de Google es la conexión (bootstrap privado y **SASL_SSL + OAUTHBEARER** con el *login handler* de Google, que toma el token de ADC). Aquí: un constructor puro de propiedades y dimensionamiento de particiones, y un adaptador con `Admin` que revisa réplicas e ISR de cada tema. El productor y consumidor con Spring Kafka, Quarkus Messaging y reactivo están en el módulo transversal [Kafka](../../../transversal/kafka/README.md).

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

### 2.2 Configuración (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Construye las propiedades del cliente Kafka para Managed Kafka (SASL_SSL + OAUTHBEARER con tokens de Google)
 * y dimensiona particiones. Puro: solo mapas y aritmética.
 */
public final class ConfiguracionKafka {

    public record Dimension(int particiones, int consumidoresUtiles, List<String> avisos) { }

    private ConfiguracionKafka() {
    }

    public static String bootstrap(String cluster, String region, String proyecto) {
        return "bootstrap." + cluster + "." + region + ".managedkafka." + proyecto + ".cloud.goog:9092";
    }

    public static Map<String, Object> cliente(String bootstrap, String grupo) {
        var p = new LinkedHashMap<String, Object>();
        p.put("bootstrap.servers", bootstrap);
        p.put("security.protocol", "SASL_SSL");
        p.put("sasl.mechanism", "OAUTHBEARER");
        p.put("sasl.login.callback.handler.class", "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler");
        p.put("sasl.jaas.config", "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;");
        p.put("acks", "all");
        p.put("enable.idempotence", "true");
        if (grupo != null) {
            p.put("group.id", grupo);
            p.put("enable.auto.commit", "false");
        }
        return p;
    }

    /** Particiones = techo(tasa / tasa por consumidor) con margen de crecimiento. */
    public static Dimension dimensionar(double eventosPorSegundo, double porConsumidor, double margen, int consumidoresPlaneados) {
        int base = (int) Math.ceil(eventosPorSegundo / porConsumidor);
        int particiones = (int) Math.ceil(base * (1 + margen));
        var avisos = new ArrayList<String>();
        if (consumidoresPlaneados > particiones) {
            avisos.add((consumidoresPlaneados - particiones) + " consumidores quedarán inactivos");
        }
        if (consumidoresPlaneados < base) {
            avisos.add("con " + consumidoresPlaneados + " consumidores habrá lag sostenido");
        }
        return new Dimension(particiones, Math.min(consumidoresPlaneados, particiones), avisos);
    }
}
```

### 2.3 Adaptador con AdminClient
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import org.apache.kafka.clients.admin.Admin;
import org.apache.kafka.clients.admin.TopicDescription;

/** Adaptador: revisa los temas del clúster con el AdminClient estándar (réplicas e ISR). */
public class KafkaGcp implements AutoCloseable {

    public record Tema(String nombre, int particiones, int replicas, List<String> problemas) { }

    private final Admin admin;

    public KafkaGcp(String bootstrap) {
        this.admin = Admin.create(ConfiguracionKafka.cliente(bootstrap, null));
    }

    public List<Tema> revisar() {
        try {
            var nombres = admin.listTopics().names().get();
            Map<String, TopicDescription> d = admin.describeTopics(nombres).allTopicNames().get();
            var out = new ArrayList<Tema>();
            for (var t : d.values()) {
                var problemas = new ArrayList<String>();
                int rf = t.partitions().isEmpty() ? 0 : t.partitions().get(0).replicas().size();
                if (rf < 3) {
                    problemas.add("factor de réplica " + rf);
                }
                long subreplicadas = t.partitions().stream().filter(p -> p.isr().size() < p.replicas().size()).count();
                if (subreplicadas > 0) {
                    problemas.add(subreplicadas + " particiones sub-replicadas");
                }
                out.add(new Tema(t.name(), t.partitions().size(), rf, problemas));
            }
            return out;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (ExecutionException e) {
            throw new IllegalStateException("no se pudo describir el clúster", e.getCause());
        }
    }

    @Override
    public void close() {
        admin.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public class ServicioDeKafka {

    private final KafkaGcp kafka;

    public ServicioDeKafka(KafkaGcp kafka) {
        this.kafka = kafka;
    }

    public ConfiguracionKafka.Dimension dimensionar(double eventos, double porConsumidor, int consumidores) {
        return ConfiguracionKafka.dimensionar(eventos, porConsumidor, 0.5, consumidores);
    }

    public List<KafkaGcp.Tema> revisar() {
        return kafka.revisar();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class KafkaConfiguracion {

    @Bean(destroyMethod = "close")
    KafkaGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${kafka.bootstrap}") String bootstrap) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new KafkaGcp(bootstrap);
    }

    @Bean
    ServicioDeKafka servicio(KafkaGcp a) {
        return new ServicioDeKafka(a);
    }
}

@RestController
@RequestMapping("/mensajeria/kafka")
class KafkaControlador {

    private final ServicioDeKafka s;

    KafkaControlador(ServicioDeKafka s) {
        this.s = s;
    }

    @GetMapping("/dimension")
    ConfiguracionKafka.Dimension dimensionar(@RequestParam double eventos, @RequestParam double porConsumidor, @RequestParam int consumidores) {
        return s.dimensionar(eventos, porConsumidor, consumidores);
    }

    @GetMapping("/temas")
    java.util.List<KafkaGcp.Tema> revisar() {
        return s.revisar();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/mensajeria/kafka")
class KafkaReactivoControlador {

    private final ServicioDeKafka s;

    KafkaReactivoControlador(ServicioDeKafka s) {
        this.s = s;
    }

    @GetMapping("/dimension")
    Mono<ConfiguracionKafka.Dimension> dimensionar(@RequestParam double eventos, @RequestParam double porConsumidor, @RequestParam int consumidores) {
        return Mono.fromCallable(() -> s.dimensionar(eventos, porConsumidor, consumidores));
    }

    @GetMapping("/temas")
    Mono<java.util.List<KafkaGcp.Tema>> revisar() {
        return Mono.fromCallable(() -> s.revisar()).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class KafkaProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "kafka.bootstrap")
    String bootstrap;

    @jakarta.enterprise.inject.Produces
    @Singleton
    KafkaGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new KafkaGcp(bootstrap);
    }

    void cerrar(@Disposes KafkaGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeKafka servicio(KafkaGcp a) {
        return new ServicioDeKafka(a);
    }
}

@Path("/mensajeria/kafka")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class KafkaRecurso {

    @Inject
    ServicioDeKafka s;

    @GET
    @Path("/dimension")
    public ConfiguracionKafka.Dimension dimensionar(@QueryParam("eventos") double eventos, @QueryParam("porConsumidor") double porConsumidor, @QueryParam("consumidores") int consumidores) {
        return s.dimensionar(eventos, porConsumidor, consumidores);
    }

    @GET
    @Path("/temas")
    public java.util.List<KafkaGcp.Tema> revisar() {
        return s.revisar();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/mensajeria/kafka")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class KafkaRecursoReactivo {

    @Inject
    ServicioDeKafka s;

    @GET
    @Path("/dimension")
    public Uni<ConfiguracionKafka.Dimension> dimensionar(@QueryParam("eventos") double eventos, @QueryParam("porConsumidor") double porConsumidor, @QueryParam("consumidores") int consumidores) {
        return Uni.createFrom().item(() -> s.dimensionar(eventos, porConsumidor, consumidores));
    }

    @GET
    @Path("/temas")
    public Uni<java.util.List<KafkaGcp.Tema>> revisar() {
        return Uni.createFrom().item(() -> s.revisar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Producir y consumir | `roles/managedkafka.client` (+ ACL por tema si aplican) |
| Revisar temas (Admin) | `roles/managedkafka.client`; administrar temas: `roles/managedkafka.admin` |

## 8. Qué NO hacer desde Java
- No olvides la dependencia del login handler de Google: sin ella falla SASL.
- No uses llaves de cuenta de servicio en base64 con SASL/PLAIN si puedes usar OAUTHBEARER.
- No produzcas sin clave cuando importa el orden.
- No crees temas desde la app: créalos como código.
