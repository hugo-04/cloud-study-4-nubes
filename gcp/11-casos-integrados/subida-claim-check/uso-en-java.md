# Google Cloud · Caso integrado · Subida con claim check · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

El validador de la cuarentena: una **máquina de estados con transiciones condicionales** (un evento duplicado no hace nada), **validación por firma** de los primeros bytes (JPEG, PNG, PDF) y tamaño, y un adaptador que lee solo 16 bytes con `ReadChannel.limit`, **copia la generación validada** a `aprobados/` con `generationMatch` + `doesNotExist` y borra el original con la misma generación (o borra el rechazado).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
subidas:
  bucket: modalima-subidas
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
subidas.bucket=modalima-subidas
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

### 2.2 Estados y validación (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/** Máquina de estados de una subida y validación por firma. Pura. */
public final class Subidas {

    private Subidas() { }

    public enum Estado { PENDIENTE, RECIBIDA, APROBADA, RECHAZADA, EXPIRADA, PROCESADA }

    private static final Map<Estado, Set<Estado>> PERMITIDAS = Map.of(
        Estado.PENDIENTE, Set.of(Estado.RECIBIDA, Estado.EXPIRADA),
        Estado.RECIBIDA, Set.of(Estado.APROBADA, Estado.RECHAZADA),
        Estado.APROBADA, Set.of(Estado.PROCESADA));

    /** Transición condicional: si el estado actual no es el esperado, no se hace nada (evento duplicado). */
    public static Optional<Estado> transicion(Estado actual, Estado esperado, Estado nuevo) {
        if (actual != esperado || !PERMITIDAS.getOrDefault(actual, Set.of()).contains(nuevo)) {
            return Optional.empty();
        }
        return Optional.of(nuevo);
    }

    public record Veredicto(boolean aprobado, String tipo, String motivo) { }

    /** Valida por los primeros bytes (firma), nunca por la extensión. */
    public static Veredicto validar(byte[] cabecera, long bytes, long maxBytes) {
        if (bytes <= 0 || bytes > maxBytes) {
            return new Veredicto(false, null, "tamaño fuera de rango");
        }
        if (empieza(cabecera, 0xFF, 0xD8, 0xFF)) {
            return new Veredicto(true, "image/jpeg", "ok");
        }
        if (empieza(cabecera, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) {
            return new Veredicto(true, "image/png", "ok");
        }
        if (empieza(cabecera, 0x25, 0x50, 0x44, 0x46, 0x2D)) {
            return new Veredicto(true, "application/pdf", "ok");
        }
        return new Veredicto(false, null, "tipo no permitido");
    }

    private static boolean empieza(byte[] b, int... firma) {
        if (b.length < firma.length) {
            return false;
        }
        for (int i = 0; i < firma.length; i++) {
            if ((b[i] & 0xFF) != firma[i]) {
                return false;
            }
        }
        return true;
    }

    public static String destino(String objetoEnCuarentena) {
        if (!objetoEnCuarentena.matches("cuarentena/S-[0-9]{1,20}\\.[a-z]{3,4}")) {
            throw new IllegalArgumentException("nombre fuera de la convención");
        }
        return "aprobados/" + objetoEnCuarentena.substring("cuarentena/".length());
    }
}
```

### 2.3 Adaptador de Cloud Storage
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.ByteBuffer;
import java.util.Arrays;

/** Adaptador: lee la cabecera por rango y mueve/borra con precondiciones de generación. */
public class SubidasGcp implements AutoCloseable {

    public record Info(long bytes, long generacion) { }

    private final Storage storage;
    private final String bucket;

    public SubidasGcp(GoogleCredentials cred, String proyecto, String bucket) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public Info info(String objeto) {
        var b = storage.get(BlobId.of(bucket, objeto));
        if (b == null) {
            throw new IllegalArgumentException("no existe " + objeto);
        }
        return new Info(b.getSize(), b.getGeneration());
    }

    public byte[] cabecera(String objeto, int n) {
        try (var r = storage.reader(BlobId.of(bucket, objeto))) {
            r.limit(n);                                   // solo los primeros n bytes
            var buf = ByteBuffer.allocate(n);
            int leidos = r.read(buf);
            return Arrays.copyOf(buf.array(), Math.max(leidos, 0));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Copia la generación validada solo si el destino no existe y luego borra esa misma generación. */
    public void mover(String origen, String destino, long generacion) {
        storage.copy(Storage.CopyRequest.newBuilder()
            .setSource(BlobId.of(bucket, origen, generacion))
            .setSourceOptions(Storage.BlobSourceOption.generationMatch(generacion))
            .setTarget(BlobInfo.newBuilder(bucket, destino).build(), Storage.BlobTargetOption.doesNotExist())
            .build()).getResult();
        borrar(origen, generacion);
    }

    public void borrar(String objeto, long generacion) {
        storage.delete(BlobId.of(bucket, objeto), Storage.BlobSourceOption.generationMatch(generacion));
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDeSubidas {

    public record Resultado(String id, String estado, String detalle) { }

    private final SubidasGcp objetos;
    // Demo: estados en memoria; en la app real, Firestore o la base con actualización condicional.
    private final Map<String, Subidas.Estado> estados = new ConcurrentHashMap<>();

    public ServicioDeSubidas(SubidasGcp objetos) {
        this.objetos = objetos;
    }

    /** Lo invoca el consumidor del evento OBJECT_FINALIZE (función o endpoint). */
    public Resultado alLlegar(String objeto) {
        String id = objeto.substring(objeto.indexOf('/') + 1, objeto.lastIndexOf('.'));
        estados.putIfAbsent(id, Subidas.Estado.PENDIENTE);
        if (Subidas.transicion(estados.get(id), Subidas.Estado.PENDIENTE, Subidas.Estado.RECIBIDA).isEmpty()) {
            return new Resultado(id, estados.get(id).name(), "evento duplicado: ignorado");
        }
        estados.put(id, Subidas.Estado.RECIBIDA);
        var info = objetos.info(objeto);
        var v = Subidas.validar(objetos.cabecera(objeto, 16), info.bytes(), 25L * 1024 * 1024);
        if (!v.aprobado()) {
            objetos.borrar(objeto, info.generacion());
            estados.put(id, Subidas.Estado.RECHAZADA);
            return new Resultado(id, "RECHAZADA", v.motivo());
        }
        objetos.mover(objeto, Subidas.destino(objeto), info.generacion());
        estados.put(id, Subidas.Estado.APROBADA);
        return new Resultado(id, "APROBADA", v.tipo()); // aquí se envía el ticket a la cola
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class SubidasConfiguracion {

    @Bean(destroyMethod = "close")
    SubidasGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${subidas.bucket}") String bucket) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SubidasGcp(cred, proyecto, bucket);
    }

    @Bean
    ServicioDeSubidas servicio(SubidasGcp a) {
        return new ServicioDeSubidas(a);
    }
}

@RestController
@RequestMapping("/tienda/subidas")
class SubidasControlador {

    private final ServicioDeSubidas s;

    SubidasControlador(ServicioDeSubidas s) {
        this.s = s;
    }

    @PostMapping("/llegada")
    ServicioDeSubidas.Resultado alLlegar(@RequestParam String objeto) {
        return s.alLlegar(objeto);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/tienda/subidas")
class SubidasReactivoControlador {

    private final ServicioDeSubidas s;

    SubidasReactivoControlador(ServicioDeSubidas s) {
        this.s = s;
    }

    @PostMapping("/llegada")
    Mono<ServicioDeSubidas.Resultado> alLlegar(@RequestParam String objeto) {
        return Mono.fromCallable(() -> s.alLlegar(objeto)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class SubidasProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "subidas.bucket")
    String bucket;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SubidasGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SubidasGcp(cred, proyecto, bucket);
    }

    void cerrar(@Disposes SubidasGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeSubidas servicio(SubidasGcp a) {
        return new ServicioDeSubidas(a);
    }
}

@Path("/tienda/subidas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class SubidasRecurso {

    @Inject
    ServicioDeSubidas s;

    @POST
    @Path("/llegada")
    public ServicioDeSubidas.Resultado alLlegar(@QueryParam("objeto") String objeto) {
        return s.alLlegar(objeto);
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
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/tienda/subidas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class SubidasRecursoReactivo {

    @Inject
    ServicioDeSubidas s;

    @POST
    @Path("/llegada")
    public Uni<ServicioDeSubidas.Resultado> alLlegar(@QueryParam("objeto") String objeto) {
        return Uni.createFrom().item(() -> s.alLlegar(objeto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Validar y mover | `roles/storage.objectUser` en el bucket para `run-validador` |
| Publicar el ticket | `roles/pubsub.publisher` en `subidas-aprobadas` |

## 8. Qué NO hacer desde Java
- No descargues el archivo completo para validar el tipo.
- No muevas sin precondición de generación.
- No apruebes por extensión ni por `Content-Type`.
- No registres URLs firmadas.
