# AWS · URLs prefirmadas · Uso desde Java

El backend hace cuatro cosas: **decidir** qué se puede subir (tipo, tamaño, clave), **calcular una caducidad realista**, **firmar** (PUT/GET con `S3Presigner`; POST con política a mano) y **servir descargas** sin exponer la URL. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  cloud:
    aws:
      region:
        static: us-east-1
app:
  bucket: modalima-prod-subidas-111122223333-us-east-1
  max-bytes: 10485760        # 10 MiB
```
```properties
# Quarkus (application.properties)
quarkus.s3.aws.region=us-east-1
app.region=us-east-1
app.bucket=modalima-prod-subidas-111122223333-us-east-1
app.max-bytes=10485760
```
Credenciales: **rol del servicio**. Con un rol, la caducidad efectiva de la URL la limita la sesión (ver `ExpiracionEfectiva`).

## 2. Núcleo común

### 2.1 Qué se puede subir y con qué clave
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

public final class PoliticaSubida {
    public record Solicitud(String tenant, String nombreOriginal, String contentType, long tamano) {}

    public record Autorizacion(String clave, String contentType, long maxBytes) {}

    private static final Map<String, Set<String>> EXTENSIONES = Map.of(
            "image/png", Set.of("png"),
            "image/jpeg", Set.of("jpg", "jpeg"),
            "application/pdf", Set.of("pdf"),
            "text/csv", Set.of("csv"));
    private static final Pattern TENANT = Pattern.compile("[a-z0-9][a-z0-9-]{0,39}");
    private static final DateTimeFormatter FECHA = DateTimeFormatter.ofPattern("yyyy/MM/dd").withZone(ZoneOffset.UTC);

    private final long maxBytes;

    public PoliticaSubida(long maxBytes) {
        if (maxBytes <= 0) {
            throw new IllegalArgumentException("maxBytes debe ser positivo");
        }
        this.maxBytes = maxBytes;
    }

    /** Valida la solicitud y fija la clave. El cliente NUNCA decide la clave. */
    public Autorizacion evaluar(Solicitud s, Instant ahora, UUID id) {
        if (s.tenant() == null || !TENANT.matcher(s.tenant()).matches()) {
            throw new IllegalArgumentException("tenant inválido");
        }
        Set<String> permitidas = EXTENSIONES.get(s.contentType());
        if (permitidas == null) {
            throw new IllegalArgumentException("tipo no permitido: " + s.contentType());
        }
        if (s.tamano() < 1 || s.tamano() > maxBytes) {
            throw new IllegalArgumentException("tamaño fuera de rango (1.." + maxBytes + ")");
        }
        String nombre = s.nombreOriginal() == null ? "" : s.nombreOriginal();
        int punto = nombre.lastIndexOf('.');
        String ext = punto < 0 ? "" : nombre.substring(punto + 1).toLowerCase(Locale.ROOT);
        if (!permitidas.contains(ext)) {
            throw new IllegalArgumentException("la extensión '" + ext + "' no corresponde a " + s.contentType());
        }
        String clave = "uploads/" + s.tenant() + "/" + FECHA.format(ahora) + "/" + id + "." + ext;
        return new Autorizacion(clave, s.contentType(), maxBytes);
    }

    /** ¿La clave pertenece al tenant del usuario autenticado? Compruébalo siempre antes de firmar una descarga. */
    public static boolean pertenece(String tenant, String clave) {
        return tenant != null && TENANT.matcher(tenant).matches() && clave != null
                && clave.startsWith("uploads/" + tenant + "/") && !clave.contains("..");
    }
}
```

### 2.2 Caducidad efectiva
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;

public final class ExpiracionEfectiva {
    private static final Duration MAXIMA = Duration.ofDays(7);

    private ExpiracionEfectiva() {}

    /** El menor entre lo pedido, 7 días y lo que le queda a las credenciales (null = sin caducidad conocida). */
    public static Duration calcular(Duration pedida, Instant ahora, Instant expiranCredenciales) {
        if (pedida == null || pedida.compareTo(Duration.ofSeconds(1)) < 0) {
            throw new IllegalArgumentException("la caducidad pedida debe ser de al menos 1 s");
        }
        Duration d = pedida.compareTo(MAXIMA) > 0 ? MAXIMA : pedida;
        if (expiranCredenciales != null) {
            Duration resto = Duration.between(ahora, expiranCredenciales);
            if (resto.compareTo(Duration.ofSeconds(1)) < 0) {
                throw new IllegalStateException("las credenciales están por caducar: renueva antes de firmar");
            }
            if (resto.compareTo(d) < 0) {
                d = resto;
            }
        }
        return Duration.ofSeconds(d.toSeconds());
    }
}
```

### 2.3 Nombre de descarga seguro
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;

public final class NombreDescarga {
    private NombreDescarga() {}

    /** Quita rutas, comillas, saltos de línea y caracteres de control. Nunca devuelve vacío. */
    public static String limpiar(String nombre) {
        String n = nombre == null ? "" : nombre;
        n = n.substring(Math.max(n.lastIndexOf('/'), n.lastIndexOf('\\')) + 1);
        StringBuilder sb = new StringBuilder();
        for (char c : n.toCharArray()) {
            if (c < 0x20 || c == 0x7f || c == '"' || c == ';') {
                continue;
            }
            sb.append(c);
        }
        String r = sb.toString().strip();
        if (r.isEmpty() || r.equals(".") || r.equals("..")) {
            return "descarga";
        }
        return r.length() > 150 ? r.substring(0, 150) : r;
    }

    /** RFC 6266: filename ASCII de respaldo + filename* en UTF-8. */
    public static String contentDisposition(String nombre) {
        String limpio = limpiar(nombre);
        StringBuilder ascii = new StringBuilder();
        for (char c : limpio.toCharArray()) {
            ascii.append(c < 0x80 ? c : '_');
        }
        StringBuilder pct = new StringBuilder();
        for (byte b : limpio.getBytes(StandardCharsets.UTF_8)) {
            int v = b & 0xff;
            boolean seguro = (v >= 'a' && v <= 'z') || (v >= 'A' && v <= 'Z') || (v >= '0' && v <= '9')
                    || v == '.' || v == '-' || v == '_';
            if (seguro) {
                pct.append((char) v);
            } else {
                pct.append('%').append(String.format("%02X", v));
            }
        }
        return "attachment; filename=\"" + ascii + "\"; filename*=UTF-8''" + pct;
    }
}
```

### 2.4 POST prefirmado (el SDK no lo trae: se firma la política a mano)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class PostPolicyS3 {
    public record Formulario(String url, Map<String, String> campos) {}

    private static final DateTimeFormatter FECHA8 = DateTimeFormatter.ofPattern("yyyyMMdd").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter FECHA_HORA =
            DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter EXPIRACION =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC);

    private PostPolicyS3() {}

    static byte[] hmac(byte[] clave, String dato) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(clave, "HmacSHA256"));
            return mac.doFinal(dato.getBytes(StandardCharsets.UTF_8));
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Derivación de la clave de firma de SigV4: HMAC encadenado fecha → región → servicio → "aws4_request". */
    public static byte[] claveDeFirma(String secreto, String fecha8, String region, String servicio) {
        byte[] kDate = hmac(("AWS4" + secreto).getBytes(StandardCharsets.UTF_8), fecha8);
        byte[] kRegion = hmac(kDate, region);
        byte[] kService = hmac(kRegion, servicio);
        return hmac(kService, "aws4_request");
    }

    private static String esc(String s) {
        StringBuilder sb = new StringBuilder();
        for (char c : s.toCharArray()) {
            if (c == '"' || c == '\\') {
                sb.append('\\').append(c);
            } else if (c < 0x20) {
                sb.append(String.format("\\u%04x", (int) c));
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    public static Formulario generar(String accessKeyId, String secreto, String token, String region, String bucket,
                                     String clave, String contentType, long maxBytes, Instant ahora, Duration validez) {
        if (bucket.indexOf('.') >= 0) {
            throw new IllegalArgumentException("buckets con puntos rompen el certificado TLS de estilo virtual-host");
        }
        String fecha8 = FECHA8.format(ahora);
        String fechaHora = FECHA_HORA.format(ahora);
        String credencial = accessKeyId + "/" + fecha8 + "/" + region + "/s3/aws4_request";

        StringBuilder cond = new StringBuilder();
        cond.append("{\"bucket\":\"").append(esc(bucket)).append("\"},");
        cond.append("{\"key\":\"").append(esc(clave)).append("\"},");
        cond.append("[\"content-length-range\",1,").append(maxBytes).append("],");
        cond.append("{\"Content-Type\":\"").append(esc(contentType)).append("\"},");
        cond.append("{\"x-amz-algorithm\":\"AWS4-HMAC-SHA256\"},");
        cond.append("{\"x-amz-credential\":\"").append(esc(credencial)).append("\"},");
        cond.append("{\"x-amz-date\":\"").append(fechaHora).append("\"},");
        if (token != null) {
            cond.append("{\"x-amz-security-token\":\"").append(esc(token)).append("\"},");
        }
        cond.append("{\"success_action_status\":\"201\"}");
        String politica = "{\"expiration\":\"" + EXPIRACION.format(ahora.plus(validez)) + "\",\"conditions\":[" + cond + "]}";

        String politicaB64 = Base64.getEncoder().encodeToString(politica.getBytes(StandardCharsets.UTF_8));
        byte[] kFirma = claveDeFirma(secreto, fecha8, region, "s3");
        String firma = HexFormat.of().formatHex(hmac(kFirma, politicaB64));

        Map<String, String> campos = new LinkedHashMap<>();       // el campo "file" va siempre el último en el formulario
        campos.put("key", clave);
        campos.put("Content-Type", contentType);
        campos.put("x-amz-algorithm", "AWS4-HMAC-SHA256");
        campos.put("x-amz-credential", credencial);
        campos.put("x-amz-date", fechaHora);
        if (token != null) {
            campos.put("x-amz-security-token", token);
        }
        campos.put("success_action_status", "201");
        campos.put("policy", politicaB64);
        campos.put("x-amz-signature", firma);
        return new Formulario("https://" + bucket + ".s3." + region + ".amazonaws.com/", campos);
    }
}
```

### 2.5 Firmar con el SDK (PUT, GET y POST)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.AwsSessionCredentials;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;

public final class UrlsS3 {
    public record UrlFirmada(String clave, String url, String metodo, Map<String, List<String>> cabeceras, Instant expira) {}

    private final S3Presigner presigner;
    private final AwsCredentialsProvider credenciales;
    private final String region;
    private final String bucket;
    private final PoliticaSubida politica;

    public UrlsS3(S3Presigner presigner, AwsCredentialsProvider credenciales, String region, String bucket,
                  PoliticaSubida politica) {
        this.presigner = presigner;
        this.credenciales = credenciales;
        this.region = region;
        this.bucket = bucket;
        this.politica = politica;
    }

    private Duration validez(Duration pedida, Instant ahora) {
        AwsCredentials c = credenciales.resolveCredentials();       // puede hacer una llamada de red la primera vez
        return ExpiracionEfectiva.calcular(pedida, ahora, c.expirationTime().orElse(null));
    }

    /** PUT prefirmado: el cliente DEBE enviar las cabeceras devueltas tal cual (Content-Type incluido). */
    public UrlFirmada subida(PoliticaSubida.Solicitud solicitud, Duration pedida) {
        Instant ahora = Instant.now();
        PoliticaSubida.Autorizacion a = politica.evaluar(solicitud, ahora, UUID.randomUUID());
        PutObjectRequest put = PutObjectRequest.builder().bucket(bucket).key(a.clave())
                .contentType(a.contentType()).build();
        PresignedPutObjectRequest p = presigner.presignPutObject(
                r -> r.signatureDuration(validez(pedida, ahora)).putObjectRequest(put));
        return new UrlFirmada(a.clave(), p.url().toString(), "PUT", p.signedHeaders(), p.expiration());
    }

    /** GET prefirmado con nombre de descarga. Comprueba ANTES que la clave pertenece al usuario. */
    public UrlFirmada descarga(String tenant, String clave, String nombre, Duration pedida) {
        if (!PoliticaSubida.pertenece(tenant, clave)) {
            throw new SecurityException("la clave no pertenece al tenant");
        }
        Instant ahora = Instant.now();
        GetObjectRequest get = GetObjectRequest.builder().bucket(bucket).key(clave)
                .responseContentDisposition(NombreDescarga.contentDisposition(nombre)).build();
        PresignedGetObjectRequest p = presigner.presignGetObject(
                r -> r.signatureDuration(validez(pedida, ahora)).getObjectRequest(get));
        return new UrlFirmada(clave, p.url().toString(), "GET", p.signedHeaders(), p.expiration());
    }

    /** POST prefirmado con límite de tamaño real (content-length-range). */
    public PostPolicyS3.Formulario formulario(PoliticaSubida.Solicitud solicitud, Duration pedida) {
        Instant ahora = Instant.now();
        PoliticaSubida.Autorizacion a = politica.evaluar(solicitud, ahora, UUID.randomUUID());
        AwsCredentials c = credenciales.resolveCredentials();
        Duration v = ExpiracionEfectiva.calcular(pedida, ahora, c.expirationTime().orElse(null));
        String token = c instanceof AwsSessionCredentials sc ? sc.sessionToken() : null;
        return PostPolicyS3.generar(c.accessKeyId(), c.secretAccessKey(), token, region, bucket,
                a.clave(), a.contentType(), a.maxBytes(), ahora, v);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.net.URI;
import java.security.Principal;
import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

@Configuration
class PresignConfig {
    @Bean(destroyMethod = "close")
    DefaultCredentialsProvider credenciales() {
        return DefaultCredentialsProvider.builder().build();
    }

    @Bean(destroyMethod = "close")
    S3Presigner presigner(AwsCredentialsProvider credenciales, @Value("${spring.cloud.aws.region.static}") String region) {
        return S3Presigner.builder().region(Region.of(region)).credentialsProvider(credenciales).build();
    }

    @Bean
    UrlsS3 urls(S3Presigner presigner, AwsCredentialsProvider credenciales,
                @Value("${spring.cloud.aws.region.static}") String region, @Value("${app.bucket}") String bucket,
                @Value("${app.max-bytes}") long maxBytes) {
        return new UrlsS3(presigner, credenciales, region, bucket, new PoliticaSubida(maxBytes));
    }
}

record SolicitudDto(String nombre, String contentType, long tamano) {}

@RestController
class SubidasController {
    private final UrlsS3 urls;

    SubidasController(UrlsS3 urls) {
        this.urls = urls;
    }

    /** El tenant sale de la identidad autenticada (token), nunca del cuerpo de la petición. */
    @PostMapping("/uploads")
    UrlsS3.UrlFirmada solicitar(@RequestBody SolicitudDto dto, Principal usuario) {
        var s = new PoliticaSubida.Solicitud(usuario.getName(), dto.nombre(), dto.contentType(), dto.tamano());
        return urls.subida(s, Duration.ofMinutes(10));
    }

    @PostMapping("/uploads/formulario")
    PostPolicyS3.Formulario formulario(@RequestBody SolicitudDto dto, Principal usuario) {
        var s = new PoliticaSubida.Solicitud(usuario.getName(), dto.nombre(), dto.contentType(), dto.tamano());
        return urls.formulario(s, Duration.ofMinutes(10));
    }

    /** Redirige a una URL de 5 minutos: nunca se guarda ni se registra la URL firmada. */
    @GetMapping("/descargas")
    ResponseEntity<Void> descargar(@RequestParam String clave, @RequestParam(defaultValue = "descarga") String nombre,
                                   Principal usuario) {
        var firmada = urls.descarga(usuario.getName(), clave, nombre, Duration.ofMinutes(5));
        return ResponseEntity.status(HttpStatus.FOUND)
                .location(URI.create(firmada.url()))
                .header(HttpHeaders.CACHE_CONTROL, "no-store")
                .header("Referrer-Policy", "no-referrer")
                .build();
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> invalida(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(SecurityException.class)
    ResponseEntity<Void> prohibida() {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.security.Principal;
import java.time.Duration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

record SolicitudDto(String nombre, String contentType, long tamano) {}

@RestController
class SubidasReactivoController {
    private final UrlsS3 urls;

    SubidasReactivoController(UrlsS3 urls) {
        this.urls = urls;
    }

    /** Firmar es CPU, pero resolver credenciales puede bloquear (red): se aísla en boundedElastic. */
    @PostMapping("/uploads-r")
    Mono<UrlsS3.UrlFirmada> solicitar(@RequestBody Mono<SolicitudDto> cuerpo, Mono<Principal> usuario) {
        return Mono.zip(cuerpo, usuario)
                .flatMap(t -> Mono.fromCallable(() -> urls.subida(
                                new PoliticaSubida.Solicitud(t.getT2().getName(), t.getT1().nombre(),
                                        t.getT1().contentType(), t.getT1().tamano()),
                                Duration.ofMinutes(10)))
                        .subscribeOn(Schedulers.boundedElastic()));
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

@ApplicationScoped
class PresignProductores {
    @Produces
    @Singleton
    AwsCredentialsProvider credenciales() {
        return DefaultCredentialsProvider.builder().build();
    }

    @Produces
    @Singleton
    S3Presigner presigner(AwsCredentialsProvider credenciales, @ConfigProperty(name = "app.region") String region) {
        return S3Presigner.builder().region(Region.of(region)).credentialsProvider(credenciales).build();
    }

    void cerrar(@Disposes S3Presigner presigner) {
        presigner.close();
    }

    @Produces
    @Singleton
    UrlsS3 urls(S3Presigner presigner, AwsCredentialsProvider credenciales,
                @ConfigProperty(name = "app.region") String region, @ConfigProperty(name = "app.bucket") String bucket,
                @ConfigProperty(name = "app.max-bytes") long maxBytes) {
        return new UrlsS3(presigner, credenciales, region, bucket, new PoliticaSubida(maxBytes));
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.ForbiddenException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.SecurityContext;
import java.time.Duration;

@Path("/uploads")
class SubidasRecurso {
    public record SolicitudDto(String nombre, String contentType, long tamano) {}

    @Inject
    UrlsS3 urls;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public UrlsS3.UrlFirmada solicitar(SolicitudDto dto, @Context SecurityContext seguridad) {
        try {
            var s = new PoliticaSubida.Solicitud(seguridad.getUserPrincipal().getName(), dto.nombre(),
                    dto.contentType(), dto.tamano());
            return urls.subida(s, Duration.ofMinutes(10));
        } catch (IllegalArgumentException e) {
            throw new BadRequestException(e.getMessage());
        } catch (SecurityException e) {
            throw new ForbiddenException();
        }
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.SecurityContext;
import java.time.Duration;

@Path("/uploads-r")
class SubidasReactivoRecurso {
    public record SolicitudDto(String nombre, String contentType, long tamano) {}

    @Inject
    UrlsS3 urls;

    /** Resolver credenciales puede bloquear: se ejecuta en el pool de trabajadores, no en el hilo de eventos. */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<UrlsS3.UrlFirmada> solicitar(SolicitudDto dto, @Context SecurityContext seguridad) {
        String tenant = seguridad.getUserPrincipal().getName();
        return Uni.createFrom().item(() -> urls.subida(
                        new PoliticaSubida.Solicitud(tenant, dto.nombre(), dto.contentType(), dto.tamano()),
                        Duration.ofMinutes(10)))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 7. Permisos de la aplicación
Rol del backend: `s3:PutObject` y `s3:GetObject` sobre `bucket/uploads/*` y, con SSE-KMS, `kms:GenerateDataKey` + `kms:Decrypt` ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)). El rol del cliente final **no existe**: la URL lleva los permisos del firmante.

## 8. Qué NO hacer desde Java
- **No** dejes que el cliente decida la clave, el tipo ni el prefijo: `PoliticaSubida` los fija.
- **No** firmes una descarga sin comprobar que la clave es del usuario (`pertenece`).
- **No** registres ni persistas la URL firmada; registra quién, qué clave y cuándo.
- **No** pidas caducidades largas con roles: usa `ExpiracionEfectiva`.
- **No** uses el nombre del archivo del usuario sin pasarlo por `NombreDescarga`.
- **No** crees un `S3Presigner` por petición; uno por aplicación y `close()` al apagar.
- **No** confíes en el `Content-Type` ni en el tamaño declarado: valida el objeto tras subirlo.
