# Oracle OCI · Datos · PostgreSQL · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **enrutador de lectura/escritura** con consistencia «leer lo que escribí»: tras una escritura, ese usuario lee del primario durante una ventana; las lecturas que no toleran retraso (stock, saldo) van siempre al primario. El adaptador descubre con `PostgresqlClient` la IP del primario y si el endpoint de lectura está activo. En la app real esto elige entre dos `DataSource` creados al arrancar (JDBC o R2DBC en reactivo).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
pg:
  hostLectura: lectura.pg-pedidos.subred.vcn.oraclevcn.com
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
pg.hostLectura=lectura.pg-pedidos.subred.vcn.oraclevcn.com
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

### 2.2 Enrutador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Decide primario o réplica con consistencia «leer lo que escribí» por usuario. Puro: reloj inyectado. */
public class EnrutadorLecturaEscritura {

    public enum Destino { PRIMARIO, LECTURA }

    private final Clock reloj;
    private final Duration ventana;
    private final Map<String, Instant> ultimaEscritura = new ConcurrentHashMap<>();

    public EnrutadorLecturaEscritura(Clock reloj, Duration ventana) {
        this.reloj = reloj;
        this.ventana = ventana;
    }

    public Destino paraEscritura(String usuario) {
        ultimaEscritura.put(usuario, reloj.instant());
        return Destino.PRIMARIO;
    }

    /** toleraRetraso=false fuerza el primario (saldos, stock en checkout). */
    public Destino paraLectura(String usuario, boolean toleraRetraso) {
        if (!toleraRetraso) {
            return Destino.PRIMARIO;
        }
        Instant ultima = ultimaEscritura.get(usuario);
        if (ultima != null && reloj.instant().isBefore(ultima.plus(ventana))) {
            return Destino.PRIMARIO;
        }
        if (ultima != null) {
            ultimaEscritura.remove(usuario, ultima); // limpieza perezosa
        }
        return Destino.LECTURA;
    }

    public static String urlJdbc(String host, String base) {
        return "jdbc:postgresql://" + host + ":5432/" + base + "?sslmode=verify-full&connectTimeout=5&tcpKeepAlive=true";
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.psql.PostgresqlClient;
import com.oracle.bmc.psql.requests.GetDbSystemRequest;

/** Adaptador del SDK: descubre la IP del primario y si el endpoint de lectura está activo. */
public class PostgresOci implements AutoCloseable {

    public record Estado(String nombre, String ciclo, String version, int nodos, String ipPrimario, boolean lectorActivo) { }

    private final PostgresqlClient cliente;
    private final String hostLectura;

    public PostgresOci(PostgresqlClient cliente, String hostLectura) {
        this.cliente = cliente;
        this.hostLectura = hostLectura;
    }

    /** El endpoint de lectura se usa por su nombre DNS privado (configurado). */
    public String hostLectura() {
        return hostLectura;
    }

    public Estado estado(String dbSystemId) {
        var d = cliente.getDbSystem(GetDbSystemRequest.builder().dbSystemId(dbSystemId).build()).getDbSystem();
        var red = d.getNetworkDetails();
        return new Estado(d.getDisplayName(), d.getLifecycleState().getValue(), d.getDbVersion(), d.getInstanceCount(),
            red.getPrimaryDbEndpointPrivateIp(), Boolean.TRUE.equals(red.getIsReaderEndpointEnabled()));
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
import java.time.Clock;
import java.time.Duration;

public class ServicioDeRutas {

    public record Ruta(String destino, String url) { }

    private final PostgresOci pg;
    private final EnrutadorLecturaEscritura enrutador = new EnrutadorLecturaEscritura(Clock.systemUTC(), Duration.ofSeconds(5));

    public ServicioDeRutas(PostgresOci pg) {
        this.pg = pg;
    }

    public PostgresOci.Estado estado(String id) {
        return pg.estado(id);
    }

    /** En una app real esto elige entre dos DataSource (primario y lectura) ya creados al arrancar. */
    public Ruta ruta(String id, String usuario, boolean escritura, boolean toleraRetraso) {
        var e = pg.estado(id);
        var d = escritura ? enrutador.paraEscritura(usuario) : enrutador.paraLectura(usuario, toleraRetraso);
        boolean usarLector = d == EnrutadorLecturaEscritura.Destino.LECTURA && e.lectorActivo();
        String host = usarLector ? pg.hostLectura() : e.ipPrimario();
        return new Ruta(usarLector ? "LECTURA" : "PRIMARIO", EnrutadorLecturaEscritura.urlJdbc(host, "pedidos"));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.psql.PostgresqlClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class RutasConfiguracion {

    @Bean(destroyMethod = "close")
    PostgresOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${pg.hostLectura}") String hostLectura) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new PostgresOci(PostgresqlClient.builder().region(Region.fromRegionId(region)).build(auth), hostLectura);
    }

    @Bean
    ServicioDeRutas servicio(PostgresOci a) {
        return new ServicioDeRutas(a);
    }
}

@RestController
@RequestMapping("/datos/pg")
class RutasControlador {

    private final ServicioDeRutas s;

    RutasControlador(ServicioDeRutas s) {
        this.s = s;
    }

    @GetMapping("/{id}")
    PostgresOci.Estado estado(@PathVariable String id) {
        return s.estado(id);
    }

    @GetMapping("/{id}/ruta")
    ServicioDeRutas.Ruta ruta(@PathVariable String id, @RequestParam String usuario, @RequestParam boolean escritura, @RequestParam boolean tolera) {
        return s.ruta(id, usuario, escritura, tolera);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.psql.PostgresqlClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/pg")
class RutasReactivoControlador {

    private final ServicioDeRutas s;

    RutasReactivoControlador(ServicioDeRutas s) {
        this.s = s;
    }

    @GetMapping("/{id}")
    Mono<PostgresOci.Estado> estado(@PathVariable String id) {
        return Mono.fromCallable(() -> s.estado(id)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/{id}/ruta")
    Mono<ServicioDeRutas.Ruta> ruta(@PathVariable String id, @RequestParam String usuario, @RequestParam boolean escritura, @RequestParam boolean tolera) {
        return Mono.fromCallable(() -> s.ruta(id, usuario, escritura, tolera)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.psql.PostgresqlClient;
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
class RutasProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "pg.hostLectura")
    String hostLectura;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PostgresOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new PostgresOci(PostgresqlClient.builder().region(Region.fromRegionId(region)).build(auth), hostLectura);
    }

    void cerrar(@Disposes PostgresOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeRutas servicio(PostgresOci a) {
        return new ServicioDeRutas(a);
    }
}

@Path("/datos/pg")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class RutasRecurso {

    @Inject
    ServicioDeRutas s;

    @GET
    @Path("/{id}")
    public PostgresOci.Estado estado(@PathParam("id") String id) {
        return s.estado(id);
    }

    @GET
    @Path("/{id}/ruta")
    public ServicioDeRutas.Ruta ruta(@PathParam("id") String id, @QueryParam("usuario") String usuario, @QueryParam("escritura") boolean escritura, @QueryParam("tolera") boolean tolera) {
        return s.ruta(id, usuario, escritura, tolera);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.psql.PostgresqlClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/datos/pg")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class RutasRecursoReactivo {

    @Inject
    ServicioDeRutas s;

    @GET
    @Path("/{id}")
    public Uni<PostgresOci.Estado> estado(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> s.estado(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/{id}/ruta")
    public Uni<ServicioDeRutas.Ruta> ruta(@PathParam("id") String id, @QueryParam("usuario") String usuario, @QueryParam("escritura") boolean escritura, @QueryParam("tolera") boolean tolera) {
        return Uni.createFrom().item(() -> s.ruta(id, usuario, escritura, tolera)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer el DB system | `Allow dynamic-group plataforma to read postgres-db-systems in compartment datos-prod` |

## 8. Qué NO hacer desde Java
- No mezcles JDBC bloqueante en el hilo de eventos de WebFlux: usa R2DBC o aísla en `boundedElastic`.
- No abras pools grandes: PostgreSQL paga cada conexión con memoria.
- No leas de réplica justo después de escribir.
- No ejecutes migraciones con el rol de la aplicación.
- No uses `sslmode=disable` ni `require` sin verificar el servidor en producción.
