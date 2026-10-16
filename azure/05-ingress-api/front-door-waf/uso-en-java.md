# Azure · Front Door · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40**. Verifica las vigentes.

Front Door no se llama desde Java; tu servicio vive **detrás** de él. Lo que debes programar:

1. **Aceptar solo tráfico de tu Front Door** (validar `X-Azure-FDID`).
2. **Registrar `X-Azure-Ref`** en cada línea de log.
3. **Leer bien la IP del cliente** (`X-Azure-ClientIP` / `X-Forwarded-For`).
4. **Emitir cabeceras de caché correctas** (`Cache-Control`, `ETag`).
5. Exponer una **sonda ligera** que admita `HEAD`.
6. No pasarte del **tiempo de espera** del origen.

## 1. Configuración base

```properties
# Spring Boot
server.port=8080
server.forward-headers-strategy=framework
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
app.frontdoor.id=${FRONT_DOOR_ID:}          # el "Front Door ID" del perfil (GUID); vacío = no validar (solo desarrollo)
```
```properties
# Quarkus
quarkus.http.port=8080
quarkus.http.proxy.proxy-address-forwarding=true
quarkus.http.proxy.allow-x-forwarded=true
quarkus.http.proxy.enable-forwarded-host=true
app.frontdoor.id=${FRONT_DOOR_ID:}
```
El GUID sale de `az afd profile show --query frontDoorId`. Guárdalo en una variable de entorno o configuración; **no es un secreto fuerte** (viaja en cada petición), por eso se combina siempre con restricciones de red.

## 2. Validar `X-Azure-FDID` (Spring MVC, imperativo)

```java
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
class FrontDoorFilter extends OncePerRequestFilter {

    private final String idEsperado;

    FrontDoorFilter(@Value("${app.frontdoor.id:}") String idEsperado) {
        this.idEsperado = idEsperado;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        // Las sondas internas de Kubernetes/ACA no pasan por Front Door.
        return req.getRequestURI().startsWith("/actuator/health");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        if (!idEsperado.isBlank() && !idEsperado.equalsIgnoreCase(req.getHeader("X-Azure-FDID"))) {
            res.sendError(HttpServletResponse.SC_FORBIDDEN, "Solo se acepta tráfico de Front Door");
            return;
        }
        try {
            String ref = req.getHeader("X-Azure-Ref");           // Front Door lo pone en la RESPUESTA; en la petición puede venir vacío
            String ip = req.getHeader("X-Azure-ClientIP");
            MDC.put("clienteIp", ip != null ? ip : req.getRemoteAddr());
            if (ref != null) {
                MDC.put("azureRef", ref);
            }
            chain.doFilter(req, res);
        } finally {
            MDC.clear();
        }
    }
}
```
> `X-Azure-Ref` se **devuelve** en la respuesta al cliente. Si quieres correlación completa, pide al equipo de plataforma una regla de Front Door que lo copie, o registra el que el cliente reporte desde su respuesta. Además genera tu propio `X-Request-Id` y devuélvelo.

### WebFlux (reactivo)
```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
class FrontDoorWebFilter implements WebFilter {

    private final String idEsperado;

    FrontDoorWebFilter(@Value("${app.frontdoor.id:}") String idEsperado) {
        this.idEsperado = idEsperado;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String ruta = exchange.getRequest().getPath().value();
        if (ruta.startsWith("/actuator/health") || idEsperado.isBlank()) {
            return chain.filter(exchange);
        }
        String recibido = exchange.getRequest().getHeaders().getFirst("X-Azure-FDID");
        if (!idEsperado.equalsIgnoreCase(recibido)) {
            exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN);
            return exchange.getResponse().setComplete();
        }
        return chain.filter(exchange);
    }
}
```

### Quarkus (RESTEasy Reactive)
```java
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.resteasy.reactive.server.ServerRequestFilter;

import java.util.Optional;

public class FrontDoorFiltro {

    @ConfigProperty(name = "app.frontdoor.id")
    Optional<String> idEsperado;

    @ServerRequestFilter(priority = 1)
    public Response validar(ContainerRequestContext ctx) {
        String ruta = ctx.getUriInfo().getPath();
        if (ruta.startsWith("/q/health") || idEsperado.filter(s -> !s.isBlank()).isEmpty()) {
            return null;                          // null = continuar
        }
        String recibido = ctx.getHeaderString("X-Azure-FDID");
        if (!idEsperado.get().equalsIgnoreCase(recibido)) {
            return Response.status(Response.Status.FORBIDDEN).entity("Solo Front Door").build();
        }
        return null;
    }
}
```

## 3. La IP del cliente

Front Door entrega la IP en `X-Azure-ClientIP` (la del cliente) y en `X-Forwarded-For` (puede ser una lista). Prefiere la primera, pero **solo si la petición viene de tu Front Door** (validación anterior).

```java
import jakarta.servlet.http.HttpServletRequest;

final class IpDelCliente {

    private IpDelCliente() {
    }

    static String de(HttpServletRequest req) {
        String directa = req.getHeader("X-Azure-ClientIP");
        if (directa != null && !directa.isBlank()) {
            return directa.trim();
        }
        String xff = req.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isBlank()) {
            return xff.split(",")[0].trim();
        }
        return req.getRemoteAddr();
    }
}
```

## 4. Cabeceras de caché: lo que Front Door necesita saber

Front Door cachea según lo que digas en la respuesta (si la ruta lo permite). Sé explícito.

```java
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.Map;

@RestController
class CatalogoController {

    // Imagen/contenido público y estable: cacheable en el borde y en el navegador
    @GetMapping("/static/banner/{id}")
    ResponseEntity<byte[]> banner(@PathVariable String id) {
        byte[] contenido = ("banner-" + id).getBytes();
        return ResponseEntity.ok()
                .cacheControl(CacheControl.maxAge(Duration.ofHours(6)).cachePublic())
                .eTag("\"v1-" + id + "\"")
                .body(contenido);
    }

    // Datos de un usuario: NUNCA en caché compartida
    @GetMapping("/api/perfil")
    ResponseEntity<Map<String, String>> perfil() {
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore().cachePrivate())
                .body(Map.of("nombre", "Hugo"));
    }

    // API dinámica pública pero fresca: validar siempre con el origen
    @GetMapping("/api/precios")
    ResponseEntity<Map<String, Double>> precios() {
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noCache())
                .body(Map.of("camisa", 49.9));
    }
}
```
Para que el servidor genere `ETag` automáticamente en respuestas estáticas, registra `ShallowEtagHeaderFilter`:

```java
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.filter.ShallowEtagHeaderFilter;

@Configuration
class EtagConfig {

    @Bean
    FilterRegistrationBean<ShallowEtagHeaderFilter> etag() {
        FilterRegistrationBean<ShallowEtagHeaderFilter> reg = new FilterRegistrationBean<>(new ShallowEtagHeaderFilter());
        reg.addUrlPatterns("/static/*");
        return reg;
    }
}
```
Si la respuesta varía por idioma o cabecera, añade `Vary` (por ejemplo `Vary: Accept-Language`) o desactiva la caché.

## 5. Sonda ligera que admite `HEAD`

Las sondas de Front Door suelen ser `HEAD`. Un `@GetMapping` ya responde a `HEAD` en Spring MVC; en JAX-RS declara `@HEAD` o deja que RESTEasy lo derive del `GET`.

```java
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

@RestController
class SondaController {

    @RequestMapping(value = "/livez", method = {RequestMethod.GET, RequestMethod.HEAD})
    ResponseEntity<Void> viva() {
        return ResponseEntity.ok().build();        // sin base de datos, sin llamadas externas
    }
}
```
Apúntala en el grupo de orígenes (`/livez`) y **no** la autentiques. La salud profunda va en `/actuator/health/readiness` para el orquestador, no para Front Door.

## 6. Operaciones largas (tiempo de espera del origen)

Mismo patrón que en [Application Gateway](../application-gateway/uso-en-java.md#4-más-lento-que-el-timeout-del-gateway-patrón-202-accepted): `202 Accepted` + `Location` de estado, y descarga por **SAS** cuando termine ([SAS](../../06-storage/sas-tokens/README.md)).

## 7. Imperativo vs reactivo detrás de Front Door

| | Imperativo (MVC / Quarkus clásico) | Reactivo (WebFlux / Quarkus REST + Mutiny) |
|---|---|---|
| Efecto de Front Door | Igual | Igual |
| Muchas conexiones largas (SSE) | Un hilo (o virtual) por conexión | Pocos hilos para muchas conexiones |
| Filtro de FDID | `OncePerRequestFilter` | `WebFilter` |
| Contexto de log | MDC | Contexto de Reactor / Micrometer |

## 8. Qué NO hacer en el código
- Tratar `X-Azure-FDID` como secreto único de seguridad.
- Devolver `Cache-Control: public` en respuestas con datos del usuario.
- Dejar que la sonda toque la base de datos.
- Registrar `X-Forwarded-For` completo y usarlo como identidad.
- Permitir que el cliente elija `X-Forwarded-Host` sin validar dominios permitidos.
