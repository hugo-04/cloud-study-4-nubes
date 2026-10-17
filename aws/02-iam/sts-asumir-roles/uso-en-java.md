# AWS · STS y asumir roles · Uso desde Java

Caso típico de ModaLima: el servicio de **reportes** (cuenta A) debe leer los logs de cada **cliente corporativo** (cuentas B, C, D…) asumiendo un rol en cada una, con un **ExternalId** distinto por cliente. Lo importante en Java: **asumir una vez y reutilizar**, validar entradas con funciones puras y no mezclar identidades. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. La pieza clave: `StsAssumeRoleCredentialsProvider`
Pide el rol, **guarda las credenciales y las refresca solo** (en segundo plano) antes de que caduquen. Nunca llames a `AssumeRole` por petición.
```java
import java.time.Duration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.auth.StsAssumeRoleCredentialsProvider;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;

class EjemploMinimo {
    S3Client s3DelCliente(StsClient sts, String rolArn, String externalId) {
        StsAssumeRoleCredentialsProvider proveedor = StsAssumeRoleCredentialsProvider.builder()
                .stsClient(sts)
                .refreshRequest(AssumeRoleRequest.builder()
                        .roleArn(rolArn)
                        .roleSessionName("reportes-cafe-andino")
                        .externalId(externalId)
                        .durationSeconds(3600)
                        .build())
                .staleTime(Duration.ofMinutes(1))                // se considera vieja 1 min antes de vencer
                .prefetchTime(Duration.ofMinutes(5))             // empieza a refrescar 5 min antes
                .asyncCredentialUpdateEnabled(true)              // refresco en segundo plano
                .build();
        return S3Client.builder().region(Region.US_EAST_1).credentialsProvider(proveedor).build();
    }
}
```

## 2. Fábrica con caché, validación y ExternalId derivado

### Núcleo común
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.auth.StsAssumeRoleCredentialsProvider;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;

record RolArn(String cuenta, String nombre) {}

final class Roles {
    private Roles() {}

    private static final Pattern ARN = Pattern.compile("^arn:aws[a-z-]*:iam::(\\d{12}):role/([\\w+=,.@/-]{1,512})$");

    /** Valida y descompone un ARN de rol. Lanza IllegalArgumentException si no es válido. */
    static RolArn parse(String arn) {
        Matcher m = arn == null ? null : ARN.matcher(arn);
        if (m == null || !m.matches()) throw new IllegalArgumentException("ARN de rol inválido: " + arn);
        return new RolArn(m.group(1), m.group(2));
    }

    /** RoleSessionName: 2-64 caracteres de [\w+=,.@-]. Se ve en CloudTrail, así que debe ser informativo. */
    static String nombreDeSesion(String prefijo, String tenant) {
        String limpio = (prefijo + "-" + tenant).replaceAll("[^\\w+=,.@-]", "_");
        return limpio.length() > 64 ? limpio.substring(0, 64) : limpio.length() < 2 ? limpio + "_x" : limpio;
    }

    /** ExternalId único por cliente y NO adivinable: HMAC-SHA256(secreto de la plataforma, tenant). */
    static String externalId(String secretoPlataforma, String tenant) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secretoPlataforma.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(tenant.getBytes(StandardCharsets.UTF_8)));
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    /** "cafe-andino=arn:aws:iam::444455556666:role/lector-logs;otro=arn:..." -> mapa validado. */
    static Map<String, String> catalogo(String texto) {
        Map<String, String> r = new HashMap<>();
        if (texto == null || texto.isBlank()) return r;
        for (String par : texto.split(";")) {
            String[] kv = par.trim().split("=", 2);
            if (kv.length != 2 || kv[0].isBlank()) throw new IllegalArgumentException("Par inválido: " + par);
            parse(kv[1].trim());                                  // valida el ARN
            r.put(kv[0].trim(), kv[1].trim());
        }
        return r;
    }
}

/** Un S3Client por cliente, con credenciales asumidas y refrescadas automáticamente. */
final class ClientesPorTenant implements AutoCloseable {
    private final StsClient sts;
    private final Map<String, String> roles;
    private final String secreto;
    private final Map<String, S3Client> s3 = new ConcurrentHashMap<>();
    private final Map<String, StsAssumeRoleCredentialsProvider> proveedores = new ConcurrentHashMap<>();

    ClientesPorTenant(StsClient sts, Map<String, String> roles, String secretoPlataforma) {
        this.sts = sts;
        this.roles = roles;
        this.secreto = secretoPlataforma;
    }

    S3Client s3(String tenant) {
        String rol = roles.get(tenant);
        if (rol == null) throw new IllegalArgumentException("Cliente desconocido: " + tenant);   // jamás aceptes un ARN de la petición
        return s3.computeIfAbsent(tenant, t -> {
            StsAssumeRoleCredentialsProvider p = StsAssumeRoleCredentialsProvider.builder()
                    .stsClient(sts)
                    .refreshRequest(AssumeRoleRequest.builder()
                            .roleArn(rol)
                            .roleSessionName(Roles.nombreDeSesion("reportes", t))
                            .externalId(Roles.externalId(secreto, t))
                            .durationSeconds(3600)
                            .build())
                    .asyncCredentialUpdateEnabled(true)
                    .build();
            proveedores.put(t, p);
            return S3Client.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")))
                    .credentialsProvider(p).build();
        });
    }

    List<String> claves(String tenant, String bucket, String prefijo, int max) {
        return s3(tenant).listObjectsV2(ListObjectsV2Request.builder().bucket(bucket).prefix(prefijo).maxKeys(max).build())
                .contents().stream().map(o -> o.key()).toList();
    }

    @Override
    public void close() {
        s3.values().forEach(S3Client::close);
        proveedores.values().forEach(StsAssumeRoleCredentialsProvider::close);
    }
}
```

### Spring MVC (imperativo)
```java
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.ExceptionHandler;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sts.StsClient;

@Configuration
class CrossAccountConfig {
    @Bean(destroyMethod = "close")
    StsClient sts() {
        // STS regional (no el endpoint global)
        return StsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean(destroyMethod = "close")
    ClientesPorTenant clientes(StsClient sts, @Value("${reportes.roles:}") String roles, @Value("${reportes.secreto:cambiar}") String secreto) {
        return new ClientesPorTenant(sts, Roles.catalogo(roles), secreto);
    }
}

@RestController
public class LogsClienteController {
    private final ClientesPorTenant clientes;

    LogsClienteController(ClientesPorTenant clientes) { this.clientes = clientes; }

    @GetMapping("/clientes/{tenant}/logs")
    List<String> logs(@PathVariable String tenant, @RequestParam String bucket, @RequestParam(defaultValue = "") String prefijo) {
        return clientes.claves(tenant, bucket, prefijo, 20);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    String desconocido(IllegalArgumentException e) { return e.getMessage(); }
}
```
```properties
# application.properties (el secreto viene de Secrets Manager o del entorno, nunca del repositorio)
reportes.roles=cafe-andino=arn:aws:iam::444455556666:role/lector-logs;moda-sur=arn:aws:iam::777788889999:role/lector-logs
reportes.secreto=${REPORTES_SECRETO}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
public class LogsClienteReactivoController {
    private final ClientesPorTenant clientes;

    LogsClienteReactivoController(ClientesPorTenant clientes) { this.clientes = clientes; }

    @GetMapping("/reactivo/clientes/{tenant}/logs")
    Mono<List<String>> logs(@PathVariable String tenant, @RequestParam String bucket, @RequestParam(defaultValue = "") String prefijo) {
        return Mono.fromCallable(() -> clientes.claves(tenant, bucket, prefijo, 20))
                .subscribeOn(Schedulers.boundedElastic());     // S3Client síncrono: fuera del bucle de eventos
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sts.StsClient;

@ApplicationScoped
class CrossAccountProductores {
    @ConfigProperty(name = "reportes.roles", defaultValue = "")
    String roles;
    @ConfigProperty(name = "reportes.secreto", defaultValue = "cambiar")
    String secreto;

    @Produces
    @ApplicationScoped
    StsClient sts() {
        return StsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Produces
    @ApplicationScoped
    ClientesPorTenant clientes(StsClient sts) {
        return new ClientesPorTenant(sts, Roles.catalogo(roles), secreto);
    }
}

@Path("/clientes/{tenant}/logs")
public class LogsClienteResource {
    @Inject
    ClientesPorTenant clientes;

    @GET
    public List<String> logs(@PathParam("tenant") String tenant, @QueryParam("bucket") String bucket, @QueryParam("prefijo") String prefijo) {
        return clientes.claves(tenant, bucket, prefijo == null ? "" : prefijo, 20);
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/clientes/{tenant}/logs")
public class LogsClienteReactivoResource {
    @Inject
    ClientesPorTenant clientes;

    @GET
    public Uni<List<String>> logs(@PathParam("tenant") String tenant, @QueryParam("bucket") String bucket) {
        return Uni.createFrom().item(() -> clientes.claves(tenant, bucket, "", 20))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 3. Reglas de oro en Java
- **Un proveedor por rol** (no por petición) y se **cierra** al apagar la aplicación.
- **Jamás** aceptes un ARN de rol del cliente en la petición: busca el rol en un **catálogo** tuyo.
- El **ExternalId** lo genera la plataforma (HMAC con un secreto de Secrets Manager); el cliente solo lo copia en la confianza de su rol.
- `RoleSessionName` informativo (cliente + servicio): es tu rastro en CloudTrail.
- STS **regional**; el cliente de STS vive tanto como la aplicación.
- Si el cliente cambia su rol, el proveedor falla al refrescar: captura el error, reporta y reintenta con *backoff*.

## 4. Qué NO hacer desde Java
- No llamar a `assumeRole` a mano en cada petición.
- No guardar credenciales temporales en disco, en caché compartida ni en logs.
- No reutilizar un `S3Client` de un cliente para otro (mezcla identidades).
