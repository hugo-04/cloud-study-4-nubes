# Oracle OCI · Datos · Autonomous Database · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **selector de conexión**: lee con `DatabaseClient` los perfiles reales de la ADB y elige el servicio según la carga (`TP` para transacciones, `TPURGENT` para lo crítico, `LOW`/`MEDIUM` para reportes), prefiriendo TLS one-way si la base no exige mTLS, y añade reintentos al descriptor para sobrevivir a un *failover*. Con esa URL configuras el pool (UCP o Hikari) con el driver `ojdbc11` y la contraseña desde Vault.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
```

## 2. Núcleo común

### 2.1 Autenticación según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
        }
    }
}
```

### 2.2 Selector de perfil (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Elige el perfil de conexión según la carga y prefiere TLS one-way. Puro. */
public class SelectorDePerfil {

    public enum Carga { TRANSACCIONAL, CRITICA, REPORTE, ANALITICA }

    public record Perfil(String nombre, String grupo, String tls, String connectString) { }

    private static final Map<Carga, String> GRUPO = Map.of(
        Carga.TRANSACCIONAL, "TP", Carga.CRITICA, "TPURGENT", Carga.REPORTE, "LOW", Carga.ANALITICA, "MEDIUM");

    public Optional<String> urlJdbc(Carga carga, List<Perfil> perfiles, boolean mtlsObligatorio) {
        String grupo = GRUPO.get(carga);
        return perfiles.stream()
            .filter(p -> grupo.equalsIgnoreCase(p.grupo()))
            .filter(p -> !mtlsObligatorio || "MUTUAL".equals(p.tls()))
            // SERVER (one-way, sin wallet) primero cuando está permitido
            .min(Comparator.comparing((Perfil p) -> "SERVER".equals(p.tls()) ? 0 : 1))
            .map(p -> "jdbc:oracle:thin:@" + conReintentos(p.connectString()));
    }

    /** Asegura reintentos de conexión en el descriptor (útil durante failover de Data Guard). */
    static String conReintentos(String descriptor) {
        if (descriptor.contains("retry_count")) {
            return descriptor;
        }
        return descriptor.replaceFirst("(?i)\\(description=", "(description=(retry_count=20)(retry_delay=3)");
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.database.DatabaseClient;
import com.oracle.bmc.database.requests.GetAutonomousDatabaseRequest;
import java.util.List;

/** Adaptador del SDK: lee estado, si exige mTLS y los perfiles de conexión de la ADB. */
public class AutonomaOci implements AutoCloseable {

    public record Estado(String nombre, String ciclo, boolean mtls, List<SelectorDePerfil.Perfil> perfiles) { }

    private final DatabaseClient cliente;

    public AutonomaOci(DatabaseClient cliente) {
        this.cliente = cliente;
    }

    public Estado estado(String adbId) {
        var a = cliente.getAutonomousDatabase(GetAutonomousDatabaseRequest.builder()
            .autonomousDatabaseId(adbId).build()).getAutonomousDatabase();
        var perfiles = a.getConnectionStrings().getProfiles().stream()
            .map(p -> new SelectorDePerfil.Perfil(p.getDisplayName(), p.getConsumerGroup().getValue(),
                p.getTlsAuthentication().getValue(), p.getValue()))
            .toList();
        return new Estado(a.getDisplayName(), a.getLifecycleState().getValue(),
            Boolean.TRUE.equals(a.getIsMtlsConnectionRequired()), perfiles);
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
public class ServicioDeConexion {

    public record Respuesta(String base, String estado, String url) { }

    private final AutonomaOci adb;
    private final SelectorDePerfil selector = new SelectorDePerfil();

    public ServicioDeConexion(AutonomaOci adb) {
        this.adb = adb;
    }

    /** La URL se usa para configurar el pool al arrancar (no se pide en cada consulta). */
    public Respuesta url(String adbId, SelectorDePerfil.Carga carga) {
        var e = adb.estado(adbId);
        String url = selector.urlJdbc(carga, e.perfiles(), e.mtls())
            .orElseThrow(() -> new IllegalStateException("no hay perfil para " + carga));
        return new Respuesta(e.nombre(), e.ciclo(), url);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.database.DatabaseClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ConexionConfiguracion {

    @Bean(destroyMethod = "close")
    AutonomaOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new AutonomaOci(DatabaseClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeConexion servicio(AutonomaOci a) {
        return new ServicioDeConexion(a);
    }
}

@RestController
@RequestMapping("/datos/adb")
class ConexionControlador {

    private final ServicioDeConexion s;

    ConexionControlador(ServicioDeConexion s) {
        this.s = s;
    }

    @GetMapping("/{id}/url")
    ServicioDeConexion.Respuesta url(@PathVariable String id, @RequestParam SelectorDePerfil.Carga carga) {
        return s.url(id, carga);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.database.DatabaseClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/adb")
class ConexionReactivoControlador {

    private final ServicioDeConexion s;

    ConexionReactivoControlador(ServicioDeConexion s) {
        this.s = s;
    }

    @GetMapping("/{id}/url")
    Mono<ServicioDeConexion.Respuesta> url(@PathVariable String id, @RequestParam SelectorDePerfil.Carga carga) {
        return Mono.fromCallable(() -> s.url(id, carga)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.database.DatabaseClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ConexionProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    AutonomaOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new AutonomaOci(DatabaseClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes AutonomaOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeConexion servicio(AutonomaOci a) {
        return new ServicioDeConexion(a);
    }
}

@Path("/datos/adb")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ConexionRecurso {

    @Inject
    ServicioDeConexion s;

    @GET
    @Path("/{id}/url")
    public ServicioDeConexion.Respuesta url(@PathParam("id") String id, @QueryParam("carga") SelectorDePerfil.Carga carga) {
        return s.url(id, carga);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.database.DatabaseClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/datos/adb")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ConexionRecursoReactivo {

    @Inject
    ServicioDeConexion s;

    @GET
    @Path("/{id}/url")
    public Uni<ServicioDeConexion.Respuesta> url(@PathParam("id") String id, @QueryParam("carga") SelectorDePerfil.Carga carga) {
        return Uni.createFrom().item(() -> s.url(id, carga)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer la ADB y sus perfiles | `Allow dynamic-group app-pedidos to read autonomous-databases in compartment datos-prod` |
| Contraseña del usuario de app | `Allow dynamic-group app-pedidos to read secret-bundles in compartment datos-prod where target.secret.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No expongas la URL ni credenciales en un endpoint público: este ejemplo es para diagnóstico interno.
- No pidas el perfil en cada consulta: resuélvelo al arrancar y configura el pool.
- No uses `ADMIN` desde la aplicación.
- No uses el servicio `high` para OLTP.
- No olvides cerrar `ResultSet`/`Statement` (o usa `JdbcTemplate`).
