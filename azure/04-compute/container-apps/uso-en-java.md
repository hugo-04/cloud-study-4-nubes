# Azure · Container Apps · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40**. Verifica las vigentes.

En Container Apps tu servicio es un contenedor que **puede aparecer y desaparecer** (escala a cero, nuevas revisiones). Lo que debes cuidar en Java: el **puerto**, las **cabeceras del proxy**, el **arranque en frío**, el **apagado con `SIGTERM`**, la **llamada entre servicios** y, si usas Dapr, hablar con el *sidecar*.

## 1. Puerto, proxy y arranque
```properties
# Spring Boot
server.port=8080                                      # = targetPort del ingress
server.forward-headers-strategy=framework             # el ingress (Envoy) termina el TLS
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
management.endpoint.health.probes.enabled=true
management.endpoint.health.probes.add-additional-paths=true
management.endpoints.web.exposure.include=health,prometheus
```
```properties
# Quarkus
quarkus.http.port=8080
quarkus.http.host=0.0.0.0
quarkus.http.proxy.proxy-address-forwarding=true
quarkus.shutdown.timeout=30s
```
Sondas (en la plantilla del contenedor, ver [ejemplos/yaml/containerapp.yaml](ejemplos/yaml/containerapp.yaml)): *startup* y *liveness* → `/actuator/health/liveness` (Quarkus: `/q/health/live`), *readiness* → `/actuator/health/readiness` (`/q/health/ready`). La *liveness* **no** debe depender de bases de datos externas.

## 2. Variables que inyecta la plataforma
| Variable | Contenido | Uso |
|---|---|---|
| `CONTAINER_APP_NAME` | Nombre de la app | Etiquetar logs y métricas |
| `CONTAINER_APP_REVISION` | Revisión en ejecución | Saber **qué versión** respondió |
| `CONTAINER_APP_REPLICA_NAME` | Réplica concreta | Diagnóstico de una réplica |
| `CONTAINER_APP_ENV_DNS_SUFFIX` | Sufijo DNS del entorno | Construir FQDN internos |
| `CONTAINER_APP_HOSTNAME` | Nombre del host | Logs |

```java
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
class EntornoContainerApps {

    private static final org.slf4j.Logger LOG = org.slf4j.LoggerFactory.getLogger(EntornoContainerApps.class);

    @EventListener(ApplicationReadyEvent.class)
    void alArrancar() {
        LOG.info("App={} revision={} replica={}",
                System.getenv().getOrDefault("CONTAINER_APP_NAME", "local"),
                System.getenv().getOrDefault("CONTAINER_APP_REVISION", "local"),
                System.getenv().getOrDefault("CONTAINER_APP_REPLICA_NAME", "local"));
    }
}
```
Registrar la **revisión** en cada línea de log (por ejemplo con el MDC) permite ver, durante un reparto 90/10, cuál versión causa los errores.

## 3. Llamar a otra Container App del mismo entorno
Dentro del entorno, una app se alcanza por su **nombre** y el puerto del ingress:
- `http://api-pedidos` (si el ingress de destino acepta tráfico HTTP interno; la plataforma gestiona el TLS entre apps según configuración),
- o `https://api-pedidos.internal.<sufijo-del-entorno>`.

```java
import java.net.http.HttpClient;
import java.time.Duration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

class ClienteInterno {
    static RestClient crear() {
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(2))
                .build();
        JdkClientHttpRequestFactory fabrica = new JdkClientHttpRequestFactory(http);
        fabrica.setReadTimeout(Duration.ofSeconds(5));     // si el destino escala desde 0, incluye su arranque

        return RestClient.builder()
                .baseUrl("http://api-pedidos")             // nombre de la Container App
                .requestFactory(fabrica)
                .build();
    }
}
```
> Si la app destino puede estar en **cero réplicas**, la primera llamada incluye su arranque en frío: sube el *timeout* de lectura o mantén `minReplicas = 1` en servicios que otros consumen en línea.

## 4. Dapr desde Java
El *sidecar* escucha en `http://localhost:3500` (puerto configurable). Tu código usa HTTP; el componente (YAML del entorno) decide el backend.

### 4.1 Publicar un evento (pub/sub)
```java
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

class PublicadorDapr {
    private static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();

    /** Publica en el componente "pubsub", tema "pedidos". El cuerpo es JSON. */
    static void publicar(String json) throws Exception {
        HttpRequest peticion = HttpRequest.newBuilder(URI.create("http://localhost:3500/v1.0/publish/pubsub/pedidos"))
                .timeout(Duration.ofSeconds(3))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(json))
                .build();
        HttpResponse<String> respuesta = HTTP.send(peticion, HttpResponse.BodyHandlers.ofString());
        if (respuesta.statusCode() >= 300) {
            throw new IllegalStateException("Dapr respondió " + respuesta.statusCode() + ": " + respuesta.body());
        }
    }
}
```

### 4.2 Recibir eventos (suscripción programática en Spring MVC)
Dapr pregunta a tu app qué temas escucha (`GET /dapr/subscribe`) y entrega cada evento con un `POST` a la ruta que le indiques. Responder `200` confirma; un error provoca reintento.

```java
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
class SuscripcionDapr {

    @GetMapping("/dapr/subscribe")
    List<Map<String, String>> suscripciones() {
        return List.of(Map.of(
                "pubsubname", "pubsub",
                "topic", "pedidos",
                "route", "/eventos/pedidos"));
    }

    @PostMapping("/eventos/pedidos")
    ResponseEntity<Void> recibir(@RequestBody Map<String, Object> cloudEvent) {
        Object datos = cloudEvent.get("data");        // el evento viene en formato CloudEvents
        // procesar de forma idempotente usando cloudEvent.get("id")
        return ResponseEntity.ok().build();           // 200 = confirmado; 5xx = reintento; 404 = descartar
    }
}
```
Equivalente Quarkus (reactivo con Mutiny):
```java
import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Map;

@Path("/")
class SuscripcionDaprQuarkus {

    @GET
    @Path("/dapr/subscribe")
    @Produces(MediaType.APPLICATION_JSON)
    public List<Map<String, String>> suscripciones() {
        return List.of(Map.of("pubsubname", "pubsub", "topic", "pedidos", "route", "/eventos/pedidos"));
    }

    @POST
    @Path("/eventos/pedidos")
    @Consumes({MediaType.APPLICATION_JSON, "application/cloudevents+json"})
    public Uni<Response> recibir(Map<String, Object> cloudEvent) {
        return Uni.createFrom().item(() -> Response.ok().build());   // procesa aquí, sin bloquear el hilo de E/S
    }
}
```
El SDK `io.dapr:dapr-sdk` y las integraciones con Spring Boot simplifican esto; el contrato HTTP de arriba es lo que hay debajo. *Verifica las versiones del SDK de Dapr compatibles con tu Spring Boot.*

### 4.3 Invocar otro servicio con reintentos
`GET http://localhost:3500/v1.0/invoke/api-pedidos/method/pedidos/123` : Dapr resuelve el destino por su `app-id`, aplica reintentos y mTLS.

## 5. Escala a cero y arranque en frío
| Palanca | Efecto |
|---|---|
| `minReplicas = 1` en servicios de cara al usuario | Elimina el arranque en frío |
| **AppCDS / CDS** (Java 21) | Reduce el arranque de la JVM: `-XX:+AutoCreateSharedArchive -XX:SharedArchiveFile=/tmp/app.jsa` |
| Menos trabajo en el arranque | Inicialización perezosa, evita escanear demasiado |
| **Imagen nativa** (Quarkus/GraalVM) | Arranque en milisegundos, menos memoria; compilación más lenta |
| Recursos suficientes | Más CPU en el arranque = arranque más corto |

Para **workers por cola** el arranque en frío importa poco: pueden estar en cero.

## 6. Jobs en Java
Un Job es un contenedor que **termina**. El código de salida decide si tuvo éxito (`0`) o falló (reintento).

```java
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.stereotype.Component;

@SpringBootApplication
class ReporteApp {

    public static void main(String[] args) {
        // exit() convierte el resultado del contexto en código de salida del proceso
        System.exit(SpringApplication.exit(SpringApplication.run(ReporteApp.class, args)));
    }
}

@Component
class ReporteDiario implements ApplicationRunner {
    @Override
    public void run(ApplicationArguments args) {
        // generar el reporte; si lanza una excepción, el proceso sale con código ≠ 0
    }
}
```
```properties
spring.main.web-application-type=none
```
Quarkus:
```java
import io.quarkus.runtime.Quarkus;
import io.quarkus.runtime.QuarkusApplication;
import io.quarkus.runtime.annotations.QuarkusMain;

@QuarkusMain
public class ReporteMain implements QuarkusApplication {

    @Override
    public int run(String... args) {
        try {
            // generar el reporte
            return 0;
        } catch (RuntimeException e) {
            e.printStackTrace();
            return 1;               // fallo: la plataforma reintenta según replicaRetryLimit
        }
    }

    public static void main(String... args) {
        Quarkus.run(ReporteMain.class, args);
    }
}
```
Haz el trabajo **idempotente**: un reintento no debe duplicar el reporte.

## 7. Secretos e identidad
- Variable desde secreto: `DB_PASSWORD=secretref:db-password`; Spring la lee como `${DB_PASSWORD}`.
- Acceso a Azure: `DefaultAzureCredential` con la identidad administrada; si hay varias, fija `AZURE_CLIENT_ID` ([Managed Identity · uso en Java](../../02-iam/managed-identity/uso-en-java.md)).
- Rotación: al cambiar la versión del secreto de Key Vault, **reinicia la revisión** (las variables se leen al arrancar la réplica). Para valores que cambian en caliente, lee con el SDK y caché corta ([Key Vault · uso en Java](../../03-secretos/key-vault/uso-en-java.md)).

## 8. Imperativo vs reactivo aquí
- Con **escala a cero y réplicas pequeñas** (0.5–1 vCPU), una app reactiva o con hilos virtuales aprovecha mejor la CPU en E/S intensiva.
- Para workers de colas con KEDA, la **concurrencia por réplica** (cuántos mensajes procesas a la vez) y `maxReplicas` definen cuánta presión recibe tu base de datos: limítalos explícitamente.
- `spring.threads.virtual.enabled=true` o `@RunOnVirtualThread` (Quarkus) simplifican el código bloqueante sin pasar a reactivo.

## 9. Qué NO hacer
- No asumir que la réplica sobrevive: guarda estado fuera.
- No usar `localhost` para llamar a otra app (usa su nombre).
- No olvidar `SIGTERM`: termina las peticiones y detén consumidores.
- No dejar `maxReplicas` sin tope en workers que escriben en una base de datos.
- No poner la base de datos en la *liveness probe*.
