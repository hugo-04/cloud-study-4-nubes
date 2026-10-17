# Google Cloud · Datos · Spanner · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: un **revisor puro de claves primarias** que detecta columnas crecientes al inicio de la PK (hotspot) y genera claves UUID o con prefijo de hash, y un adaptador que **reserva stock** en una transacción de lectura-escritura con `readWriteTransaction().run(...)`: si otra transacción choca, Spanner aborta y la biblioteca **reintenta el bloque completo**, por eso el bloque no debe tener efectos externos.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
spanner:
  instancia: modalima-tienda
  base: tienda
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
spanner.instancia=modalima-tienda
spanner.base=tienda
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

### 2.2 Claves (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Revisa diseños de clave primaria (riesgo de hotspot) y genera claves seguras. Puro.
 */
public final class ClavesSpanner {

    public record Revision(String tabla, boolean riesgo, List<String> motivos) { }

    private static final Pattern CRECIENTE = Pattern.compile("(?i).*(fecha|timestamp|creado|time|_at|seq|secuencia|contador|autoinc).*");

    private ClavesSpanner() {
    }

    /** columnasPk en orden; la primera es la que decide la división. */
    public static Revision revisar(String tabla, List<String> columnasPk, boolean interleavedEnPadre) {
        var motivos = new ArrayList<String>();
        if (!columnasPk.isEmpty() && !interleavedEnPadre && CRECIENTE.matcher(columnasPk.get(0)).matches()) {
            motivos.add("la primera columna de la PK (" + columnasPk.get(0) + ") parece creciente: hotspot");
        }
        if (columnasPk.isEmpty()) {
            motivos.add("tabla sin clave primaria");
        }
        return new Revision(tabla, !motivos.isEmpty(), motivos);
    }

    public static String nuevaClave() {
        return UUID.randomUUID().toString();
    }

    /** Alternativa cuando necesitas ordenar por tiempo dentro de un cliente: prefijo de hash. */
    public static String conPrefijo(String natural, int fragmentos) {
        int f = Math.floorMod(natural.hashCode(), fragmentos);
        return String.format("%02d#%s", f, natural);
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.spanner.DatabaseClient;
import com.google.cloud.spanner.DatabaseId;
import com.google.cloud.spanner.Key;
import com.google.cloud.spanner.Mutation;
import com.google.cloud.spanner.Spanner;
import com.google.cloud.spanner.SpannerOptions;
import java.util.List;

/** Adaptador: reserva de stock en una transacción de lectura-escritura (reintentos automáticos ante ABORTED). */
public class SpannerGcp implements AutoCloseable {

    public record Reserva(String sku, boolean reservada, long stockRestante) { }

    private final Spanner spanner;
    private final DatabaseClient db;

    public SpannerGcp(GoogleCredentials cred, String proyecto, String instancia, String base) {
        this.spanner = SpannerOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.db = spanner.getDatabaseClient(DatabaseId.of(proyecto, instancia, base));
    }

    public Reserva reservar(String sku, long cantidad) {
        return db.readWriteTransaction().run(tx -> {
            var fila = tx.readRow("Inventario", Key.of(sku), List.of("Stock"));
            long stock = fila == null ? 0 : fila.getLong("Stock");
            if (stock < cantidad) {
                return new Reserva(sku, false, stock);   // sin escritura: la transacción termina sin cambios
            }
            tx.buffer(Mutation.newUpdateBuilder("Inventario")
                .set("Sku").to(sku)
                .set("Stock").to(stock - cantidad)
                .set("Actualizado").to(com.google.cloud.spanner.Value.COMMIT_TIMESTAMP)
                .build());
            return new Reserva(sku, true, stock - cantidad);
        });
    }

    @Override
    public void close() {
        spanner.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public class ServicioDeInventario {

    private final SpannerGcp spanner;

    public ServicioDeInventario(SpannerGcp spanner) {
        this.spanner = spanner;
    }

    public ClavesSpanner.Revision revisar(String tabla, List<String> pk) {
        return ClavesSpanner.revisar(tabla, pk, false);
    }

    public SpannerGcp.Reserva reservar(String sku, long cantidad) {
        if (cantidad <= 0) {
            throw new IllegalArgumentException("cantidad inválida");
        }
        return spanner.reservar(sku, cantidad);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class InventarioConfiguracion {

    @Bean(destroyMethod = "close")
    SpannerGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${spanner.instancia}") String instancia, @Value("${spanner.base}") String base) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SpannerGcp(cred, proyecto, instancia, base);
    }

    @Bean
    ServicioDeInventario servicio(SpannerGcp a) {
        return new ServicioDeInventario(a);
    }
}

@RestController
@RequestMapping("/datos/inventario")
class InventarioControlador {

    private final ServicioDeInventario s;

    InventarioControlador(ServicioDeInventario s) {
        this.s = s;
    }

    @PostMapping("/claves/{tabla}")
    ClavesSpanner.Revision revisar(@PathVariable String tabla, @RequestBody java.util.List<String> pk) {
        return s.revisar(tabla, pk);
    }

    @PostMapping("/{sku}/reserva")
    SpannerGcp.Reserva reservar(@PathVariable String sku, @RequestParam long cantidad) {
        return s.reservar(sku, cantidad);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/inventario")
class InventarioReactivoControlador {

    private final ServicioDeInventario s;

    InventarioReactivoControlador(ServicioDeInventario s) {
        this.s = s;
    }

    @PostMapping("/claves/{tabla}")
    Mono<ClavesSpanner.Revision> revisar(@PathVariable String tabla, @RequestBody java.util.List<String> pk) {
        return Mono.fromCallable(() -> s.revisar(tabla, pk));
    }

    @PostMapping("/{sku}/reserva")
    Mono<SpannerGcp.Reserva> reservar(@PathVariable String sku, @RequestParam long cantidad) {
        return Mono.fromCallable(() -> s.reservar(sku, cantidad)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class InventarioProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "spanner.instancia")
    String instancia;

    @ConfigProperty(name = "spanner.base")
    String base;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SpannerGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SpannerGcp(cred, proyecto, instancia, base);
    }

    void cerrar(@Disposes SpannerGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeInventario servicio(SpannerGcp a) {
        return new ServicioDeInventario(a);
    }
}

@Path("/datos/inventario")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class InventarioRecurso {

    @Inject
    ServicioDeInventario s;

    @POST
    @Path("/claves/{tabla}")
    @Consumes(MediaType.APPLICATION_JSON)
    public ClavesSpanner.Revision revisar(@PathParam("tabla") String tabla, java.util.List<String> pk) {
        return s.revisar(tabla, pk);
    }

    @POST
    @Path("/{sku}/reserva")
    public SpannerGcp.Reserva reservar(@PathParam("sku") String sku, @QueryParam("cantidad") long cantidad) {
        return s.reservar(sku, cantidad);
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
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/datos/inventario")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class InventarioRecursoReactivo {

    @Inject
    ServicioDeInventario s;

    @POST
    @Path("/claves/{tabla}")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ClavesSpanner.Revision> revisar(@PathParam("tabla") String tabla, java.util.List<String> pk) {
        return Uni.createFrom().item(() -> s.revisar(tabla, pk));
    }

    @POST
    @Path("/{sku}/reserva")
    public Uni<SpannerGcp.Reserva> reservar(@PathParam("sku") String sku, @QueryParam("cantidad") long cantidad) {
        return Uni.createFrom().item(() -> s.reservar(sku, cantidad)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer y escribir | `roles/spanner.databaseUser` en la base |
| Solo lectura | `roles/spanner.databaseReader` |

## 8. Qué NO hacer desde Java
- No llames a servicios externos dentro de la transacción: se puede repetir.
- No uses PK crecientes.
- No abras un `Spanner` por petición: es caro; uno por aplicación.
- No hagas lecturas fuertes donde una obsoleta basta.
