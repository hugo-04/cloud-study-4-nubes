# Transversal · Spring Boot para microservicios

**Spring Boot** arma una aplicación Spring lista para producción con **auto-configuración** (configura beans según lo que hay en el classpath y en la configuración), **starters** (dependencias coherentes por tema), servidor embebido y **Actuator** (salud, métricas). Esta guía cubre lo que usa un microservicio real: configuración tipada, API REST con validación y errores estándar, persistencia transaccional, clientes HTTP, observabilidad, seguridad y pruebas. Versión objetivo: **Spring Boot 4.1 sobre Spring Framework 7 y Java 21** *(verifica)*.

## 1. Qué es

**Analogía:** un departamento amoblado: llegas con tu ropa (código de negocio) y ya hay cocina, luz y agua conectadas (servidor, JSON, pool de conexiones, métricas). Si quieres otra cocina, la cambias (declaras tu propio bean) y la que venía se retira sola.

```
 main() → SpringApplication.run
   ├─ Environment: application.yml + perfiles + variables de entorno + secretos montados
   ├─ Auto-configuración (@ConditionalOnClass / OnMissingBean / OnProperty)
   ├─ Contenedor de beans (inyección por constructor)
   └─ Servidor embebido (Tomcat/Netty) ─► @RestController ─► servicio (@Transactional) ─► repositorio
                                           Actuator: /actuator/health/{liveness,readiness}, /actuator/prometheus
```

## 2. Cómo funciona por dentro

| Pieza | Qué es | Consejo |
|---|---|---|
| **Starters** | `spring-boot-starter-webmvc`, `-webflux`, `-data-jpa`, `-validation`, `-actuator`, `-security`… | Usa el BOM del parent; no fijes versiones sueltas |
| **Auto-configuración** | Clases condicionadas que crean beans por defecto | `--debug` o `/actuator/conditions` para ver qué se activó |
| **Configuración** | Orden de precedencia: argumentos > variables de entorno > `application-<perfil>.yml` > `application.yml` | 12-factor: lo que cambia por entorno, por variables |
| **`@ConfigurationProperties`** | Configuración tipada (records) con validación | Mejor que `@Value` disperso |
| **Perfiles** | `dev`, `test`, `prod` | No metas lógica de negocio por perfil |
| **Hilos virtuales** | `spring.threads.virtual.enabled=true` | Bloqueo barato en I/O; cuida los `synchronized` largos |
| **Actuator** | Salud (con grupos liveness/readiness), métricas Micrometer, info | Expón solo lo necesario |
| **AOT / nativo** | Compilación anticipada con GraalVM | Arranque rápido; revisa reflexión |
| **Clientes HTTP** | `RestClient`, interfaces `@HttpExchange` | *Timeouts* siempre |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Microservicio REST con base relacional | Spring MVC + JPA (+ hilos virtuales) |
| Alta concurrencia de I/O y *streaming* | WebFlux (ver [programación reactiva](../programacion-reactiva/README.md)) |
| Arranque en milisegundos y poca memoria | Imagen nativa o [Quarkus](../quarkus/README.md) |
| Una función mínima | Puede sobrar el framework completo |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Bean** | Objeto administrado por el contenedor |
| **Inyección por constructor** | Dependencias explícitas e inmutables |
| **Transacción** | `@Transactional` en el servicio, nunca en el controlador |
| **ProblemDetail** | Errores HTTP con formato estándar (RFC 9457) |
| **Slice test** | Prueba que levanta solo una capa (web, datos) |

## 5. Cómo se usa: un microservicio de pedidos

### Configuración tipada
```java
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/** pedidos.pasarela.url / pedidos.pasarela.timeout / pedidos.max-items en application.yml */
@Validated
@ConfigurationProperties(prefix = "pedidos")
record PropiedadesPedidos(Pasarela pasarela, @Min(1) @Max(100) int maxItems) {

    record Pasarela(@NotBlank String url, Duration timeout) { }
}
```

### API REST con validación y errores estándar
```java
// (clase reutilizada en los bloques siguientes)
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Repository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

record LineaPedido(@NotBlank String sku, @Positive int cantidad, @Positive long precioCentimos) { }

record CrearPedido(@NotBlank String cliente, @Size(min = 1, max = 100) List<@Valid LineaPedido> lineas) { }

record Pedido(String id, String cliente, long totalCentimos, String estado) { }

class PedidoNoEncontrado extends RuntimeException {
    PedidoNoEncontrado(String id) {
        super("pedido " + id + " no existe");
    }
}

/** Puerto de persistencia: en la app real, un repositorio JPA (ver más abajo). */
interface RepositorioPedidos {
    Pedido guardar(Pedido p);

    Optional<Pedido> buscar(String id);
}

@Repository
class RepositorioPedidosEnMemoria implements RepositorioPedidos {
    private final Map<String, Pedido> datos = new ConcurrentHashMap<>();

    public Pedido guardar(Pedido p) {
        datos.put(p.id(), p);
        return p;
    }

    public Optional<Pedido> buscar(String id) {
        return Optional.ofNullable(datos.get(id));
    }
}

@Service
class ServicioPedidos {
    private final RepositorioPedidos repo;

    ServicioPedidos(RepositorioPedidos repo) {
        this.repo = repo;
    }

    @Transactional
    Pedido crear(CrearPedido c) {
        long total = c.lineas().stream().mapToLong(l -> l.cantidad() * l.precioCentimos()).sum();
        return repo.guardar(new Pedido(UUID.randomUUID().toString(), c.cliente(), total, "CREADO"));
    }

    @Transactional(readOnly = true)
    Pedido obtener(String id) {
        return repo.buscar(id).orElseThrow(() -> new PedidoNoEncontrado(id));
    }
}

@RestController
@RequestMapping("/v1/pedidos")
class ControladorPedidos {
    private final ServicioPedidos servicio;

    ControladorPedidos(ServicioPedidos servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    ResponseEntity<Pedido> crear(@Valid @RequestBody CrearPedido c) {
        var p = servicio.crear(c);
        return ResponseEntity.created(URI.create("/v1/pedidos/" + p.id())).body(p);
    }

    @GetMapping("/{id}")
    Pedido obtener(@PathVariable String id) {
        return servicio.obtener(id);
    }
}

/** Errores de negocio como ProblemDetail; la validación (400) ya la resuelve Spring con spring.mvc.problemdetails.enabled=true. */
@RestControllerAdvice
class ManejadorDeErrores {
    @ExceptionHandler(PedidoNoEncontrado.class)
    ProblemDetail noEncontrado(PedidoNoEncontrado e) {
        var pd = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        pd.setTitle("Pedido no encontrado");
        return pd;
    }
}
```

### Persistencia con JPA (sin N+1)
```java
import jakarta.persistence.CascadeType;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Version;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

@Entity
class PedidoEntidad {
    @Id
    String id;
    String cliente;
    long totalCentimos;
    @Version
    long version;   // bloqueo optimista: dos ediciones simultáneas no se pisan
    @OneToMany(mappedBy = "pedido", cascade = CascadeType.ALL, orphanRemoval = true)
    List<LineaEntidad> lineas = new ArrayList<>();
}

@Entity
class LineaEntidad {
    @Id
    String id;
    @ManyToOne(fetch = FetchType.LAZY)
    PedidoEntidad pedido;
    String sku;
    int cantidad;
}

interface PedidoJpa extends JpaRepository<PedidoEntidad, String> {
    /** join fetch: una consulta en vez de 1 + N. */
    @Query("select p from PedidoEntidad p left join fetch p.lineas where p.id = :id")
    Optional<PedidoEntidad> conLineas(String id);
}
```

### Cliente HTTP con timeout
```java
import java.time.Duration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

class ClientePasarela {
    private final RestClient http;

    ClientePasarela(String url, Duration timeout) {
        var f = new SimpleClientHttpRequestFactory();
        f.setConnectTimeout(timeout);
        f.setReadTimeout(timeout);
        this.http = RestClient.builder().baseUrl(url).requestFactory(f).build();
    }

    String autorizar(String idPedido, long total) {
        return http.post().uri("/autorizaciones")
            .header("Idempotency-Key", idPedido)   // el reintento no cobra dos veces
            .body(java.util.Map.of("pedido", idPedido, "total", total))
            .retrieve().body(String.class);
    }
}
```

### Configuración de producción
```yaml
spring:
  threads.virtual.enabled: true
  jpa.open-in-view: false            # nada de consultas perezosas desde la vista
  mvc.problemdetails.enabled: true
management:
  endpoints.web.exposure.include: health,info,prometheus
  endpoint.health.probes.enabled: true   # /actuator/health/liveness y /readiness
server:
  shutdown: graceful
```

### Pruebas
```java
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import org.junit.jupiter.api.Test;

class ServicioPedidosTest {
    private final ServicioPedidos servicio = new ServicioPedidos(new RepositorioPedidosEnMemoria());

    @Test
    void calculaElTotal() {
        var p = servicio.crear(new CrearPedido("ana", List.of(new LineaPedido("SKU-1", 2, 1500), new LineaPedido("SKU-2", 1, 990))));
        assertThat(p.totalCentimos()).isEqualTo(3990);
    }

    @Test
    void pedidoInexistente() {
        assertThatThrownBy(() -> servicio.obtener("x")).isInstanceOf(PedidoNoEncontrado.class);
    }
}
```
Capas de prueba: unitarias del servicio (arriba, sin Spring), *slice* web con `@WebMvcTest` + `MockMvc` (validación y códigos HTTP), *slice* de datos con `@DataJpaTest` contra una base real en contenedor, y pocas pruebas de punta a punta con `@SpringBootTest`.

## 6. Seguridad
| Tema | Práctica |
|---|---|
| Autenticación de APIs | `spring-boot-starter-oauth2-resource-server` con JWT; valida emisor y audiencia |
| Autorización | `@PreAuthorize` o reglas en `SecurityFilterChain`, por *scopes*/roles |
| Secretos | Variables de entorno o archivos montados; nunca en `application.yml` del repositorio |
| Actuator | Solo `health` público; el resto en un puerto o red interna |
| Dependencias | BOM del parent, escaneo de vulnerabilidades en CI |

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Inyección por constructor | `@Autowired` en campos |
| `@ConfigurationProperties` con records validados | `@Value` por todas partes |
| `@Transactional` en servicios, transacciones cortas | Llamadas HTTP dentro de una transacción |
| `open-in-view: false` y *join fetch* | Descubrir N+1 en producción |
| *Timeouts* y `Idempotency-Key` en clientes | Clientes sin límite de tiempo |
| Sondas liveness/readiness separadas | Una sola salud que reinicia por una dependencia caída |
| `server.shutdown: graceful` | Cortar peticiones en cada despliegue |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El listado lento | El listado de pedidos de ModaLima hacía 1 + 200 consultas | `join fetch` o proyecciones; `open-in-view: false` |
| Reinicios en cadena | La liveness incluía la base; al caer la base, el orquestador reiniciaba todos los pods | La base va en readiness, no en liveness |
| El cobro doble | Un reintento del cliente HTTP de Café Andino cobró dos veces | `Idempotency-Key` y *timeouts* |
| Hilos agotados | Con 200 hilos de plataforma, una dependencia lenta tumbó el servicio | Hilos virtuales + *timeouts* + *bulkhead* |
| Secreto en el repositorio | Contraseña en `application-prod.yml` | Variables de entorno/archivos montados y escaneo de secretos |

**Siguiente:** [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
