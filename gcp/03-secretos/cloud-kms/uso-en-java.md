# Google Cloud · Secretos · Cloud KMS · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

**Cifrado de sobre con contexto**: la lógica pura genera una DEK AES-256 por documento, cifra con AES-GCM usando como AAD el id del cliente y delega a KMS envolver/desenvolver la DEK (con la misma AAD) mediante `KeyManagementServiceClient.encrypt/decrypt`. Un documento copiado al registro de otro cliente no se descifra.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
kms:
  ubicacion: southamerica-west1
  llavero: tienda
  llave: datos-clientes
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
kms.ubicacion=southamerica-west1
kms.llavero=tienda
kms.llave=datos-clientes
```

## 2. Núcleo común

### 2.1 Credenciales según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ImpersonatedCredentials;
import java.io.IOException;
import java.util.List;

public final class Credenciales {

    private static final List<String> ALCANCE = List.of("https://www.googleapis.com/auth/cloud-platform");

    private Credenciales() { }

    /**
     * ADC (Application Default Credentials): en la laptop, «gcloud auth application-default login»;
     * en GKE, Cloud Run, Functions o Compute Engine, la cuenta de servicio adjunta (sin llaves).
     * suplantar = correo de una cuenta de servicio para actuar como ella, o "ninguna".
     */
    public static GoogleCredentials crear(String suplantar) {
        try {
            var base = GoogleCredentials.getApplicationDefault().createScoped(ALCANCE);
            if (suplantar == null || suplantar.isBlank() || "ninguna".equals(suplantar)) {
                return base;
            }
            return ImpersonatedCredentials.create(base, suplantar, null, ALCANCE, 3600);
        } catch (IOException e) {
            throw new IllegalStateException("no hay credenciales ADC disponibles", e);
        }
    }
}
```

### 2.2 Cifrado de sobre (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.ByteBuffer;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Cifrado de sobre: AES-256-GCM local con DEK y AAD; la DEK la envuelve KMS. Puro (sin red). */
public class CifradoDeSobre {

    public record Sobre(byte[] dekEnvuelta, byte[] nonce, byte[] cifrado) { }

    public interface Envolvedor {
        byte[] envolver(byte[] dek, byte[] aad);

        byte[] desenvolver(byte[] dekEnvuelta, byte[] aad);
    }

    private static final SecureRandom AZAR = new SecureRandom();
    private final Envolvedor kms;

    public CifradoDeSobre(Envolvedor kms) {
        this.kms = kms;
    }

    public Sobre cifrar(byte[] datos, byte[] aad) {
        try {
            KeyGenerator kg = KeyGenerator.getInstance("AES");
            kg.init(256);
            SecretKey dek = kg.generateKey();
            byte[] nonce = new byte[12];
            AZAR.nextBytes(nonce);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, dek, new GCMParameterSpec(128, nonce));
            c.updateAAD(aad);
            byte[] cifrado = c.doFinal(datos);
            return new Sobre(kms.envolver(dek.getEncoded(), aad), nonce, cifrado);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    public byte[] descifrar(Sobre s, byte[] aad) {
        try {
            byte[] dek = kms.desenvolver(s.dekEnvuelta(), aad);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(dek, "AES"), new GCMParameterSpec(128, s.nonce()));
            c.updateAAD(aad);
            return c.doFinal(s.cifrado());
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("no se pudo descifrar: contexto (AAD) o datos alterados", e);
        }
    }

    /** Formato de almacenamiento: [len dek][dek][nonce 12][cifrado]. */
    public static byte[] serializar(Sobre s) {
        return ByteBuffer.allocate(4 + s.dekEnvuelta().length + 12 + s.cifrado().length)
            .putInt(s.dekEnvuelta().length).put(s.dekEnvuelta()).put(s.nonce()).put(s.cifrado()).array();
    }

    public static Sobre deserializar(byte[] b) {
        var buf = ByteBuffer.wrap(b);
        byte[] dek = new byte[buf.getInt()];
        buf.get(dek);
        byte[] nonce = new byte[12];
        buf.get(nonce);
        byte[] cif = new byte[buf.remaining()];
        buf.get(cif);
        return new Sobre(dek, nonce, cif);
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.kms.v1.CryptoKeyName;
import com.google.cloud.kms.v1.DecryptRequest;
import com.google.cloud.kms.v1.EncryptRequest;
import com.google.cloud.kms.v1.KeyManagementServiceClient;
import com.google.cloud.kms.v1.KeyManagementServiceSettings;
import com.google.protobuf.ByteString;
import java.io.IOException;
import java.io.UncheckedIOException;

/** Adaptador: KMS envuelve y desenvuelve la DEK con la misma AAD. */
public class KmsGcp implements CifradoDeSobre.Envolvedor, AutoCloseable {

    private final KeyManagementServiceClient cliente;
    private final String llave;

    public KmsGcp(GoogleCredentials cred, String proyecto, String ubicacion, String llavero, String nombreLlave) {
        try {
            this.cliente = KeyManagementServiceClient.create(KeyManagementServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.llave = CryptoKeyName.of(proyecto, ubicacion, llavero, nombreLlave).toString();
    }

    @Override
    public byte[] envolver(byte[] dek, byte[] aad) {
        return cliente.encrypt(EncryptRequest.newBuilder().setName(llave).setPlaintext(ByteString.copyFrom(dek))
            .setAdditionalAuthenticatedData(ByteString.copyFrom(aad)).build()).getCiphertext().toByteArray();
    }

    @Override
    public byte[] desenvolver(byte[] dekEnvuelta, byte[] aad) {
        return cliente.decrypt(DecryptRequest.newBuilder().setName(llave).setCiphertext(ByteString.copyFrom(dekEnvuelta))
            .setAdditionalAuthenticatedData(ByteString.copyFrom(aad)).build()).getPlaintext().toByteArray();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class ServicioDeCifrado {

    private final CifradoDeSobre sobre;

    public ServicioDeCifrado(KmsGcp kms) {
        this.sobre = new CifradoDeSobre(kms);
    }

    /** El id del cliente es el contexto: un documento copiado a otro cliente no se descifra. */
    public String cifrar(String idCliente, String documento) {
        var s = sobre.cifrar(documento.getBytes(StandardCharsets.UTF_8), ("cliente:" + idCliente).getBytes(StandardCharsets.UTF_8));
        return Base64.getEncoder().encodeToString(CifradoDeSobre.serializar(s));
    }

    public String descifrar(String idCliente, String base64) {
        var s = CifradoDeSobre.deserializar(Base64.getDecoder().decode(base64));
        return new String(sobre.descifrar(s, ("cliente:" + idCliente).getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class CifradoConfiguracion {

    @Bean(destroyMethod = "close")
    KmsGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar, @Value("${kms.ubicacion}") String ubicacion, @Value("${kms.llavero}") String llavero, @Value("${kms.llave}") String llave) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new KmsGcp(cred, proyecto, ubicacion, llavero, llave);
    }

    @Bean
    ServicioDeCifrado servicio(KmsGcp a) {
        return new ServicioDeCifrado(a);
    }
}

@RestController
@RequestMapping("/secretos/cifrado")
class CifradoControlador {

    private final ServicioDeCifrado s;

    CifradoControlador(ServicioDeCifrado s) {
        this.s = s;
    }

    @PostMapping("/{cliente}/cifrar")
    String cifrar(@PathVariable String cliente, @RequestBody String doc) {
        return s.cifrar(cliente, doc);
    }

    @PostMapping("/{cliente}/descifrar")
    String descifrar(@PathVariable String cliente, @RequestBody String b64) {
        return s.descifrar(cliente, b64);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
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

    @PostMapping("/{cliente}/cifrar")
    Mono<String> cifrar(@PathVariable String cliente, @RequestBody String doc) {
        return Mono.fromCallable(() -> s.cifrar(cliente, doc)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/{cliente}/descifrar")
    Mono<String> descifrar(@PathVariable String cliente, @RequestBody String b64) {
        return Mono.fromCallable(() -> s.descifrar(cliente, b64)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.google.auth.oauth2.GoogleCredentials;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class CifradoProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @ConfigProperty(name = "kms.ubicacion")
    String ubicacion;

    @ConfigProperty(name = "kms.llavero")
    String llavero;

    @ConfigProperty(name = "kms.llave")
    String llave;

    @jakarta.enterprise.inject.Produces
    @Singleton
    KmsGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new KmsGcp(cred, proyecto, ubicacion, llavero, llave);
    }

    void cerrar(@Disposes KmsGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCifrado servicio(KmsGcp a) {
        return new ServicioDeCifrado(a);
    }
}

@Path("/secretos/cifrado")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class CifradoRecurso {

    @Inject
    ServicioDeCifrado s;

    @POST
    @Path("/{cliente}/cifrar")
    @Consumes(MediaType.APPLICATION_JSON)
    public String cifrar(@PathParam("cliente") String cliente, String doc) {
        return s.cifrar(cliente, doc);
    }

    @POST
    @Path("/{cliente}/descifrar")
    @Consumes(MediaType.APPLICATION_JSON)
    public String descifrar(@PathParam("cliente") String cliente, String b64) {
        return s.descifrar(cliente, b64);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/secretos/cifrado")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class CifradoRecursoReactivo {

    @Inject
    ServicioDeCifrado s;

    @POST
    @Path("/{cliente}/cifrar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> cifrar(@PathParam("cliente") String cliente, String doc) {
        return Uni.createFrom().item(() -> s.cifrar(cliente, doc)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/{cliente}/descifrar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> descifrar(@PathParam("cliente") String cliente, String b64) {
        return Uni.createFrom().item(() -> s.descifrar(cliente, b64)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Envolver y desenvolver DEK | `roles/cloudkms.cryptoKeyEncrypterDecrypter` **en esa llave** |

## 8. Qué NO hacer desde Java
- No envíes documentos grandes a `encrypt`: cifra localmente y envuelve la DEK.
- No reutilices nonce con la misma DEK.
- No omitas la AAD.
- No registres DEK ni texto plano.
- No uses el endpoint de descifrado sin autorización de negocio (¿este usuario puede ver este documento?).
