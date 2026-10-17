# Google Cloud · Datos · Bigtable · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

En Bigtable todo depende de la **clave de fila**. La lógica pura arma `maquina#timestampInvertido` (19 dígitos con ceros para que el orden lexicográfico funcione), recupera el instante y detecta claves que empiezan por fecha; el adaptador escribe con `mutateRow` y lee las últimas N con `Query.prefix(...).limit(n)`, que gracias a la inversión son las más recientes.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
bigtable:
  instancia: telemetria-cafe
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
bigtable.instancia=telemetria-cafe
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

### 2.2 Clave de fila (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Diseño de clave de fila para series de tiempo: entidad#timestampInvertido (lo último primero). Puro.
 */
public final class ClaveDeFila {

    public record Revision(boolean riesgo, List<String> motivos) { }

    private ClaveDeFila() {
    }

    public static String de(String entidad, Instant momento) {
        long invertido = Long.MAX_VALUE - momento.toEpochMilli();
        return entidad + "#" + String.format("%019d", invertido);
    }

    public static Instant momento(String clave) {
        long invertido = Long.parseLong(clave.substring(clave.lastIndexOf('#') + 1));
        return Instant.ofEpochMilli(Long.MAX_VALUE - invertido);
    }

    public static String prefijo(String entidad) {
        return entidad + "#";
    }

    public static Revision revisar(String clave) {
        var motivos = new ArrayList<String>();
        if (clave.matches("^\\d{8}.*") || clave.matches("^\\d{4}-\\d{2}-\\d{2}.*")) {
            motivos.add("empieza por fecha: todas las escrituras recientes caen en el mismo rango");
        }
        if (clave.length() > 4096) {
            motivos.add("clave demasiado larga");
        }
        return new Revision(!motivos.isEmpty(), motivos);
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.bigtable.data.v2.BigtableDataClient;
import com.google.cloud.bigtable.data.v2.BigtableDataSettings;
import com.google.cloud.bigtable.data.v2.models.Query;
import com.google.cloud.bigtable.data.v2.models.RowMutation;
import com.google.cloud.bigtable.data.v2.models.TableId;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: escribe lecturas por máquina y lee las últimas N por prefijo. */
public class BigtableGcp implements AutoCloseable {

    public record Lectura(Instant momento, double temperatura) { }

    private static final TableId TABLA = TableId.of("lecturas");
    private final BigtableDataClient cliente;

    public BigtableGcp(GoogleCredentials cred, String proyecto, String instancia) {
        try {
            this.cliente = BigtableDataClient.create(BigtableDataSettings.newBuilder()
                .setProjectId(proyecto).setInstanceId(instancia)
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public void escribir(String maquina, Lectura l) {
        cliente.mutateRow(RowMutation.create(TABLA, ClaveDeFila.de(maquina, l.momento()))
            .setCell("m", "temp", Double.toString(l.temperatura())));
    }

    public List<Lectura> ultimas(String maquina, int n) {
        var out = new ArrayList<Lectura>();
        for (var fila : cliente.readRows(Query.create(TABLA).prefix(ClaveDeFila.prefijo(maquina)).limit(n))) {
            var celdas = fila.getCells("m", "temp");
            if (!celdas.isEmpty()) {
                out.add(new Lectura(ClaveDeFila.momento(fila.getKey().toStringUtf8()),
                    Double.parseDouble(celdas.get(0).getValue().toStringUtf8())));
            }
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
import java.time.Instant;
import java.util.List;

public class ServicioDeTelemetria {

    private final BigtableGcp bt;

    public ServicioDeTelemetria(BigtableGcp bt) {
        this.bt = bt;
    }

    public ClaveDeFila.Revision revisar(String clave) {
        return ClaveDeFila.revisar(clave);
    }

    public List<BigtableGcp.Lectura> registrar(String maquina, double temperatura) {
        bt.escribir(maquina, new BigtableGcp.Lectura(Instant.now(), temperatura));
        return bt.ultimas(maquina, 10);
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
class TelemetriaConfiguracion {

    @Bean(destroyMethod = "close")
    BigtableGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${bigtable.instancia}") String instancia) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new BigtableGcp(cred, proyecto, instancia);
    }

    @Bean
    ServicioDeTelemetria servicio(BigtableGcp a) {
        return new ServicioDeTelemetria(a);
    }
}

@RestController
@RequestMapping("/datos/telemetria")
class TelemetriaControlador {

    private final ServicioDeTelemetria s;

    TelemetriaControlador(ServicioDeTelemetria s) {
        this.s = s;
    }

    @GetMapping("/clave")
    ClaveDeFila.Revision revisar(@RequestParam String clave) {
        return s.revisar(clave);
    }

    @PostMapping("/{maquina}")
    java.util.List<BigtableGcp.Lectura> registrar(@PathVariable String maquina, @RequestParam double temperatura) {
        return s.registrar(maquina, temperatura);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/telemetria")
class TelemetriaReactivoControlador {

    private final ServicioDeTelemetria s;

    TelemetriaReactivoControlador(ServicioDeTelemetria s) {
        this.s = s;
    }

    @GetMapping("/clave")
    Mono<ClaveDeFila.Revision> revisar(@RequestParam String clave) {
        return Mono.fromCallable(() -> s.revisar(clave));
    }

    @PostMapping("/{maquina}")
    Mono<java.util.List<BigtableGcp.Lectura>> registrar(@PathVariable String maquina, @RequestParam double temperatura) {
        return Mono.fromCallable(() -> s.registrar(maquina, temperatura)).subscribeOn(Schedulers.boundedElastic());
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
class TelemetriaProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "bigtable.instancia")
    String instancia;

    @jakarta.enterprise.inject.Produces
    @Singleton
    BigtableGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new BigtableGcp(cred, proyecto, instancia);
    }

    void cerrar(@Disposes BigtableGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeTelemetria servicio(BigtableGcp a) {
        return new ServicioDeTelemetria(a);
    }
}

@Path("/datos/telemetria")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class TelemetriaRecurso {

    @Inject
    ServicioDeTelemetria s;

    @GET
    @Path("/clave")
    public ClaveDeFila.Revision revisar(@QueryParam("clave") String clave) {
        return s.revisar(clave);
    }

    @POST
    @Path("/{maquina}")
    public java.util.List<BigtableGcp.Lectura> registrar(@PathParam("maquina") String maquina, @QueryParam("temperatura") double temperatura) {
        return s.registrar(maquina, temperatura);
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
import java.util.List;

@Path("/reactivo/datos/telemetria")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class TelemetriaRecursoReactivo {

    @Inject
    ServicioDeTelemetria s;

    @GET
    @Path("/clave")
    public Uni<ClaveDeFila.Revision> revisar(@QueryParam("clave") String clave) {
        return Uni.createFrom().item(() -> s.revisar(clave));
    }

    @POST
    @Path("/{maquina}")
    public Uni<java.util.List<BigtableGcp.Lectura>> registrar(@PathParam("maquina") String maquina, @QueryParam("temperatura") double temperatura) {
        return Uni.createFrom().item(() -> s.registrar(maquina, temperatura)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer y escribir | `roles/bigtable.user` en la instancia |
| Solo lectura | `roles/bigtable.reader` |

## 8. Qué NO hacer desde Java
- No empieces la clave con una fecha.
- No hagas escaneos completos desde la API: exporta para analítica.
- No guardes celdas grandes (> 10 MB).
- No crees un cliente por petición.
