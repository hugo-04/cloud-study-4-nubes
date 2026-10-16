# Azure · Application Gateway · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40**. Verifica las vigentes.

Application Gateway no se "usa" desde Java: se **convive** con él. Lo que tu servicio debe resolver: aceptar el `Host` correcto, **normalizar `X-Forwarded-For`** (llega con puerto), **correlacionar** con `X-AppGW-Trace-Id`, tener una **sonda de salud** que no falle por tonterías, no pasar del *timeout* de solicitud y, si usas TLS extremo a extremo, servir un certificado válido.

## 1. Proxy, apagado y puertos

```properties
# Spring Boot
server.port=8080
server.forward-headers-strategy=framework
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
management.endpoint.health.probes.enabled=true
management.endpoint.health.probes.add-additional-paths=true   # /livez y /readyz si lo prefieres
```
```properties
# Quarkus
quarkus.http.port=8080
quarkus.http.proxy.proxy-address-forwarding=true
quarkus.http.proxy.allow-x-forwarded=true
quarkus.http.proxy.enable-forwarded-host=true
quarkus.shutdown.timeout=30s
```
La **sonda** del gateway llama a una ruta fija: `/actuator/health/readiness` (Spring) o `/q/health/ready` (Quarkus). Debe responder `200` **sin autenticación**.

## 2. Dejar pasar la sonda en Spring Security

Sin esto, la sonda recibe `401`, el backend queda `Unhealthy` y todos los usuarios ven 502.

```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
class SeguridadWeb {

    @Bean
    SecurityFilterChain filtros(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(a -> a
                .requestMatchers("/actuator/health/**").permitAll()   // sonda del gateway: sin token
                .anyRequest().authenticated())
            .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()));
        return http.build();
    }
}
```
Expón solo `health` en la web (`management.endpoints.web.exposure.include=health`) para no abrir otras rutas sin querer.

## 3. IP del cliente y correlación con el gateway

`X-Forwarded-For` en Application Gateway puede ser `203.0.113.7:51234` (IPv4 con puerto) o `[2001:db8::1]:51234` (IPv6). Normalízala y guarda el `X-AppGW-Trace-Id` en el MDC para cruzar tus logs con los del gateway.

```java
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
class ContextoGatewayFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        try {
            MDC.put("clienteIp", IpUtil.limpiar(req.getHeader("X-Forwarded-For"), req.getRemoteAddr()));
            String traza = req.getHeader("X-AppGW-Trace-Id");
            if (traza != null) {
                MDC.put("appgwTraceId", traza);
                res.setHeader("X-AppGW-Trace-Id", traza);   // útil para soporte: el usuario puede citarlo
            }
            chain.doFilter(req, res);
        } finally {
            MDC.clear();
        }
    }
}

final class IpUtil {

    private IpUtil() {
    }

    /** "203.0.113.7:51234" → "203.0.113.7"; "[2001:db8::1]:443" → "2001:db8::1"; lista → primer elemento. */
    static String limpiar(String xff, String respaldo) {
        if (xff == null || xff.isBlank()) {
            return respaldo;
        }
        String primera = xff.split(",")[0].trim();
        if (primera.startsWith("[")) {
            int fin = primera.indexOf(']');
            return fin > 0 ? primera.substring(1, fin) : primera;
        }
        int dosPuntos = primera.indexOf(':');
        boolean ipv4ConPuerto = dosPuntos > 0 && primera.indexOf(':', dosPuntos + 1) < 0;
        return ipv4ConPuerto ? primera.substring(0, dosPuntos) : primera;
    }
}
```
Añade `%X{clienteIp} %X{appgwTraceId}` al patrón de logs. **Confía en la cabecera solo si todo el tráfico pasa por el gateway** (restricciones de acceso/NSG).

### Quarkus
```java
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import org.jboss.logging.MDC;
import org.jboss.resteasy.reactive.server.ServerRequestFilter;
import org.jboss.resteasy.reactive.server.ServerResponseFilter;

public class ContextoGateway {

    @ServerRequestFilter
    public void alEntrar(ContainerRequestContext ctx) {
        String xff = ctx.getHeaderString("X-Forwarded-For");
        if (xff != null) {
            String ip = xff.split(",")[0].trim();
            int i = ip.lastIndexOf(':');
            if (i > 0 && ip.indexOf(':') == i) {
                ip = ip.substring(0, i);          // IPv4:puerto
            }
            MDC.put("clienteIp", ip);
        }
        String traza = ctx.getHeaderString("X-AppGW-Trace-Id");
        if (traza != null) {
            MDC.put("appgwTraceId", traza);
        }
    }

    @ServerResponseFilter
    public void alSalir(ContainerResponseContext ctx) {
        MDC.clear();
    }
}
```

## 4. Más lento que el *timeout* del gateway: patrón `202 Accepted`

El *timeout* de solicitud por defecto del gateway es corto (20 s). Un reporte de 40 s acabaría en 502/504. En lugar de subir el límite, responde enseguida y deja que el cliente pregunte.

```java
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;

@RestController
class ReportesController {

    private final Map<UUID, CompletableFuture<String>> trabajos = new ConcurrentHashMap<>();

    @PostMapping("/reportes")
    ResponseEntity<Void> solicitar() {
        UUID id = UUID.randomUUID();
        trabajos.put(id, CompletableFuture.supplyAsync(this::generarReporteLento));
        return ResponseEntity.accepted().location(URI.create("/reportes/" + id)).build();   // 202 + dónde preguntar
    }

    @GetMapping("/reportes/{id}")
    ResponseEntity<?> estado(@PathVariable UUID id) {
        CompletableFuture<String> trabajo = trabajos.get(id);
        if (trabajo == null) {
            return ResponseEntity.notFound().build();
        }
        if (!trabajo.isDone()) {
            return ResponseEntity.ok(Map.of("estado", "EN_CURSO"));
        }
        return ResponseEntity.ok(Map.of("estado", "LISTO", "resultado", trabajo.join()));
    }

    private String generarReporteLento() {
        try {
            Thread.sleep(40_000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return "reporte-ventas.csv";
    }
}
```
En producción guarda el estado en una base de datos o cola (no en memoria: hay varias réplicas) y entrega el resultado con una **SAS** de Blob Storage ([SAS](../../06-storage/sas-tokens/README.md)).

## 5. Cliente con tiempos menores que los del gateway

Cuando tu servicio llama a otro que también está detrás de un gateway, ajusta tus *timeouts* para fallar **antes** y reintentar con criterio.

```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;

@Configuration
class ClienteHttp {

    @Bean
    RestClient pedidosClient(RestClient.Builder builder) {
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(2))
                .build();
        JdkClientHttpRequestFactory fabrica = new JdkClientHttpRequestFactory(http);
        fabrica.setReadTimeout(Duration.ofSeconds(15));        // menor que los 20 s del gateway
        return builder
                .baseUrl("https://api.modalima.example")
                .requestFactory(fabrica)
                .build();
    }
}
```

## 6. TLS extremo a extremo con el certificado del backend

El gateway puede hablar HTTPS con tu servicio. El certificado (de Key Vault) se monta como archivos con el CSI Secrets Store ([Key Vault](../../03-secretos/key-vault/README.md)) y Spring Boot lo consume con un *SSL bundle*:

```properties
# Spring Boot
spring.ssl.bundle.pem.backend.keystore.certificate=file:/mnt/certs/tls.crt
spring.ssl.bundle.pem.backend.keystore.private-key=file:/mnt/certs/tls.key
server.ssl.bundle=backend
server.port=8443
```
```properties
# Quarkus
quarkus.http.ssl-port=8443
quarkus.http.insecure-requests=disabled
quarkus.http.ssl.certificate.files=/mnt/certs/tls.crt
quarkus.http.ssl.certificate.key-files=/mnt/certs/tls.key
```
El nombre del certificado (CN/SAN) debe coincidir con el host que el gateway usa para validar; si usas una CA interna, carga su raíz como *trusted root* en la configuración HTTP del gateway.

## 7. Imperativo vs reactivo detrás del gateway

| | Imperativo (MVC / Quarkus clásico) | Reactivo (WebFlux / Quarkus REST + Mutiny) |
|---|---|---|
| Comportamiento frente al gateway | Igual: HTTP/1.1 hacia el backend | Igual |
| WebSocket / SSE | Soportados por el gateway; latido necesario | Mejor escala con muchas conexiones |
| Filtros de contexto | `OncePerRequestFilter` y MDC | `WebFilter` y `Context` de Reactor (el MDC no viaja solo entre hilos) |
| Sonda | Actuator `/health/readiness` | Igual |

En WebFlux, propaga la traza con el contexto de Reactor o con la integración de Micrometer, no con `ThreadLocal` suelto.

## 8. Qué NO hacer en el código
- Autenticar la ruta de la sonda.
- Hacer que la sonda consulte la base de datos o un servicio externo caro.
- Suponer que `X-Forwarded-For` es solo una IP.
- Confiar en `Host` sin validar el dominio permitido en aplicaciones multi-tenant.
- Subir el *timeout* del cliente por encima del del gateway.
