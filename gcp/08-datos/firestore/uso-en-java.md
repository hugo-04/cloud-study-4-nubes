# Google Cloud · Datos · Firestore · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un patrón propio de Firestore: el **contador distribuido**. La lógica pura calcula cuántos fragmentos hacen falta para una tasa de escritura (un documento sostiene poco), elige uno al azar y suma; el adaptador escribe con `FieldValue.increment` y `SetOptions.merge()` sobre el fragmento y lee la subcolección completa. Las llamadas devuelven `ApiFuture`: aquí se esperan, en WebFlux/Mutiny se aíslan del hilo de eventos.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
firestore:
  base: tienda
  fragmentos: 20
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
firestore.base=tienda
firestore.fragmentos=20
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

### 2.2 Contador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.random.RandomGenerator;

/**
 * Contador distribuido: cuántos fragmentos hacen falta, a cuál escribir y cómo leer. Puro.
 */
public final class ContadorDistribuido {

    public record Plan(int fragmentos, double escriturasPorFragmento) { }

    private ContadorDistribuido() {
    }

    /** Un documento sostiene ~1 escritura/s (verifica): fragmentos = techo(tasa / capacidad) con margen. */
    public static Plan planificar(double escriturasPorSegundo, double capacidadPorDocumento, double margen) {
        int f = Math.max(1, (int) Math.ceil(escriturasPorSegundo * (1 + margen) / capacidadPorDocumento));
        return new Plan(f, escriturasPorSegundo / f);
    }

    public static String rutaFragmento(String contador, int fragmentos, RandomGenerator azar) {
        return "contadores/" + contador + "/fragmentos/" + azar.nextInt(fragmentos);
    }

    public static long sumar(List<Long> valores) {
        return valores.stream().mapToLong(Long::longValue).sum();
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.FieldValue;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.FirestoreOptions;
import com.google.cloud.firestore.SetOptions;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.random.RandomGenerator;

/** Adaptador: incrementa un fragmento aleatorio y suma todos al leer. */
public class FirestoreGcp implements AutoCloseable {

    private final Firestore db;
    private final int fragmentos;
    private final RandomGenerator azar = RandomGenerator.getDefault();

    public FirestoreGcp(GoogleCredentials cred, String proyecto, String base, int fragmentos) {
        this.db = FirestoreOptions.newBuilder().setProjectId(proyecto).setDatabaseId(base).setCredentials(cred).build().getService();
        this.fragmentos = fragmentos;
    }

    public void incrementar(String contador) {
        var ruta = ContadorDistribuido.rutaFragmento(contador, fragmentos, azar);
        esperar(db.document(ruta).set(Map.of("n", FieldValue.increment(1)), SetOptions.merge()));
    }

    public long leer(String contador) {
        var docs = esperar(db.collection("contadores/" + contador + "/fragmentos").get()).getDocuments();
        return ContadorDistribuido.sumar(docs.stream().map(d -> d.getLong("n") == null ? 0L : d.getLong("n")).toList());
    }

    private static <T> T esperar(com.google.api.core.ApiFuture<T> f) {
        try {
            return f.get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (ExecutionException e) {
            throw new IllegalStateException(e.getCause());
        }
    }

    @Override
    public void close() {
        try {
            db.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
public class ServicioDeContadores {

    private final FirestoreGcp fs;

    public ServicioDeContadores(FirestoreGcp fs) {
        this.fs = fs;
    }

    public ContadorDistribuido.Plan planificar(double escrituras) {
        return ContadorDistribuido.planificar(escrituras, 1.0, 0.5);
    }

    public long visitar(String producto) {
        fs.incrementar("visitas-" + producto);
        return fs.leer("visitas-" + producto);
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
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ContadoresConfiguracion {

    @Bean(destroyMethod = "close")
    FirestoreGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${firestore.base}") String base, @Value("${firestore.fragmentos}") String fragmentos) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FirestoreGcp(cred, proyecto, base, Integer.parseInt(fragmentos));
    }

    @Bean
    ServicioDeContadores servicio(FirestoreGcp a) {
        return new ServicioDeContadores(a);
    }
}

@RestController
@RequestMapping("/datos/contadores")
class ContadoresControlador {

    private final ServicioDeContadores s;

    ContadoresControlador(ServicioDeContadores s) {
        this.s = s;
    }

    @GetMapping("/plan")
    ContadorDistribuido.Plan planificar(@RequestParam double escrituras) {
        return s.planificar(escrituras);
    }

    @PostMapping("/{producto}")
    Long visitar(@PathVariable String producto) {
        return s.visitar(producto);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/contadores")
class ContadoresReactivoControlador {

    private final ServicioDeContadores s;

    ContadoresReactivoControlador(ServicioDeContadores s) {
        this.s = s;
    }

    @GetMapping("/plan")
    Mono<ContadorDistribuido.Plan> planificar(@RequestParam double escrituras) {
        return Mono.fromCallable(() -> s.planificar(escrituras));
    }

    @PostMapping("/{producto}")
    Mono<Long> visitar(@PathVariable String producto) {
        return Mono.fromCallable(() -> s.visitar(producto)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ContadoresProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "firestore.base")
    String base;

    @ConfigProperty(name = "firestore.fragmentos")
    String fragmentos;

    @jakarta.enterprise.inject.Produces
    @Singleton
    FirestoreGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FirestoreGcp(cred, proyecto, base, Integer.parseInt(fragmentos));
    }

    void cerrar(@Disposes FirestoreGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeContadores servicio(FirestoreGcp a) {
        return new ServicioDeContadores(a);
    }
}

@Path("/datos/contadores")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ContadoresRecurso {

    @Inject
    ServicioDeContadores s;

    @GET
    @Path("/plan")
    public ContadorDistribuido.Plan planificar(@QueryParam("escrituras") double escrituras) {
        return s.planificar(escrituras);
    }

    @POST
    @Path("/{producto}")
    public Long visitar(@PathParam("producto") String producto) {
        return s.visitar(producto);
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/datos/contadores")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ContadoresRecursoReactivo {

    @Inject
    ServicioDeContadores s;

    @GET
    @Path("/plan")
    public Uni<ContadorDistribuido.Plan> planificar(@QueryParam("escrituras") double escrituras) {
        return Uni.createFrom().item(() -> s.planificar(escrituras));
    }

    @POST
    @Path("/{producto}")
    public Uni<Long> visitar(@PathParam("producto") String producto) {
        return Uni.createFrom().item(() -> s.visitar(producto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer y escribir | `roles/datastore.user` |
| Solo lectura | `roles/datastore.viewer` |

## 8. Qué NO hacer desde Java
- No escribas cientos de veces por segundo al mismo documento.
- No uses IDs secuenciales.
- No confíes en reglas de seguridad desde el backend: aplica IAM.
- No abras un cliente por petición.
