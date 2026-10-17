# Google Cloud · Storage · URLs firmadas · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **emisor de URLs firmadas con reglas**: la lógica pura fija prefijo, método, vencimiento y, en subidas, el `Content-Type` exacto y la precondición `x-goog-if-generation-match: 0`; el adaptador firma con V4 mediante `Storage.signUrl` usando las credenciales adjuntas como `ServiceAccountSigner` (firma vía IAM `signBlob`, sin llaves). El servicio devuelve también las cabeceras que el cliente debe enviar tal cual.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
urls:
  bucket: modalima-tienda-prod-fotos
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
urls.bucket=modalima-tienda-prod-fotos
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

### 2.2 Política de firma (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import java.util.Set;

/** Reglas para emitir URLs firmadas: prefijo, método, vencimiento y tipo fijados por el backend. Puro. */
public class PoliticaDeFirma {

    public enum Metodo { GET, PUT }

    public record Plan(String objeto, Metodo metodo, int minutos, Map<String, String> cabeceras) { }

    private final Set<String> prefijos;
    private final Set<String> tipos;

    public PoliticaDeFirma(Set<String> prefijos, Set<String> tipos) {
        this.prefijos = Set.copyOf(prefijos);
        this.tipos = Set.copyOf(tipos);
    }

    public Plan descarga(String objeto, int minutos) {
        validarObjeto(objeto);
        if (minutos < 1 || minutos > 15) {
            throw new IllegalArgumentException("descargas: 1 a 15 minutos");
        }
        return new Plan(objeto, Metodo.GET, minutos, Map.of());
    }

    /** La subida exige el tipo exacto y que el objeto no exista (precondición firmada). */
    public Plan subida(String objeto, String tipo, int minutos) {
        validarObjeto(objeto);
        if (!tipos.contains(tipo)) {
            throw new IllegalArgumentException("tipo no permitido");
        }
        if (minutos < 1 || minutos > 30) {
            throw new IllegalArgumentException("subidas: 1 a 30 minutos");
        }
        return new Plan(objeto, Metodo.PUT, minutos, Map.of("Content-Type", tipo, "x-goog-if-generation-match", "0"));
    }

    private void validarObjeto(String objeto) {
        if (objeto == null || objeto.contains("..") || objeto.startsWith("/") || prefijos.stream().noneMatch(objeto::startsWith)) {
            throw new IllegalArgumentException("objeto fuera de los prefijos permitidos");
        }
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.ServiceAccountSigner;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.HttpMethod;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.util.concurrent.TimeUnit;

/** Adaptador: firma V4 sin llaves (las credenciales adjuntas firman vía IAM signBlob). */
public class FirmadorGcs implements AutoCloseable {

    private final Storage storage;
    private final ServiceAccountSigner firmante;
    private final String bucket;

    public FirmadorGcs(GoogleCredentials cred, String proyecto, String bucket) {
        if (!(cred instanceof ServiceAccountSigner s)) {
            throw new IllegalStateException("estas credenciales no pueden firmar: usa la SA adjunta o suplanta una SA (gcp.suplantar)");
        }
        this.firmante = s;
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public String firmar(PoliticaDeFirma.Plan p) {
        var info = BlobInfo.newBuilder(BlobId.of(bucket, p.objeto())).build();
        var metodo = p.metodo() == PoliticaDeFirma.Metodo.GET ? HttpMethod.GET : HttpMethod.PUT;
        return storage.signUrl(info, p.minutos(), TimeUnit.MINUTES,
            Storage.SignUrlOption.withV4Signature(),
            Storage.SignUrlOption.httpMethod(metodo),
            Storage.SignUrlOption.withExtHeaders(p.cabeceras()),
            Storage.SignUrlOption.signWith(firmante)).toString();
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Set;

public class ServicioDeUrls {

    public record Emitida(String url, String metodo, int minutos, java.util.Map<String, String> cabecerasObligatorias) { }

    private final FirmadorGcs firmador;
    private final PoliticaDeFirma politica = new PoliticaDeFirma(Set.of("fotos/", "pedidos/"), Set.of("image/jpeg", "image/png", "application/pdf"));

    public ServicioDeUrls(FirmadorGcs firmador) {
        this.firmador = firmador;
    }

    public Emitida descarga(String objeto) {
        // aquí va la autorización de negocio: ¿este usuario puede ver este objeto?
        var p = politica.descarga(objeto, 10);
        return new Emitida(firmador.firmar(p), "GET", p.minutos(), p.cabeceras());
    }

    public Emitida subida(String idFoto, String tipo) {
        String ext = tipo.equals("image/png") ? "png" : "jpg";
        var p = politica.subida("fotos/" + idFoto + "." + ext, tipo, 10);
        return new Emitida(firmador.firmar(p), "PUT", p.minutos(), p.cabeceras());
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
class UrlsConfiguracion {

    @Bean(destroyMethod = "close")
    FirmadorGcs adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${urls.bucket}") String bucket) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FirmadorGcs(cred, proyecto, bucket);
    }

    @Bean
    ServicioDeUrls servicio(FirmadorGcs a) {
        return new ServicioDeUrls(a);
    }
}

@RestController
@RequestMapping("/storage/urls")
class UrlsControlador {

    private final ServicioDeUrls s;

    UrlsControlador(ServicioDeUrls s) {
        this.s = s;
    }

    @GetMapping("/descarga")
    ServicioDeUrls.Emitida descarga(@RequestParam String objeto) {
        return s.descarga(objeto);
    }

    @PostMapping("/subida/{id}")
    ServicioDeUrls.Emitida subida(@PathVariable String id, @RequestParam String tipo) {
        return s.subida(id, tipo);
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
@RequestMapping("/reactivo/storage/urls")
class UrlsReactivoControlador {

    private final ServicioDeUrls s;

    UrlsReactivoControlador(ServicioDeUrls s) {
        this.s = s;
    }

    @GetMapping("/descarga")
    Mono<ServicioDeUrls.Emitida> descarga(@RequestParam String objeto) {
        return Mono.fromCallable(() -> s.descarga(objeto)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/subida/{id}")
    Mono<ServicioDeUrls.Emitida> subida(@PathVariable String id, @RequestParam String tipo) {
        return Mono.fromCallable(() -> s.subida(id, tipo)).subscribeOn(Schedulers.boundedElastic());
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
class UrlsProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "urls.bucket")
    String bucket;

    @jakarta.enterprise.inject.Produces
    @Singleton
    FirmadorGcs adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FirmadorGcs(cred, proyecto, bucket);
    }

    void cerrar(@Disposes FirmadorGcs a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeUrls servicio(FirmadorGcs a) {
        return new ServicioDeUrls(a);
    }
}

@Path("/storage/urls")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class UrlsRecurso {

    @Inject
    ServicioDeUrls s;

    @GET
    @Path("/descarga")
    public ServicioDeUrls.Emitida descarga(@QueryParam("objeto") String objeto) {
        return s.descarga(objeto);
    }

    @POST
    @Path("/subida/{id}")
    public ServicioDeUrls.Emitida subida(@PathParam("id") String id, @QueryParam("tipo") String tipo) {
        return s.subida(id, tipo);
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

@Path("/reactivo/storage/urls")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class UrlsRecursoReactivo {

    @Inject
    ServicioDeUrls s;

    @GET
    @Path("/descarga")
    public Uni<ServicioDeUrls.Emitida> descarga(@QueryParam("objeto") String objeto) {
        return Uni.createFrom().item(() -> s.descarga(objeto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/subida/{id}")
    public Uni<ServicioDeUrls.Emitida> subida(@PathParam("id") String id, @QueryParam("tipo") String tipo) {
        return Uni.createFrom().item(() -> s.subida(id, tipo)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Firmar sin llaves | `roles/iam.serviceAccountTokenCreator` de la SA sobre sí misma (signBlob) |
| Permisos delegados | `roles/storage.objectCreator` (subidas) / `objectViewer` (descargas) en el bucket |

## 8. Qué NO hacer desde Java
- No firmes con llaves JSON.
- No dejes que el cliente elija el nombre del objeto.
- No registres URLs firmadas.
- No firmes por más tiempo del necesario: no se pueden revocar.
