# Azure · APIM · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3**. Verifica las vigentes.

Con APIM hay **dos lados**:

- **Tu microservicio detrás de APIM** (lo más común): valida el JWT también (defensa en profundidad), lee las cabeceras que APIM añade, es idempotente en escrituras, devuelve errores consistentes y publica su contrato OpenAPI.
- **Tu código como cliente de APIM**: envía la clave de suscripción y el token, respeta `429` con `Retry-After`.

## 1. Configuración

```properties
# Spring Boot (servicio detrás de APIM)
server.port=8080
server.forward-headers-strategy=framework
server.shutdown=graceful
app.entra.tenant-id=${AZURE_TENANT_ID}
app.entra.audience=api://modalima-backend      # la audiencia que APIM pone al llamar (authentication-managed-identity)
spring.mvc.problemdetails.enabled=true          # errores en application/problem+json
management.endpoints.web.exposure.include=health
management.endpoint.health.probes.enabled=true
```
```properties
# Quarkus (servicio detrás de APIM)
quarkus.http.port=8080
quarkus.http.proxy.proxy-address-forwarding=true
quarkus.oidc.application-type=service
quarkus.oidc.auth-server-url=https://login.microsoftonline.com/${AZURE_TENANT_ID}/v2.0
quarkus.oidc.client-id=api://modalima-backend
quarkus.oidc.token.audience=api://modalima-backend
quarkus.oidc.roles.role-claim-path=roles        # roles de aplicación de Entra ID
```

## 2. El backend también valida el JWT (Spring, imperativo)

APIM ya validó el token del consumidor y, para llamar al backend, usa su **identidad administrada** (token con la audiencia del backend y un rol de aplicación). El backend no debe "confiar a ciegas" en que el tráfico viene de APIM.

```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.SecurityFilterChain;

import java.util.Collection;
import java.util.List;

@Configuration
@EnableMethodSecurity
class SeguridadApi {

    @Bean
    JwtDecoder jwtDecoder(@Value("${app.entra.tenant-id}") String tenant,
                          @Value("${app.entra.audience}") String audiencia) {
        String emisor = "https://login.microsoftonline.com/" + tenant + "/v2.0";
        // withJwkSetUri no hace red al arrancar: descarga las claves la primera vez que se necesitan.
        NimbusJwtDecoder decoder = NimbusJwtDecoder
                .withJwkSetUri("https://login.microsoftonline.com/" + tenant + "/discovery/v2.0/keys")
                .build();

        OAuth2TokenValidator<Jwt> deEmisor = JwtValidators.createDefaultWithIssuer(emisor);   // iss + exp + nbf
        OAuth2TokenValidator<Jwt> deAudiencia = new JwtClaimValidator<List<String>>(
                "aud", aud -> aud != null && aud.contains(audiencia));
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(deEmisor, deAudiencia));
        return decoder;
    }

    /** Los roles de aplicación de Entra ID viajan en el claim "roles" → autoridades ROLE_xxx. */
    @Bean
    JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtAuthenticationConverter conversor = new JwtAuthenticationConverter();
        conversor.setJwtGrantedAuthoritiesConverter(jwt -> {
            List<String> roles = jwt.getClaimAsStringList("roles");
            Collection<GrantedAuthority> autoridades = new java.util.ArrayList<>();
            if (roles != null) {
                for (String rol : roles) {
                    autoridades.add(new SimpleGrantedAuthority("ROLE_" + rol));
                }
            }
            return autoridades;
        });
        return conversor;
    }

    @Bean
    SecurityFilterChain filtros(HttpSecurity http, JwtAuthenticationConverter conversor) throws Exception {
        http.authorizeHttpRequests(a -> a
                .requestMatchers("/actuator/health/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(o -> o.jwt(j -> j.jwtAuthenticationConverter(conversor)));
        return http.build();
    }
}
```
```java
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/pedidos")
class PedidosApi {

    @GetMapping("/{id}")
    @PreAuthorize("hasRole('Pedidos.Leer')")           // rol de aplicación definido en Entra ID
    Map<String, Object> leer(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
        return Map.of("id", id, "llamadoPor", jwt.getSubject(), "appId", String.valueOf(jwt.getClaimAsString("azp")));
    }
}
```

### Reactivo (WebFlux)
```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusReactiveJwtDecoder;
import org.springframework.security.oauth2.jwt.ReactiveJwtDecoder;
import org.springframework.security.web.server.SecurityWebFilterChain;

import java.util.List;

@Configuration
@EnableWebFluxSecurity
class SeguridadReactiva {

    @Bean
    ReactiveJwtDecoder jwtDecoder(@Value("${app.entra.tenant-id}") String tenant,
                                  @Value("${app.entra.audience}") String audiencia) {
        NimbusReactiveJwtDecoder decoder = NimbusReactiveJwtDecoder
                .withJwkSetUri("https://login.microsoftonline.com/" + tenant + "/discovery/v2.0/keys")
                .build();
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<Jwt>(
                JwtValidators.createDefaultWithIssuer("https://login.microsoftonline.com/" + tenant + "/v2.0"),
                new JwtClaimValidator<List<String>>("aud", aud -> aud != null && aud.contains(audiencia))));
        return decoder;
    }

    @Bean
    SecurityWebFilterChain cadena(ServerHttpSecurity http) {
        return http
                .authorizeExchange(a -> a
                        .pathMatchers("/actuator/health/**").permitAll()
                        .anyExchange().authenticated())
                .oauth2ResourceServer(o -> o.jwt(j -> { }))
                .build();
    }
}
```

### Quarkus (imperativo y reactivo)
```java
import io.quarkus.security.identity.SecurityIdentity;
import io.smallrye.mutiny.Uni;
import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.util.Map;

@Path("/pedidos")
@Produces(MediaType.APPLICATION_JSON)
public class PedidosResource {

    @Inject
    SecurityIdentity identidad;

    @GET
    @Path("/{id}")
    @RolesAllowed("Pedidos.Leer")
    public Map<String, String> leer(@PathParam("id") String id) {          // imperativo
        return Map.of("id", id, "llamadoPor", identidad.getPrincipal().getName());
    }

    @GET
    @Path("/{id}/reactivo")
    @RolesAllowed("Pedidos.Leer")
    public Uni<Map<String, String>> leerReactivo(@PathParam("id") String id) {   // reactivo (Mutiny)
        return Uni.createFrom().item(() -> Map.of("id", id, "llamadoPor", identidad.getPrincipal().getName()));
    }
}
```

## 3. Cabeceras que APIM añade (si las configuras en la política)

Ejemplo de política en [ejemplos/xml/10-api-policy.xml](ejemplos/xml/10-api-policy.xml): `X-Correlation-Id`, `X-Consumer-Id` (id de suscripción) y `X-Forwarded-For`.

```java
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

@Component
class CorrelacionApimFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String correlacion = req.getHeader("X-Correlation-Id");
        if (correlacion == null || correlacion.isBlank()) {
            correlacion = UUID.randomUUID().toString();
        }
        try {
            MDC.put("correlacionId", correlacion);
            MDC.put("consumidor", String.valueOf(req.getHeader("X-Consumer-Id")));
            res.setHeader("X-Correlation-Id", correlacion);          // devuélvelo: el cliente lo cita en soporte
            chain.doFilter(req, res);
        } finally {
            MDC.clear();
        }
    }
}
```
Propaga `X-Correlation-Id` en **todas** las llamadas salientes (RestClient/WebClient) para ver la cadena completa en Application Insights.

## 4. Escrituras idempotentes (porque alguien reintentará)

APIM, el cliente o un balanceador pueden repetir un `POST`. Acepta `Idempotency-Key` y devuelve **el mismo resultado** si ya lo procesaste.

```java
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

record NuevoPedido(@NotBlank String sku, @Min(1) int cantidad) {
}

@RestController
class PedidosEscritura {

    // En producción: tabla con clave única (Idempotency-Key) y TTL, no memoria (hay varias réplicas).
    private final Map<String, UUID> procesados = new ConcurrentHashMap<>();

    @PostMapping("/pedidos")
    ResponseEntity<Void> crear(@RequestHeader("Idempotency-Key") String clave, @Valid @RequestBody NuevoPedido pedido) {
        UUID id = procesados.computeIfAbsent(clave, k -> UUID.randomUUID());   // misma clave → mismo id
        return ResponseEntity.created(URI.create("/pedidos/" + id)).build();
    }
}
```

## 5. Errores consistentes (`application/problem+json`)

APIM puede `validate-content` y devolver su propio formato; tu servicio debería usar el **mismo** estándar para que el consumidor vea una sola forma de error.

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;
import java.util.Map;
import java.util.stream.Collectors;

@RestControllerAdvice
class ErroresApi {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ProblemDetail validacion(MethodArgumentNotValidException ex) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "La solicitud no es válida");
        p.setType(URI.create("https://api.modalima.example/errores/validacion"));
        p.setTitle("Validación fallida");
        Map<String, String> campos = ex.getBindingResult().getFieldErrors().stream()
                .collect(Collectors.toMap(f -> f.getField(), f -> String.valueOf(f.getDefaultMessage()), (a, b) -> a));
        p.setProperty("campos", campos);
        return p;
    }
}
```

## 6. Tu código como **cliente** de APIM

Necesitas **dos** cosas: la clave de suscripción (`Ocp-Apim-Subscription-Key`) y un token de Entra ID (`Authorization: Bearer ...`) para la API.

```java
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.ClientSecretCredentialBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

@Component
class ClienteApim {

    private final RestClient rest;
    private final TokenCredential credencial;
    private final String clave;

    ClienteApim(@Value("${apim.base-url}") String baseUrl,
                @Value("${apim.subscription-key}") String clave,
                @Value("${AZURE_TENANT_ID}") String tenant,
                @Value("${CLIENT_ID}") String clientId,
                @Value("${CLIENT_SECRET}") String secreto) {
        this.rest = RestClient.builder().baseUrl(baseUrl).build();
        this.clave = clave;
        this.credencial = new ClientSecretCredentialBuilder()
                .tenantId(tenant).clientId(clientId).clientSecret(secreto).build();   // mejor: certificado o identidad administrada
    }

    String pedido(String id) {
        for (int intento = 1; ; intento++) {
            try {
                String token = credencial
                        .getTokenSync(new TokenRequestContext().addScopes("api://modalima-pedidos/.default"))
                        .getToken();
                return rest.get().uri("/pedidos/{id}", id)
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + token)
                        .header("Ocp-Apim-Subscription-Key", clave)
                        .retrieve()
                        .body(String.class);
            } catch (HttpClientErrorException.TooManyRequests e) {
                if (intento >= 3) {
                    throw e;
                }
                dormir(segundos(e.getResponseHeaders()));
            }
        }
    }

    private static long segundos(HttpHeaders cabeceras) {
        String valor = cabeceras == null ? null : cabeceras.getFirst("Retry-After");
        try {
            return valor == null ? 1 : Math.min(Long.parseLong(valor.trim()), 30);
        } catch (NumberFormatException ex) {
            return 1;
        }
    }

    private static void dormir(long segundos) {
        try {
            Thread.sleep(segundos * 1000);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrumpido durante la espera de Retry-After", ie);
        }
    }
}
```
> `ClientSecretCredential` sirve para estudiar. En producción: **identidad administrada** o **certificado** ([Workload Identity](../../02-iam/workload-identity/README.md)); nunca secretos en el código.

### Reactivo (WebClient) respetando `Retry-After`
```java
import org.springframework.http.HttpHeaders;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;

class ClienteApimReactivo {

    private final WebClient web;

    ClienteApimReactivo(WebClient.Builder builder, String baseUrl, String clave) {
        this.web = builder.baseUrl(baseUrl).defaultHeader("Ocp-Apim-Subscription-Key", clave).build();
    }

    Mono<String> pedido(String id, String token) {
        return web.get().uri("/pedidos/{id}", id)
                .headers(h -> h.setBearerAuth(token))
                .retrieve()
                .bodyToMono(String.class)
                .retryWhen(Retry.from(senales -> senales.flatMap(s -> {
                    Throwable fallo = s.failure();
                    if (fallo instanceof WebClientResponseException.TooManyRequests e && s.totalRetries() < 3) {
                        return Mono.delay(Duration.ofSeconds(segundos(e.getHeaders()))).thenReturn(s.totalRetries());
                    }
                    return Mono.error(fallo);
                })));
    }

    private static long segundos(HttpHeaders cabeceras) {
        String valor = cabeceras.getFirst("Retry-After");
        try {
            return valor == null ? 1 : Math.min(Long.parseLong(valor.trim()), 30);
        } catch (NumberFormatException ex) {
            return 1;
        }
    }
}
```

## 7. Publicar el contrato (OpenAPI) para importarlo en APIM

| Framework | Cómo | Ruta del documento |
|---|---|---|
| Spring Boot | Dependencia `springdoc-openapi-starter-webmvc-api` (o `-webflux-api`); *verifica la versión compatible con tu Spring Boot* | `/v3/api-docs` |
| Quarkus | Extensión `quarkus-smallrye-openapi` | `/q/openapi` |

Flujo recomendado: el pipeline genera el JSON → `az apim api import` ([CLI](ejemplos/cli/apim.sh)) → APIM conserva el contrato como fuente de verdad. Añade en `servers` la URL **de APIM**, no la del pod.

## 8. Imperativo vs reactivo detrás de APIM

| | Imperativo (MVC / Quarkus clásico) | Reactivo (WebFlux / Quarkus REST + Mutiny) |
|---|---|---|
| APIM | No distingue | No distingue |
| Concurrencia alta con backends lentos | Hilos virtuales (`spring.threads.virtual.enabled=true`) o más hilos | Pocos hilos, sin bloquear |
| Validación de JWT | `JwtDecoder` | `ReactiveJwtDecoder` |
| Propagar correlación | MDC | Contexto de Reactor / Micrometer |
| Cuándo | Equipo y librerías bloqueantes (JDBC) | I/O intensivo, streaming, muchos clientes lentos |

## 9. Qué NO hacer en el código
- Confiar en que "si llegó, viene de APIM": valida audiencia, emisor y roles.
- Devolver `500` con trazas al consumidor: APIM las reenviaría tal cual.
- Reintentar `POST` sin idempotencia.
- Poner la clave de suscripción en el código o en el repositorio.
- Ignorar `Retry-After` y reintentar en bucle apretado.
- Aceptar tráfico directo al microservicio saltándote APIM (cierra la red con NetworkPolicy/NSG).
