# Azure · Azure SQL Database · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1 (Spring Framework 7, Hibernate 7, Spring Data JPA/R2DBC), Quarkus 3.40 (Hibernate ORM/Reactive con Panache), `mssql-jdbc` gestionado por cada framework, Azure SDK BOM 1.3**. Verifica las vigentes.

Principios: **sin contraseñas** (identidad administrada), **pool pequeño y validado**, **reintentos de errores transitorios**, **consultas parametrizadas**, **transacciones cortas**, concurrencia **optimista**, esquema versionado con identidad de migración distinta a la de la aplicación.

```xml
<!-- Spring Boot -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
<dependency><groupId>com.microsoft.sqlserver</groupId><artifactId>mssql-jdbc</artifactId></dependency>
<dependency><groupId>org.flywaydb</groupId><artifactId>flyway-sqlserver</artifactId></dependency>
<!-- Quarkus -->
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-jdbc-mssql</artifactId></dependency>
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-hibernate-orm-panache</artifactId></dependency>
<dependency><groupId>io.quarkus</groupId><artifactId>quarkus-flyway</artifactId></dependency>
```
Permisos en la base: ver [SQL de usuarios y roles](ejemplos/sql/01-usuarios-y-roles.sql). La aplicación se conecta con una **identidad administrada** convertida en usuario contenido.

## 1. Conexión sin contraseña (Spring Boot)

```yaml
# application.yml
spring:
  datasource:
    url: >-
      jdbc:sqlserver://sql-modalima.database.windows.net:1433;
      database=pedidos;
      encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;
      loginTimeout=30;
      authentication=ActiveDirectoryManagedIdentity;
      msiClientId=${AZURE_CLIENT_ID}
    hikari:
      pool-name: pedidos
      maximum-pool-size: 10          # pequeño: pods x pool no debe superar los límites de la base
      minimum-idle: 2
      connection-timeout: 30000
      validation-timeout: 5000
      max-lifetime: 1500000          # 25 min: renueva conexiones antes de cortes por reconfiguración
      keepalive-time: 300000
      leak-detection-threshold: 20000
  jpa:
    open-in-view: false              # no mantener la conexión durante toda la petición HTTP
    properties:
      hibernate.jdbc.batch_size: 50
      hibernate.order_inserts: true
      hibernate.order_updates: true
  flyway:
    enabled: false                   # las migraciones las corre el pipeline con otra identidad
```
- Con **identidad asignada por el sistema** omite `msiClientId`. En tu máquina usa `authentication=ActiveDirectoryDefault` (toma tu sesión de `az login`).
- El `driver` obtiene y renueva el token de Entra por ti; no hay contraseña que rotar.
- **Dimensiona el pool:** `pods × maximum-pool-size` ≤ conexiones/workers que tu nivel soporta. Más conexiones no aceleran: hacen cola dentro de la base.

## 2. Entidades, repositorio y concurrencia optimista (JPA)

```java
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.http.HttpStatus;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Table(name = "pedido", schema = "ventas")
class Pedido {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;

    @Column(name = "cliente_id", nullable = false, length = 40)
    String clienteId;

    @Column(nullable = false, length = 20)
    String estado;

    @Column(nullable = false, precision = 12, scale = 2)
    BigDecimal total;

    @Column(name = "creado_en", nullable = false)
    Instant creadoEn = Instant.now();

    @Version                       // concurrencia optimista: UPDATE ... WHERE id = ? AND version = ?
    long version;
}

interface PedidoRepositorio extends JpaRepository<Pedido, Long> {

    Page<Pedido> findByClienteIdOrderByCreadoEnDesc(String clienteId, Pageable pagina);

    @Modifying
    @Query("update Pedido p set p.estado = :nuevo, p.version = p.version + 1 where p.id = :id and p.estado = :esperado")
    int cambiarEstado(@Param("id") Long id, @Param("esperado") String esperado, @Param("nuevo") String nuevo);
}

@Service
class PedidoServicio {

    private final PedidoRepositorio repo;

    PedidoServicio(PedidoRepositorio repo) {
        this.repo = repo;
    }

    @Transactional                 // transacción CORTA: solo acceso a datos, sin llamadas HTTP dentro
    Pedido crear(String clienteId, BigDecimal total) {
        Pedido p = new Pedido();
        p.clienteId = clienteId;
        p.estado = "CREADO";
        p.total = total;
        return repo.save(p);
    }

    @Transactional
    boolean pagar(Long id) {
        // transición condicionada: solo si sigue "CREADO"; devuelve 0 si otro proceso ya lo cambió
        return repo.cambiarEstado(id, "CREADO", "PAGADO") == 1;
    }
}

@RestControllerAdvice
class ErroresDeConcurrencia {

    @ExceptionHandler(ObjectOptimisticLockingFailureException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    String conflicto() {
        return "El pedido cambió mientras lo editabas; vuelve a cargarlo";
    }
}
```
Tabla correspondiente: [04-esquema-pedidos.sql](ejemplos/sql/04-esquema-pedidos.sql).

## 3. Consultas con `JdbcClient`: parámetros, paginación por clave y lotes

`JdbcClient` es la forma moderna y ligera de escribir SQL propio sin ORM. **Siempre parámetros con nombre** (nunca concatenar texto).

```java
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;

record PedidoResumen(long id, String clienteId, String estado, BigDecimal total, Instant creadoEn) {
}

@Repository
class PedidoConsultas {

    private final JdbcClient jdbc;

    PedidoConsultas(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Paginación por clave (keyset): rápida con índices; OFFSET grande se vuelve lento. */
    List<PedidoResumen> siguientePagina(String clienteId, long despuesDeId, int tamano) {
        return jdbc.sql("""
                        SELECT TOP (:tamano) id, cliente_id, estado, total, creado_en
                        FROM ventas.pedido
                        WHERE cliente_id = :cliente AND id > :despues
                        ORDER BY id
                        """)
                .param("tamano", tamano)
                .param("cliente", clienteId)
                .param("despues", despuesDeId)
                .query((rs, n) -> new PedidoResumen(
                        rs.getLong("id"), rs.getString("cliente_id"), rs.getString("estado"),
                        rs.getBigDecimal("total"), rs.getTimestamp("creado_en").toInstant()))
                .list();
    }

    /** Paginación clásica con OFFSET/FETCH (el ORDER BY es obligatorio y debe ser determinista). */
    List<PedidoResumen> pagina(String clienteId, int pagina, int tamano) {
        return jdbc.sql("""
                        SELECT id, cliente_id, estado, total, creado_en
                        FROM ventas.pedido
                        WHERE cliente_id = :cliente
                        ORDER BY creado_en DESC, id DESC
                        OFFSET :salto ROWS FETCH NEXT :tamano ROWS ONLY
                        """)
                .param("cliente", clienteId)
                .param("salto", pagina * tamano)
                .param("tamano", tamano)
                .query((rs, n) -> new PedidoResumen(
                        rs.getLong("id"), rs.getString("cliente_id"), rs.getString("estado"),
                        rs.getBigDecimal("total"), rs.getTimestamp("creado_en").toInstant()))
                .list();
    }

    /** Inserción por lotes: una ida y vuelta por bloque, no por fila. */
    void insertarLote(List<PedidoResumen> pedidos) {
        List<Map<String, Object>> filas = pedidos.stream()
                .map(p -> Map.<String, Object>of("cliente", p.clienteId(), "estado", p.estado(), "total", p.total()))
                .toList();
        for (Map<String, Object> fila : filas) {
            jdbc.sql("INSERT INTO ventas.pedido (cliente_id, estado, total) VALUES (:cliente, :estado, :total)")
                    .params(fila)
                    .update();
        }
        // Para volúmenes grandes: JdbcTemplate.batchUpdate o, con mssql-jdbc, useBulkCopyForBatchInsert=true en la URL
    }
}
```

## 4. Reintentos de errores transitorios

Durante un *failover*, un escalado o una reconfiguración, Azure SQL puede cortar conexiones por segundos. Solo se reintenta lo **idempotente** (lecturas, o escrituras con clave única/condición).

```java
import java.sql.SQLException;
import java.sql.SQLRecoverableException;
import java.sql.SQLTransientException;
import java.time.Duration;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Supplier;

final class ErroresTransitorios {

    // 40613 base no disponible, 40501 servicio ocupado, 40197 error de procesamiento, 49918-49920 recursos insuficientes,
    // 4060 no se puede abrir la base, 10928/10929 límite de recursos, 1205 víctima de interbloqueo
    private static final Set<Integer> CODIGOS = Set.of(40613, 40501, 40197, 49918, 49919, 49920, 4060, 10928, 10929, 1205);

    private ErroresTransitorios() {
    }

    static boolean esTransitorio(Throwable error) {
        for (Throwable t = error; t != null; t = t.getCause()) {
            if (t instanceof SQLTransientException || t instanceof SQLRecoverableException) {
                return true;
            }
            if (t instanceof SQLException sql && CODIGOS.contains(sql.getErrorCode())) {
                return true;
            }
        }
        return false;
    }

    /** Reintento con retroceso exponencial y variación aleatoria (jitter). */
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
Uso: `ErroresTransitorios.conReintentos(4, () -> consultas.pagina("u-42", 0, 20));`

**Con Spring Framework 7** puedes declararlo con anotaciones (`@EnableResilientMethods` y `@Retryable`):

```java
import org.springframework.dao.TransientDataAccessException;
import org.springframework.resilience.annotation.EnableResilientMethods;
import org.springframework.resilience.annotation.Retryable;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

@Configuration
@EnableResilientMethods
class ResilienciaConfig {
}

@Service
class CatalogoConsultas {

    @Retryable(includes = TransientDataAccessException.class, maxRetries = 3, delay = 200, multiplier = 2)
    String nombreDelProducto(long id) {
        return "producto-" + id;        // aquí iría la consulta de solo lectura
    }
}
```
*(Los nombres exactos de los atributos de `@Retryable` cambiaron entre los candidatos de Spring 7 y la versión final: verifica los vigentes.)*

## 5. Patrón Outbox: guardar el pedido y el evento en la misma transacción

Problema: guardar en la base **y** publicar en [Service Bus](../../07-mensajeria/service-bus/README.md) no es atómico. Solución: escribir el evento en una tabla `outbox` **dentro de la misma transacción**, y un publicador la lee y envía.

```java
import com.azure.core.util.BinaryData;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusSenderClient;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

record EventoSalida(long id, String tipo, String cuerpo, UUID mensajeId) {
}

@Component
class OutboxPublicador {

    private final JdbcClient jdbc;
    private final ServiceBusSenderClient emisor;

    OutboxPublicador(JdbcClient jdbc, ServiceBusSenderClient emisor) {
        this.jdbc = jdbc;
        this.emisor = emisor;
    }

    /** Se llama dentro de la misma @Transactional que guarda el pedido. */
    void registrar(String tipo, String json) {
        jdbc.sql("INSERT INTO ventas.outbox (mensaje_id, tipo, cuerpo) VALUES (NEWID(), :tipo, :cuerpo)")
                .param("tipo", tipo)
                .param("cuerpo", json)
                .update();
    }

    @Scheduled(fixedDelay = 1000)
    @Transactional
    void publicarPendientes() {
        // UPDLOCK + READPAST: varias réplicas pueden publicar a la vez sin tomar las mismas filas
        List<EventoSalida> lote = jdbc.sql("""
                        SELECT TOP (50) id, tipo, cuerpo, mensaje_id
                        FROM ventas.outbox WITH (UPDLOCK, READPAST, ROWLOCK)
                        WHERE publicado_en IS NULL
                        ORDER BY id
                        """)
                .query((rs, n) -> new EventoSalida(rs.getLong("id"), rs.getString("tipo"),
                        rs.getString("cuerpo"), UUID.fromString(rs.getString("mensaje_id"))))
                .list();

        for (EventoSalida e : lote) {
            ServiceBusMessage mensaje = new ServiceBusMessage(BinaryData.fromString(e.cuerpo()))
                    .setMessageId(e.mensajeId().toString())      // permite detección de duplicados en Service Bus
                    .setSubject(e.tipo())
                    .setContentType("application/json");
            emisor.sendMessage(mensaje);
            jdbc.sql("UPDATE ventas.outbox SET publicado_en = SYSUTCDATETIME() WHERE id = :id")
                    .param("id", e.id())
                    .update();
        }
    }
}
```
Si el publicador cae después de enviar y antes de marcar, el evento se enviará otra vez: por eso el `MessageId` fijo (detección de duplicados) y consumidores idempotentes.

## 6. Multi-inquilino con seguridad a nivel de fila (RLS)

La base filtra las filas por inquilino con una política RLS que lee `SESSION_CONTEXT('tenant_id')`. La aplicación fija ese valor **cada vez que toma una conexión del pool**:

```java
import org.springframework.jdbc.datasource.DelegatingDataSource;

import javax.sql.DataSource;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.function.Supplier;

class InquilinoDataSource extends DelegatingDataSource {

    private final Supplier<String> inquilinoActual;      // p. ej. del token JWT de la petición

    InquilinoDataSource(DataSource real, Supplier<String> inquilinoActual) {
        super(real);
        this.inquilinoActual = inquilinoActual;
    }

    @Override
    public Connection getConnection() throws SQLException {
        Connection c = super.getConnection();
        try (CallableStatement s = c.prepareCall("EXEC sp_set_session_context @key = N'tenant_id', @value = ?, @read_only = 0")) {
            s.setString(1, inquilinoActual.get());
            s.execute();
        } catch (SQLException e) {
            c.close();
            throw e;
        }
        return c;
    }
}
```
La política y el esquema están en [02-seguridad-datos.sql](ejemplos/sql/02-seguridad-datos.sql). Así un error en una consulta no puede filtrar datos de otro inquilino.

## 7. Spring WebFlux (reactivo)

Para SQL Server la opción **más práctica** en WebFlux es **JDBC en un planificador elástico** (o hilos virtuales): conserva autenticación con identidad administrada, `@Version`, Hibernate y todo el ecosistema. R2DBC (`r2dbc-mssql`) existe, pero solo admite usuario/contraseña (sin `ActiveDirectoryManagedIdentity`): úsalo solo si puedes aceptar esa limitación.

```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

record PedidoResumen(long id, String clienteId, String estado, BigDecimal total, Instant creadoEn) {
}

interface PedidoConsultas {
    List<PedidoResumen> pagina(String clienteId, int pagina, int tamano);

    PedidoResumen porId(long id);
}

@RestController
class PedidosReactivoController {

    private final PedidoConsultas consultas;

    PedidosReactivoController(PedidoConsultas consultas) {
        this.consultas = consultas;
    }

    @GetMapping("/clientes/{clienteId}/pedidos")
    Flux<PedidoResumen> listar(@PathVariable String clienteId) {
        return Mono.fromCallable(() -> consultas.pagina(clienteId, 0, 50))
                .subscribeOn(Schedulers.boundedElastic())           // el bloqueo JDBC vive en otro hilo
                .flatMapMany(Flux::fromIterable);
    }

    @GetMapping("/pedidos/{id}")
    Mono<PedidoResumen> uno(@PathVariable long id) {
        return Mono.fromCallable(() -> consultas.porId(id))
                .subscribeOn(Schedulers.boundedElastic())
                .switchIfEmpty(Mono.error(new ResponseStatusException(HttpStatus.NOT_FOUND)));
    }
}
```
**Con Java 21 y hilos virtuales** (`spring.threads.virtual.enabled=true`) puedes escribir código imperativo sin bloquear hilos de plataforma: suele ser más simple que WebFlux para acceso a datos JDBC.

Si aun así usas R2DBC (usuario/contraseña, por ejemplo hacia una base de desarrollo):

```java
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Repository;
import reactor.core.publisher.Flux;

import java.math.BigDecimal;

record Linea(long id, String estado, BigDecimal total) {
}

@Repository
class PedidoR2dbc {

    private final DatabaseClient cliente;

    PedidoR2dbc(DatabaseClient cliente) {
        this.cliente = cliente;
    }

    Flux<Linea> porCliente(String clienteId) {
        return cliente.sql("SELECT id, estado, total FROM ventas.pedido WHERE cliente_id = :c ORDER BY id")
                .bind("c", clienteId)
                .map((fila, meta) -> new Linea(
                        fila.get("id", Long.class), fila.get("estado", String.class), fila.get("total", BigDecimal.class)))
                .all();
    }
}
```

## 8. Quarkus · imperativo (Hibernate ORM con Panache)

```properties
# application.properties
quarkus.datasource.db-kind=mssql
quarkus.datasource.jdbc.url=jdbc:sqlserver://sql-modalima.database.windows.net:1433;database=pedidos;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;authentication=ActiveDirectoryManagedIdentity
quarkus.datasource.jdbc.max-size=10
quarkus.datasource.jdbc.min-size=2
quarkus.datasource.jdbc.max-lifetime=25M
quarkus.datasource.jdbc.validation-query-sql=SELECT 1
quarkus.datasource.jdbc.background-validation-interval=2M
quarkus.hibernate-orm.database.generation=none
# Migraciones: las ejecuta el pipeline con otra identidad
quarkus.flyway.migrate-at-start=false
```

```java
import io.quarkus.hibernate.orm.panache.PanacheEntity;
import io.quarkus.panache.common.Page;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.Response;

import java.math.BigDecimal;
import java.util.List;

@Entity
@Table(name = "pedido", schema = "ventas")
class PedidoEntidad extends PanacheEntity {

    @Column(name = "cliente_id")
    public String clienteId;

    public String estado;

    public BigDecimal total;

    @Version
    public long version;

    static List<PedidoEntidad> delCliente(String clienteId, int pagina, int tamano) {
        return find("clienteId = ?1 order by id desc", clienteId).page(Page.of(pagina, tamano)).list();
    }
}

@Path("/clientes/{clienteId}/pedidos")
@ApplicationScoped
class PedidosRecurso {

    @GET
    public List<PedidoEntidad> listar(@PathParam("clienteId") String clienteId) {
        return PedidoEntidad.delCliente(clienteId, 0, 50);
    }

    @POST
    @Transactional                   // transacción corta
    public Response crear(@PathParam("clienteId") String clienteId, BigDecimal total) {
        PedidoEntidad p = new PedidoEntidad();
        p.clienteId = clienteId;
        p.estado = "CREADO";
        p.total = total;
        p.persist();
        return Response.status(Response.Status.CREATED).entity(p).build();
    }
}
```

## 9. Quarkus · reactivo (Hibernate Reactive con Panache y `Uni`)

El cliente reactivo de SQL Server de Quarkus (Vert.x) usa **usuario y contraseña**. Para identidad administrada con Quarkus, usa la variante JDBC (sección 8) con `@RunOnVirtualThread` o `@Blocking`. Si aceptas usuario/contraseña (por ejemplo contra la base de pruebas), así se escribe el código reactivo:

```properties
quarkus.datasource.db-kind=mssql
quarkus.datasource.username=${DB_USER}
quarkus.datasource.password=${DB_PASSWORD}
quarkus.datasource.reactive.url=sqlserver://sql-modalima.database.windows.net:1433/pedidos
quarkus.datasource.reactive.max-size=10
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

## 10. Migraciones con Flyway (ejecutadas por el pipeline)

```properties
# flyway.conf del pipeline (identidad de migración con db_ddladmin; token por federación OIDC, sin secretos)
flyway.url=jdbc:sqlserver://sql-modalima.database.windows.net:1433;database=pedidos;encrypt=true;authentication=ActiveDirectoryDefault
flyway.locations=filesystem:db/migration
flyway.baselineOnMigrate=true
```
Scripts `V1__esquema_inicial.sql`, `V2__outbox.sql`… Ejemplo en [04-esquema-pedidos.sql](ejemplos/sql/04-esquema-pedidos.sql). Reglas: **nunca** edites una migración ya aplicada; cambios **compatibles hacia atrás** (añadir columna nullable → desplegar código → llenar → exigir) para despliegues sin caída.

## 11. Pruebas
| Necesidad | Herramienta |
|---|---|
| Probar consultas contra SQL Server real | **Testcontainers** con la imagen `mcr.microsoft.com/mssql/server` (acepta licencia en la prueba) |
| Pruebas de repositorio rápidas | Spring `@DataJpaTest` sobre Testcontainers (no H2: el dialecto difiere) |
| Quarkus | *Dev Services* levanta un SQL Server en `quarkus:dev` y en pruebas |
| Errores transitorios | Pruebas unitarias con una operación que lanza `SQLTransientException` y verifica los reintentos |

## 12. Resumen de buenas prácticas en código
- `ActiveDirectoryManagedIdentity`, sin contraseñas; usuario contenido con roles mínimos.
- Pool de 10, `max-lifetime` 25 min, validación activada; `open-in-view=false`.
- Parámetros siempre; paginación por clave en tablas grandes; `ORDER BY` determinista.
- `@Version` en entidades con actualizaciones concurrentes; `409` en conflicto.
- Reintentos solo de errores transitorios y de operaciones idempotentes.
- Outbox para publicar eventos de forma confiable; consumidores idempotentes.
- Transacciones cortas, sin llamadas externas dentro.
- Migraciones con identidad separada y compatibles hacia atrás.
