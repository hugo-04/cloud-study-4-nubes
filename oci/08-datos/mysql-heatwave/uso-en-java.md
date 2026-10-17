# Oracle OCI · Datos · MySQL HeatWave · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **planificador de pools**: reparte `max_connections` entre servicios según réplicas y peso (con reserva y margen) para que escalar réplicas no tumbe la base, y lee con `DbSystemClient` el endpoint real de escritura y si HeatWave está activo. El resultado alimenta `spring.datasource.hikari.maximum-pool-size` o `quarkus.datasource.jdbc.max-size`.

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

### 2.2 Repartidor de conexiones (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.LinkedHashMap;
import java.util.Map;

/** Reparte max_connections entre servicios según réplicas y peso. Puro. */
public class RepartidorDeConexiones {

    public record Servicio(int replicas, int peso) { }

    private final int maxConexiones;
    private final int reserva;

    public RepartidorDeConexiones(int maxConexiones, int reserva) {
        this.maxConexiones = maxConexiones;
        this.reserva = reserva;
    }

    /** Devuelve el tamaño máximo del pool POR RÉPLICA de cada servicio (mínimo 2). */
    public Map<String, Integer> poolPorReplica(Map<String, Servicio> servicios) {
        int disponibles = (int) Math.floor((maxConexiones - reserva) * 0.9); // 10 % de margen para picos y reconexiones
        int pesoTotal = servicios.values().stream().mapToInt(s -> s.peso() * s.replicas()).sum();
        if (pesoTotal == 0) {
            throw new IllegalArgumentException("sin servicios");
        }
        var out = new LinkedHashMap<String, Integer>();
        int usadas = 0;
        for (var e : servicios.entrySet()) {
            var s = e.getValue();
            int porReplica = Math.max(2, disponibles * s.peso() / pesoTotal);
            out.put(e.getKey(), porReplica);
            usadas += porReplica * s.replicas();
        }
        if (usadas > maxConexiones - reserva) {
            throw new IllegalStateException("no alcanzan las conexiones: " + usadas + " > " + (maxConexiones - reserva));
        }
        return out;
    }

    public static String urlJdbc(String host, int puerto, String base) {
        return "jdbc:mysql://" + host + ":" + puerto + "/" + base + "?sslMode=REQUIRED&connectTimeout=5000&tcpKeepAlive=true";
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.mysql.DbSystemClient;
import com.oracle.bmc.mysql.model.DbSystemEndpoint;
import com.oracle.bmc.mysql.requests.GetDbSystemRequest;
import java.util.List;

/** Adaptador del SDK: descubre endpoints (escritura/lectura) y si HeatWave está activo. */
public class MysqlOci implements AutoCloseable {

    public record Endpoint(String ip, int puerto, boolean escritura) { }

    public record Estado(String nombre, String ciclo, boolean ha, boolean heatwave, List<Endpoint> endpoints) { }

    private final DbSystemClient cliente;

    public MysqlOci(DbSystemClient cliente) {
        this.cliente = cliente;
    }

    public Estado estado(String dbSystemId) {
        var d = cliente.getDbSystem(GetDbSystemRequest.builder().dbSystemId(dbSystemId).build()).getDbSystem();
        var eps = d.getEndpoints().stream()
            .map(e -> new Endpoint(e.getIpAddress(), e.getPort(), e.getModes().contains(DbSystemEndpoint.Modes.Write)))
            .toList();
        boolean hw = Boolean.TRUE.equals(d.getIsHeatWaveClusterAttached()) && d.getHeatWaveCluster() != null
            && "ACTIVE".equals(d.getHeatWaveCluster().getLifecycleState().getValue());
        return new Estado(d.getDisplayName(), d.getLifecycleState().getValue(), Boolean.TRUE.equals(d.getIsHighlyAvailable()), hw, eps);
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
import java.util.Map;

public class ServicioDePools {

    public record Plan(String urlEscritura, boolean heatwave, Map<String, Integer> poolPorReplica) { }

    private final MysqlOci mysql;

    public ServicioDePools(MysqlOci mysql) {
        this.mysql = mysql;
    }

    public Plan planificar(String dbSystemId, int maxConexiones, Map<String, RepartidorDeConexiones.Servicio> servicios) {
        var e = mysql.estado(dbSystemId);
        var escritura = e.endpoints().stream().filter(MysqlOci.Endpoint::escritura).findFirst()
            .orElseThrow(() -> new IllegalStateException("sin endpoint de escritura"));
        var pools = new RepartidorDeConexiones(maxConexiones, 20).poolPorReplica(servicios);
        return new Plan(RepartidorDeConexiones.urlJdbc(escritura.ip(), escritura.puerto(), "catalogo"), e.heatwave(), pools);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.mysql.DbSystemClient;
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
class PoolsConfiguracion {

    @Bean(destroyMethod = "close")
    MysqlOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new MysqlOci(DbSystemClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDePools servicio(MysqlOci a) {
        return new ServicioDePools(a);
    }
}

@RestController
@RequestMapping("/datos/mysql")
class PoolsControlador {

    private final ServicioDePools s;

    PoolsControlador(ServicioDePools s) {
        this.s = s;
    }

    @PostMapping("/{id}/plan")
    ServicioDePools.Plan planificar(@PathVariable String id, @RequestParam int max, @RequestBody java.util.Map<String, RepartidorDeConexiones.Servicio> servicios) {
        return s.planificar(id, max, servicios);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.mysql.DbSystemClient;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/mysql")
class PoolsReactivoControlador {

    private final ServicioDePools s;

    PoolsReactivoControlador(ServicioDePools s) {
        this.s = s;
    }

    @PostMapping("/{id}/plan")
    Mono<ServicioDePools.Plan> planificar(@PathVariable String id, @RequestParam int max, @RequestBody java.util.Map<String, RepartidorDeConexiones.Servicio> servicios) {
        return Mono.fromCallable(() -> s.planificar(id, max, servicios)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.mysql.DbSystemClient;
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
class PoolsProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    MysqlOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new MysqlOci(DbSystemClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes MysqlOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePools servicio(MysqlOci a) {
        return new ServicioDePools(a);
    }
}

@Path("/datos/mysql")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class PoolsRecurso {

    @Inject
    ServicioDePools s;

    @POST
    @Path("/{id}/plan")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDePools.Plan planificar(@PathParam("id") String id, @QueryParam("max") int max, java.util.Map<String, RepartidorDeConexiones.Servicio> servicios) {
        return s.planificar(id, max, servicios);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.mysql.DbSystemClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/datos/mysql")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class PoolsRecursoReactivo {

    @Inject
    ServicioDePools s;

    @POST
    @Path("/{id}/plan")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDePools.Plan> planificar(@PathParam("id") String id, @QueryParam("max") int max, java.util.Map<String, RepartidorDeConexiones.Servicio> servicios) {
        return Uni.createFrom().item(() -> s.planificar(id, max, servicios)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer el DB system | `Allow dynamic-group plataforma to read mysql-db-systems in compartment datos-prod` |

## 8. Qué NO hacer desde Java
- No dimensiones el pool por réplica sin mirar el total global.
- No uses el usuario administrador desde la app.
- No leas de réplicas lo que el usuario acaba de escribir.
- No desactives TLS (`sslMode=DISABLED`).
- No ejecutes reportes pesados sin HeatWave sobre el primario en horas punta.
