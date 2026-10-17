# Google Cloud · Storage · Cloud Storage · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **guardado idempotente de comprobantes**: la lógica pura valida tipo y tamaño y arma un nombre determinista; el adaptador escribe con `Storage.create(..., BlobTargetOption.doesNotExist())` (equivale a `ifGenerationMatch=0`), así un reintento nunca pisa el comprobante ya enviado: un `412` significa «ya existía».

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
almacen:
  bucket: modalima-tienda-prod-comprobantes
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
almacen.bucket=modalima-tienda-prod-comprobantes
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

### 2.2 Reglas de nombre (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/** Nombre determinista, tipo y tamaño de los comprobantes. Puro: reloj inyectado. */
public class ReglasDeComprobantes {

    private static final Map<String, String> EXTENSIONES = Map.of("application/pdf", "pdf", "image/png", "png", "image/jpeg", "jpg");
    private static final DateTimeFormatter RUTA = DateTimeFormatter.ofPattern("yyyy/MM/dd");

    private final Clock reloj;
    private final long maxBytes;

    public ReglasDeComprobantes(Clock reloj, long maxBytes) {
        this.reloj = reloj;
        this.maxBytes = maxBytes;
    }

    public String nombre(String idPedido, String tipo, long bytes) {
        if (idPedido == null || !idPedido.matches("P-[0-9]{1,12}")) {
            throw new IllegalArgumentException("idPedido inválido");
        }
        String ext = EXTENSIONES.get(tipo);
        if (ext == null) {
            throw new IllegalArgumentException("tipo no permitido: " + tipo);
        }
        if (bytes <= 0 || bytes > maxBytes) {
            throw new IllegalArgumentException("tamaño fuera de rango");
        }
        return "pedidos/" + LocalDate.now(reloj).format(RUTA) + "/" + idPedido + "." + ext;
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageException;
import com.google.cloud.storage.StorageOptions;
import java.util.Map;

/** Adaptador: escribe solo si el objeto no existe (ifGenerationMatch=0). */
public class AlmacenGcs implements AutoCloseable {

    public record Guardado(String objeto, boolean nuevo, Long generacion) { }

    private final Storage storage;
    private final String bucket;

    public AlmacenGcs(GoogleCredentials cred, String proyecto, String bucket) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public Guardado guardarSiNoExiste(String objeto, byte[] datos, String tipo, Map<String, String> meta) {
        var info = BlobInfo.newBuilder(BlobId.of(bucket, objeto)).setContentType(tipo).setMetadata(meta).build();
        try {
            var b = storage.create(info, datos, Storage.BlobTargetOption.doesNotExist());
            return new Guardado(objeto, true, b.getGeneration());
        } catch (StorageException e) {
            if (e.getCode() == 412) {
                return new Guardado(objeto, false, null); // ya existía: el reintento es inocuo
            }
            throw e;
        }
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            throw new IllegalStateException("error al cerrar Storage", e);
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.util.Base64;
import java.util.Map;

public class ServicioDeComprobantes {

    public record Subida(String tipo, String contenidoBase64) { }

    private final AlmacenGcs almacen;
    private final ReglasDeComprobantes reglas = new ReglasDeComprobantes(Clock.systemUTC(), 5 * 1024 * 1024);

    public ServicioDeComprobantes(AlmacenGcs almacen) {
        this.almacen = almacen;
    }

    public AlmacenGcs.Guardado subir(String idPedido, Subida s) {
        byte[] datos = Base64.getDecoder().decode(s.contenidoBase64());
        return almacen.guardarSiNoExiste(reglas.nombre(idPedido, s.tipo(), datos.length), datos, s.tipo(), Map.of("pedido", idPedido));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ComprobantesConfiguracion {

    @Bean(destroyMethod = "close")
    AlmacenGcs adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${almacen.bucket}") String bucket) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new AlmacenGcs(cred, proyecto, bucket);
    }

    @Bean
    ServicioDeComprobantes servicio(AlmacenGcs a) {
        return new ServicioDeComprobantes(a);
    }
}

@RestController
@RequestMapping("/storage/comprobantes")
class ComprobantesControlador {

    private final ServicioDeComprobantes s;

    ComprobantesControlador(ServicioDeComprobantes s) {
        this.s = s;
    }

    @PostMapping("/{id}")
    AlmacenGcs.Guardado subir(@PathVariable String id, @RequestBody ServicioDeComprobantes.Subida sub) {
        return s.subir(id, sub);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/storage/comprobantes")
class ComprobantesReactivoControlador {

    private final ServicioDeComprobantes s;

    ComprobantesReactivoControlador(ServicioDeComprobantes s) {
        this.s = s;
    }

    @PostMapping("/{id}")
    Mono<AlmacenGcs.Guardado> subir(@PathVariable String id, @RequestBody ServicioDeComprobantes.Subida sub) {
        return Mono.fromCallable(() -> s.subir(id, sub)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ComprobantesProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "almacen.bucket")
    String bucket;

    @jakarta.enterprise.inject.Produces
    @Singleton
    AlmacenGcs adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new AlmacenGcs(cred, proyecto, bucket);
    }

    void cerrar(@Disposes AlmacenGcs a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeComprobantes servicio(AlmacenGcs a) {
        return new ServicioDeComprobantes(a);
    }
}

@Path("/storage/comprobantes")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ComprobantesRecurso {

    @Inject
    ServicioDeComprobantes s;

    @POST
    @Path("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public AlmacenGcs.Guardado subir(@PathParam("id") String id, ServicioDeComprobantes.Subida sub) {
        return s.subir(id, sub);
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
import jakarta.ws.rs.PathParam;

@Path("/reactivo/storage/comprobantes")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ComprobantesRecursoReactivo {

    @Inject
    ServicioDeComprobantes s;

    @POST
    @Path("/{id}")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<AlmacenGcs.Guardado> subir(@PathParam("id") String id, ServicioDeComprobantes.Subida sub) {
        return Uni.createFrom().item(() -> s.subir(id, sub)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Crear objetos (sin leer ni borrar) | `roles/storage.objectCreator` en el bucket |

## 8. Qué NO hacer desde Java
- No cargues archivos grandes en memoria: usa `storage.writer(...)` (subida reanudable) con un `InputStream`.
- No crees un cliente `Storage` por petición.
- No confíes en el `Content-Type` que envía el usuario.
- No uses ACL por objeto: acceso uniforme e IAM.
