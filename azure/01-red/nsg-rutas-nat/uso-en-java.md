# Azure · NSG, Rutas y NAT · Uso desde Java

Aquí la red te afecta en tres cosas concretas: **cuántas conexiones nuevas abres**, **cuánto duran** y **a quién le pides permiso** cuando algo se bloquea.

## 1. Evita agotar los puertos SNAT: reutiliza conexiones
Cada conexión nueva hacia internet consume un puerto SNAT. Si por cada petición abres una conexión nueva, en un pico te quedas sin puertos y aparecen timeouts "intermitentes".

**Regla:** un solo cliente HTTP por destino, compartido, con *pool* de conexiones.

### Spring Boot imperativo (Apache HttpClient 5)
```java
import java.util.concurrent.TimeUnit;
import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.core5.util.TimeValue;
import org.apache.hc.core5.util.Timeout;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create()
        .setMaxConnTotal(200)
        .setMaxConnPerRoute(50)
        .setDefaultConnectionConfig(ConnectionConfig.custom()
                .setConnectTimeout(Timeout.ofSeconds(3))
                .setSocketTimeout(Timeout.ofSeconds(5))
                .setTimeToLive(TimeValue.of(10, TimeUnit.MINUTES))   // vida máxima de cada conexión
                .build())
        .build();

CloseableHttpClient http = HttpClients.custom()
        .setConnectionManager(cm)
        .evictIdleConnections(TimeValue.of(2, TimeUnit.MINUTES))     // cierra las dormidas antes del idle de la red
        .build();

RestClient client = RestClient.builder()
        .requestFactory(new HttpComponentsClientHttpRequestFactory(http))
        .baseUrl("https://api.proveedor.example")
        .build();
```
> Nota: `evictIdleConnections` debe ser **menor** que el idle timeout del NAT/balanceador (por defecto ~4 minutos), para no reutilizar conexiones que la red ya cerró.

### Spring Boot reactivo (Reactor Netty)
```java
import java.time.Duration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;
import reactor.netty.resources.ConnectionProvider;

ConnectionProvider pool = ConnectionProvider.builder("proveedor")
        .maxConnections(200)
        .maxIdleTime(Duration.ofSeconds(120))          // menor que el idle de la red
        .maxLifeTime(Duration.ofMinutes(10))
        .pendingAcquireTimeout(Duration.ofSeconds(5))
        .evictInBackground(Duration.ofSeconds(60))
        .build();

WebClient client = WebClient.builder()
        .baseUrl("https://api.proveedor.example")
        .clientConnector(new ReactorClientHttpConnector(HttpClient.create(pool)))
        .build();
```

### Quarkus
```properties
quarkus.rest-client.proveedor.url=https://api.proveedor.example
quarkus.rest-client.proveedor.connection-pool-size=50
quarkus.rest-client.proveedor.connection-ttl=120000
quarkus.rest-client.proveedor.connect-timeout=3000
quarkus.rest-client.proveedor.read-timeout=5000
```
> Verifica los nombres exactos de propiedades en la guía de REST Client de tu versión de Quarkus.

## 2. Reintentos con criterio
Un timeout por una regla de NSG **no se arregla reintentando**. Reintenta solo errores transitorios (`503`, reset de conexión), con espera creciente y con tope.

```java
// Resilience4j con Spring Boot (idea)
// resilience4j.retry.instances.proveedor.max-attempts=3
// resilience4j.retry.instances.proveedor.wait-duration=300ms
// resilience4j.retry.instances.proveedor.enable-exponential-backoff=true
```

## 3. IP de salida conocida
Si un tercero te pidió tu IP, esa IP es la del **NAT Gateway**. Comprueba desde la aplicación qué IP ve el mundo:

```java
var req = java.net.http.HttpRequest.newBuilder(java.net.URI.create("https://api.ipify.org")).build();
var ip = java.net.http.HttpClient.newHttpClient().send(req, java.net.http.HttpResponse.BodyHandlers.ofString()).body();
System.out.println("IP de salida: " + ip);   // debe coincidir con la IP pública del NAT Gateway
```
(Úsalo solo en pruebas; no dependas de un servicio externo en producción.)

## 4. Registrar el destino cuando falla
En los logs incluye siempre **host y puerto** del destino y el tipo de error (`UnknownHost`, `ConnectTimeout`, `ConnectionRefused`, `SSLHandshake`). Con eso sabes en qué escalón de la escalera de diagnóstico estás sin adivinar.
