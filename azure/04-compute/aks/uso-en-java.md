# Azure · AKS · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40**. Verifica las vigentes.

En Kubernetes tu aplicación deja de ser "un proceso en un servidor" y pasa a ser **un pod efímero que puede morir, moverse o duplicarse en cualquier momento**. Lo que cambia para el código Java: *configuración externa, salud, apagado ordenado, tamaño de la JVM, descubrimiento de servicios y ausencia de estado local*.

## 1. La JVM dentro de un contenedor

| Tema | Qué pasa | Qué hacer |
|---|---|---|
| **Memoria** | La JVM lee el límite del cgroup. Heap + metaspace + hilos + buffers directos + código JIT deben caber | `-XX:MaxRAMPercentage=70` (no fijes `-Xmx` igual al límite) |
| **CPU** | Con menos de 2 CPU (o < ~1.8 GB) la JVM elige **SerialGC** por defecto | Fija el GC: `-XX:+UseG1GC` (latencia) o `-XX:+UseParallelGC` (rendimiento) |
| **Límite de CPU** | Un `limits.cpu` bajo provoca *throttling* y pausas | `requests.cpu` realistas; evita límites de CPU estrictos |
| **OOM** | Si la JVM supera el límite, el kernel la mata (`OOMKilled`) | Deja margen; `-XX:+ExitOnOutOfMemoryError` para que el pod reinicie limpio |
| **Arranque** | Spring puede tardar 15–40 s | `startupProbe` generosa; CDS/AOT/imagen nativa si importa |
| **DNS** | La JVM cachea resoluciones | `-Dnetworkaddress.cache.ttl=30` |

```
JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=70 -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError -Dnetworkaddress.cache.ttl=30
```
Comprueba lo que la JVM "ve": `java -XX:+PrintFlagsFinal -version | grep -E "MaxHeapSize|UseG1GC|ActiveProcessorCount"` dentro del contenedor.

## 2. Construir la imagen
Opciones sin Dockerfile: **Jib** (Maven/Gradle), **buildpacks** (`mvn spring-boot:build-image`) o **Quarkus** (`quarkus-container-image-jib`). Con Dockerfile: ver [ejemplos/java/Dockerfile](ejemplos/java/Dockerfile) (multi-etapa, usuario no root, capas).

```bash
mvn -B package
az acr login -n acrmodalima
mvn -B compile jib:build -Dimage=acrmodalima.azurecr.io/api-pedidos:1.4.0
```
Usa **etiquetas inmutables** (versión o hash del commit) y, en producción, referencia por *digest*.

## 3. Configuración tipada que viene de ConfigMap y Secrets
Kubernetes entrega la configuración como **variables de entorno** o **archivos montados**. Spring la lee con *relaxed binding* (`APP_PEDIDOS_URL` → `app.pedidos.url`).

```java
import jakarta.validation.constraints.NotBlank;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "app")
record AppProperties(
        @NotBlank String pedidosUrl,
        Duration timeoutLectura,
        int maxReintentos) {

    AppProperties {
        if (timeoutLectura == null) timeoutLectura = Duration.ofSeconds(3);
        if (maxReintentos <= 0) maxReintentos = 2;
    }
}
```
```yaml
# ConfigMap -> variables de entorno del pod
envFrom:
  - configMapRef: { name: api-config }          # APP_PEDIDOS_URL, APP_TIMEOUT_LECTURA ...
```
Los **Secret** de Kubernetes y los secretos montados por CSI llegan igual (variable o archivo). Para archivos: `spring.config.import=optional:configtree:/mnt/secrets-store/` ([Key Vault · uso en Java](../../03-secretos/key-vault/uso-en-java.md)).

> Cambiar un ConfigMap **no reinicia** los pods ni recarga la app. O reinicias el Deployment (`kubectl rollout restart`) o diseñas recarga explícita.

## 4. Salud: tres sondas, tres propósitos

| Sonda | Pregunta | Qué incluir | Si falla |
|---|---|---|---|
| **startupProbe** | ¿Ya terminó de arrancar? | Solo que el proceso responde | Espera; si agota el tiempo, reinicia |
| **readinessProbe** | ¿Puede recibir tráfico **ahora**? | Dependencias críticas (base de datos) | Saca el pod del Service (no lo mata) |
| **livenessProbe** | ¿Está vivo o colgado? | **Solo** estado interno; nunca dependencias externas | Reinicia el contenedor |

> Error clásico: meter la base de datos en la *liveness*. Cae la base → Kubernetes reinicia **todos** los pods → la tormenta de reinicios empeora el incidente.

```properties
# Spring Boot (application.properties)
management.endpoint.health.probes.enabled=true
management.endpoint.health.probes.add-additional-paths=true     # /livez y /readyz en el puerto principal
management.endpoint.health.group.readiness.include=readinessState,db
management.endpoint.health.group.liveness.include=livenessState
management.endpoints.web.exposure.include=health,prometheus
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```
Sin tocar código, el pod publica `/actuator/health/liveness` y `/actuator/health/readiness`. Si detectas un estado irrecuperable, puedes marcar la *liveness* como rota para que Kubernetes reinicie el pod:

```java
import org.springframework.boot.availability.AvailabilityChangeEvent;
import org.springframework.boot.availability.LivenessState;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

@Component
class AutoDiagnostico {
    private final ApplicationEventPublisher publicador;

    AutoDiagnostico(ApplicationEventPublisher publicador) {
        this.publicador = publicador;
    }

    void marcarIrrecuperable() {
        AvailabilityChangeEvent.publish(publicador, this, LivenessState.BROKEN);   // Kubernetes reinicia el pod
    }
}
```

Quarkus (SmallRye Health): `/q/health/live`, `/q/health/ready`, `/q/health/started`.
```java
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Liveness;
import org.eclipse.microprofile.health.Readiness;
import org.eclipse.microprofile.health.Startup;

@ApplicationScoped
class Salud {

    @Liveness
    HealthCheck viva() {
        return () -> HealthCheckResponse.up("proceso");
    }

    @Readiness
    HealthCheck lista() {
        // comprueba aquí tus dependencias críticas (pool de base de datos, etc.)
        return () -> HealthCheckResponse.up("dependencias");
    }

    @Startup
    HealthCheck iniciada() {
        return () -> HealthCheckResponse.up("arranque");
    }
}
```

## 5. Apagado ordenado (el origen de los 502 en cada despliegue)
Secuencia cuando Kubernetes termina un pod:
1. El pod pasa a *Terminating* y se **retira de los endpoints** del Service (tarda unos segundos en propagarse por todo el clúster).
2. Se ejecuta el `preStop` (si existe).
3. Se envía `SIGTERM` al proceso.
4. Si el proceso sigue vivo tras `terminationGracePeriodSeconds`, `SIGKILL`.

```yaml
lifecycle:
  preStop:
    exec: { command: ["sh", "-c", "sleep 10"] }     # deja que los balanceadores dejen de enviarte tráfico
terminationGracePeriodSeconds: 45                   # > preStop + timeout de apagado de la app
```
Dentro de la app: `server.shutdown=graceful` (Spring) o `quarkus.shutdown.timeout=30s`, y detener consumidores de mensajes **antes** de cerrar conexiones:

```java
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

@Component
class ConsumidorDeCola implements SmartLifecycle {
    private final AtomicBoolean activo = new AtomicBoolean(false);

    @Override
    public void start() {
        activo.set(true);
        // iniciar el consumo de mensajes
    }

    @Override
    public void stop() {
        activo.set(false);      // dejar de pedir mensajes; terminar el que está en curso
    }

    @Override
    public boolean isRunning() {
        return activo.get();
    }

    @Override
    public int getPhase() {
        return Integer.MAX_VALUE - 100;   // se detiene ANTES que el servidor web y el pool
    }
}
```

## 6. Hablar con otros servicios del clúster
Cada Service tiene DNS `servicio.namespace.svc.cluster.local`. Usa la forma **completa** (FQDN) para evitar búsquedas inútiles por `ndots:5`, y fija **timeouts siempre**.

```java
import java.net.http.HttpClient;
import java.time.Duration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

class ClientePedidos {
    static RestClient crear() {
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(2))
                .build();
        JdkClientHttpRequestFactory fabrica = new JdkClientHttpRequestFactory(http);
        fabrica.setReadTimeout(Duration.ofSeconds(3));

        return RestClient.builder()
                .baseUrl("http://svc-pedidos.modalima.svc.cluster.local")   // FQDN, no "svc-pedidos"
                .requestFactory(fabrica)
                .build();
    }
}
```
Equivalente **reactivo** (WebFlux) con pool de conexiones que no sobrevive al tiempo de inactividad de la red:

```java
import java.time.Duration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;
import reactor.netty.resources.ConnectionProvider;

class ClientePedidosReactivo {
    static WebClient crear() {
        ConnectionProvider pool = ConnectionProvider.builder("pedidos")
                .maxConnections(100)
                .maxIdleTime(Duration.ofSeconds(30))
                .maxLifeTime(Duration.ofMinutes(5))
                .evictInBackground(Duration.ofSeconds(60))
                .build();
        HttpClient http = HttpClient.create(pool)
                .responseTimeout(Duration.ofSeconds(3));

        return WebClient.builder()
                .baseUrl("http://svc-pedidos.modalima.svc.cluster.local")
                .clientConnector(new ReactorClientHttpConnector(http))
                .build();
    }
}
```
Quarkus (cliente REST declarativo):
```java
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

@RegisterRestClient(configKey = "pedidos")
@Path("/pedidos")
interface PedidosClient {
    @GET
    @Path("/{id}")
    String porId(@PathParam("id") String id);
}
```
```properties
quarkus.rest-client.pedidos.url=http://svc-pedidos.modalima.svc.cluster.local
quarkus.rest-client.pedidos.connect-timeout=2000
quarkus.rest-client.pedidos.read-timeout=3000
```
Resiliencia reactiva en Quarkus (SmallRye Fault Tolerance):
```java
import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import org.eclipse.microprofile.faulttolerance.CircuitBreaker;
import org.eclipse.microprofile.faulttolerance.Retry;
import org.eclipse.microprofile.faulttolerance.Timeout;

@Path("/resumen")
class ResumenResource {

    @GET
    @Timeout(2000)
    @Retry(maxRetries = 2, delay = 200)
    @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5000)
    public Uni<String> resumen() {
        return Uni.createFrom().item("ok");     // llamada real a otro servicio
    }
}
```

## 7. Hilos virtuales (Java 21+)
Para servicios con mucha E/S bloqueante, los hilos virtuales dan concurrencia sin pasar a código reactivo.
```properties
# Spring Boot
spring.threads.virtual.enabled=true
```
```java
import io.smallrye.common.annotation.RunOnVirtualThread;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/listado")
class ListadoResource {

    @GET
    @RunOnVirtualThread                 // Quarkus: el método bloqueante corre en un hilo virtual
    public String listar() {
        return "datos";                 // JDBC / HTTP bloqueantes sin saturar el pool de hilos
    }
}
```
Vigila: *pinning* con `synchronized` y el tamaño de tus pools de conexiones (la concurrencia ya no la limitan los hilos, la limitan las conexiones).

## 8. Imperativo vs reactivo en Kubernetes: cómo decidir

| Pregunta | Imperativo (+ hilos virtuales) | Reactivo (WebFlux / Mutiny) |
|---|---|---|
| Código más fácil de leer y depurar | Sí | Más curva |
| Mucha E/S concurrente con pocos recursos | Bien con hilos virtuales | Muy bien |
| Streaming, *backpressure*, SSE, WebSocket | Posible | Natural |
| Drivers disponibles (JDBC vs R2DBC/reactivos) | JDBC maduro | R2DBC, clientes reactivos |
| Pods pequeños (pocos CPU) | Bien | Muy bien |
| Equipo sin experiencia reactiva | Recomendado | Evítalo si no hay necesidad |

Un solo pod reactivo con 1 CPU puede atender miles de conexiones; uno imperativo con hilos de plataforma necesita más memoria por conexión. Decide por **la forma de la carga**, no por moda. Detalle en los módulos transversales de programación reactiva.

## 9. Métricas hacia Managed Prometheus
```properties
# Spring Boot (micrometer-registry-prometheus)
management.endpoints.web.exposure.include=health,prometheus
management.metrics.tags.application=api-pedidos
```
```properties
# Quarkus (quarkus-micrometer-registry-prometheus): /q/metrics
quarkus.micrometer.export.prometheus.enabled=true
```
Se recolectan con un `PodMonitor` ([ejemplos/yaml/50-podmonitor.yaml](ejemplos/yaml/50-podmonitor.yaml)). Métricas imprescindibles de una JVM en un pod: `jvm_memory_used_bytes`, `jvm_gc_pause_seconds`, `jvm_threads_live_threads`, `hikaricp_connections_active`, `http_server_requests_seconds`.

## 10. Identidad hacia Azure desde un pod
El código no cambia: `DefaultAzureCredential` detecta Workload Identity ([Workload Identity · uso en Java](../../02-iam/workload-identity/uso-en-java.md)). Asegúrate de tener la etiqueta `azure.workload.identity/use: "true"` en el **pod** y la anotación `azure.workload.identity/client-id` en el ServiceAccount.

## 11. Tareas programadas en varios pods
`@Scheduled` correría en **cada réplica**. Usa un **CronJob** de Kubernetes (un pod por ejecución), o un lock distribuido si debe vivir dentro del servicio.

## 12. Qué NO hacer
- No usar `latest` como etiqueta de imagen.
- No poner dependencias externas en la *liveness probe*.
- No ignorar `SIGTERM` (el proceso debe apagarse con orden en menos del tiempo de gracia).
- No escribir datos importantes en el disco del pod.
- No fijar `-Xmx` igual al límite de memoria del contenedor.
- No abrir un cliente HTTP/pool por petición.
- No usar `localhost` para llegar a otro servicio: cada servicio tiene su Service y su DNS.
