# Google Cloud · Terraform · Estado remoto · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Desde Java **no ejecutas `apply` ni editas el estado**: eso lo hacen los pipelines. Lo que sí construyes es un **auditor de solo lectura** del bucket del estado: ¿versionado, acceso uniforme, sin acceso público y con CMEK? ¿Hay `.tflock` viejos (runner muerto)? ¿Objetos fuera de la convención `componente/workspace.tfstate` o estados demasiado grandes? Usa `Storage.get(bucket)` y `Storage.list`, **sin descargar** nunca el estado.

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

### 2.2 Reglas (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Reglas del bucket del estado y de sus objetos (convención, tamaño, candados viejos). Puro.
 */
public final class RevisionDeEstado {

    public record Bucket(boolean versionado, boolean accesoUniforme, boolean sinAccesoPublico, String kms) { }

    public record Objeto(String nombre, long bytes, Instant creado) { }

    public record Informe(List<String> problemas, List<String> candadosViejos, List<String> estados) { }

    private static final Pattern CONVENCION = Pattern.compile("[a-z0-9-]+/[a-z0-9-]+\\.(tfstate|tflock)");

    private RevisionDeEstado() {
    }

    public static Informe revisar(Bucket b, List<Objeto> objetos, Instant ahora, Duration candadoMaximo, long bytesMaximo) {
        var p = new ArrayList<String>();
        if (!b.versionado()) {
            p.add("bucket sin versionado");
        }
        if (!b.accesoUniforme()) {
            p.add("acceso uniforme desactivado (ACL por objeto)");
        }
        if (!b.sinAccesoPublico()) {
            p.add("prevención de acceso público no forzada");
        }
        if (b.kms() == null || b.kms().isBlank()) {
            p.add("sin CMEK por defecto");
        }
        var viejos = new ArrayList<String>();
        var estados = new ArrayList<String>();
        for (var o : objetos) {
            if (!CONVENCION.matcher(o.nombre()).matches()) {
                p.add("objeto fuera de convención: " + o.nombre());
            }
            if (o.nombre().endsWith(".tflock") && Duration.between(o.creado(), ahora).compareTo(candadoMaximo) > 0) {
                viejos.add(o.nombre());
            }
            if (o.nombre().endsWith(".tfstate")) {
                estados.add(o.nombre());
                if (o.bytes() > bytesMaximo) {
                    p.add("estado grande (divídelo): " + o.nombre());
                }
            }
        }
        return new Informe(p, viejos, estados);
    }
}
```

### 2.3 Adaptador de Cloud Storage
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;

/** Adaptador de solo lectura: metadatos del bucket y lista de objetos (nunca descarga el estado). */
public class EstadoGcp implements AutoCloseable {

    private final Storage storage;

    public EstadoGcp(GoogleCredentials cred, String proyecto) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
    }

    public RevisionDeEstado.Informe auditar(String bucket) {
        var b = storage.get(bucket);
        if (b == null) {
            throw new IllegalArgumentException("no existe el bucket " + bucket);
        }
        var iam = b.getIamConfiguration();
        var datos = new RevisionDeEstado.Bucket(Boolean.TRUE.equals(b.versioningEnabled()),
            iam != null && Boolean.TRUE.equals(iam.isUniformBucketLevelAccessEnabled()),
            iam != null && iam.getPublicAccessPrevention() == com.google.cloud.storage.BucketInfo.PublicAccessPrevention.ENFORCED,
            b.getDefaultKmsKeyName());
        var objetos = new ArrayList<RevisionDeEstado.Objeto>();
        for (var blob : storage.list(bucket).iterateAll()) {
            var creado = blob.getCreateTimeOffsetDateTime();
            objetos.add(new RevisionDeEstado.Objeto(blob.getName(), blob.getSize() == null ? 0 : blob.getSize(),
                creado == null ? Instant.EPOCH : creado.toInstant()));
        }
        return RevisionDeEstado.revisar(datos, objetos, Instant.now(), Duration.ofHours(2), 5_000_000);
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
public class ServicioDeEstado {

    private final EstadoGcp gcp;

    public ServicioDeEstado(EstadoGcp gcp) {
        this.gcp = gcp;
    }

    public RevisionDeEstado.Informe auditar(String bucket) {
        return gcp.auditar(bucket);
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EstadoConfiguracion {

    @Bean(destroyMethod = "close")
    EstadoGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new EstadoGcp(cred, proyecto);
    }

    @Bean
    ServicioDeEstado servicio(EstadoGcp a) {
        return new ServicioDeEstado(a);
    }
}

@RestController
@RequestMapping("/terraform/estado")
class EstadoControlador {

    private final ServicioDeEstado s;

    EstadoControlador(ServicioDeEstado s) {
        this.s = s;
    }

    @GetMapping("/{bucket}")
    RevisionDeEstado.Informe auditar(@PathVariable String bucket) {
        return s.auditar(bucket);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/terraform/estado")
class EstadoReactivoControlador {

    private final ServicioDeEstado s;

    EstadoReactivoControlador(ServicioDeEstado s) {
        this.s = s;
    }

    @GetMapping("/{bucket}")
    Mono<RevisionDeEstado.Informe> auditar(@PathVariable String bucket) {
        return Mono.fromCallable(() -> s.auditar(bucket)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EstadoProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    EstadoGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new EstadoGcp(cred, proyecto);
    }

    void cerrar(@Disposes EstadoGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEstado servicio(EstadoGcp a) {
        return new ServicioDeEstado(a);
    }
}

@Path("/terraform/estado")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EstadoRecurso {

    @Inject
    ServicioDeEstado s;

    @GET
    @Path("/{bucket}")
    public RevisionDeEstado.Informe auditar(@PathParam("bucket") String bucket) {
        return s.auditar(bucket);
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
import jakarta.ws.rs.PathParam;

@Path("/reactivo/terraform/estado")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EstadoRecursoReactivo {

    @Inject
    ServicioDeEstado s;

    @GET
    @Path("/{bucket}")
    public Uni<RevisionDeEstado.Informe> auditar(@PathParam("bucket") String bucket) {
        return Uni.createFrom().item(() -> s.auditar(bucket)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer metadatos del bucket | `roles/storage.legacyBucketReader` *(verifica)* |
| Listar objetos | `storage.objects.list` (sin `objects.get` para no poder leer el estado) |

## 8. Qué NO hacer desde Java
- No descargues el estado: contiene secretos.
- No borres candados desde la app: `force-unlock` es una decisión humana.
- No uses la SA del pipeline para auditar.
- No expongas el informe fuera de plataforma.
