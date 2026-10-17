# Google Cloud · Storage · Filestore · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **auditor de opciones de exportación NFS**: como el BOM no incluye una biblioteca de Filestore, lee las instancias desde **Cloud Asset Inventory** (`AssetServiceClient.listAssets` con tipo `file.googleapis.com/Instance` y contenido `RESOURCE`), recorre la estructura (`fileShares[].nfsExportOptions[]`) y marca compartidos sin opciones, rangos demasiado amplios y lectura-escritura sin *root squash*. El acceso a los datos en sí se hace montando NFS y usando `java.nio.file`.

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

### 2.2 Auditor (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

/** Audita opciones de exportación NFS de instancias de Filestore. Puro. */
public class AuditorDeExportaciones {

    public record Opcion(List<String> rangos, String acceso, String squash) { }

    public record Compartido(String instancia, String nombre, List<Opcion> opciones) { }

    public record Hallazgo(String compartido, String severidad, String mensaje) { }

    public List<Hallazgo> auditar(List<Compartido> compartidos) {
        var h = new ArrayList<Hallazgo>();
        for (Compartido c : compartidos) {
            String id = c.instancia() + ":" + c.nombre();
            if (c.opciones().isEmpty()) {
                h.add(new Hallazgo(id, "ALTA", "sin opciones de exportación: cualquier cliente de la red monta en RW"));
            }
            for (Opcion o : c.opciones()) {
                for (String r : o.rangos()) {
                    int pre = r.contains("/") ? Integer.parseInt(r.substring(r.indexOf('/') + 1)) : 32;
                    if (pre < 16) {
                        h.add(new Hallazgo(id, "MEDIA", "rango muy amplio " + r));
                    }
                }
                if ("READ_WRITE".equals(o.acceso()) && "NO_ROOT_SQUASH".equals(o.squash())) {
                    h.add(new Hallazgo(id, "ALTA", "lectura-escritura sin root squash para " + o.rangos()));
                }
            }
        }
        return h;
    }
}
```

### 2.3 Adaptador (Cloud Asset Inventory)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.asset.v1.AssetServiceClient;
import com.google.cloud.asset.v1.AssetServiceSettings;
import com.google.cloud.asset.v1.ContentType;
import com.google.cloud.asset.v1.ListAssetsRequest;
import com.google.protobuf.Struct;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: lee instancias de Filestore desde Cloud Asset Inventory (contenido RESOURCE). */
public class FilestoreGcp implements AutoCloseable {

    private final AssetServiceClient cliente;
    private final String proyecto;

    public FilestoreGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = AssetServiceClient.create(AssetServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeExportaciones.Compartido> compartidos() {
        var req = ListAssetsRequest.newBuilder().setParent("projects/" + proyecto)
            .addAssetTypes("file.googleapis.com/Instance").setContentType(ContentType.RESOURCE).build();
        var out = new ArrayList<AuditorDeExportaciones.Compartido>();
        for (var a : cliente.listAssets(req).iterateAll()) {
            Struct data = a.getResource().getData();
            String instancia = a.getName().substring(a.getName().lastIndexOf('/') + 1);
            for (com.google.protobuf.Value fs : lista(data, "fileShares")) {
                var s = fs.getStructValue();
                var opciones = lista(s, "nfsExportOptions").stream().map(v -> {
                    var o = v.getStructValue();
                    return new AuditorDeExportaciones.Opcion(lista(o, "ipRanges").stream().map(com.google.protobuf.Value::getStringValue).toList(),
                        texto(o, "accessMode"), texto(o, "squashMode"));
                }).toList();
                out.add(new AuditorDeExportaciones.Compartido(instancia, texto(s, "name"), opciones));
            }
        }
        return out;
    }

    private static List<com.google.protobuf.Value> lista(Struct s, String campo) {
        var v = s.getFieldsMap().get(campo);
        return v == null ? List.of() : v.getListValue().getValuesList();
    }

    private static String texto(Struct s, String campo) {
        var v = s.getFieldsMap().get(campo);
        return v == null ? "" : v.getStringValue();
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

public class ServicioDeFilestore {

    private final FilestoreGcp filestore;
    private final AuditorDeExportaciones auditor = new AuditorDeExportaciones();

    public ServicioDeFilestore(FilestoreGcp filestore) {
        this.filestore = filestore;
    }

    public List<AuditorDeExportaciones.Hallazgo> auditar() {
        return auditor.auditar(filestore.compartidos());
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class FilestoreConfiguracion {

    @Bean(destroyMethod = "close")
    FilestoreGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FilestoreGcp(cred, proyecto);
    }

    @Bean
    ServicioDeFilestore servicio(FilestoreGcp a) {
        return new ServicioDeFilestore(a);
    }
}

@RestController
@RequestMapping("/storage/filestore")
class FilestoreControlador {

    private final ServicioDeFilestore s;

    FilestoreControlador(ServicioDeFilestore s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeExportaciones.Hallazgo> auditar() {
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/storage/filestore")
class FilestoreReactivoControlador {

    private final ServicioDeFilestore s;

    FilestoreReactivoControlador(ServicioDeFilestore s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeExportaciones.Hallazgo>> auditar() {
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class FilestoreProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    FilestoreGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FilestoreGcp(cred, proyecto);
    }

    void cerrar(@Disposes FilestoreGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeFilestore servicio(FilestoreGcp a) {
        return new ServicioDeFilestore(a);
    }
}

@Path("/storage/filestore")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class FilestoreRecurso {

    @Inject
    ServicioDeFilestore s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeExportaciones.Hallazgo> auditar() {
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
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/storage/filestore")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class FilestoreRecursoReactivo {

    @Inject
    ServicioDeFilestore s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeExportaciones.Hallazgo>> auditar() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer el inventario de recursos | `roles/cloudasset.viewer` en el proyecto |

## 8. Qué NO hacer desde Java
- No uses la API para leer archivos: monta NFS.
- No escribas el mismo archivo desde varias réplicas sin coordinación (renombrado atómico, nombres únicos).
- No corras contenedores como root para «arreglar» permisos.
