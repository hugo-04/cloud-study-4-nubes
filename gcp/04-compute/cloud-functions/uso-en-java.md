# Google Cloud · Compute · Cloud Run functions · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: la **lógica pura del manejador** de un mensaje de Pub/Sub (decodifica base64, deduplica por `messageId`, valida el nombre y calcula una salida determinista en otro prefijo), que se usa tal cual dentro de la función ([`ejemplos/funcion/MiniaturaFuncion.java`](ejemplos/funcion/MiniaturaFuncion.java)) o en un endpoint *push*; y un **auditor de funciones** con `FunctionServiceClient.listFunctions` (ingress abierto, sin máximo de instancias, cuenta por defecto, runtime viejo).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
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

### 2.2 Manejador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Lógica del manejador de un mensaje de Pub/Sub recibido como CloudEvent. Pura y probable sin la plataforma. */
public class ManejadorDeFoto {

    /** Forma del cuerpo que entrega Pub/Sub (push o CloudEvent messagePublished). */
    public record Envoltura(Mensaje message, String subscription) { }

    public record Mensaje(String data, String messageId, Map<String, String> attributes) { }

    public record Resultado(String estado, String detalle) { }

    private final Set<String> procesados = ConcurrentHashMap.newKeySet(); // en producción: almacén compartido

    public Resultado manejar(Envoltura e) {
        if (e == null || e.message() == null || e.message().messageId() == null) {
            return new Resultado("DESCARTADO", "mensaje incompleto");
        }
        if (!procesados.add(e.message().messageId())) {
            return new Resultado("DUPLICADO", e.message().messageId());
        }
        String objeto = new String(Base64.getDecoder().decode(e.message().data() == null ? "" : e.message().data()), StandardCharsets.UTF_8);
        if (!objeto.matches("fotos/[A-Za-z0-9_-]{1,80}\\.(jpg|png)")) {
            return new Resultado("DESCARTADO", "objeto fuera de convención");
        }
        String salida = "miniaturas/" + objeto.substring("fotos/".length()); // determinista y en otro prefijo/bucket
        return new Resultado("PROCESAR", salida);
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.functions.v2.FunctionServiceClient;
import com.google.cloud.functions.v2.FunctionServiceSettings;
import com.google.cloud.functions.v2.ServiceConfig;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: inventario y auditoría de funciones del proyecto (todas las regiones). */
public class FuncionesGcp implements AutoCloseable {

    public record Hallazgo(String funcion, String mensaje) { }

    private final FunctionServiceClient cliente;
    private final String proyecto;

    public FuncionesGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = FunctionServiceClient.create(FunctionServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Hallazgo> auditar() {
        var h = new ArrayList<Hallazgo>();
        for (var f : cliente.listFunctions("projects/" + proyecto + "/locations/-").iterateAll()) {
            String n = f.getName().substring(f.getName().lastIndexOf('/') + 1);
            var sc = f.getServiceConfig();
            if (sc.getIngressSettings() == ServiceConfig.IngressSettings.ALLOW_ALL) {
                h.add(new Hallazgo(n, "ingress abierto a Internet: ¿es un webhook con firma?"));
            }
            if (sc.getMaxInstanceCount() == 0 || sc.getMaxInstanceCount() > 100) {
                h.add(new Hallazgo(n, "sin máximo de instancias razonable"));
            }
            if (sc.getServiceAccountEmail().endsWith("-compute@developer.gserviceaccount.com")) {
                h.add(new Hallazgo(n, "usa la cuenta por defecto de Compute"));
            }
            String rt = f.getBuildConfig().getRuntime();
            if (rt.startsWith("java") && Integer.parseInt(rt.substring(4)) < 21) {
                h.add(new Hallazgo(n, "runtime " + rt + ": actualiza a java21"));
            }
        }
        return h;
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

public class ServicioDeFunciones {

    private final FuncionesGcp funciones;
    private final ManejadorDeFoto manejador = new ManejadorDeFoto();

    public ServicioDeFunciones(FuncionesGcp funciones) {
        this.funciones = funciones;
    }

    /** Misma lógica que la función: aquí se expone como endpoint push de Pub/Sub para probarla. */
    public ManejadorDeFoto.Resultado recibir(ManejadorDeFoto.Envoltura e) {
        return manejador.manejar(e);
    }

    public List<FuncionesGcp.Hallazgo> auditar() {
        return funciones.auditar();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class FuncionesConfiguracion {

    @Bean(destroyMethod = "close")
    FuncionesGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FuncionesGcp(cred, proyecto);
    }

    @Bean
    ServicioDeFunciones servicio(FuncionesGcp a) {
        return new ServicioDeFunciones(a);
    }
}

@RestController
@RequestMapping("/compute/funciones")
class FuncionesControlador {

    private final ServicioDeFunciones s;

    FuncionesControlador(ServicioDeFunciones s) {
        this.s = s;
    }

    @PostMapping("/push")
    ManejadorDeFoto.Resultado recibir(@RequestBody ManejadorDeFoto.Envoltura e) {
        return s.recibir(e);
    }

    @GetMapping("/auditoria")
    List<FuncionesGcp.Hallazgo> auditar() {
        return s.auditar();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/compute/funciones")
class FuncionesReactivoControlador {

    private final ServicioDeFunciones s;

    FuncionesReactivoControlador(ServicioDeFunciones s) {
        this.s = s;
    }

    @PostMapping("/push")
    Mono<ManejadorDeFoto.Resultado> recibir(@RequestBody ManejadorDeFoto.Envoltura e) {
        return Mono.fromCallable(() -> s.recibir(e));
    }

    @GetMapping("/auditoria")
    Mono<List<FuncionesGcp.Hallazgo>> auditar() {
        return Mono.fromCallable(() -> s.auditar()).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class FuncionesProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    FuncionesGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FuncionesGcp(cred, proyecto);
    }

    void cerrar(@Disposes FuncionesGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeFunciones servicio(FuncionesGcp a) {
        return new ServicioDeFunciones(a);
    }
}

@Path("/compute/funciones")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class FuncionesRecurso {

    @Inject
    ServicioDeFunciones s;

    @POST
    @Path("/push")
    @Consumes(MediaType.APPLICATION_JSON)
    public ManejadorDeFoto.Resultado recibir(ManejadorDeFoto.Envoltura e) {
        return s.recibir(e);
    }

    @GET
    @Path("/auditoria")
    public List<FuncionesGcp.Hallazgo> auditar() {
        return s.auditar();
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
import java.util.List;

@Path("/reactivo/compute/funciones")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class FuncionesRecursoReactivo {

    @Inject
    ServicioDeFunciones s;

    @POST
    @Path("/push")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ManejadorDeFoto.Resultado> recibir(ManejadorDeFoto.Envoltura e) {
        return Uni.createFrom().item(() -> s.recibir(e));
    }

    @GET
    @Path("/auditoria")
    public Uni<List<FuncionesGcp.Hallazgo>> auditar() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar funciones | `roles/cloudfunctions.viewer` |

## 8. Qué NO hacer desde Java
- No proceses dos veces el mismo `messageId`.
- No escribas la salida donde dispara el evento.
- No dejes el ingress abierto sin verificar firmas.
- No hagas trabajo de minutos en una función de eventos.
