# Google Cloud · Terraform · Módulos y entornos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Las reglas del módulo (prod con al menos una instancia, no-prod con tope de costo, labels obligatorios) se escriben **también** en Java puro para dos usos: validar los `tfvars` en el pipeline antes del `plan`, y comparar contra lo **desplegado** en Cloud Run (`ServicesClient.listServices`) para detectar **deriva** hecha a mano: escalado distinto, labels faltantes o ingress abierto.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
entorno:
  region: southamerica-west1
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
entorno.region=southamerica-west1
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

### 2.2 Reglas (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Reglas por entorno (las mismas que validan las variables del módulo) y comparación con lo desplegado:
 * sirve para detectar deriva hecha a mano en la consola. Puro.
 */
public final class ReglasDeEntorno {

    public record Esperado(String entorno, int minInstancias, int maxInstancias) { }

    public record Desplegado(String servicio, Map<String, String> labels, int minInstancias, int maxInstancias, String ingress) { }

    public record Hallazgo(String servicio, List<String> problemas) { }

    private static final Set<String> LABELS = Set.of("equipo", "entorno", "modulo");

    private ReglasDeEntorno() {
    }

    public static List<String> validar(Esperado e) {
        var p = new ArrayList<String>();
        if (!Set.of("dev", "staging", "prod").contains(e.entorno())) {
            p.add("entorno desconocido");
        }
        if ("prod".equals(e.entorno()) && e.minInstancias() < 1) {
            p.add("prod requiere min_instancias >= 1");
        }
        if (e.maxInstancias() < e.minInstancias()) {
            p.add("max < min");
        }
        if (!"prod".equals(e.entorno()) && e.maxInstancias() > 10) {
            p.add("no-prod limitado a 10 instancias (costo)");
        }
        return p;
    }

    public static Hallazgo comparar(Esperado e, Desplegado d) {
        var p = new ArrayList<String>(validar(e));
        for (String l : LABELS) {
            if (!d.labels().containsKey(l)) {
                p.add("falta label " + l + " (¿creado fuera del módulo?)");
            }
        }
        if (d.minInstancias() != e.minInstancias() || d.maxInstancias() != e.maxInstancias()) {
            p.add("deriva de escalado: desplegado " + d.minInstancias() + "-" + d.maxInstancias()
                + ", código " + e.minInstancias() + "-" + e.maxInstancias());
        }
        if ("INGRESS_TRAFFIC_ALL".equals(d.ingress())) {
            p.add("ingress abierto a Internet");
        }
        return new Hallazgo(d.servicio(), p);
    }
}
```

### 2.3 Adaptador de Cloud Run
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.run.v2.ServicesClient;
import com.google.cloud.run.v2.ServicesSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee los servicios de Cloud Run creados por el módulo y los resume. */
public class EntornoGcp implements AutoCloseable {

    private final ServicesClient cliente;
    private final String proyecto;
    private final String region;

    public EntornoGcp(GoogleCredentials cred, String proyecto, String region) {
        try {
            this.cliente = ServicesClient.create(ServicesSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
        this.region = region;
    }

    public List<ReglasDeEntorno.Desplegado> servicios() {
        var out = new ArrayList<ReglasDeEntorno.Desplegado>();
        for (var s : cliente.listServices("projects/" + proyecto + "/locations/" + region).iterateAll()) {
            var esc = s.getTemplate().getScaling();
            out.add(new ReglasDeEntorno.Desplegado(s.getName().substring(s.getName().lastIndexOf('/') + 1),
                s.getLabelsMap(), esc.getMinInstanceCount(), esc.getMaxInstanceCount(), s.getIngress().name()));
        }
        return out;
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
import java.util.Map;

public class ServicioDeEntornos {

    private final EntornoGcp gcp;

    public ServicioDeEntornos(EntornoGcp gcp) {
        this.gcp = gcp;
    }

    public List<String> validar(ReglasDeEntorno.Esperado e) {
        return ReglasDeEntorno.validar(e);
    }

    /** esperado: servicio → valores del código (en la práctica, leídos de los tfvars del entorno). */
    public List<ReglasDeEntorno.Hallazgo> deriva(Map<String, ReglasDeEntorno.Esperado> esperado) {
        return gcp.servicios().stream().filter(d -> esperado.containsKey(d.servicio()))
            .map(d -> ReglasDeEntorno.comparar(esperado.get(d.servicio()), d))
            .filter(h -> !h.problemas().isEmpty()).toList();
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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EntornosConfiguracion {

    @Bean(destroyMethod = "close")
    EntornoGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${entorno.region}") String region) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new EntornoGcp(cred, proyecto, region);
    }

    @Bean
    ServicioDeEntornos servicio(EntornoGcp a) {
        return new ServicioDeEntornos(a);
    }
}

@RestController
@RequestMapping("/terraform/entornos")
class EntornosControlador {

    private final ServicioDeEntornos s;

    EntornosControlador(ServicioDeEntornos s) {
        this.s = s;
    }

    @PostMapping("/validacion")
    java.util.List<String> validar(@RequestBody ReglasDeEntorno.Esperado esperado) {
        return s.validar(esperado);
    }

    @PostMapping("/deriva")
    java.util.List<ReglasDeEntorno.Hallazgo> deriva(@RequestBody java.util.Map<String, ReglasDeEntorno.Esperado> esperado) {
        return s.deriva(esperado);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/terraform/entornos")
class EntornosReactivoControlador {

    private final ServicioDeEntornos s;

    EntornosReactivoControlador(ServicioDeEntornos s) {
        this.s = s;
    }

    @PostMapping("/validacion")
    Mono<java.util.List<String>> validar(@RequestBody ReglasDeEntorno.Esperado esperado) {
        return Mono.fromCallable(() -> s.validar(esperado));
    }

    @PostMapping("/deriva")
    Mono<java.util.List<ReglasDeEntorno.Hallazgo>> deriva(@RequestBody java.util.Map<String, ReglasDeEntorno.Esperado> esperado) {
        return Mono.fromCallable(() -> s.deriva(esperado)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EntornosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "entorno.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    EntornoGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new EntornoGcp(cred, proyecto, region);
    }

    void cerrar(@Disposes EntornoGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEntornos servicio(EntornoGcp a) {
        return new ServicioDeEntornos(a);
    }
}

@Path("/terraform/entornos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EntornosRecurso {

    @Inject
    ServicioDeEntornos s;

    @POST
    @Path("/validacion")
    @Consumes(MediaType.APPLICATION_JSON)
    public java.util.List<String> validar(ReglasDeEntorno.Esperado esperado) {
        return s.validar(esperado);
    }

    @POST
    @Path("/deriva")
    @Consumes(MediaType.APPLICATION_JSON)
    public java.util.List<ReglasDeEntorno.Hallazgo> deriva(java.util.Map<String, ReglasDeEntorno.Esperado> esperado) {
        return s.deriva(esperado);
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
import java.util.List;

@Path("/reactivo/terraform/entornos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EntornosRecursoReactivo {

    @Inject
    ServicioDeEntornos s;

    @POST
    @Path("/validacion")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<java.util.List<String>> validar(ReglasDeEntorno.Esperado esperado) {
        return Uni.createFrom().item(() -> s.validar(esperado));
    }

    @POST
    @Path("/deriva")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<java.util.List<ReglasDeEntorno.Hallazgo>> deriva(java.util.Map<String, ReglasDeEntorno.Esperado> esperado) {
        return Uni.createFrom().item(() -> s.deriva(esperado)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer servicios | `roles/run.viewer` en el proyecto del entorno |

## 8. Qué NO hacer desde Java
- No corrijas la deriva desde la app: corrige el código y aplica.
- No dupliques reglas sin pruebas que las mantengan iguales a las del módulo.
- No uses la SA de Terraform para leer.
- No compares contra prod con credenciales de dev.
