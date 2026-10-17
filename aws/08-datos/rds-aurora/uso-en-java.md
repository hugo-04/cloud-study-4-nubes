# AWS · RDS y Aurora · Uso desde Java

Aquí la parte difícil no es escribir SQL sino **sobrevivir a la nube**: conexiones limitadas, failovers, credenciales que rotan y errores transitorios. Por eso el núcleo común son cinco piezas pequeñas y probadas: **cuenta del pool**, **clasificador de errores SQL**, **reintento de la transacción completa**, **caché de tokens IAM** y **consulta/ensayo del clúster**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56), AWS Advanced JDBC Wrapper 4.x, PostgreSQL (Aurora).

## 1. Configuración
```yaml
# Spring Boot (application.yml) — JDBC con el wrapper de AWS (failover + IAM)
app:
  max-replicas: 12                           # el MÁXIMO que escalará tu autoscaling
  db-host: ${DB_CLUSTER_ENDPOINT}            # endpoint de clúster o del RDS Proxy
spring:
  datasource:
    url: jdbc:aws-wrapper:postgresql://${DB_CLUSTER_ENDPOINT}:5432/pedidos?sslmode=verify-full&sslrootcert=/etc/ssl/rds/global-bundle.pem&wrapperPlugins=failover2,efm2,iam
    username: app_iam
    driver-class-name: software.amazon.jdbc.Driver
    hikari:
      maximum-pool-size: 8
      minimum-idle: 2
      connection-timeout: 5000
      max-lifetime: 840000                   # 14 min: renueva conexiones antes de que algo intermedio las corte
  flyway:
    enabled: true
```
```properties
# Quarkus (application.properties) — IAM con un CredentialsProvider propio
quarkus.datasource.db-kind=postgresql
quarkus.datasource.jdbc.url=jdbc:postgresql://${DB_CLUSTER_ENDPOINT}:5432/pedidos?sslmode=verify-full&sslrootcert=/etc/ssl/rds/global-bundle.pem
quarkus.datasource.reactive.url=postgresql://${DB_CLUSTER_ENDPOINT}:5432/pedidos
quarkus.datasource.credentials-provider=rds-iam
quarkus.datasource.credentials-provider-name=rds-iam
quarkus.datasource.jdbc.max-size=8
quarkus.datasource.reactive.max-size=8
app.db-host=${DB_CLUSTER_ENDPOINT}
app.db-usuario=app_iam
```
> Con **RDS Proxy** apunta `DB_CLUSTER_ENDPOINT` al endpoint del proxy y baja el pool: el proxy multiplexa.

## 2. Núcleo común

### 2.1 Cuenta del pool
La cuenta que evita el «too many connections»: **todas las réplicas de tu aplicación, en su máximo de autoescalado, deben caber en ~80 % de `max_connections`**, menos las conexiones reservadas (migraciones, administración, otras aplicaciones).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

public final class PoolDimensionado {
    public record Plan(int maxConnections, int disponibles, int maximoPorInstancia, List<String> avisos) {}

    private PoolDimensionado() {}

    /** Valor por defecto aproximado en PostgreSQL de RDS/Aurora: LEAST(memoria / 9531392, 5000). Verifica con SHOW max_connections. */
    public static int maxConnectionsPostgres(long memoriaBytes) {
        return (int) Math.min(memoriaBytes / 9_531_392L, 5_000L);
    }

    /**
     * @param reservadas      conexiones que no son de esta aplicación (migraciones, administración, otros servicios)
     * @param instanciasApp   réplicas MÁXIMAS de la aplicación
     * @param usoMaximo       fracción del máximo que aceptas ocupar (0.8)
     */
    public static Plan calcular(int maxConnections, int reservadas, int instanciasApp, double usoMaximo) {
        if (maxConnections < 1 || reservadas < 0 || instanciasApp < 1 || usoMaximo <= 0 || usoMaximo > 1) {
            throw new IllegalArgumentException("parámetros inválidos");
        }
        int disponibles = Math.max(0, (int) Math.floor(maxConnections * usoMaximo) - reservadas);
        int porInstancia = disponibles / instanciasApp;
        List<String> avisos = new ArrayList<>();
        if (porInstancia < 2) {
            avisos.add("menos de 2 conexiones por instancia: usa RDS Proxy, reduce réplicas o sube la clase de la base");
        }
        if (porInstancia > 20) {
            avisos.add("un pool mayor de ~20 rara vez mejora el rendimiento; usa menos conexiones");
        }
        return new Plan(maxConnections, disponibles, porInstancia, avisos);
    }
}
```

### 2.2 Clasificador de errores SQL
Separa lo que **vale la pena reintentar** (failover, deadlock, conexión caída) de lo que **nunca mejora** (violación de restricción, sintaxis) y de lo que pide **refrescar la credencial** (autenticación fallida tras una rotación).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.sql.SQLException;
import java.sql.SQLRecoverableException;
import java.sql.SQLTransientException;
import java.util.Set;

public final class ErrorSql {
    public enum Clase { TRANSITORIO, CREDENCIAL, PERMANENTE }

    /** Códigos de MySQL: 1213 deadlock, 1205 lock wait, 2006/2013 conexión perdida, 1290/1836 solo lectura (failover). */
    private static final Set<Integer> MYSQL_TRANSITORIOS = Set.of(1213, 1205, 2006, 2013, 1290, 1836);

    private ErrorSql() {}

    public static Clase clasificar(String sqlState, int codigoProveedor) {
        if (sqlState != null) {
            if (sqlState.startsWith("28")) {
                return Clase.CREDENCIAL;                 // 28P01 contraseña inválida, 28000 autorización
            }
            if (sqlState.startsWith("08")                  // excepción de conexión
                    || sqlState.equals("40001")            // serialization_failure
                    || sqlState.equals("40P01")            // deadlock_detected
                    || sqlState.equals("25006")            // read_only_sql_transaction (escritor viejo tras failover)
                    || sqlState.equals("53300")            // too_many_connections
                    || sqlState.equals("55P03")            // lock_not_available
                    || sqlState.startsWith("57P")) {       // apagado del administrador / recuperación
                return Clase.TRANSITORIO;
            }
        }
        return MYSQL_TRANSITORIOS.contains(codigoProveedor) ? Clase.TRANSITORIO : Clase.PERMANENTE;
    }

    public static Clase clasificar(Throwable t) {
        for (Throwable c = t; c != null; c = c.getCause()) {
            if (c instanceof SQLException e) {
                Clase porEstado = clasificar(e.getSQLState(), e.getErrorCode());
                if (porEstado != Clase.PERMANENTE) {
                    return porEstado;
                }
                if (e instanceof SQLTransientException || e instanceof SQLRecoverableException) {
                    return Clase.TRANSITORIO;
                }
            } else if (c instanceof IOException) {
                return Clase.TRANSITORIO;                  // socket cerrado, reinicio de conexión
            }
            if (c.getCause() == c) {
                break;
            }
        }
        return Clase.PERMANENTE;
    }
}
```

### 2.3 Reintentar la transacción completa
Si falla una sentencia a mitad de una transacción, **toda la transacción** se descarta; reintentar solo esa sentencia sería un error. El bloque que recibe esta clase debe **abrir la transacción, hacer todo y cerrarla**.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.concurrent.Callable;
import java.util.function.DoubleSupplier;
import java.util.function.LongConsumer;

public final class Reintentar {
    private Reintentar() {}

    public static <T> T transaccion(Callable<T> transaccion, int maxIntentos, LongConsumer pausaMs,
                                    DoubleSupplier azar, Runnable refrescarCredencial) throws Exception {
        boolean credencialRefrescada = false;
        Exception ultima = null;
        for (int intento = 1; intento <= maxIntentos; intento++) {
            try {
                return transaccion.call();
            } catch (Exception e) {
                ultima = e;
                switch (ErrorSql.clasificar(e)) {
                    case PERMANENTE -> throw e;
                    case CREDENCIAL -> {
                        if (credencialRefrescada) {
                            throw e;
                        }
                        credencialRefrescada = true;
                        refrescarCredencial.run();
                    }
                    case TRANSITORIO -> {
                        if (intento < maxIntentos) {
                            long base = Math.min(5_000L, 200L << (intento - 1));
                            pausaMs.accept((long) (base * (0.5 + azar.getAsDouble() / 2)));   // «jitter»: entre 50 % y 100 %
                        }
                    }
                }
            }
        }
        throw ultima;
    }

    public static <T> T transaccion(Callable<T> transaccion, Runnable refrescarCredencial) throws Exception {
        return transaccion(transaccion, 5, ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException(e);
            }
        }, Math::random, refrescarCredencial);
    }
}
```

### 2.4 Token IAM con caché
El token vale **15 minutos para iniciar sesión** (una conexión ya abierta sigue viva). Se genera en local, sin llamar a la red, pero cuesta CPU: se guarda y se renueva antes de vencer.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.function.Supplier;
import software.amazon.awssdk.services.rds.RdsClient;

public final class TokenIam {
    private final Supplier<String> generador;
    private final Clock reloj;
    private final Duration vida;
    private String token;
    private Instant expira = Instant.MIN;

    public TokenIam(Supplier<String> generador, Clock reloj, Duration vida) {
        this.generador = generador;
        this.reloj = reloj;
        this.vida = vida;
    }

    /** Genera el token con las credenciales del cliente RDS (rol del pod/tarea). Vida en caché: 10 de los 15 minutos. */
    public static TokenIam conSdk(RdsClient rds, String host, int puerto, String usuario) {
        return new TokenIam(() -> rds.utilities().generateAuthenticationToken(r -> r.hostname(host).port(puerto).username(usuario)),
                Clock.systemUTC(), Duration.ofMinutes(10));
    }

    public synchronized String obtener() {
        Instant ahora = reloj.instant();
        if (token == null || !ahora.isBefore(expira)) {
            token = generador.get();
            expira = ahora.plus(vida);
        }
        return token;
    }

    /** Fuerza un token nuevo (p. ej. tras un fallo de autenticación). */
    public synchronized void invalidar() {
        token = null;
    }
}
```

### 2.5 Estado del clúster y ensayo de failover
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import software.amazon.awssdk.services.rds.RdsClient;
import software.amazon.awssdk.services.rds.model.DBCluster;
import software.amazon.awssdk.services.rds.model.DescribeDbClustersRequest;
import software.amazon.awssdk.services.rds.model.FailoverDbClusterRequest;

public final class ClusterRds {
    public record Estado(String id, String estado, String endpointEscritor, String endpointLector,
                         String instanciaEscritora, List<String> lectores) {}

    private final RdsClient rds;

    public ClusterRds(RdsClient rds) {
        this.rds = rds;
    }

    public Estado consultar(String clusterId) {
        DBCluster c = rds.describeDBClusters(DescribeDbClustersRequest.builder().dbClusterIdentifier(clusterId).build())
                .dbClusters().stream().findFirst().orElseThrow(() -> new IllegalArgumentException("clúster inexistente: " + clusterId));
        String escritora = c.dbClusterMembers().stream().filter(m -> Boolean.TRUE.equals(m.isClusterWriter()))
                .map(m -> m.dbInstanceIdentifier()).findFirst().orElse(null);
        List<String> lectores = c.dbClusterMembers().stream().filter(m -> !Boolean.TRUE.equals(m.isClusterWriter()))
                .map(m -> m.dbInstanceIdentifier()).toList();
        return new Estado(c.dbClusterIdentifier(), c.status(), c.endpoint(), c.readerEndpoint(), escritora, lectores);
    }

    /** Ensayo controlado: exige repetir el identificador para evitar un failover accidental. */
    public void ensayarFailover(String clusterId, String confirmacion) {
        if (!clusterId.equals(confirmacion)) {
            throw new IllegalArgumentException("confirmación inválida: repite el identificador del clúster");
        }
        rds.failoverDBCluster(FailoverDbClusterRequest.builder().dbClusterIdentifier(clusterId).build());
    }
}
```

## 3. Spring MVC (imperativo, JDBC)
```java
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.rds.RdsClient;

@Configuration
class RdsConfig {
    @Bean(destroyMethod = "close")
    RdsClient rds() {
        return RdsClient.create();
    }

    /** Al arrancar, compara «réplicas máximas × pool» con max_connections de la base y avisa si no cabe. */
    @Bean
    ApplicationRunner verificarPool(JdbcClient jdbc, @Value("${app.max-replicas}") int replicas,
                                    @Value("${spring.datasource.hikari.maximum-pool-size}") int pool) {
        return args -> {
            int max = jdbc.sql("select current_setting('max_connections')::int").query(Integer.class).single();
            var plan = PoolDimensionado.calcular(max, 20, replicas, 0.8);
            if (pool > plan.maximoPorInstancia()) {
                System.err.println("AVISO: pool " + pool + " > " + plan.maximoPorInstancia() + " permitido por instancia (max_connections=" + max + ")");
            }
            plan.avisos().forEach(a -> System.err.println("AVISO: " + a));
        };
    }
}

class ConflictoDeVersion extends RuntimeException {
    ConflictoDeVersion(UUID id) {
        super("el pedido " + id + " cambió mientras lo editabas");
    }
}

@Service
class PedidoServicio {
    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    PedidoServicio(JdbcClient jdbc, TransactionTemplate tx) {
        this.jdbc = jdbc;
        this.tx = tx;
    }

    /** Bloqueo optimista: solo actualiza si la versión coincide. El reintento envuelve la transacción ENTERA. */
    void confirmar(UUID id, int versionEsperada) throws Exception {
        Reintentar.transaccion(() -> tx.execute(status -> {
            int filas = jdbc.sql("update pedido set estado = 'CONFIRMADO', version = version + 1 where id = :id and version = :v")
                    .param("id", id).param("v", versionEsperada).update();
            if (filas == 0) {
                throw new ConflictoDeVersion(id);
            }
            return null;
        }), () -> { });   // con el wrapper IAM no hay credencial que refrescar a mano
    }

    Map<String, Object> obtener(UUID id) {
        return jdbc.sql("select id, estado, total, version from pedido where id = :id").param("id", id).query().singleRow();
    }
}

@RestController
class PedidoController {
    private final PedidoServicio servicio;

    PedidoController(PedidoServicio servicio) {
        this.servicio = servicio;
    }

    @GetMapping("/pedidos/{id}")
    Map<String, Object> obtener(@PathVariable UUID id) {
        return servicio.obtener(id);
    }

    @PostMapping("/pedidos/{id}/confirmar")
    ResponseEntity<String> confirmar(@PathVariable UUID id, @RequestParam int version) throws Exception {
        try {
            servicio.confirmar(id, version);
            return ResponseEntity.ok("confirmado");
        } catch (ConflictoDeVersion e) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(e.getMessage());
        }
    }
}
```

## 4. Spring WebFlux (reactivo, R2DBC)
```java
import io.r2dbc.postgresql.PostgresqlConnectionConfiguration;
import io.r2dbc.postgresql.PostgresqlConnectionFactory;
import io.r2dbc.postgresql.client.SSLMode;
import io.r2dbc.spi.ConnectionFactory;
import io.r2dbc.spi.R2dbcException;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.transaction.reactive.TransactionalOperator;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;
import software.amazon.awssdk.services.rds.RdsClient;

@Configuration
class R2dbcRdsConfig {
    @Bean
    TokenIam tokenIam(RdsClient rds, @Value("${app.db-host}") String host) {
        return TokenIam.conSdk(rds, host, 5432, "app_iam");
    }

    /** La contraseña es un Supplier: cada conexión NUEVA pide el token a la caché. */
    @Bean
    ConnectionFactory connectionFactory(TokenIam token, @Value("${app.db-host}") String host) {
        return new PostgresqlConnectionFactory(PostgresqlConnectionConfiguration.builder()
                .host(host).port(5432).database("pedidos").username("app_iam")
                .password(token::obtener).sslMode(SSLMode.VERIFY_FULL).build());
    }
}

@RestController
class PedidoReactivoController {
    private final DatabaseClient db;
    private final TransactionalOperator tx;

    PedidoReactivoController(DatabaseClient db, TransactionalOperator tx) {
        this.db = db;
        this.tx = tx;
    }

    @GetMapping("/pedidos-r/{id}")
    Mono<Map<String, Object>> obtener(@PathVariable UUID id) {
        return db.sql("select id, estado, total, version from pedido where id = :id").bind("id", id).fetch().one();
    }

    /** El reintento envuelve la transacción completa (tx.transactional(...)), no solo la sentencia. */
    @PostMapping("/pedidos-r/{id}/confirmar")
    Mono<String> confirmar(@PathVariable UUID id, @RequestParam int version) {
        Mono<Long> actualizar = db.sql("update pedido set estado = 'CONFIRMADO', version = version + 1 where id = :id and version = :v")
                .bind("id", id).bind("v", version).fetch().rowsUpdated();
        return tx.transactional(actualizar)
                .retryWhen(Retry.backoff(4, Duration.ofMillis(200)).maxBackoff(Duration.ofSeconds(5))
                        .filter(e -> e instanceof R2dbcException r
                                && ErrorSql.clasificar(r.getSqlState(), r.getErrorCode()) == ErrorSql.Clase.TRANSITORIO))
                .map(filas -> filas == 1 ? "confirmado" : "conflicto de versión");
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.quarkus.credentials.CredentialsProvider;
import io.quarkus.runtime.annotations.RegisterForReflection;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Named;
import jakarta.inject.Singleton;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.rds.RdsClient;

/** Entrega usuario y token IAM al pool de conexiones (JDBC y reactivo) cada vez que abre una conexión nueva. */
@ApplicationScoped
@Named("rds-iam")
@RegisterForReflection
class ProveedorIam implements CredentialsProvider {
    private final TokenIam token;
    private final String usuario;

    ProveedorIam(@ConfigProperty(name = "app.db-host") String host, @ConfigProperty(name = "app.db-usuario") String usuario) {
        this.usuario = usuario;
        this.token = TokenIam.conSdk(RdsClient.create(), host, 5432, usuario);
    }

    @Override
    public Map<String, String> getCredentials(String nombre) {
        return Map.of(USER_PROPERTY_NAME, usuario, PASSWORD_PROPERTY_NAME, token.obtener());
    }
}
```
```java
import io.agroal.api.AgroalDataSource;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.UUID;

@Path("/pedidos")
class PedidoRecurso {
    @Inject
    AgroalDataSource datos;

    @POST
    @Path("/{id}/confirmar")
    @Produces(MediaType.TEXT_PLAIN)
    public Response confirmar(@PathParam("id") UUID id, @QueryParam("version") int version) throws Exception {
        int filas = Reintentar.transaccion(() -> QuarkusTransaction.requiringNew().call(() -> {
            try (Connection c = datos.getConnection();
                 PreparedStatement ps = c.prepareStatement("update pedido set estado = 'CONFIRMADO', version = version + 1 where id = ? and version = ?")) {
                ps.setObject(1, id);
                ps.setInt(2, version);
                return ps.executeUpdate();
            }
        }), () -> { });
        return filas == 1 ? Response.ok("confirmado").build() : Response.status(Response.Status.CONFLICT).entity("conflicto de versión").build();
    }
}
```
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import software.amazon.awssdk.services.rds.RdsClient;

@ApplicationScoped
class RdsProductores {
    @Produces
    @Singleton
    RdsClient rds() {
        return RdsClient.create();
    }

    @Produces
    @Singleton
    ClusterRds cluster(RdsClient rds) {
        return new ClusterRds(rds);
    }
}
```

## 6. Quarkus reactivo (Mutiny, cliente reactivo de PostgreSQL)
```java
import io.smallrye.mutiny.Uni;
import io.vertx.mutiny.pgclient.PgPool;
import io.vertx.mutiny.sqlclient.Tuple;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Duration;
import java.util.UUID;

@Path("/pedidos-m")
class PedidoMutinyRecurso {
    @Inject
    PgPool pool;

    /** withTransaction abre y cierra la transacción; el reintento envuelve ese bloque completo. */
    @POST
    @Path("/{id}/confirmar")
    @Produces(MediaType.TEXT_PLAIN)
    public Uni<Response> confirmar(@PathParam("id") UUID id, @QueryParam("version") int version) {
        return pool.withTransaction(c -> c
                        .preparedQuery("update pedido set estado = 'CONFIRMADO', version = version + 1 where id = $1 and version = $2")
                        .execute(Tuple.of(id, version)))
                .onFailure(e -> e instanceof io.vertx.pgclient.PgException p
                        && ErrorSql.clasificar(p.getSqlState(), 0) == ErrorSql.Clase.TRANSITORIO)
                .retry().withBackOff(Duration.ofMillis(200), Duration.ofSeconds(5)).atMost(4)
                .map(rs -> rs.rowCount() == 1
                        ? Response.ok("confirmado").build()
                        : Response.status(Response.Status.CONFLICT).entity("conflicto de versión").build());
    }
}
```

## 7. Permisos
Aplicación: política de conexión IAM [`ejemplos/json/politica-conexion-iam.json`](ejemplos/json/politica-conexion-iam.json) y el usuario creado con [`ejemplos/sql/usuarios.sql`](ejemplos/sql/usuarios.sql). Operación (consultar estado, ensayar failover): [`ejemplos/json/politica-operacion.json`](ejemplos/json/politica-operacion.json), en una identidad **distinta** de la de la aplicación.

## 8. Qué NO hacer desde Java
- **No** pongas un pool grande «por si acaso»: haz la cuenta (§2.1).
- **No** reintentes solo una sentencia dentro de una transacción: reintenta la transacción **entera** (§2.3).
- **No** reintentes errores permanentes (restricciones, sintaxis).
- **No** guardes la contraseña ni el token en una variable estática de por vida: usa `TokenIam` o el wrapper.
- **No** conectes a una instancia concreta: usa el endpoint de clúster (o el del proxy).
- **No** hagas I/O JDBC en un hilo de eventos de WebFlux/Quarkus reactivo: usa R2DBC / cliente reactivo.
- **No** dejes transacciones abiertas durante llamadas HTTP a otros servicios.
- **No** uses `ensayarFailover` en producción sin una ventana acordada.
