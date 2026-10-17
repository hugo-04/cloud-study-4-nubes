# Oracle OCI · Secretos · Vault: llaves (KMS) · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **cifrado de sobre**: el núcleo (AES-256-GCM con contexto autenticado) es Java puro y se prueba sin red; solo la obtención y apertura de la llave de datos usa `KmsCryptoClient` con el endpoint de criptografía del vault.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
kms:
  endpoint-cripto: https://xxxx-crypto.kms.sa-saopaulo-1.oraclecloud.com
  llave-id: ocid1.key.oc1.sa-saopaulo-1.xxxx
```
```properties
# Quarkus (application.properties)
oci.auth=instance
kms.endpoint-cripto=https://xxxx-crypto.kms.sa-saopaulo-1.oraclecloud.com
kms.llave-id=ocid1.key.oc1.sa-saopaulo-1.xxxx
```

## 2. Núcleo común

### 2.1 Autenticación según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
        }
    }
}
```

### 2.2 Contrato con el Vault
```java
// (clase reutilizada en los bloques siguientes, ambos)
/** Lo que necesita el sobre de Vault: una llave de datos nueva y poder abrir una envuelta. */
public interface Llaves {

    /** Llave de datos: en claro (para usar y olvidar) y envuelta (para guardar). */
    record LlaveDeDatos(byte[] enClaro, String envuelta) { }

    LlaveDeDatos nueva();

    byte[] abrir(String envuelta);
}
```

### 2.3 Cifrado de sobre
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Cifrado de sobre: AES-256-GCM local con una llave de datos protegida por Vault. */
public class CifradoDeSobre {

    private static final String VERSION = "v1";
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;

    private final Llaves llaves;
    private final SecureRandom azar = new SecureRandom();

    public CifradoDeSobre(Llaves llaves) {
        this.llaves = llaves;
    }

    /** Formato: v1.llaveEnvuelta.iv.textoCifrado (todo en Base64 URL). */
    public String cifrar(String texto, String contexto) {
        var dek = llaves.nueva();
        try {
            byte[] iv = new byte[IV_BYTES];
            azar.nextBytes(iv);
            byte[] cifrado = aes(Cipher.ENCRYPT_MODE, dek.enClaro(), iv, contexto, texto.getBytes(StandardCharsets.UTF_8));
            var b64 = Base64.getUrlEncoder().withoutPadding();
            return String.join(".", VERSION, b64.encodeToString(dek.envuelta().getBytes(StandardCharsets.UTF_8)),
                b64.encodeToString(iv), b64.encodeToString(cifrado));
        } finally {
            Arrays.fill(dek.enClaro(), (byte) 0);
        }
    }

    public String descifrar(String sobre, String contexto) {
        String[] p = sobre.split("\\.");
        if (p.length != 4 || !VERSION.equals(p[0])) {
            throw new IllegalArgumentException("formato de sobre desconocido");
        }
        var b64 = Base64.getUrlDecoder();
        String envuelta = new String(b64.decode(p[1]), StandardCharsets.UTF_8);
        byte[] clave = llaves.abrir(envuelta);
        try {
            return new String(aes(Cipher.DECRYPT_MODE, clave, b64.decode(p[2]), contexto, b64.decode(p[3])), StandardCharsets.UTF_8);
        } finally {
            Arrays.fill(clave, (byte) 0);
        }
    }

    private static byte[] aes(int modo, byte[] clave, byte[] iv, String contexto, byte[] datos) {
        try {
            var c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(modo, new SecretKeySpec(clave, "AES"), new GCMParameterSpec(TAG_BITS, iv));
            c.updateAAD(contexto.getBytes(StandardCharsets.UTF_8));
            return c.doFinal(datos);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("no se pudo cifrar/descifrar (¿contexto distinto o dato alterado?)", e);
        }
    }
}
```

### 2.4 Implementación con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.keymanagement.KmsCryptoClient;
import com.oracle.bmc.keymanagement.model.DecryptDataDetails;
import com.oracle.bmc.keymanagement.model.GenerateKeyDetails;
import com.oracle.bmc.keymanagement.model.KeyShape;
import com.oracle.bmc.keymanagement.requests.DecryptRequest;
import com.oracle.bmc.keymanagement.requests.GenerateDataEncryptionKeyRequest;
import java.util.Base64;

/** Implementa Llaves con el endpoint de criptografía del vault. */
public class LlavesKms implements Llaves, AutoCloseable {

    private final KmsCryptoClient cliente;
    private final String llaveMaestraId;

    public LlavesKms(BasicAuthenticationDetailsProvider auth, String endpointCripto, String llaveMaestraId) {
        this.cliente = KmsCryptoClient.builder().endpoint(endpointCripto).build(auth);
        this.llaveMaestraId = llaveMaestraId;
    }

    @Override
    public LlaveDeDatos nueva() {
        var detalles = GenerateKeyDetails.builder()
            .keyId(llaveMaestraId)
            .includePlaintextKey(true)
            .keyShape(KeyShape.builder().algorithm(KeyShape.Algorithm.Aes).length(32).build())
            .build();
        var k = cliente.generateDataEncryptionKey(
            GenerateDataEncryptionKeyRequest.builder().generateKeyDetails(detalles).build()).getGeneratedKey();
        return new LlaveDeDatos(Base64.getDecoder().decode(k.getPlaintext()), k.getCiphertext());
    }

    @Override
    public byte[] abrir(String envuelta) {
        var detalles = DecryptDataDetails.builder().keyId(llaveMaestraId).ciphertext(envuelta).build();
        var r = cliente.decrypt(DecryptRequest.builder().decryptDataDetails(detalles).build()).getDecryptedData();
        return Base64.getDecoder().decode(r.getPlaintext());
    }

    @Override
    public void close() {
        cliente.close();
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
public class ServicioDeCifrado {

    private final CifradoDeSobre sobre;

    public ServicioDeCifrado(CifradoDeSobre sobre) {
        this.sobre = sobre;
    }

    public record Peticion(String id, String texto) { }

    public record Sobre(String id, String valor) { }

    public Sobre cifrar(Peticion p) {
        return new Sobre(p.id(), sobre.cifrar(p.texto(), p.id()));
    }

    /** El id es el contexto autenticado: un sobre copiado a otro id no se abre. */
    public String descifrar(String id, String valor) {
        return sobre.descifrar(valor, id);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class CifradoConfiguracion {

    @Bean(destroyMethod = "close")
    LlavesKms llavesKms(@Value("${oci.auth}") String modo, @Value("${kms.endpoint-cripto}") String endpoint,
                        @Value("${kms.llave-id}") String llaveId) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new LlavesKms(auth, endpoint, llaveId);
    }

    @Bean
    ServicioDeCifrado servicioDeCifrado(LlavesKms llaves) {
        return new ServicioDeCifrado(new CifradoDeSobre(llaves));
    }
}

@RestController
@RequestMapping("/secretos/cifrado")
class CifradoControlador {

    private final ServicioDeCifrado s;

    CifradoControlador(ServicioDeCifrado s) {
        this.s = s;
    }

    @PostMapping("/cifrar")
    ServicioDeCifrado.Sobre cifrar(@RequestBody ServicioDeCifrado.Peticion p) {
        return s.cifrar(p);
    }

    @GetMapping("/descifrar")
    String descifrar(@RequestParam String id, @RequestParam String valor) {
        return s.descifrar(id, valor);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/secretos/cifrado")
class CifradoReactivoControlador {

    private final ServicioDeCifrado s;

    CifradoReactivoControlador(ServicioDeCifrado s) {
        this.s = s;
    }

    @PostMapping("/cifrar")
    Mono<ServicioDeCifrado.Sobre> cifrar(@RequestBody ServicioDeCifrado.Peticion p) {
        return Mono.fromCallable(() -> s.cifrar(p)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/descifrar")
    Mono<String> descifrar(@RequestParam String id, @RequestParam String valor) {
        return Mono.fromCallable(() -> s.descifrar(id, valor)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class CifradoProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "kms.endpoint-cripto")
    String endpoint;

    @ConfigProperty(name = "kms.llave-id")
    String llaveId;

    @jakarta.enterprise.inject.Produces
    @Singleton
    LlavesKms llavesKms() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new LlavesKms(auth, endpoint, llaveId);
    }

    void cerrar(@Disposes LlavesKms l) {
        l.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCifrado servicioDeCifrado(LlavesKms llaves) {
        return new ServicioDeCifrado(new CifradoDeSobre(llaves));
    }
}

@Path("/secretos/cifrado")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class CifradoRecurso {

    @Inject
    ServicioDeCifrado s;

    @POST
    @Path("/cifrar")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeCifrado.Sobre cifrar(ServicioDeCifrado.Peticion p) {
        return s.cifrar(p);
    }

    @GET
    @Path("/descifrar")
    public String descifrar(@QueryParam("id") String id, @QueryParam("valor") String valor) {
        return s.descifrar(id, valor);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/secretos/cifrado")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class CifradoRecursoReactivo {

    @Inject
    ServicioDeCifrado s;

    @POST
    @Path("/cifrar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeCifrado.Sobre> cifrar(ServicioDeCifrado.Peticion p) {
        return Uni.createFrom().item(() -> s.cifrar(p)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/descifrar")
    public Uni<String> descifrar(@QueryParam("id") String id, @QueryParam("valor") String valor) {
        return Uni.createFrom().item(() -> s.descifrar(id, valor)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `GenerateDataEncryptionKey`, `Decrypt` | `Allow dynamic-group app-tienda-prod to use keys in compartment tienda-prod where target.key.id = '<ocid>'` |

## 8. Qué NO hacer desde Java
- No registres la llave de datos en claro, ni el texto descifrado; el código borra el arreglo de bytes tras usarlo.
- No reutilices un IV con la misma llave (el código genera uno aleatorio por mensaje y una DEK nueva cada vez).
- No expongas `/descifrar` sin autenticación y autorización propias: devuelve el dato en claro.
- No uses `Encrypt` directo para datos grandes.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
