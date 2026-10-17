# AWS · CloudFront y WAF · Uso desde Java

Cuatro tareas típicas de una aplicación Java con CloudFront delante: **(1)** emitir **URLs firmadas** para contenido privado, **(2)** **aceptar solo tráfico que pasó por CloudFront** (cabecera secreta, con rotación), **(3)** **invalidar** rutas por lotes y **(4)** poner el `Cache-Control` correcto a cada respuesta. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Núcleo común

La parte con reglas es **pura** (se prueba sin AWS); la firma usa las utilidades oficiales del SDK (`CloudFrontUtilities`).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import software.amazon.awssdk.services.cloudfront.CloudFrontClient;
import software.amazon.awssdk.services.cloudfront.CloudFrontUtilities;
import software.amazon.awssdk.services.cloudfront.model.CreateInvalidationRequest;
import software.amazon.awssdk.services.cloudfront.model.InvalidationBatch;
import software.amazon.awssdk.services.cloudfront.model.Paths;

/** Emite URLs firmadas de vida corta, con política de qué rutas y cuánto tiempo se permiten. */
final class FirmadorUrls {
    private final String dominio;
    private final String prefijoPermitido;
    private final String keyPairId;
    private final PrivateKey clave;
    private final Duration vidaMaxima;
    private final Clock reloj;

    FirmadorUrls(String dominio, String prefijoPermitido, String keyPairId, PrivateKey clave,
                 Duration vidaMaxima, Clock reloj) {
        this.dominio = dominio;
        this.prefijoPermitido = prefijoPermitido;
        this.keyPairId = keyPairId;
        this.clave = clave;
        this.vidaMaxima = vidaMaxima;
        this.reloj = reloj;
    }

    /** Lee una clave RSA en PKCS#8 (convierte con: openssl pkcs8 -topk8 -nocrypt -in privada.pem). */
    static PrivateKey leerPkcs8(String pem) {
        try {
            String base64 = pem.replaceAll("-----(BEGIN|END) PRIVATE KEY-----", "").replaceAll("\\s", "");
            return KeyFactory.getInstance("RSA")
                    .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64)));
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new IllegalArgumentException("Clave privada ilegible: se espera RSA en formato PKCS#8", e);
        }
    }

    /** Reglas puras de qué se puede firmar. */
    void validar(String ruta, Duration vida) {
        if (ruta == null || !ruta.startsWith("/")) throw new IllegalArgumentException("La ruta debe empezar con '/'");
        if (ruta.contains("..") || ruta.contains("?") || ruta.contains("#") || ruta.contains("\\")) {
            throw new IllegalArgumentException("Ruta no permitida");
        }
        if (!ruta.startsWith(prefijoPermitido)) {
            throw new IllegalArgumentException("Solo se firman rutas bajo " + prefijoPermitido);
        }
        if (vida.isZero() || vida.isNegative() || vida.compareTo(vidaMaxima) > 0) {
            throw new IllegalArgumentException("La vida debe estar entre 1 s y " + vidaMaxima.toMinutes() + " min");
        }
    }

    String firmar(String ruta, Duration vida) {
        validar(ruta, vida);
        String recurso = "https://" + dominio + ruta;
        return CloudFrontUtilities.create().getSignedUrlWithCannedPolicy(r -> r
                .resourceUrl(recurso).privateKey(clave).keyPairId(keyPairId)
                .expirationDate(reloj.instant().plus(vida))).url();
    }
}

/** Acepta solo peticiones que traen la cabecera secreta (dos valores válidos a la vez para poder rotar). */
final class VerificadorOrigen {
    private final List<byte[]> validos;

    VerificadorOrigen(List<String> secretos) {
        this.validos = secretos.stream().filter(s -> s != null && !s.isBlank())
                .map(s -> s.getBytes(StandardCharsets.UTF_8)).toList();
    }

    /** Sin secretos configurados NO permite nada (falla cerrado). Comparación en tiempo constante. */
    boolean permite(String cabecera) {
        if (cabecera == null) return false;
        byte[] recibido = cabecera.getBytes(StandardCharsets.UTF_8);
        boolean ok = false;
        for (byte[] v : validos) {
            ok |= MessageDigest.isEqual(v, recibido);      // sin cortocircuito
        }
        return ok;
    }
}

final class Invalidaciones {
    private static final Pattern PROHIBIDO = Pattern.compile("(\\.\\.|\\s)");

    private final CloudFrontClient cloudfront;

    Invalidaciones(CloudFrontClient cloudfront) {
        this.cloudfront = cloudfront;
    }

    static String normalizar(String ruta) {
        String p = ruta.trim();
        if (p.isEmpty() || PROHIBIDO.matcher(p).find()) throw new IllegalArgumentException("Ruta inválida: " + ruta);
        return p.startsWith("/") ? p : "/" + p;
    }

    /** Normaliza, quita duplicados y reparte en lotes (cada solicitud admite un máximo de rutas; verifica el límite vigente). */
    static List<List<String>> lotes(Collection<String> rutas, int maxPorLote) {
        Set<String> unicas = new LinkedHashSet<>();
        rutas.forEach(r -> unicas.add(normalizar(r)));
        List<String> todas = new ArrayList<>(unicas);
        List<List<String>> r = new ArrayList<>();
        for (int i = 0; i < todas.size(); i += maxPorLote) {
            r.add(todas.subList(i, Math.min(i + maxPorLote, todas.size())));
        }
        return r;
    }

    /** Devuelve los ids de invalidación creados. Para un despliegue, invalida SOLO lo que apunta a lo versionado. */
    List<String> invalidar(String distribucionId, Collection<String> rutas) {
        List<String> ids = new ArrayList<>();
        for (List<String> lote : lotes(rutas, 1000)) {
            var r = cloudfront.createInvalidation(CreateInvalidationRequest.builder()
                    .distributionId(distribucionId)
                    .invalidationBatch(InvalidationBatch.builder()
                            .paths(Paths.builder().items(lote).quantity(lote.size()).build())
                            .callerReference(UUID.randomUUID().toString())
                            .build())
                    .build());
            ids.add(r.invalidation().id());
        }
        return ids;
    }
}

final class CacheControlPorTipo {
    private static final Pattern CON_HASH = Pattern.compile(".*[.-][0-9a-f]{6,}\\.(js|css|woff2?|png|jpg|jpeg|webp|svg)$");

    private CacheControlPorTipo() {}

    /** Cabecera Cache-Control recomendada. Lo privado nunca se comparte en la CDN. */
    static String para(String archivo, boolean privado) {
        if (privado) return "private, no-store";
        String f = archivo.toLowerCase();
        if (CON_HASH.matcher(f).matches()) return "public, max-age=31536000, immutable";
        if (f.endsWith(".html") || f.equals("/") || f.endsWith("/config.json")) return "no-cache";
        if (f.matches(".*\\.(png|jpg|jpeg|webp|svg|ico|woff2?)$")) return "public, max-age=86400";
        return "public, max-age=300";
    }
}
```

## 2. Spring MVC (imperativo)
Descarga autorizada: el servicio comprueba que el usuario **es dueño** del recurso y responde con una redirección a la URL firmada. Un filtro exige la cabecera secreta que añade CloudFront.
```java
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URI;
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.filter.OncePerRequestFilter;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cloudfront.CloudFrontClient;

@Configuration
class CloudFrontConfig {
    @Bean(destroyMethod = "close")
    CloudFrontClient cloudfront() {
        return CloudFrontClient.builder().region(Region.AWS_GLOBAL).build();   // CloudFront es un servicio global
    }

    @Bean
    FirmadorUrls firmador(@Value("${cf.dominio}") String dominio, @Value("${cf.key-pair-id}") String keyPairId,
                          @Value("${cf.clave-pem}") String pem) {   // el PEM viene de Secrets Manager, no del repositorio
        return new FirmadorUrls(dominio, "/privado/", keyPairId, FirmadorUrls.leerPkcs8(pem),
                Duration.ofMinutes(15), Clock.systemUTC());
    }

    @Bean
    VerificadorOrigen verificadorOrigen(@Value("${cf.secreto-origen:}") String actual,
                                        @Value("${cf.secreto-origen-anterior:}") String anterior) {
        return new VerificadorOrigen(List.of(actual, anterior));
    }

    @Bean
    Invalidaciones invalidaciones(CloudFrontClient cf) {
        return new Invalidaciones(cf);
    }
}

@Component
class FiltroOrigen extends OncePerRequestFilter {
    private final VerificadorOrigen verificador;

    FiltroOrigen(VerificadorOrigen verificador) {
        this.verificador = verificador;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        return req.getRequestURI().startsWith("/actuator/health");     // el ALB comprueba la salud sin la cabecera
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain cadena)
            throws ServletException, IOException {
        if (!verificador.permite(req.getHeader("X-Origin-Verify"))) {
            res.sendError(HttpServletResponse.SC_FORBIDDEN);
            return;
        }
        cadena.doFilter(req, res);
    }
}

@RestController
class DescargasController {
    private final FirmadorUrls firmador;

    DescargasController(FirmadorUrls firmador) {
        this.firmador = firmador;
    }

    @GetMapping("/api/facturas/{id}/pdf")
    ResponseEntity<Void> descargar(@PathVariable String id) {
        // 1) Autorización: ¿la factura pertenece al usuario autenticado? (omitido: depende de tu dominio)
        // 2) Redirección a una URL firmada de vida corta
        String url = firmador.firmar("/privado/facturas/" + id + ".pdf", Duration.ofMinutes(10));
        return ResponseEntity.status(302).location(URI.create(url))
                .header("Cache-Control", CacheControlPorTipo.para(id, true)).build();
    }
}
```

## 3. Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
class FiltroOrigenReactivo implements WebFilter {
    private final VerificadorOrigen verificador;

    FiltroOrigenReactivo(@Value("${cf.secreto-origen:}") String actual,
                         @Value("${cf.secreto-origen-anterior:}") String anterior) {
        this.verificador = new VerificadorOrigen(List.of(actual, anterior));
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain cadena) {
        if (exchange.getRequest().getPath().value().startsWith("/actuator/health")) {
            return cadena.filter(exchange);
        }
        if (!verificador.permite(exchange.getRequest().getHeaders().getFirst("X-Origin-Verify"))) {
            exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN);
            return exchange.getResponse().setComplete();
        }
        return cadena.filter(exchange);
    }
}
```

## 4. Quarkus (imperativo)
```java
import jakarta.annotation.Priority;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import java.net.URI;
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cloudfront.CloudFrontClient;

@Singleton
class CloudFrontProductores {
    @Produces
    @Singleton
    CloudFrontClient cloudfront() {
        return CloudFrontClient.builder().region(Region.AWS_GLOBAL).build();
    }

    void cerrar(@Disposes CloudFrontClient cf) {
        cf.close();
    }

    @Produces
    @Singleton
    FirmadorUrls firmador(@ConfigProperty(name = "cf.dominio") String dominio,
                          @ConfigProperty(name = "cf.key-pair-id") String keyPairId,
                          @ConfigProperty(name = "cf.clave-pem") String pem) {
        return new FirmadorUrls(dominio, "/privado/", keyPairId, FirmadorUrls.leerPkcs8(pem),
                Duration.ofMinutes(15), Clock.systemUTC());
    }

    @Produces
    @Singleton
    VerificadorOrigen verificador(@ConfigProperty(name = "cf.secreto-origen", defaultValue = "") String actual,
                                  @ConfigProperty(name = "cf.secreto-origen-anterior", defaultValue = "") String anterior) {
        return new VerificadorOrigen(List.of(actual, anterior));
    }
}

@Provider
@Priority(Priorities.AUTHENTICATION)
class FiltroOrigenQuarkus implements ContainerRequestFilter {
    @Inject
    VerificadorOrigen verificador;

    @Override
    public void filter(ContainerRequestContext ctx) {
        if (ctx.getUriInfo().getPath().startsWith("q/health")) return;
        if (!verificador.permite(ctx.getHeaderString("X-Origin-Verify"))) {
            ctx.abortWith(Response.status(Response.Status.FORBIDDEN).build());
        }
    }
}

@Path("/api/facturas")
class DescargasRecurso {
    @Inject
    FirmadorUrls firmador;

    @GET
    @Path("/{id}/pdf")
    public Response descargar(@PathParam("id") String id) {
        String url = firmador.firmar("/privado/facturas/" + id + ".pdf", Duration.ofMinutes(10));
        return Response.temporaryRedirect(URI.create(url)).header("Cache-Control", "private, no-store").build();
    }
}
```

## 5. Quarkus reactivo (Mutiny): invalidar sin bloquear
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/interno/cdn")
class CdnReactivoRecurso {
    @Inject
    Invalidaciones invalidaciones;

    @POST
    @Path("/invalidar")
    @jakarta.ws.rs.Consumes("application/json")
    @jakarta.ws.rs.Produces("application/json")
    Uni<List<String>> invalidar(List<String> rutas) {
        return Uni.createFrom().item(() -> invalidaciones.invalidar("E123ABCDEF4567", rutas))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 6. Permisos
- Firmar URLs es **local**: solo necesita la clave privada (de Secrets Manager); no llama a AWS.
- Invalidar: `cloudfront:CreateInvalidation` sobre esa distribución, nada más.
- La **clave pública** vive en un grupo de claves de confianza de CloudFront (se administra con Terraform).

## 7. Qué NO hacer desde Java
- ❌ Firmar rutas arbitrarias que llegan del cliente sin comprobar prefijo, `..` y propiedad del recurso.
- ❌ URLs firmadas de horas o días: 10–15 minutos para descargas.
- ❌ Dejar la clave privada en el repositorio o en variables de entorno visibles: Secrets Manager con permisos mínimos.
- ❌ Comparar el secreto de origen con `equals` (filtra tiempo de respuesta) o dejar la ruta de salud sin excepción (el ALB no envía la cabecera).
- ❌ Invalidar `/*` en cada despliegue: versiona los archivos e invalida solo el punto de entrada.
- ❌ Poner `Cache-Control: public` a respuestas con datos del usuario.
