# AWS · S3 · Uso desde Java

Con S3 desde Java se resuelven cuatro cosas: **claves sanas**, **subidas grandes** (partes y reintentos), **integridad** (checksums) y **no pisarse** (escrituras condicionales). Versiones: Java 21, Spring Boot 4.1 (Spring Cloud AWS 4.2), Quarkus 3.40 (`quarkus-amazon-s3`), AWS SDK v2 (BOM 2.56).

## 1. Configuración

```yaml
# Spring Boot (application.yml)
spring:
  cloud:
    aws:
      region:
        static: us-east-1
      s3:
        path-style-access-enabled: false
app:
  bucket: modalima-prod-facturas-111122223333-us-east-1
  kms-key-arn: arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555
```
```properties
# Quarkus (application.properties)
quarkus.s3.aws.region=us-east-1
quarkus.s3.sync-client.type=url-connection        # o apache
app.bucket=modalima-prod-facturas-111122223333-us-east-1
app.kms-key-arn=arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555
```
Credenciales: **rol de IAM del servicio** (tarea de ECS, Pod Identity, rol de Lambda). Nunca claves en el código ni en el YAML.

## 2. Núcleo común

### 2.1 Claves de objeto seguras
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.UUID;
import java.util.regex.Pattern;

public final class ClaveObjeto {
    private static final DateTimeFormatter FECHA = DateTimeFormatter.ofPattern("yyyy/MM/dd").withZone(ZoneOffset.UTC);
    private static final Pattern TENANT = Pattern.compile("[a-z0-9][a-z0-9-]{0,39}");
    private static final Pattern EXTENSION = Pattern.compile("[a-z0-9]{1,8}");

    private ClaveObjeto() {}

    /** Rechaza claves que causan problemas: vacías, largas, con "..", "//", barras invertidas o caracteres de control. */
    public static void validar(String clave) {
        if (clave == null || clave.isEmpty()) {
            throw new IllegalArgumentException("clave vacía");
        }
        if (clave.getBytes(StandardCharsets.UTF_8).length > 1024) {
            throw new IllegalArgumentException("clave de más de 1024 bytes");
        }
        if (clave.startsWith("/") || clave.indexOf('\\') >= 0) {
            throw new IllegalArgumentException("clave con inicio '/' o con '\\'");
        }
        for (int i = 0; i < clave.length(); i++) {
            char c = clave.charAt(i);
            if (c < 0x20 || c == 0x7f) {
                throw new IllegalArgumentException("clave con caracteres de control");
            }
        }
        for (String segmento : clave.split("/", -1)) {
            if (segmento.isEmpty() || segmento.equals(".") || segmento.equals("..")) {
                throw new IllegalArgumentException("segmento no permitido en la clave: '" + segmento + "'");
            }
        }
    }

    /** tenant/dominio/aaaa/MM/dd/uuid.ext — sin datos personales ni nombres de archivo del usuario. */
    public static String construir(String tenant, String dominio, Instant cuando, UUID id, String extension) {
        if (!TENANT.matcher(tenant).matches() || !TENANT.matcher(dominio).matches()) {
            throw new IllegalArgumentException("tenant o dominio inválido");
        }
        String ext = extension == null ? "" : extension.toLowerCase();
        if (!ext.isEmpty() && !EXTENSION.matcher(ext).matches()) {
            throw new IllegalArgumentException("extensión inválida");
        }
        String clave = tenant + "/" + dominio + "/" + FECHA.format(cuando) + "/" + id + (ext.isEmpty() ? "" : "." + ext);
        validar(clave);
        return clave;
    }
}
```

### 2.2 Plan de partes para subidas grandes
```java
// (clase reutilizada en los bloques siguientes, ambos)
public record PlanDePartes(long tamanoParte, int cantidad) {
    private static final long MIB = 1L << 20;
    private static final long MIN_PARTE = 5 * MIB;
    private static final long MAX_OBJETO = 5L << 40;      // 5 TiB
    private static final int MAX_PARTES = 10_000;

    /** Elige un tamaño de parte >= preferida, >= 5 MiB, que no supere las 10 000 partes (múltiplo de 1 MiB). */
    public static PlanDePartes calcular(long bytes, long preferida) {
        if (bytes <= 0) {
            throw new IllegalArgumentException("tamaño inválido");
        }
        if (bytes > MAX_OBJETO) {
            throw new IllegalArgumentException("un objeto de S3 no puede superar 5 TiB");
        }
        long minimaPorCantidad = (bytes + MAX_PARTES - 1) / MAX_PARTES;
        long parte = Math.max(Math.max(MIN_PARTE, preferida), minimaPorCantidad);
        parte = ((parte + MIB - 1) / MIB) * MIB;
        int cantidad = (int) ((bytes + parte - 1) / parte);
        return new PlanDePartes(parte, cantidad);
    }
}
```

### 2.3 Checksum SHA-256 en streaming
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;

public final class Sha256Base64 {
    private Sha256Base64() {}

    /** Formato que espera S3 en x-amz-checksum-sha256: Base64 del digest binario. */
    public static String de(InputStream in) throws IOException {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
            return Base64.getEncoder().encodeToString(md.digest());
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public static String de(java.nio.file.Path archivo) throws IOException {
        try (InputStream in = Files.newInputStream(archivo)) {
            return de(in);
        }
    }
}
```

### 2.4 Operaciones con el SDK (sirve en cualquier framework)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.io.InputStream;
import java.time.Instant;
import java.util.List;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ChecksumAlgorithm;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.ServerSideEncryption;

public final class AlmacenS3 {
    public record Objeto(String clave, long tamano, String etag, Instant modificado) {}

    private final S3Client s3;
    private final String bucket;
    private final String kmsKeyArn;      // null = cifrado por defecto del bucket

    public AlmacenS3(S3Client s3, String bucket, String kmsKeyArn) {
        this.s3 = s3;
        this.bucket = bucket;
        this.kmsKeyArn = kmsKeyArn;
    }

    private PutObjectRequest.Builder put(String clave, String contentType) {
        ClaveObjeto.validar(clave);
        PutObjectRequest.Builder b = PutObjectRequest.builder().bucket(bucket).key(clave)
                .contentType(contentType).checksumAlgorithm(ChecksumAlgorithm.SHA256);
        if (kmsKeyArn != null) {
            b.serverSideEncryption(ServerSideEncryption.AWS_KMS).ssekmsKeyId(kmsKeyArn);
        }
        return b;
    }

    /** Sube un archivo local; S3 verifica el SHA-256. Devuelve el versionId (null si el bucket no tiene versionado). */
    public String subir(String clave, java.nio.file.Path archivo, String contentType) {
        return s3.putObject(put(clave, contentType).build(), RequestBody.fromFile(archivo)).versionId();
    }

    /** «Crear solo si no existe»: true si lo creó, false si ya existía (HTTP 412). */
    public boolean subirSiNoExiste(String clave, byte[] datos, String contentType) {
        try {
            s3.putObject(put(clave, contentType).ifNoneMatch("*").build(), RequestBody.fromBytes(datos));
            return true;
        } catch (S3Exception e) {
            if (e.statusCode() == 412) {
                return false;
            }
            throw e;
        }
    }

    /** Descarga en streaming: quien lo llama debe cerrar el flujo (try-with-resources). */
    public ResponseInputStream<GetObjectResponse> abrir(String clave) {
        ClaveObjeto.validar(clave);
        return s3.getObject(GetObjectRequest.builder().bucket(bucket).key(clave).build());
    }

    public boolean existe(String clave) {
        ClaveObjeto.validar(clave);
        try {
            s3.headObject(HeadObjectRequest.builder().bucket(bucket).key(clave).build());
            return true;
        } catch (NoSuchKeyException e) {
            return false;
        }
    }

    /** Lista hasta "max" objetos de un prefijo recorriendo las páginas. */
    public List<Objeto> listar(String prefijo, int max) {
        ListObjectsV2Request req = ListObjectsV2Request.builder().bucket(bucket).prefix(prefijo).build();
        return s3.listObjectsV2Paginator(req).contents().stream()
                .limit(max)
                .map(o -> new Objeto(o.key(), o.size(), o.eTag(), o.lastModified()))
                .toList();
    }

    public void borrar(String clave) {
        ClaveObjeto.validar(clave);
        s3.deleteObject(DeleteObjectRequest.builder().bucket(bucket).key(clave).build());
    }

    public static void cerrar(InputStream in) throws IOException {
        if (in != null) {
            in.close();
        }
    }
}
```

## 3. Spring MVC (imperativo)
```java
import io.awspring.cloud.s3.S3Template;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
class AlmacenConfig {
    @Bean
    AlmacenS3 almacen(S3Client s3, @Value("${app.bucket}") String bucket, @Value("${app.kms-key-arn:}") String kms) {
        return new AlmacenS3(s3, bucket, kms.isBlank() ? null : kms);   // S3Client lo crea Spring Cloud AWS
    }
}

@RestController
class ArchivosController {
    private final AlmacenS3 almacen;
    private final S3Template plantilla;        // alternativa de alto nivel de Spring Cloud AWS
    private final String bucket;

    ArchivosController(AlmacenS3 almacen, S3Template plantilla, @Value("${app.bucket}") String bucket) {
        this.almacen = almacen;
        this.plantilla = plantilla;
        this.bucket = bucket;
    }

    /** Sube al disco temporal y luego a S3 con checksum: el archivo nunca se carga completo en memoria. */
    @PostMapping("/archivos/{tenant}")
    Map<String, String> subir(@PathVariable String tenant, @RequestParam("archivo") MultipartFile archivo)
            throws IOException {
        String ext = extension(archivo.getOriginalFilename());
        String clave = ClaveObjeto.construir(tenant, "facturas", Instant.now(), UUID.randomUUID(), ext);
        Path tmp = Files.createTempFile("subida-", ".tmp");
        try {
            archivo.transferTo(tmp);
            String version = almacen.subir(clave, tmp, archivo.getContentType());
            return Map.of("clave", clave, "version", version == null ? "" : version);
        } finally {
            Files.deleteIfExists(tmp);
        }
    }

    @GetMapping("/archivos/{tenant}/lista")
    List<AlmacenS3.Objeto> listar(@PathVariable String tenant) {
        return almacen.listar(tenant + "/facturas/", 100);
    }

    @GetMapping("/archivos/existe")
    ResponseEntity<Void> existe(@RequestParam String clave) {
        return plantilla.objectExists(bucket, clave) ? ResponseEntity.ok().build() : ResponseEntity.notFound().build();
    }

    private static String extension(String nombre) {
        if (nombre == null || !nombre.contains(".")) {
            return "";
        }
        return nombre.substring(nombre.lastIndexOf('.') + 1);
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import software.amazon.awssdk.core.async.AsyncRequestBody;
import software.amazon.awssdk.services.s3.S3AsyncClient;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Configuration
class AlmacenReactivoConfig {
    @Bean(destroyMethod = "close")
    S3AsyncClient s3Async() {
        return S3AsyncClient.builder().multipartEnabled(true).build();    // partes en paralelo con el cliente asíncrono
    }

    @Bean
    AlmacenS3 almacen(S3Client s3, @Value("${app.bucket}") String bucket) {
        return new AlmacenS3(s3, bucket, null);
    }
}

@RestController
class ArchivosReactivoController {
    private final S3AsyncClient s3;
    private final AlmacenS3 almacen;
    private final String bucket;

    ArchivosReactivoController(S3AsyncClient s3, AlmacenS3 almacen, @Value("${app.bucket}") String bucket) {
        this.s3 = s3;
        this.almacen = almacen;
        this.bucket = bucket;
    }

    /** Recibe el archivo en disco (no bloquea el hilo de eventos) y lo sube con el cliente asíncrono. */
    @PostMapping(value = "/archivos-r/{tenant}", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    Mono<Map<String, String>> subir(@PathVariable String tenant, @RequestPart("archivo") FilePart parte) {
        String clave = ClaveObjeto.construir(tenant, "facturas", Instant.now(), UUID.randomUUID(), "bin");
        return Mono.fromCallable(() -> Files.createTempFile("subida-", ".tmp"))
                .subscribeOn(Schedulers.boundedElastic())
                .flatMap(tmp -> parte.transferTo(tmp)
                        .then(Mono.fromFuture(() -> s3.putObject(
                                PutObjectRequest.builder().bucket(bucket).key(clave).build(),
                                AsyncRequestBody.fromFile(tmp))))
                        .doFinally(s -> borrar(tmp))
                        .thenReturn(Map.of("clave", clave)));
    }

    /** El listado usa el cliente síncrono: se aísla en boundedElastic. */
    @GetMapping("/archivos-r/{tenant}/lista")
    Mono<List<AlmacenS3.Objeto>> listar(@PathVariable String tenant) {
        return Mono.fromCallable(() -> almacen.listar(tenant + "/facturas/", 100))
                .subscribeOn(Schedulers.boundedElastic());
    }

    private static void borrar(Path tmp) {
        try {
            Files.deleteIfExists(tmp);
        } catch (java.io.IOException ignorada) {
            // el sistema operativo limpia el directorio temporal
        }
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.List;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.s3.S3Client;

@ApplicationScoped
class AlmacenProductor {
    @Produces
    @Singleton
    AlmacenS3 almacen(S3Client s3, @ConfigProperty(name = "app.bucket") String bucket,
                      @ConfigProperty(name = "app.kms-key-arn") Optional<String> kms) {
        return new AlmacenS3(s3, bucket, kms.orElse(null));        // S3Client lo administra quarkus-amazon-s3
    }
}

@Path("/archivos")
class ArchivosRecurso {
    @Inject
    AlmacenS3 almacen;

    @GET
    @Path("/{tenant}/lista")
    public List<AlmacenS3.Objeto> listar(@PathParam("tenant") String tenant) {
        return almacen.listar(tenant + "/facturas/", 100);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.s3.S3AsyncClient;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;

@Path("/archivos-r")
class ArchivosReactivoRecurso {
    @Inject
    S3AsyncClient s3;                                       // cliente asíncrono de quarkus-amazon-s3

    @ConfigProperty(name = "app.bucket")
    String bucket;

    @GET
    @Path("/{tenant}/claves")
    public Uni<List<String>> claves(@PathParam("tenant") String tenant) {
        ListObjectsV2Request req = ListObjectsV2Request.builder().bucket(bucket)
                .prefix(tenant + "/facturas/").maxKeys(100).build();
        return Uni.createFrom().completionStage(() -> s3.listObjectsV2(req))
                .map(r -> r.contents().stream().map(o -> o.key()).toList());
    }
}
```

## 7. Permisos de la aplicación
`s3:GetObject`/`s3:PutObject` sobre `bucket/prefijo/*`, `s3:ListBucket` con condición de prefijo y `kms:GenerateDataKey` + `kms:Decrypt` sobre la clave (ver [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)).

## 8. Qué NO hacer desde Java
- **No** cargues archivos completos en `byte[]`: usa archivo temporal o streaming.
- **No** uses el nombre de archivo del usuario como clave (colisiones, `../`, datos personales): genera la clave con `ClaveObjeto.construir`.
- **No** uses el ETag como hash: pide `SHA-256` y compáralo.
- **No** crees clientes por petición: uno por aplicación, con `close()` al apagar.
- **No** pongas claves de acceso en el código; usa el rol del servicio.
- **No** hagas «existe → escribir»: usa `subirSiNoExiste` (`If-None-Match`).
- **No** olvides cerrar el `ResponseInputStream` de `abrir`: mantiene la conexión ocupada.
