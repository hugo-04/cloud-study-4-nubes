# AWS · KMS · Uso desde Java

Dos patrones que cubren casi todo: (1) **cifrado de sobre** de campos o archivos de la aplicación con `GenerateDataKey` + AES-GCM, y (2) **dejar que los servicios cifren por ti** (S3, SQS, Secrets Manager) dándole a tu rol los permisos de la clave. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Cifrado de sobre con contexto de cifrado

### Núcleo común
La lógica criptográfica está separada del acceso a KMS (`ProveedorClaves`): así se **prueba sin AWS** con un proveedor falso.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Map;
import java.util.TreeMap;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.kms.KmsClient;
import software.amazon.awssdk.services.kms.model.DataKeySpec;
import software.amazon.awssdk.services.kms.model.DecryptRequest;
import software.amazon.awssdk.services.kms.model.GenerateDataKeyRequest;
import software.amazon.awssdk.services.kms.model.GenerateDataKeyResponse;

record ClaveDeDatos(byte[] enClaro, byte[] cifrada) {}

interface ProveedorClaves {
    ClaveDeDatos generar(Map<String, String> contexto);

    byte[] descifrar(byte[] cifrada, Map<String, String> contexto);
}

final class ProveedorKms implements ProveedorClaves {
    private final KmsClient kms;
    private final String claveId;       // alias/prod-pedidos-datos o ARN

    ProveedorKms(KmsClient kms, String claveId) {
        this.kms = kms;
        this.claveId = claveId;
    }

    @Override
    public ClaveDeDatos generar(Map<String, String> contexto) {
        GenerateDataKeyResponse r = kms.generateDataKey(GenerateDataKeyRequest.builder()
                .keyId(claveId).keySpec(DataKeySpec.AES_256).encryptionContext(contexto).build());
        return new ClaveDeDatos(r.plaintext().asByteArray(), r.ciphertextBlob().asByteArray());
    }

    @Override
    public byte[] descifrar(byte[] cifrada, Map<String, String> contexto) {
        // Indicar keyId en Decrypt evita descifrar con una clave que no esperabas
        return kms.decrypt(DecryptRequest.builder().keyId(claveId).ciphertextBlob(SdkBytes.fromByteArray(cifrada))
                .encryptionContext(contexto).build()).plaintext().asByteArray();
    }
}

/**
 * Formato: [versión 1 byte][longitud del blob 4 bytes][blob cifrado por KMS][IV 12 bytes][texto cifrado + etiqueta GCM].
 * El contexto se usa dos veces: en KMS (EncryptionContext) y como datos autenticados adicionales de AES-GCM.
 */
final class SobreCifrado {
    private static final byte VERSION = 1;
    private static final int IV_BYTES = 12;
    private static final int ETIQUETA_BITS = 128;

    private final ProveedorClaves claves;
    private final SecureRandom azar = new SecureRandom();

    SobreCifrado(ProveedorClaves claves) { this.claves = claves; }

    byte[] cifrar(byte[] plano, Map<String, String> contexto) {
        ClaveDeDatos clave = claves.generar(contexto);
        try {
            byte[] iv = new byte[IV_BYTES];
            azar.nextBytes(iv);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(clave.enClaro(), "AES"), new GCMParameterSpec(ETIQUETA_BITS, iv));
            c.updateAAD(aad(contexto));
            byte[] cifrado = c.doFinal(plano);
            return ByteBuffer.allocate(1 + 4 + clave.cifrada().length + IV_BYTES + cifrado.length)
                    .put(VERSION).putInt(clave.cifrada().length).put(clave.cifrada()).put(iv).put(cifrado).array();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("No se pudo cifrar", e);
        } finally {
            Arrays.fill(clave.enClaro(), (byte) 0);         // la clave en claro no debe sobrevivir
        }
    }

    byte[] descifrar(byte[] sobre, Map<String, String> contexto) {
        ByteBuffer b = ByteBuffer.wrap(sobre);
        if (b.get() != VERSION) throw new IllegalArgumentException("Versión de sobre desconocida");
        int n = b.getInt();
        if (n <= 0 || n > b.remaining()) throw new IllegalArgumentException("Sobre dañado");
        byte[] blob = new byte[n];
        b.get(blob);
        byte[] iv = new byte[IV_BYTES];
        b.get(iv);
        byte[] cifrado = new byte[b.remaining()];
        b.get(cifrado);
        byte[] clave = claves.descifrar(blob, contexto);
        try {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(clave, "AES"), new GCMParameterSpec(ETIQUETA_BITS, iv));
            c.updateAAD(aad(contexto));
            return c.doFinal(cifrado);
        } catch (GeneralSecurityException e) {
            throw new IllegalArgumentException("Dato alterado o contexto distinto", e);
        } finally {
            Arrays.fill(clave, (byte) 0);
        }
    }

    /** Contexto canónico (ordenado) como datos autenticados adicionales. */
    static byte[] aad(Map<String, String> contexto) {
        StringBuilder sb = new StringBuilder();
        new TreeMap<>(contexto).forEach((k, v) -> sb.append(k).append('=').append(v).append('\n'));
        return sb.toString().getBytes(StandardCharsets.UTF_8);
    }
}
```
Detalles importantes: **IV nuevo y aleatorio** por cifrado (con la misma clave de datos jamás repitas IV; aquí cada cifrado usa su propia clave de datos); **la clave en claro se borra** en `finally`; el sobre incluye una **versión** para poder evolucionar el formato.

### Spring MVC (imperativo)
```java
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.kms.KmsClient;

@Configuration
class KmsConfig {
    @Bean(destroyMethod = "close")
    KmsClient kms() {
        return KmsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    SobreCifrado sobre(KmsClient kms, @Value("${kms.clave:alias/prod-pedidos-datos}") String clave) {
        return new SobreCifrado(new ProveedorKms(kms, clave));
    }
}

@RestController
class KmsController {
    private final SobreCifrado sobre;

    KmsController(SobreCifrado sobre) { this.sobre = sobre; }

    /** Prueba de humo: cifra y descifra un valor aleatorio. Útil como verificación de despliegue. */
    @PostMapping("/kms/humo")
    Map<String, Object> humo() {
        Map<String, String> contexto = Map.of("servicio", "pedidos", "uso", "humo");
        long t0 = System.nanoTime();
        byte[] secreto = ("humo-" + System.nanoTime()).getBytes(StandardCharsets.UTF_8);
        byte[] envuelto = sobre.cifrar(secreto, contexto);
        boolean ok = java.util.Arrays.equals(secreto, sobre.descifrar(envuelto, contexto));
        return Map.of("ok", ok, "bytesSobre", envuelto.length, "ms", (System.nanoTime() - t0) / 1_000_000,
                "muestra", Base64.getEncoder().encodeToString(envuelto).substring(0, 12) + "…");
    }
}
```
> En una entidad real el contexto lleva **quién es el dueño del dato** (`tenant`, `tabla`, `id`): `Map.of("servicio","pedidos","tenant",t,"pedido",id)`. Así un campo copiado a otra fila ya no descifra.

### Spring WebFlux (reactivo)
```java
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class KmsReactivoController {
    private final SobreCifrado sobre;

    KmsReactivoController(SobreCifrado sobre) { this.sobre = sobre; }

    @PostMapping("/reactivo/kms/humo")
    Mono<Map<String, Object>> humo() {
        return Mono.fromCallable(() -> {
                    Map<String, String> contexto = Map.of("servicio", "pedidos", "uso", "humo");
                    byte[] secreto = ("humo-" + System.nanoTime()).getBytes(StandardCharsets.UTF_8);
                    boolean ok = java.util.Arrays.equals(secreto, sobre.descifrar(sobre.cifrar(secreto, contexto), contexto));
                    return Map.<String, Object>of("ok", ok);
                })
                .subscribeOn(Schedulers.boundedElastic());      // el KmsClient síncrono bloquea
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.kms.KmsClient;

@ApplicationScoped
class KmsProductores {
    @ConfigProperty(name = "kms.clave", defaultValue = "alias/prod-pedidos-datos")
    String clave;

    @Produces
    @ApplicationScoped
    KmsClient kms() {
        return KmsClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Produces
    @ApplicationScoped
    SobreCifrado sobre(KmsClient kms) {
        return new SobreCifrado(new ProveedorKms(kms, clave));
    }
}

@Path("/kms/humo")
public class KmsResource {
    @Inject
    SobreCifrado sobre;

    @POST
    public Map<String, Object> humo() {
        Map<String, String> contexto = Map.of("servicio", "pedidos", "uso", "humo");
        byte[] secreto = ("humo-" + System.nanoTime()).getBytes(StandardCharsets.UTF_8);
        boolean ok = java.util.Arrays.equals(secreto, sobre.descifrar(sobre.cifrar(secreto, contexto), contexto));
        return Map.of("ok", ok);
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.nio.charset.StandardCharsets;
import java.util.Map;

@Path("/reactivo/kms/humo")
public class KmsReactivoResource {
    @Inject
    SobreCifrado sobre;

    @POST
    public Uni<Map<String, Object>> humo() {
        return Uni.createFrom().item(() -> {
                    Map<String, String> contexto = Map.of("servicio", "pedidos", "uso", "humo");
                    byte[] secreto = ("humo-" + System.nanoTime()).getBytes(StandardCharsets.UTF_8);
                    boolean ok = java.util.Arrays.equals(secreto, sobre.descifrar(sobre.cifrar(secreto, contexto), contexto));
                    return Map.<String, Object>of("ok", ok);
                })
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 2. Que el servicio cifre por ti
No siempre necesitas código: en **S3**, **SQS**, **Secrets Manager**, **DynamoDB**… eliges la CMK en el recurso y el SDK sigue igual. Lo que cambia es que **el rol de la aplicación necesita permisos de clave**:
```java
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.ServerSideEncryption;

class SubidaCifrada {
    void subir(S3Client s3, byte[] datos) {
        s3.putObject(PutObjectRequest.builder()
                        .bucket("modalima-datos").key("facturas/f-1001.json")
                        .serverSideEncryption(ServerSideEncryption.AWS_KMS)
                        .ssekmsKeyId("alias/prod-pedidos-datos")
                        .bucketKeyEnabled(true)                       // menos llamadas a KMS
                        .build(),
                RequestBody.fromBytes(datos));
    }
}
```
Permisos del rol para S3 con SSE-KMS: `kms:GenerateDataKey` y `kms:Decrypt` sobre la CMK (con `kms:ViaService` = `s3.<región>.amazonaws.com`).

## 3. Rendimiento y costo
- Cada `cifrar` hace **una llamada** a `GenerateDataKey` y cada `descifrar` otra a `Decrypt`. Para volúmenes altos: **cachea claves de datos** por contexto durante segundos o por N mensajes (la **AWS Encryption SDK for Java** lo implementa con límites de edad/uso/mensajes).
- Ten **reintentos con backoff** ante `ThrottlingException` y mide con métricas.
- Cifra en **lote**: una clave de datos para un archivo grande, no una por línea.

## 4. Qué NO hacer desde Java
- No usar `Encrypt` para datos grandes (límite de 4 KB): usa cifrado de sobre.
- No reutilizar el IV con la misma clave ni usar ECB/CBC sin autenticación: **AES-GCM**.
- No guardar la clave de datos **en claro**; ni en logs ni en base.
- No cifrar sin **contexto de cifrado**.
- No capturar y tragar las excepciones de descifrado: un fallo de autenticación puede indicar manipulación.
