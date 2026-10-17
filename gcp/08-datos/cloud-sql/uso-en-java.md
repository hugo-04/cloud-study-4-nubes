# Google Cloud · Datos · Cloud SQL · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Con Cloud SQL el SQL es el de siempre; lo propio de Google es **la conexión**. Aquí: un armador puro de propiedades del **conector Java** (`socketFactory`, `cloudSqlInstance`, `enableIamAuth`, usuario IAM sin sufijo) más el **cálculo del pool** contra `max_connections`, y un adaptador que prueba la conexión. En Spring estas propiedades van en `spring.datasource.hikari.data-source-properties.*` y en Quarkus en `quarkus.datasource.jdbc.additional-jdbc-properties.*`.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
sql:
  connection: modalima-prod:southamerica-west1:pedidos-pg
  base: pedidos
  cuenta: app-pedidos@modalima-prod.iam.gserviceaccount.com
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
sql.connection=modalima-prod:southamerica-west1:pedidos-pg
sql.base=pedidos
sql.cuenta=app-pedidos@modalima-prod.iam.gserviceaccount.com
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

### 2.2 Conexión y pool (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

/**
 * Arma la conexión JDBC al conector de Cloud SQL con autenticación IAM y calcula el pool
 * para que (pool × instancias) no supere max_connections. Puro.
 */
public final class ConexionCloudSql {

    public record Pool(int porInstancia, int totalMaximo, List<String> avisos) { }

    private ConexionCloudSql() {
    }

    /** connectionName = proyecto:region:instancia. Sin host: el conector abre el túnel TLS. */
    public static String url(String base) {
        return "jdbc:postgresql:///" + base;
    }

    public static Properties propiedades(String connectionName, String cuentaServicio, boolean ipPrivada) {
        var p = new Properties();
        p.setProperty("socketFactory", "com.google.cloud.sql.postgres.SocketFactory");
        p.setProperty("cloudSqlInstance", connectionName);
        p.setProperty("enableIamAuth", "true");
        p.setProperty("user", usuarioIam(cuentaServicio));
        p.setProperty("password", "no-se-usa");   // el driver exige un valor; el token IAM la reemplaza
        p.setProperty("sslmode", "disable");       // el conector ya cifra
        if (ipPrivada) {
            p.setProperty("ipTypes", "PRIVATE");
        }
        return p;
    }

    /** En PostgreSQL el usuario IAM es el email de la SA sin el sufijo .gserviceaccount.com. */
    public static String usuarioIam(String email) {
        return email.endsWith(".gserviceaccount.com") ? email.substring(0, email.length() - ".gserviceaccount.com".length()) : email;
    }

    public static Pool pool(int maxConnections, int reserva, int instanciasMaximas, int deseadoPorInstancia) {
        int disponible = Math.max(0, maxConnections - reserva);
        int porInstancia = Math.max(1, Math.min(deseadoPorInstancia, disponible / Math.max(1, instanciasMaximas)));
        var avisos = new ArrayList<String>();
        if (porInstancia < deseadoPorInstancia) {
            avisos.add("pool reducido de " + deseadoPorInstancia + " a " + porInstancia);
        }
        if ((long) porInstancia * instanciasMaximas > disponible) {
            avisos.add("aun con pool 1 se supera el límite: baja instancias o usa réplicas");
        }
        return new Pool(porInstancia, porInstancia * instanciasMaximas, avisos);
    }
}
```

### 2.3 Adaptador JDBC
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * Adaptador: comprueba la conexión con el conector (en la app real usa el pool del framework
 * con las mismas propiedades; aquí DriverManager para no mezclar el ejemplo con el pool).
 */
public class CloudSqlGcp implements AutoCloseable {

    public record Prueba(String usuario, String version, boolean soloLectura) { }

    private final String connectionName;
    private final String base;
    private final String cuenta;

    public CloudSqlGcp(String connectionName, String base, String cuenta) {
        this.connectionName = connectionName;
        this.base = base;
        this.cuenta = cuenta;
    }

    public Prueba probar() {
        var props = ConexionCloudSql.propiedades(connectionName, cuenta, true);
        try (var c = DriverManager.getConnection(ConexionCloudSql.url(base), props);
             var st = c.createStatement();
             var rs = st.executeQuery("select current_user, version(), pg_is_in_recovery()")) {
            rs.next();
            return new Prueba(rs.getString(1), rs.getString(2), rs.getBoolean(3));
        } catch (SQLException e) {
            throw new IllegalStateException("conexión fallida (" + e.getSQLState() + ")", e);
        }
    }

    @Override
    public void close() {
        // sin recursos abiertos entre llamadas
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
public class ServicioDeBase {

    private final CloudSqlGcp sql;

    public ServicioDeBase(CloudSqlGcp sql) {
        this.sql = sql;
    }

    public ConexionCloudSql.Pool pool(int maxConnections, int instancias, int deseado) {
        return ConexionCloudSql.pool(maxConnections, 20, instancias, deseado);
    }

    public CloudSqlGcp.Prueba probar() {
        return sql.probar();
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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class BaseConfiguracion {

    @Bean(destroyMethod = "close")
    CloudSqlGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${sql.connection}") String connection, @Value("${sql.base}") String base, @Value("${sql.cuenta}") String cuenta) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new CloudSqlGcp(connection, base, cuenta);
    }

    @Bean
    ServicioDeBase servicio(CloudSqlGcp a) {
        return new ServicioDeBase(a);
    }
}

@RestController
@RequestMapping("/datos/base")
class BaseControlador {

    private final ServicioDeBase s;

    BaseControlador(ServicioDeBase s) {
        this.s = s;
    }

    @GetMapping("/pool")
    ConexionCloudSql.Pool pool(@RequestParam int maxConnections, @RequestParam int instancias, @RequestParam int deseado) {
        return s.pool(maxConnections, instancias, deseado);
    }

    @GetMapping("/prueba")
    CloudSqlGcp.Prueba probar() {
        return s.probar();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/base")
class BaseReactivoControlador {

    private final ServicioDeBase s;

    BaseReactivoControlador(ServicioDeBase s) {
        this.s = s;
    }

    @GetMapping("/pool")
    Mono<ConexionCloudSql.Pool> pool(@RequestParam int maxConnections, @RequestParam int instancias, @RequestParam int deseado) {
        return Mono.fromCallable(() -> s.pool(maxConnections, instancias, deseado));
    }

    @GetMapping("/prueba")
    Mono<CloudSqlGcp.Prueba> probar() {
        return Mono.fromCallable(() -> s.probar()).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class BaseProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "sql.connection")
    String connection;

    @ConfigProperty(name = "sql.base")
    String base;

    @ConfigProperty(name = "sql.cuenta")
    String cuenta;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CloudSqlGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new CloudSqlGcp(connection, base, cuenta);
    }

    void cerrar(@Disposes CloudSqlGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeBase servicio(CloudSqlGcp a) {
        return new ServicioDeBase(a);
    }
}

@Path("/datos/base")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class BaseRecurso {

    @Inject
    ServicioDeBase s;

    @GET
    @Path("/pool")
    public ConexionCloudSql.Pool pool(@QueryParam("maxConnections") int maxConnections, @QueryParam("instancias") int instancias, @QueryParam("deseado") int deseado) {
        return s.pool(maxConnections, instancias, deseado);
    }

    @GET
    @Path("/prueba")
    public CloudSqlGcp.Prueba probar() {
        return s.probar();
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
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/datos/base")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class BaseRecursoReactivo {

    @Inject
    ServicioDeBase s;

    @GET
    @Path("/pool")
    public Uni<ConexionCloudSql.Pool> pool(@QueryParam("maxConnections") int maxConnections, @QueryParam("instancias") int instancias, @QueryParam("deseado") int deseado) {
        return Uni.createFrom().item(() -> s.pool(maxConnections, instancias, deseado));
    }

    @GET
    @Path("/prueba")
    public Uni<CloudSqlGcp.Prueba> probar() {
        return Uni.createFrom().item(() -> s.probar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Conectar por el conector | `roles/cloudsql.client` |
| Entrar con IAM | `roles/cloudsql.instanceUser` + usuario `CLOUD_IAM_SERVICE_ACCOUNT` + `GRANT` en la base |

## 8. Qué NO hacer desde Java
- No pongas contraseñas en la configuración: usa IAM.
- No abras la IP pública «para probar».
- No dimensiones el pool sin contar las instancias máximas.
- No expongas `/prueba` fuera de la red interna.
