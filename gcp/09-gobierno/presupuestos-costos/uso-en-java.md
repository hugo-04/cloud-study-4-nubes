# Google Cloud · Gobierno · Presupuestos y costos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Dos piezas: una **reacción pura** al mensaje del presupuesto en Pub/Sub (llega varias veces al día: solo actúa cuando se cruza un **umbral nuevo** en el periodo, y detiene solo lo que es sandbox) más una proyección lineal; y un adaptador que consulta el **costo neto por equipo** (costo + créditos) en la exportación de facturación de BigQuery con parámetro de mes. El nombre de la tabla se valida porque no puede ir como parámetro.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
costos:
  tabla: modalima-finanzas.facturacion.gcp_billing_export_resource_v1_ABC123
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
costos.tabla=modalima-finanzas.facturacion.gcp_billing_export_resource_v1_ABC123
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

### 2.2 Reacción (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

/**
 * Reacción a las notificaciones del presupuesto (llegan varias veces al día):
 * solo actúa cuando se cruza un umbral nuevo en el periodo. Más una proyección lineal de fin de mes. Puro.
 */
public final class ReaccionAPresupuesto {

    public record Aviso(String presupuesto, String periodo, double costo, double monto, Double umbralCruzado) { }

    public record Decision(String accion, double porcentaje, String motivo) { }

    private static final Pattern TABLA = Pattern.compile("[a-z][a-z0-9-]{4,28}[a-z0-9]\\.[A-Za-z0-9_]+\\.[A-Za-z0-9_]+");
    private final Map<String, Double> ultimoUmbral = new ConcurrentHashMap<>();

    /** Campos del JSON del mensaje: budgetDisplayName, costIntervalStart, costAmount, budgetAmount, alertThresholdExceeded. */
    public static Aviso desde(Map<String, Object> m) {
        Object u = m.get("alertThresholdExceeded");
        return new Aviso((String) m.get("budgetDisplayName"), String.valueOf(m.get("costIntervalStart")),
            ((Number) m.get("costAmount")).doubleValue(), ((Number) m.get("budgetAmount")).doubleValue(),
            u == null ? null : ((Number) u).doubleValue());
    }

    public Decision evaluar(Aviso a, boolean esSandbox) {
        double pct = a.monto() == 0 ? 0 : a.costo() / a.monto();
        if (a.umbralCruzado() == null) {
            return new Decision("nada", pct, "sin umbral cruzado");
        }
        String clave = a.presupuesto() + "|" + a.periodo();
        Double previo = ultimoUmbral.get(clave);
        if (previo != null && previo >= a.umbralCruzado()) {
            return new Decision("nada", pct, "umbral ya procesado");
        }
        ultimoUmbral.put(clave, a.umbralCruzado());
        if (a.umbralCruzado() >= 1.0 && esSandbox) {
            return new Decision("detener-sandbox", pct, "100 % alcanzado en sandbox");
        }
        return new Decision("avisar", pct, "umbral " + Math.round(a.umbralCruzado() * 100) + " %");
    }

    /** Gasto proyectado a fin de mes con ritmo constante. */
    public static double proyectar(double gastoAlDia, int diaDelMes, int diasDelMes) {
        return diaDelMes <= 0 ? 0 : gastoAlDia / diaDelMes * diasDelMes;
    }

    public static String tablaValida(String tabla) {
        if (!TABLA.matcher(tabla).matches()) {
            throw new IllegalArgumentException("tabla de exportación inválida");
        }
        return tabla;
    }
}
```

### 2.3 Adaptador de BigQuery
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.BigQueryOptions;
import com.google.cloud.bigquery.QueryJobConfiguration;
import com.google.cloud.bigquery.QueryParameterValue;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: costo neto por equipo desde la exportación de facturación en BigQuery. */
public class CostosGcp implements AutoCloseable {

    public record CostoEquipo(String equipo, double costoNeto, String moneda) { }

    private final BigQuery bq;
    private final String tabla;

    public CostosGcp(GoogleCredentials cred, String proyecto, String tabla) {
        this.bq = BigQueryOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.tabla = ReaccionAPresupuesto.tablaValida(tabla);   // el nombre de tabla no admite parámetros
    }

    public List<CostoEquipo> porEquipo(String mes) {
        String sql = "SELECT IFNULL((SELECT value FROM UNNEST(labels) WHERE key = 'equipo'), 'sin-equipo') AS equipo, "
            + "SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS neto, currency "
            + "FROM `" + tabla + "` WHERE invoice.month = @mes GROUP BY equipo, currency ORDER BY neto DESC";
        var cfg = QueryJobConfiguration.newBuilder(sql).addNamedParameter("mes", QueryParameterValue.string(mes)).build();
        try {
            var out = new ArrayList<CostoEquipo>();
            for (var fila : bq.query(cfg).iterateAll()) {
                out.add(new CostoEquipo(fila.get("equipo").getStringValue(), fila.get("neto").getDoubleValue(),
                    fila.get("currency").getStringValue()));
            }
            return out;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    @Override
    public void close() {
        // el cliente de BigQuery no mantiene conexiones que cerrar
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Map;

public class ServicioDeCostos {

    private final CostosGcp gcp;
    private final ReaccionAPresupuesto reaccion = new ReaccionAPresupuesto();

    public ServicioDeCostos(CostosGcp gcp) {
        this.gcp = gcp;
    }

    /** Recibe el JSON ya decodificado del mensaje de Pub/Sub del presupuesto. */
    public ReaccionAPresupuesto.Decision aviso(Map<String, Object> mensaje) {
        var a = ReaccionAPresupuesto.desde(mensaje);
        return reaccion.evaluar(a, a.presupuesto() != null && a.presupuesto().startsWith("sandbox-"));
    }

    public List<CostosGcp.CostoEquipo> porEquipo(String mes) {
        return gcp.porEquipo(mes);
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class CostosConfiguracion {

    @Bean(destroyMethod = "close")
    CostosGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${costos.tabla}") String tabla) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new CostosGcp(cred, proyecto, tabla);
    }

    @Bean
    ServicioDeCostos servicio(CostosGcp a) {
        return new ServicioDeCostos(a);
    }
}

@RestController
@RequestMapping("/gobierno/costos")
class CostosControlador {

    private final ServicioDeCostos s;

    CostosControlador(ServicioDeCostos s) {
        this.s = s;
    }

    @PostMapping("/aviso")
    ReaccionAPresupuesto.Decision aviso(@RequestBody java.util.Map<String, Object> mensaje) {
        return s.aviso(mensaje);
    }

    @GetMapping("/equipos")
    java.util.List<CostosGcp.CostoEquipo> porEquipo(@RequestParam String mes) {
        return s.porEquipo(mes);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/costos")
class CostosReactivoControlador {

    private final ServicioDeCostos s;

    CostosReactivoControlador(ServicioDeCostos s) {
        this.s = s;
    }

    @PostMapping("/aviso")
    Mono<ReaccionAPresupuesto.Decision> aviso(@RequestBody java.util.Map<String, Object> mensaje) {
        return Mono.fromCallable(() -> s.aviso(mensaje));
    }

    @GetMapping("/equipos")
    Mono<java.util.List<CostosGcp.CostoEquipo>> porEquipo(@RequestParam String mes) {
        return Mono.fromCallable(() -> s.porEquipo(mes)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class CostosProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "costos.tabla")
    String tabla;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CostosGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new CostosGcp(cred, proyecto, tabla);
    }

    void cerrar(@Disposes CostosGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCostos servicio(CostosGcp a) {
        return new ServicioDeCostos(a);
    }
}

@Path("/gobierno/costos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class CostosRecurso {

    @Inject
    ServicioDeCostos s;

    @POST
    @Path("/aviso")
    @Consumes(MediaType.APPLICATION_JSON)
    public ReaccionAPresupuesto.Decision aviso(java.util.Map<String, Object> mensaje) {
        return s.aviso(mensaje);
    }

    @GET
    @Path("/equipos")
    public java.util.List<CostosGcp.CostoEquipo> porEquipo(@QueryParam("mes") String mes) {
        return s.porEquipo(mes);
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
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/gobierno/costos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class CostosRecursoReactivo {

    @Inject
    ServicioDeCostos s;

    @POST
    @Path("/aviso")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ReaccionAPresupuesto.Decision> aviso(java.util.Map<String, Object> mensaje) {
        return Uni.createFrom().item(() -> s.aviso(mensaje));
    }

    @GET
    @Path("/equipos")
    public Uni<java.util.List<CostosGcp.CostoEquipo>> porEquipo(@QueryParam("mes") String mes) {
        return Uni.createFrom().item(() -> s.porEquipo(mes)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Consultar la exportación | `roles/bigquery.dataViewer` en el dataset + `roles/bigquery.jobUser` en el proyecto |
| Detener sandbox (si lo implementas) | Permisos mínimos solo en proyectos con tag `entorno=sandbox` |

## 8. Qué NO hacer desde Java
- No concatenes el mes en el SQL: usa parámetros.
- No reacciones a cada mensaje: se repiten.
- No desvincules la facturación de producción.
- No des acceso a todo el dataset de facturación a los equipos.
