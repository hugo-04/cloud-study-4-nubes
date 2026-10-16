# Azure · PostgreSQL Flexible Server · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1 (Spring Framework 7, Hibernate 7, Spring Data JPA/R2DBC), `pgjdbc` y `r2dbc-postgresql` gestionados por Spring Boot, Quarkus 3.40 (Hibernate ORM/Reactive con Panache), Azure SDK BOM 1.3**. Verifica las vigentes.

Principios: **sin contraseñas** (token de Entra como contraseña, **uno nuevo por cada conexión física**), **pool pequeño** (+ PgBouncer con muchos pods), **reintentos** de errores transitorios, consultas parametrizadas, `ON CONFLICT` para idempotencia, `SKIP LOCKED` para colas internas y esquema con identidad dueña separada.

```xml
<!-- Spring Boot -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
<dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>org.flywaydb</groupId><artifactId>flyway-database-postgresql</artifactId></dependency>
<!-- Quarkus -->
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-jdbc-postgresql</artifactId></dependency>
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-hibernate-orm-panache</artifactId></dependency>
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-credentials</artifactId></dependency>
```
Roles en la base: ver [01-roles-y-permisos.sql](ejemplos/sql/01-roles-y-permisos.sql). La aplicación es un **rol de Entra** (identidad administrada) con permisos mínimos; **no** es dueña de las tablas.

## 1. El token de Entra como contraseña (DataSource que lo renueva)

Un token de Entra caduca en aproximadamente una hora. Si lo pones en `spring.datasource.password` al arrancar, **la aplicación empieza a fallar a la hora**. La solución es un `DataSource` que pida un token **cada vez que el pool abre una conexión física nueva**:

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.postgresql.ds.PGSimpleDataSource;

import java.sql.Connection;
import java.sql.SQLException;

/** DataSource de pgjdbc que usa un token de Entra ID como contraseña, renovado en cada conexión física nueva. */
class PostgresEntraDataSource extends PGSimpleDataSource {

    private static final TokenRequestContext AMBITO =
            new TokenRequestContext().addScopes("https://ossrdbms-aad.database.windows.net/.default");

    private final transient TokenCredential credencial;

    PostgresEntraDataSource() {
        // En Azure: identidad administrada / Workload Identity. En tu máquina: az login (DefaultAzureCredential).
        this.credencial = new DefaultAzureCredentialBuilder().build();
    }

    @Override
    public Connection getConnection(String usuario, String contrasenaIgnorada) throws SQLException {
        AccessToken token = credencial.getTokenSync(AMBITO);     // la caché de azure-identity evita pedirlo siempre a Entra
        return super.getConnection(usuario, token.getToken());
    }
}
```

## 2. Spring Boot: pool, JPA con `jsonb` y concurrencia optimista

```yaml
# application.yml
app:
  postgres:
    host: pg-modalima.postgres.database.azure.com
    puerto: 5432                   # 6432 para pasar por PgBouncer
    base: pedidos
    usuario: id-api-pedidos        # nombre del rol de Entra creado con pgaadauth_create_principal
spring:
  jpa:
    open-in-view: false
    properties:
      hibernate.jdbc.batch_size: 50
      hibernate.order_inserts: true
  flyway:
    enabled: false                 # migra el pipeline con la identidad dueña
```

```java
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import org.postgresql.ds.PGSimpleDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import javax.sql.DataSource;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;

@Configuration
class PostgresConfig {

    @Bean(destroyMethod = "close")
    DataSource dataSource(@Value("${app.postgres.host}") String host,
                          @Value("${app.postgres.puerto}") int puerto,
                          @Value("${app.postgres.base}") String base,
                          @Value("${app.postgres.usuario}") String usuario) {
        PGSimpleDataSource origen = new PostgresEntraDataSource();
        origen.setServerNames(new String[]{host});
        origen.setPortNumbers(new int[]{puerto});
        origen.setDatabaseName(base);
        origen.setUser(usuario);
        origen.setSslMode("verify-full");                 // valida el certificado del servidor
        origen.setApplicationName("api-pedidos");         // aparece en pg_stat_activity: sabrás quién abre conexiones
        origen.setConnectTimeout(10);
        if (puerto == 6432) {
            origen.setPrepareThreshold(0);                // detrás de PgBouncer en modo transacción
        }

        HikariConfig cfg = new HikariConfig();
        cfg.setDataSource(origen);
        cfg.setPoolName("pedidos");
        cfg.setMaximumPoolSize(10);
        cfg.setMinimumIdle(2);
        cfg.setConnectionTimeout(30_000);
        cfg.setMaxLifetime(30 * 60_000L);                 // menor que la vida del token y de los cortes de mantenimiento
        cfg.setKeepaliveTime(5 * 60_000L);
        cfg.setLeakDetectionThreshold(20_000);
        return new HikariDataSource(cfg);
    }
}

@Entity
@Table(name = "pedido", schema = "ventas")
class Pedido {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;

    @Column(name = "cliente_id", nullable = false)
    String clienteId;

    @Column(nullable = false)
    String estado;

    @Column(nullable = false, precision = 12, scale = 2)
    BigDecimal total;

    @JdbcTypeCode(SqlTypes.JSON)                          // columna jsonb
    @Column(columnDefinition = "jsonb")
    Map<String, Object> atributos;

    @Column(name = "creado_en", nullable = false)
    Instant creadoEn = Instant.now();

    @Version                                              // UPDATE ... WHERE id = ? AND version = ?
    long version;
}

interface PedidoRepositorio extends JpaRepository<Pedido, Long> {

    List<Pedido> findTop50ByClienteIdOrderByIdDesc(String clienteId);

    // consulta nativa sobre jsonb: pedidos de clientes VIP (usa un índice GIN sobre atributos)
    @Query(value = "SELECT * FROM ventas.pedido WHERE atributos @> CAST(:filtro AS jsonb) ORDER BY id DESC LIMIT 100",
            nativeQuery = true)
    List<Pedido> conAtributos(@Param("filtro") String filtroJson);
}
```
- **Con identidad asignada por el sistema o por el usuario**, `DefaultAzureCredentialBuilder` usa `AZURE_CLIENT_ID` si hay varias identidades.
- Alternativa soportada por Microsoft: la biblioteca `azure-identity-extensions` y el parámetro `authenticationPluginClassName` en la URL JDBC (hace lo mismo que el `DataSource` anterior). *Verifica compatibilidad con tu versión de `pgjdbc`.*

## 3. `JdbcClient`: upsert idempotente, cola con `SKIP LOCKED` y bloqueo consultivo

```java
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

record Tarea(long id, String tipo, String carga) {
}

@Repository
class PostgresPatrones {

    private final JdbcClient jdbc;

    PostgresPatrones(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Idempotencia: si el evento ya se procesó, no hace nada (clave única en evento_id). */
    boolean registrarEventoProcesado(String eventoId) {
        return jdbc.sql("INSERT INTO ventas.evento_procesado (evento_id) VALUES (:id) ON CONFLICT (evento_id) DO NOTHING")
                .param("id", eventoId)
                .update() == 1;                              // false = ya estaba: saltar el procesamiento
    }

    /** Upsert: crea o actualiza el stock en una sola sentencia atómica. */
    void ajustarStock(String productoId, int delta) {
        jdbc.sql("""
                        INSERT INTO ventas.stock (producto_id, cantidad) VALUES (:p, :d)
                        ON CONFLICT (producto_id) DO UPDATE SET cantidad = ventas.stock.cantidad + EXCLUDED.cantidad
                        """)
                .param("p", productoId)
                .param("d", delta)
                .update();
    }

    /**
     * Cola/Outbox en la propia base: varias réplicas toman tareas distintas sin pisarse.
     * FOR UPDATE SKIP LOCKED salta las filas que otra transacción ya tomó.
     */
    @Transactional
    List<Tarea> tomarTareas(int cantidad) {
        List<Tarea> tareas = jdbc.sql("""
                        SELECT id, tipo, carga::text AS carga
                        FROM ventas.tarea
                        WHERE estado = 'PENDIENTE' AND disponible_desde <= now()
                        ORDER BY id
                        LIMIT :n
                        FOR UPDATE SKIP LOCKED
                        """)
                .param("n", cantidad)
                .query((rs, i) -> new Tarea(rs.getLong("id"), rs.getString("tipo"), rs.getString("carga")))
                .list();
        for (Tarea t : tareas) {
            jdbc.sql("UPDATE ventas.tarea SET estado = 'EN_CURSO', intentos = intentos + 1 WHERE id = :id")
                    .param("id", t.id())
                    .update();
        }
        return tareas;
    }

    /** Líder único para un trabajo programado: bloqueo consultivo A NIVEL DE TRANSACCIÓN (compatible con PgBouncer). */
    @Transactional
    Optional<Boolean> soyElLider(long claveDelTrabajo) {
        Boolean obtenido = jdbc.sql("SELECT pg_try_advisory_xact_lock(:clave)")
                .param("clave", claveDelTrabajo)
                .query(Boolean.class)
                .single();
        return Optional.of(obtenido);
    }
}
```
Esquema y funciones: [03-patrones-microservicios.sql](ejemplos/sql/03-patrones-microservicios.sql). **Bloqueos consultivos de sesión** (`pg_advisory_lock`) no funcionan detrás de PgBouncer en modo transacción: usa la variante `*_xact_*`.

## 4. Reintentos de errores transitorios (códigos SQLSTATE de PostgreSQL)

```java
import java.sql.SQLException;
import java.sql.SQLRecoverableException;
import java.sql.SQLTransientException;
import java.time.Duration;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Supplier;

final class ErroresTransitoriosPg {

    // 40001 fallo de serialización, 40P01 deadlock, 57P01 apagado por el administrador (failover/mantenimiento),
    // 57P03 el servidor aún no acepta conexiones, 08xxx errores de conexión, 53300 demasiadas conexiones
    private static final Set<String> ESTADOS = Set.of("40001", "40P01", "57P01", "57P02", "57P03", "53300", "08000", "08001", "08003", "08006");

    private ErroresTransitoriosPg() {
    }

    static boolean esTransitorio(Throwable error) {
        for (Throwable t = error; t != null; t = t.getCause()) {
            if (t instanceof SQLTransientException || t instanceof SQLRecoverableException) {
                return true;
            }
            if (t instanceof SQLException sql && sql.getSQLState() != null && ESTADOS.contains(sql.getSQLState())) {
                return true;
            }
        }
        return false;
    }

    static <T> T conReintentos(int maximo, Supplier<T> operacion) {
        long espera = 200;
        for (int intento = 1; ; intento++) {
            try {
                return operacion.get();
            } catch (RuntimeException e) {
                if (intento >= maximo || !esTransitorio(e)) {
                    throw e;
                }
                try {
                    Thread.sleep(Duration.ofMillis(espera + ThreadLocalRandom.current().nextLong(100)));
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
                espera = Math.min(espera * 2, 5000);
            }
        }
    }
}
```
Durante un *failover* o mantenimiento de HA, las conexiones se cortan por 1–2 minutos: el pool valida, descarta las muertas y los reintentos con retroceso cubren el hueco.

## 5. Spring WebFlux (reactivo): R2DBC con token renovable

R2DBC para PostgreSQL **sí** admite que la contraseña sea un *proveedor* evaluado en cada conexión nueva, así que el token de Entra funciona:

```java
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.DefaultAzureCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;
import io.r2dbc.pool.ConnectionPool;
import io.r2dbc.pool.ConnectionPoolConfiguration;
import io.r2dbc.postgresql.PostgresqlConnectionConfiguration;
import io.r2dbc.postgresql.PostgresqlConnectionFactory;
import io.r2dbc.postgresql.client.SSLMode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.math.BigDecimal;
import java.time.Duration;

record PedidoLinea(long id, String estado, BigDecimal total) {
}

@Configuration
class PostgresR2dbcConfig {

    @Bean(destroyMethod = "dispose")
    ConnectionPool pool(@Value("${app.postgres.host}") String host,
                        @Value("${app.postgres.base}") String base,
                        @Value("${app.postgres.usuario}") String usuario) {
        DefaultAzureCredential credencial = new DefaultAzureCredentialBuilder().build();
        TokenRequestContext ambito = new TokenRequestContext().addScopes("https://ossrdbms-aad.database.windows.net/.default");

        PostgresqlConnectionConfiguration configuracion = PostgresqlConnectionConfiguration.builder()
                .host(host)
                .port(5432)
                .database(base)
                .username(usuario)
                .password(credencial.getToken(ambito).map(t -> t.getToken()))   // se evalúa en cada conexión nueva
                .sslMode(SSLMode.VERIFY_FULL)
                .build();

        return new ConnectionPool(ConnectionPoolConfiguration.builder(new PostgresqlConnectionFactory(configuracion))
                .maxSize(10)
                .initialSize(2)
                .maxLifeTime(Duration.ofMinutes(30))            // menor que la vida del token
                .maxIdleTime(Duration.ofMinutes(10))
                .build());
    }

    @Bean
    DatabaseClient databaseClient(ConnectionPool pool) {
        return DatabaseClient.create(pool);
    }
}

@Repository
class PedidoReactivoRepositorio {

    private final DatabaseClient cliente;

    PedidoReactivoRepositorio(DatabaseClient cliente) {
        this.cliente = cliente;
    }

    Flux<PedidoLinea> delCliente(String clienteId) {
        return cliente.sql("SELECT id, estado, total FROM ventas.pedido WHERE cliente_id = :c ORDER BY id DESC LIMIT 50")
                .bind("c", clienteId)
                .map((fila, meta) -> new PedidoLinea(
                        fila.get("id", Long.class), fila.get("estado", String.class), fila.get("total", BigDecimal.class)))
                .all();
    }

    Mono<Long> cambiarEstado(long id, String esperado, String nuevo) {
        return cliente.sql("UPDATE ventas.pedido SET estado = :nuevo, version = version + 1 WHERE id = :id AND estado = :esperado")
                .bind("nuevo", nuevo)
                .bind("id", id)
                .bind("esperado", esperado)
                .fetch()
                .rowsUpdated();
    }
}
```
**Cuándo R2DBC y cuándo JDBC con hilos virtuales:** R2DBC aporta flujo reactivo extremo a extremo y *backpressure* en flujos grandes; JDBC (con `spring.threads.virtual.enabled=true`) es más simple, tiene más herramientas (JPA, Hibernate, Flyway) y suele bastar. Elige R2DBC si tu servicio ya es 100 % reactivo.

## 6. Quarkus · imperativo (Panache + proveedor de credenciales)

Quarkus pide credenciales a un `CredentialsProvider` cada vez que su pool (Agroal) crea una conexión:

```properties
# application.properties
quarkus.datasource.db-kind=postgresql
quarkus.datasource.jdbc.url=jdbc:postgresql://pg-modalima.postgres.database.azure.com:5432/pedidos?sslmode=verify-full&ApplicationName=api-pedidos
quarkus.datasource.credentials-provider=entra-postgres
quarkus.datasource.credentials-provider-name=entra-postgres
quarkus.datasource.jdbc.max-size=10
quarkus.datasource.jdbc.min-size=2
quarkus.datasource.jdbc.max-lifetime=30M
quarkus.hibernate-orm.database.generation=none
quarkus.flyway.migrate-at-start=false
app.postgres.usuario=id-api-pedidos
```

```java
import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.DefaultAzureCredentialBuilder;
import io.quarkus.credentials.CredentialsProvider;
import io.quarkus.hibernate.orm.panache.PanacheEntity;
import io.quarkus.panache.common.Page;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Named;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@ApplicationScoped
@Named("entra-postgres")
class TokenEntraCredenciales implements CredentialsProvider {

    private final TokenCredential credencial = new DefaultAzureCredentialBuilder().build();
    private final TokenRequestContext ambito = new TokenRequestContext().addScopes("https://ossrdbms-aad.database.windows.net/.default");

    @ConfigProperty(name = "app.postgres.usuario")
    String usuario;

    @Override
    public Map<String, String> getCredentials(String nombre) {
        AccessToken token = credencial.getTokenSync(ambito);            // se llama al abrir cada conexión física
        return Map.of(USER_PROPERTY_NAME, usuario, PASSWORD_PROPERTY_NAME, token.getToken());
    }
}

@Entity
@Table(name = "pedido", schema = "ventas")
class PedidoEntidad extends PanacheEntity {

    @Column(name = "cliente_id")
    public String clienteId;

    public String estado;

    public BigDecimal total;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    public Map<String, Object> atributos;

    @Version
    public long version;

    static List<PedidoEntidad> delCliente(String clienteId) {
        return find("clienteId = ?1 order by id desc", clienteId).page(Page.ofSize(50)).list();
    }
}

@Path("/clientes/{clienteId}/pedidos")
@ApplicationScoped
class PedidosRecurso {

    @GET
    public List<PedidoEntidad> listar(@PathParam("clienteId") String clienteId) {
        return PedidoEntidad.delCliente(clienteId);
    }

    @POST
    @Transactional
    public PedidoEntidad crear(@PathParam("clienteId") String clienteId, BigDecimal total) {
        PedidoEntidad p = new PedidoEntidad();
        p.clienteId = clienteId;
        p.estado = "CREADO";
        p.total = total;
        p.persist();
        return p;
    }
}
```

## 7. Quarkus · reactivo (Hibernate Reactive + cliente Vert.x de PostgreSQL)

El mismo `CredentialsProvider` sirve al cliente reactivo, que lo consulta al crear cada conexión:

```properties
quarkus.datasource.db-kind=postgresql
quarkus.datasource.credentials-provider=entra-postgres
quarkus.datasource.credentials-provider-name=entra-postgres
quarkus.datasource.reactive.url=postgresql://pg-modalima.postgres.database.azure.com:5432/pedidos
quarkus.datasource.reactive.max-size=10
quarkus.datasource.reactive.postgresql.ssl-mode=verify-full
```

```java
import io.quarkus.hibernate.reactive.panache.PanacheEntity;
import io.quarkus.hibernate.reactive.panache.common.WithTransaction;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

import java.math.BigDecimal;
import java.util.List;

@Entity
@Table(name = "pedido", schema = "ventas")
class PedidoReactivo extends PanacheEntity {

    public String clienteId;
    public String estado;
    public BigDecimal total;
}

@Path("/reactivo/clientes/{clienteId}/pedidos")
@ApplicationScoped
class PedidosReactivosRecurso {

    @GET
    public Uni<List<PedidoReactivo>> listar(@PathParam("clienteId") String clienteId) {
        return PedidoReactivo.list("clienteId = ?1 order by id desc", clienteId);
    }

    @POST
    @WithTransaction
    public Uni<PedidoReactivo> crear(@PathParam("clienteId") String clienteId, BigDecimal total) {
        PedidoReactivo p = new PedidoReactivo();
        p.clienteId = clienteId;
        p.estado = "CREADO";
        p.total = total;
        return p.persist().replaceWith(p);
    }
}
```

## 8. Migraciones con Flyway (pipeline con la identidad dueña)

El pipeline pide un token con federación OIDC (sin secretos) y lo pasa como contraseña:

```bash
# En el pipeline (GitHub Actions / Azure DevOps) tras azure/login por OIDC:
export PGPASSWORD="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
flyway -url="jdbc:postgresql://pg-modalima.postgres.database.azure.com:5432/pedidos?sslmode=verify-full" \
       -user="id-pipeline-migraciones" -password="$PGPASSWORD" \
       -locations=filesystem:db/migration migrate
```
Reglas: la identidad de migraciones es **dueña** de los objetos (la aplicación recibe `GRANT`, no propiedad); migraciones **compatibles hacia atrás**; en PostgreSQL, `CREATE INDEX CONCURRENTLY` no puede ir dentro de una transacción (configura Flyway para ese script con `-- flyway:executeInTransaction=false`).

## 9. Pruebas
| Necesidad | Herramienta |
|---|---|
| Probar contra PostgreSQL real | **Testcontainers** con `postgres:17` (misma versión que producción) |
| Pruebas de repositorio | `@DataJpaTest` con Testcontainers (no H2: difieren `jsonb`, `ON CONFLICT`, `SKIP LOCKED`) |
| Quarkus | *Dev Services* levanta PostgreSQL en `quarkus:dev` y en pruebas |
| Colas con `SKIP LOCKED` | Prueba con dos hilos tomando tareas y verifica que no se repiten |
| Errores transitorios | Unitarias que lancen `SQLException("...", "57P01")` y validen los reintentos |

## 10. Resumen de buenas prácticas en código
- Token de Entra **por conexión nueva** (`DataSource`/`CredentialsProvider`/`Supplier` reactivo), nunca fijo.
- `sslmode=verify-full`; `ApplicationName` para identificar al servicio.
- Pool de 10; PgBouncer con muchos pods (`prepareThreshold=0`, sin funciones de sesión).
- Idempotencia con `ON CONFLICT`; colas internas con `SKIP LOCKED`; líder con `pg_try_advisory_xact_lock`.
- `@Version` para concurrencia optimista; `409` en conflicto.
- Reintentos solo de SQLSTATE transitorios y operaciones idempotentes.
- La aplicación **no** es dueña del esquema.
