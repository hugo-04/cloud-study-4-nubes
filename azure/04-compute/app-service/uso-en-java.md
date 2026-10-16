# Azure · App Service · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40**. Verifica las vigentes.

App Service ejecuta tu aplicación como un proceso detrás de un proxy. Casi todos los problemas de Java en App Service vienen de **cuatro cosas**: el puerto, las cabeceras del proxy, múltiples instancias y el arranque. Esta guía las cubre.

## 1. Puerto y dirección
| Escenario | Qué hace la plataforma | Qué haces tú |
|---|---|---|
| Java SE (JAR) | Define `SERVER_PORT` | Spring Boot lo lee solo (`server.port`). En Quarkus usa `quarkus.http.port=${SERVER_PORT:8080}` |
| Contenedor propio | Espera el puerto de `WEBSITES_PORT` | Fija `WEBSITES_PORT=8080` y escucha en `0.0.0.0` |
| Tomcat/JBoss integrado | Despliegas un WAR | Sin `main`; no uses este camino para microservicios nuevos |

```properties
# Spring Boot (application.properties)
server.port=${SERVER_PORT:8080}
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```
```properties
# Quarkus (application.properties)
quarkus.http.port=${SERVER_PORT:8080}
quarkus.http.host=0.0.0.0
quarkus.shutdown.timeout=30s
```

## 2. Configuración: app settings como variables de entorno
Un *app setting* `SPRING_DATASOURCE_URL` llega a Spring como `spring.datasource.url`. En Quarkus, `QUARKUS_DATASOURCE_JDBC_URL` equivale a `quarkus.datasource.jdbc.url`.

```properties
# Spring Boot: valores con valor por defecto para local
spring.datasource.url=${DB_URL:jdbc:postgresql://localhost:5432/pedidos}
app.keyvault.url=${KEYVAULT_URL:}
```
Secretos: usa referencias `@Microsoft.KeyVault(...)` en el setting (la app Java solo ve el valor) o lee con el SDK ([Key Vault · uso en Java](../../03-secretos/key-vault/uso-en-java.md)).

## 3. Cabeceras del proxy: HTTPS, host e IP del cliente
Los front ends terminan el TLS y llaman a tu app por HTTP. Si el framework no lo sabe, genera **redirecciones a `http://`**, enlaces mal formados y no ve la IP real.

```properties
# Spring Boot (MVC y WebFlux)
server.forward-headers-strategy=framework
```
```properties
# Quarkus
quarkus.http.proxy.proxy-address-forwarding=true
quarkus.http.proxy.allow-x-forwarded=true
```
> En App Service, `X-Forwarded-For` trae la IP **con puerto** (`203.0.113.7:51234`). La mayoría de bibliotecas no lo espera. Normalízala:

```java
class IpCliente {
    /** Devuelve la IP real a partir de X-Forwarded-For, sin puerto. */
    static String desde(String xForwardedFor, String remota) {
        if (xForwardedFor == null || xForwardedFor.isBlank()) {
            return remota;
        }
        String primera = xForwardedFor.split(",")[0].trim();
        if (primera.startsWith("[")) {                    // IPv6 con corchetes: [::1]:1234
            int fin = primera.indexOf(']');
            return fin > 0 ? primera.substring(1, fin) : primera;
        }
        int dosPuntos = primera.lastIndexOf(':');
        boolean tienePuerto = dosPuntos > 0 && primera.indexOf(':') == dosPuntos;   // solo IPv4:puerto
        return tienePuerto ? primera.substring(0, dosPuntos) : primera;
    }
}
```

Filtro para Spring MVC que deja la IP lista para tus logs:
```java
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
class IpClienteFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String xff = req.getHeader("X-Forwarded-For");
        String ip = xff == null || xff.isBlank() ? req.getRemoteAddr() : xff.split(",")[0].trim().replaceFirst(":\\d+$", "");
        MDC.put("clientIp", ip);
        try {
            chain.doFilter(req, res);
        } finally {
            MDC.remove("clientIp");
        }
    }
}
```
Equivalente reactivo (WebFlux), usando el contexto de Reactor en lugar de `MDC`:
```java
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
class IpClienteWebFilter implements WebFilter {
    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String xff = exchange.getRequest().getHeaders().getFirst("X-Forwarded-For");
        String ip = xff == null || xff.isBlank() ? "desconocida" : xff.split(",")[0].trim().replaceFirst(":\\d+$", "");
        return chain.filter(exchange).contextWrite(ctx -> ctx.put("clientIp", ip));
    }
}
```

## 4. Salud: liveness, readiness y el health check de la plataforma
La plataforma consulta **una** ruta. Apunta a *readiness*, que debe incluir las dependencias críticas (no todas: si cae un servicio opcional, no quieras sacar la instancia).

```properties
# Spring Boot
management.endpoint.health.probes.enabled=true
management.endpoint.health.group.readiness.include=readinessState,db
management.endpoint.health.show-details=never
management.endpoints.web.exposure.include=health
```
```properties
# Quarkus: /q/health/live y /q/health/ready con quarkus-smallrye-health
quarkus.smallrye-health.root-path=/q/health
```
Health check de la plataforma: `/actuator/health/readiness` (Spring) o `/q/health/ready` (Quarkus).

> Con **una sola instancia** el health check no puede sacarla del balanceador (no habría con qué reemplazarla). Usa 2 o más.

## 5. Tareas programadas con varias instancias
`@Scheduled` corre en **cada** instancia. Tres opciones, de mejor a peor:
1. Mover la tarea a una **Function de timer** o a un **job** de Container Apps/AKS.
2. **Bloqueo distribuido** (ShedLock sobre la base de datos o Redis).
3. Elegir una instancia "líder" (frágil).

```java
// nocheck  (requiere net.javacrumbs.shedlock:shedlock-spring y un LockProvider configurado)
@Scheduled(cron = "0 0 7 * * *")
@SchedulerLock(name = "resumen-diario", lockAtMostFor = "10m", lockAtLeastFor = "1m")
void enviarResumenDiario() {
    // solo una instancia lo ejecuta
}
```
En Quarkus: `quarkus-scheduler` con `@Scheduled(identity = "...", concurrentExecution = SKIP)` y clúster con `quarkus-quartz` si necesitas bloqueo entre instancias.

## 6. Ciclo de vida: arranque, apagado y reinicios
App Service puede **reiniciar instancias** (parches, escalado, swap). Tu app debe:
- **Arrancar rápido o declarar su tiempo de arranque** (`WEBSITES_CONTAINER_START_TIME_LIMIT` en contenedores).
- **Apagarse con gracia**: terminar peticiones en curso (graceful shutdown, sección 1) y cerrar consumidores de mensajes.
- Ser **idempotente** en lo que consume: un reinicio a medias puede repetir trabajo.

```java
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
class RegistroArranque {
    @EventListener(ApplicationReadyEvent.class)
    void listo() {
        String instancia = System.getenv().getOrDefault("WEBSITE_INSTANCE_ID", "local");
        String sitio = System.getenv().getOrDefault("WEBSITE_SITE_NAME", "local");
        org.slf4j.LoggerFactory.getLogger(RegistroArranque.class)
                .info("Aplicación lista en el sitio {} (instancia {})", sitio, instancia);
    }
}
```
`WEBSITE_INSTANCE_ID` te permite saber **qué instancia** respondió cuando depuras un fallo que ocurre solo en una.

## 7. JVM y memoria
```
JAVA_OPTS = -XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError -Dnetworkaddress.cache.ttl=30
```
- `MaxRAMPercentage`: deja margen al sistema; la memoria visible es la del SKU, no la de la máquina.
- `ExitOnOutOfMemoryError`: mejor que la JVM muera y la plataforma la reinicie a que quede zombi.
- `networkaddress.cache.ttl`: la JVM cachea DNS por defecto indefinidamente en algunos contextos; en entornos con Private Endpoint y cambios de IP, fija un TTL ([Red · uso en Java](../../01-red/private-endpoint-dns/uso-en-java.md)).

## 8. Llamadas salientes por VNet Integration
Con VNet Integration, las llamadas a recursos privados salen por la subred delegada y, si activas "route all", por tu NAT/Firewall. Tu cliente HTTP y tu pool de base de datos deben tener:
- **Timeouts de conexión y lectura** explícitos.
- Pools con **vida máxima menor al tiempo de inactividad de red** (~4 min en el balanceador de Azure).
- Reutilización de un cliente por aplicación (cada cliente nuevo gasta puertos SNAT).

Ejemplos de Apache HttpClient, Reactor Netty y Quarkus en [Red · NSG, rutas y NAT · uso en Java](../../01-red/nsg-rutas-nat/uso-en-java.md).

## 9. Autenticación
- **Easy Auth** (autenticación de App Service): la plataforma valida al usuario y manda a tu app cabeceras como `X-MS-CLIENT-PRINCIPAL`. Cómodo para webs internas.
- **Dentro de la app** (recomendado para APIs): Spring Security como *resource server* o Quarkus OIDC, validando `aud` y `iss` del token ([Entra ID · uso en Java](../../02-iam/entra-id/uso-en-java.md)).

> No mezcles las dos sin saber cuál manda: si Easy Auth está activo y además validas el token, un fallo de configuración produce 401 difíciles de rastrear.

## 10. Application Insights con el agente de Java
Sin cambiar código: en la app, `ApplicationInsightsAgent_EXTENSION_VERSION=~3` y `APPLICATIONINSIGHTS_CONNECTION_STRING` (referencia a Key Vault o setting). Ofrece trazas, dependencias (SQL, HTTP), excepciones y mapa de aplicación. Propaga el `traceparent` en tus llamadas salientes y registra el identificador de correlación en los logs.

## 11. Qué NO hacer
- No escribir archivos temporales importantes en disco local esperando que sobrevivan al reinicio.
- No usar sesiones HTTP en memoria con varias instancias.
- No asumir `request.getScheme()` sin configurar las cabeceras del proxy.
- No ejecutar tareas programadas sin protección en un plan de varias instancias.
- No dejar el health check apuntando a una ruta que consulta toda la base de datos cada minuto.
