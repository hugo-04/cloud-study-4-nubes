# Transversal · Quarkus (imperativo y reactivo)

**Quarkus** es un framework Java para microservicios que hace en **tiempo de compilación** lo que otros hacen al arrancar (escaneo, inyección, proxies), por eso arranca rápido, usa poca memoria y compila a **imagen nativa** con GraalVM sin dolor. Combina en el mismo servicio un estilo **imperativo** (bloqueante, en hilos de trabajo o **hilos virtuales**) y uno **reactivo** (Mutiny sobre el *event loop* de Vert.x). Versión objetivo: **Quarkus 3.40, Java 21** *(verifica)*.

## 1. Qué es

**Analogía:** una cocina de comida rápida con todo pre-cortado la noche anterior (build time): al abrir (arranque) solo queda ensamblar. Hay dos líneas: la de platos que esperan el horno (imperativo, en hilos de trabajo) y la de pedidos al paso que nunca se detienen (reactivo, en el *event loop*).

```
 build (mvn package)                         runtime
 ├─ extensiones procesan anotaciones   ─►   ├─ ArC (CDI) ya resuelto, sin reflexión
 ├─ genera bytecode / metadatos nativos     ├─ Vert.x event loop ── endpoints Uni/Multi (no bloquear)
 └─ (opcional) imagen nativa               └─ worker pool / hilos virtuales ── endpoints bloqueantes (JDBC, SDKs)
 dev mode: recarga en caliente + Dev Services (bases, brokers en contenedores) + pruebas continuas
```

## 2. Cómo funciona por dentro

| Pieza | Qué es | Consejo |
|---|---|---|
| **Extensiones** | `quarkus-rest`, `-hibernate-orm-panache`, `-smallrye-fault-tolerance`, `-messaging-kafka`, `-oidc`… | Agrégalas con `quarkus ext add` |
| **ArC (CDI)** | Inyección resuelta en build | `@ApplicationScoped` por defecto; evita `@Dependent` caro |
| **`@ConfigMapping`** | Configuración tipada en interfaces | Validación con `@WithDefault`, Bean Validation |
| **Quarkus REST** | JAX-RS sobre Vert.x | Retorno `Uni`/`Multi` ⇒ *event loop*; tipos normales ⇒ hilo de trabajo |
| **`@Blocking` / `@NonBlocking` / `@RunOnVirtualThread`** | Dónde corre cada método | Nunca bloquees el *event loop* |
| **Panache** | Repositorios/entidades activas para Hibernate ORM (y Reactive) | Consultas simples sin repetitivo |
| **SmallRye Fault Tolerance** | `@Timeout`, `@Retry`, `@CircuitBreaker`, `@Bulkhead`, `@Fallback` | Combina *timeout* + reintento acotado |
| **Dev Services** | Levanta dependencias en contenedores en dev y test | Sin configurar nada |
| **Health / métricas** | SmallRye Health (`/q/health/live`, `/ready`), Micrometer | Dependencias en readiness |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Microservicios que escalan a cero o en ráfagas | Quarkus (JVM o nativo) |
| Mucho I/O concurrente | Endpoints reactivos o hilos virtuales |
| Equipo con fuerte base en el ecosistema Spring y librerías solo de Spring | [Spring Boot](../spring-boot/README.md) |
| Librerías que dependen de reflexión intensa | JVM en vez de nativo, o configuración de reflexión |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Build time** | Trabajo hecho al compilar, no al arrancar |
| **Event loop** | Pocos hilos que nunca deben bloquearse |
| **Uni / Multi** | Un valor futuro / un flujo de valores (Mutiny) |
| **Dev Services** | Dependencias automáticas en desarrollo |
| **Imagen nativa** | Ejecutable sin JVM, arranque en milisegundos |

## 5. Cómo se usa: el mismo servicio de pedidos en ambos estilos

### Configuración tipada
```java
import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;
import java.time.Duration;

/** pedidos.max-items, pedidos.pasarela.url, pedidos.pasarela.timeout en application.properties */
@ConfigMapping(prefix = "pedidos")
interface ConfigPedidos {
    @WithDefault("100")
    int maxItems();

    Pasarela pasarela();

    interface Pasarela {
        String url();

        @WithDefault("2s")
        Duration timeout();
    }
}
```

### Núcleo y estilo imperativo (con tolerancia a fallos)
```java
// (clase reutilizada en los bloques siguientes)
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.eclipse.microprofile.faulttolerance.CircuitBreaker;
import org.eclipse.microprofile.faulttolerance.Fallback;
import org.eclipse.microprofile.faulttolerance.Retry;
import org.eclipse.microprofile.faulttolerance.Timeout;

record CrearPedidoQ(@NotBlank String cliente, @Positive long totalCentimos) { }

@Entity
class PedidoQ extends PanacheEntityBase {
    @Id
    public String id;
    public String cliente;
    public long totalCentimos;
    public String estado;
}

@ApplicationScoped
class RepositorioPedidosQ implements PanacheRepositoryBase<PedidoQ, String> {
}

/** Llamada externa protegida: timeout 2 s, 2 reintentos, circuito que se abre si falla la mitad de 10. */
@ApplicationScoped
class PasarelaQ {
    @Timeout(value = 2, unit = ChronoUnit.SECONDS)
    @Retry(maxRetries = 2, delay = 200)
    @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 10_000)
    @Fallback(fallbackMethod = "pendiente")
    public String autorizar(String idPedido, long total) {
        throw new IllegalStateException("aquí va el REST client hacia la pasarela");
    }

    String pendiente(String idPedido, long total) {
        return "PENDIENTE";   // se reintentará por un proceso aparte
    }
}

@Path("/v1/pedidos")
@Produces(MediaType.APPLICATION_JSON)
class RecursoPedidosQ {
    @Inject
    RepositorioPedidosQ repo;

    @Inject
    PasarelaQ pasarela;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Transactional
    public PedidoQ crear(@Valid CrearPedidoQ c) {   // tipo normal ⇒ corre en un hilo de trabajo
        var p = new PedidoQ();
        p.id = UUID.randomUUID().toString();
        p.cliente = c.cliente();
        p.totalCentimos = c.totalCentimos();
        p.estado = "CREADO";
        repo.persist(p);
        return p;
    }

    @GET
    @Path("/{id}")
    public PedidoQ obtener(@PathParam("id") String id) {
        return repo.findByIdOptional(id).orElseThrow(() -> new NotFoundException("pedido " + id));
    }
}
```

### Estilo reactivo (Mutiny) e hilos virtuales
```java
import io.smallrye.common.annotation.RunOnVirtualThread;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.time.Duration;

@Path("/v2/pedidos")
class RecursoPedidosReactivo {
    @Inject
    RepositorioPedidosQ repo;

    /** Uni ⇒ event loop: el trabajo bloqueante (JDBC) se manda al pool de trabajo. */
    @GET
    @Path("/{id}/estado")
    public Uni<String> estado(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> repo.findByIdOptional(id).map(p -> p.estado).orElse("DESCONOCIDO"))
            .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
            .ifNoItem().after(Duration.ofSeconds(2)).fail()
            .onFailure().recoverWithItem("NO_DISPONIBLE");
    }

    /** Alternativa simple: código bloqueante normal sobre un hilo virtual. */
    @GET
    @Path("/{id}/cliente")
    @RunOnVirtualThread
    public String cliente(@PathParam("id") String id) {
        return repo.findByIdOptional(id).map(p -> p.cliente).orElse("?");
    }
}
```

### Configuración de producción
```properties
quarkus.datasource.db-kind=postgresql
quarkus.hibernate-orm.database.generation=none
quarkus.flyway.migrate-at-start=true
quarkus.http.limits.max-body-size=1M
quarkus.shutdown.timeout=20s
# dev/test: Dev Services levanta PostgreSQL solo si no hay URL configurada
```

### Pruebas
```java
import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

// Prueba unitaria sin arrancar Quarkus; con io.quarkus.test.junit.QuarkusTest se prueba el endpoint real
class PasarelaQTest {
    @Test
    void elFallbackDevuelvePendiente() {
        assertEquals("PENDIENTE", new PasarelaQ().pendiente("P-1", 100));
    }
}
```
Con `@QuarkusTest` + REST Assured se prueba el endpoint real con Dev Services (base en contenedor); `@QuarkusIntegrationTest` prueba el artefacto empaquetado (también el nativo).

## 6. Seguridad
| Tema | Práctica |
|---|---|
| APIs | `quarkus-oidc` (JWT de un proveedor OIDC), `@RolesAllowed` / `@PermissionsAllowed` |
| Secretos | Variables de entorno, archivos montados o proveedores de credenciales |
| Salud | `/q/health/*` sin datos sensibles; métricas en red interna |
| Nativo | Menos superficie, pero revisa dependencias igual |

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Decidir por endpoint: imperativo, reactivo o hilo virtual | Bloquear dentro de un método que retorna `Uni` |
| `@Timeout` + `@Retry` acotado + `@CircuitBreaker` | Reintentos infinitos |
| `@ConfigMapping` | `@ConfigProperty` para todo |
| Dev Services y pruebas continuas | Bases compartidas de desarrollo |
| Probar el binario nativo en CI si lo usas | Descubrir problemas de reflexión en producción |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El event loop bloqueado | Un endpoint `Uni` de ModaLima llamaba JDBC directo; el servicio dejó de responder bajo carga | `runSubscriptionOn` al pool de trabajo, Hibernate Reactive o hilo virtual |
| Escalar a cero sin frío | Café Andino pasó a nativo y el arranque bajó de segundos a decenas de milisegundos | Nativo para servicios con ráfagas |
| La reflexión olvidada | Una librería de JSON fallaba solo en nativo | `@RegisterForReflection` y pruebas del nativo |
| Tormenta de reintentos | Tres capas reintentaban 3 veces cada una (27 llamadas) | Reintentar en un solo lugar y con circuito |

**Siguiente:** [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
