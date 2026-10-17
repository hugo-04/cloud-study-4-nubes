# AWS · API Gateway · Uso desde Java

Tres escenarios: **(1)** una **función Lambda** detrás de HTTP API (con un enrutador puro, fácil de probar), **(2)** un **servicio Spring/Quarkus** detrás de un VPC Link que **vuelve a validar el JWT** (defensa en profundidad) y **(3)** un **cliente Java que llama a una API protegida con IAM** firmando con SigV4. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56), `aws-lambda-java-events` 3.16.

## 1. Núcleo común: enrutador, JSON mínimo, scopes y firma SigV4

El enrutador y los scopes son **puros**; el cliente SigV4 usa el firmador oficial del SDK.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.http.ContentStreamProvider;
import software.amazon.awssdk.http.SdkHttpMethod;
import software.amazon.awssdk.http.SdkHttpRequest;
import software.amazon.awssdk.http.auth.aws.signer.AwsV4HttpSigner;
import software.amazon.awssdk.http.auth.spi.signer.SignedRequest;

record Solicitud(String metodo, String ruta, Map<String, String> parametros, Map<String, String> claims, String cuerpo) {}

record Respuesta(int estado, Map<String, String> cabeceras, String cuerpo) {
    static Respuesta json(int estado, String cuerpo) {
        return new Respuesta(estado, Map.of("content-type", "application/json"), cuerpo);
    }
}

@FunctionalInterface
interface Controlador {
    Respuesta atender(Solicitud solicitud) throws Exception;
}

/** Enrutador mínimo: "GET /catalogo/{id}". Distingue 404 (ruta) de 405 (método). */
final class Enrutador {
    private record Ruta(String metodo, String[] segmentos, Controlador controlador) {}

    private final List<Ruta> rutas = new ArrayList<>();

    Enrutador registrar(String metodo, String plantilla, Controlador c) {
        rutas.add(new Ruta(metodo, partir(plantilla), c));
        return this;
    }

    Respuesta despachar(String metodo, String ruta, Map<String, String> claims, String cuerpo) {
        String[] real = partir(ruta);
        Set<String> permitidos = new java.util.TreeSet<>();
        for (Ruta r : rutas) {
            Map<String, String> params = coincide(r.segmentos(), real);
            if (params == null) continue;
            if (!r.metodo().equals(metodo)) {
                permitidos.add(r.metodo());
                continue;
            }
            try {
                return r.controlador().atender(new Solicitud(metodo, ruta, params, claims, cuerpo));
            } catch (IllegalArgumentException e) {
                return Respuesta.json(400, MiniJson.objeto(Map.of("error", String.valueOf(e.getMessage()))));
            } catch (Exception e) {
                return Respuesta.json(500, MiniJson.objeto(Map.of("error", "error interno")));   // sin detalles al cliente
            }
        }
        if (!permitidos.isEmpty()) {
            return new Respuesta(405, Map.of("allow", String.join(", ", permitidos), "content-type", "application/json"),
                    MiniJson.objeto(Map.of("error", "método no permitido")));
        }
        return Respuesta.json(404, MiniJson.objeto(Map.of("error", "ruta no encontrada")));
    }

    private static String[] partir(String ruta) {
        String limpia = ruta.startsWith("/") ? ruta.substring(1) : ruta;
        return limpia.isEmpty() ? new String[0] : limpia.split("/");
    }

    private static Map<String, String> coincide(String[] plantilla, String[] real) {
        if (plantilla.length != real.length) return null;
        Map<String, String> params = new HashMap<>();
        for (int i = 0; i < plantilla.length; i++) {
            String p = plantilla[i];
            if (p.startsWith("{") && p.endsWith("}")) {
                params.put(p.substring(1, p.length() - 1), real[i]);
            } else if (!p.equals(real[i])) {
                return null;
            }
        }
        return params;
    }
}

final class MiniJson {
    private MiniJson() {}

    static String escapar(String s) {
        StringBuilder sb = new StringBuilder();
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) sb.append(String.format("\\u%04x", (int) c));
                    else sb.append(c);
                }
            }
        }
        return sb.toString();
    }

    static String objeto(Map<String, ?> mapa) {
        StringBuilder sb = new StringBuilder("{");
        boolean primero = true;
        for (var e : new TreeMap<String, Object>(mapa).entrySet()) {   // claves ordenadas: salida determinista
            if (!primero) sb.append(',');
            primero = false;
            sb.append('"').append(escapar(e.getKey())).append("\":").append(valor(e.getValue()));
        }
        return sb.append('}').toString();
    }

    private static String valor(Object v) {
        if (v == null) return "null";
        if (v instanceof Number || v instanceof Boolean) return v.toString();
        if (v instanceof Map<?, ?> m) {
            Map<String, Object> copia = new TreeMap<>();
            m.forEach((k, x) -> copia.put(String.valueOf(k), x));
            return objeto(copia);
        }
        if (v instanceof Iterable<?> it) {
            List<String> partes = new ArrayList<>();
            it.forEach(x -> partes.add(valor(x)));
            return "[" + String.join(",", partes) + "]";
        }
        return "\"" + escapar(v.toString()) + "\"";
    }
}

final class Scopes {
    private Scopes() {}

    /** Cognito/OIDC usan "scope" (texto separado por espacios); otros emisores usan "scp". */
    static boolean tiene(Map<String, String> claims, String requerido) {
        String valor = claims.getOrDefault("scope", claims.getOrDefault("scp", ""));
        for (String s : valor.replace("[", "").replace("]", "").replace(",", " ").trim().split("\\s+")) {
            if (s.equals(requerido)) return true;
        }
        return false;
    }
}

/** Llama a una API protegida con IAM (authorizationType AWS_IAM) firmando con SigV4. */
final class ClienteSigV4 {
    private static final Set<String> RESTRINGIDAS = Set.of("host", "content-length", "connection", "expect", "upgrade");

    private final HttpClient http = HttpClient.newHttpClient();
    private final AwsCredentialsProvider credenciales = DefaultCredentialsProvider.builder().build();
    private final String region;

    ClienteSigV4(String region) {
        this.region = region;
    }

    HttpResponse<String> post(String url, String json) throws Exception {
        SdkHttpRequest base = SdkHttpRequest.builder().uri(URI.create(url)).method(SdkHttpMethod.POST)
                .putHeader("content-type", "application/json").build();
        SignedRequest firmado = AwsV4HttpSigner.create().sign(r -> r
                .identity(credenciales.resolveCredentials())
                .request(base)
                .payload(ContentStreamProvider.fromUtf8String(json))
                .putProperty(AwsV4HttpSigner.SERVICE_SIGNING_NAME, "execute-api")
                .putProperty(AwsV4HttpSigner.REGION_NAME, region));
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(url)).POST(HttpRequest.BodyPublishers.ofString(json));
        firmado.request().headers().forEach((nombre, valores) -> {
            if (!RESTRINGIDAS.contains(nombre.toLowerCase())) valores.forEach(v -> b.header(nombre, v));
        });
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString());
    }
}
```

## 2. Lambda detrás de HTTP API (Java puro)
El evento de HTTP API (payload 2.0) trae el método, la ruta y los **claims** del JWT. El enrutador se construye **una vez** (Init).
```java
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import java.util.Map;

public class CatalogoHandler implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {
    private static final Map<String, String> CATALOGO = Map.of("P-1", "Camisa de lino", "P-2", "Pantalón sastre");

    private static final Enrutador RUTAS = new Enrutador()
            .registrar("GET", "/catalogo/{id}", s -> {
                String nombre = CATALOGO.get(s.parametros().get("id"));
                return nombre == null
                        ? Respuesta.json(404, MiniJson.objeto(Map.of("error", "no existe")))
                        : Respuesta.json(200, MiniJson.objeto(Map.of("id", s.parametros().get("id"), "nombre", nombre)));
            });

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent evento, Context contexto) {
        var http = evento.getRequestContext().getHttp();
        // La ruta llega con la etapa ("/prod/catalogo/P-1") salvo en la etapa $default: la quitamos
        String ruta = evento.getRawPath().replaceFirst("^/" + evento.getRequestContext().getStage(), "");
        Map<String, String> claims = evento.getRequestContext().getAuthorizer() == null
                || evento.getRequestContext().getAuthorizer().getJwt() == null
                ? Map.of() : evento.getRequestContext().getAuthorizer().getJwt().getClaims();
        Respuesta r = RUTAS.despachar(http.getMethod(), ruta.isEmpty() ? "/" : ruta, claims, evento.getBody());
        return APIGatewayV2HTTPResponse.builder().withStatusCode(r.estado()).withHeaders(r.cabeceras())
                .withBody(r.cuerpo()).build();
    }
}
```

## 3. Spring MVC: el servicio vuelve a validar el JWT
Detrás del VPC Link el servicio **no confía** en que «ya pasó por el gateway»: es *resource server* y exige el *scope*.
```yaml
# application.yml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://auth.modalima.com/     # valida firma, emisor y expiración
```
```java
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class SeguridadConfig {
    @Bean
    SecurityFilterChain cadena(HttpSecurity http) throws Exception {
        return http
                .authorizeHttpRequests(a -> a
                        .requestMatchers("/actuator/health/**").permitAll()
                        .requestMatchers(HttpMethod.GET, "/pedidos/**").hasAuthority("SCOPE_pedidos.leer")
                        .anyRequest().denyAll())
                .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()))
                .build();
    }
}

@RestController
class PedidosController {
    @GetMapping("/pedidos/{id}")
    Map<String, Object> obtener(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
        return Map.of("id", id, "solicitante", jwt.getSubject());
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.web.server.SecurityWebFilterChain;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@Configuration
@EnableWebFluxSecurity
class SeguridadReactivaConfig {
    @Bean
    SecurityWebFilterChain cadena(ServerHttpSecurity http) {
        return http
                .authorizeExchange(a -> a
                        .pathMatchers("/actuator/health/**").permitAll()
                        .pathMatchers(HttpMethod.GET, "/pedidos/**").hasAuthority("SCOPE_pedidos.leer")
                        .anyExchange().denyAll())
                .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()))
                .build();
    }
}

@RestController
class PedidosReactivoController {
    @GetMapping("/pedidos/{id}")
    Mono<Map<String, Object>> obtener(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
        return Mono.just(Map.of("id", id, "solicitante", jwt.getSubject()));
    }
}
```

## 5. Quarkus (imperativo)
Extensión `quarkus-oidc` como servicio (`application-type=service`): valida firma, emisor, audiencia y expiración.
```properties
# application.properties
quarkus.oidc.auth-server-url=https://auth.modalima.com/
quarkus.oidc.application-type=service
quarkus.oidc.token.audience=api-tienda
```
```java
import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.ws.rs.ForbiddenException;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.Map;
import org.eclipse.microprofile.jwt.JsonWebToken;

@Path("/pedidos")
@Authenticated
class PedidosRecurso {
    @Inject
    JsonWebToken jwt;

    @GET
    @Path("/{id}")
    @jakarta.ws.rs.Produces("application/json")
    Map<String, Object> obtener(@PathParam("id") String id) {
        String scope = jwt.getClaim("scope");
        if (!Scopes.tiene(Map.of("scope", scope == null ? "" : scope), "pedidos.leer")) {
            throw new ForbiddenException("Falta el scope pedidos.leer");
        }
        return Map.of("id", id, "solicitante", jwt.getSubject());
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.quarkus.security.Authenticated;
import io.quarkus.security.identity.SecurityIdentity;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.Map;

@Path("/pedidos-reactivo")
@Authenticated
class PedidosReactivoRecurso {
    @Inject
    SecurityIdentity identidad;

    @GET
    @Path("/{id}")
    @jakarta.ws.rs.Produces("application/json")
    Uni<Map<String, Object>> obtener(@PathParam("id") String id) {
        return Uni.createFrom().item(Map.<String, Object>of("id", id, "solicitante", identidad.getPrincipal().getName()));
    }
}
```

## 7. Permisos
- El **cliente SigV4** necesita `execute-api:Invoke` sobre `arn:aws:execute-api:<región>:<cuenta>:<api-id>/<etapa>/<método>/<ruta>`.
- La función Lambda necesita únicamente lo que su negocio requiere; API Gateway la invoca con la **política de recurso** (`aws_lambda_permission`).
- El servicio detrás del VPC Link: el *security group* solo admite el del VPC Link.

## 8. Qué NO hacer desde Java
- ❌ Devolver trazas de excepción al cliente (el enrutador responde un `500` genérico y tú registras el detalle).
- ❌ Confiar solo en el gateway: valida el JWT en el servicio.
- ❌ Imprimir tokens, cabeceras `Authorization` o cuerpos en los logs.
- ❌ Construir el enrutador dentro de `handleRequest` (hazlo una vez, en Init).
- ❌ Firmar SigV4 a mano: usa el firmador oficial (`AwsV4HttpSigner`).
- ❌ Resolver las credenciales en cada llamada creando un proveedor nuevo: reutiliza `DefaultCredentialsProvider`.
