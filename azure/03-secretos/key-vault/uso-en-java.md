# Azure · Key Vault · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3**. Verifica las vigentes.

La regla de oro de todo este archivo: **un cliente por aplicación, un secreto en caché unos minutos, y la identidad viene de `DefaultAzureCredential`** (en Azure usa Managed/Workload Identity; en tu laptop usa `az login`).

## 1. Dependencias
```xml
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>com.azure</groupId>
      <artifactId>azure-sdk-bom</artifactId>
      <version>1.3.9</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>

<dependencies>
  <dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
  <dependency><groupId>com.azure</groupId><artifactId>azure-security-keyvault-secrets</artifactId></dependency>
  <dependency><groupId>com.azure</groupId><artifactId>azure-security-keyvault-keys</artifactId></dependency>        <!-- si usas claves -->
  <dependency><groupId>com.azure</groupId><artifactId>azure-security-keyvault-certificates</artifactId></dependency> <!-- si usas certificados -->
</dependencies>
```

## 2. Cliente base y lectura (imperativo, sin framework)
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;

class LecturaBasica {
    public static void main(String[] args) {
        SecretClient cliente = new SecretClientBuilder()
                .vaultUrl("https://kv-modalima-estudio01.vault.azure.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();

        KeyVaultSecret secreto = cliente.getSecret("db-password");   // última versión
        System.out.println("versión: " + secreto.getProperties().getVersion());
        System.out.println("vence:   " + secreto.getProperties().getExpiresOn());
        // NUNCA imprimas secreto.getValue()
    }
}
```
Para una versión concreta: `cliente.getSecret("db-password", "<versión>")`.

## 3. Caché con TTL y "devolver el anterior si el vault falla"
Un secreto casi nunca cambia en segundos. Cachéalo, y si el vault tiene un mal momento, sigue usando el último valor bueno.

```java
import com.azure.core.exception.HttpResponseException;
import com.azure.security.keyvault.secrets.SecretClient;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;

class SecretoEnCache {
    private record Entrada(String valor, Instant vence) {}

    private final SecretClient cliente;
    private final Duration ttl;
    private final ConcurrentHashMap<String, Entrada> cache = new ConcurrentHashMap<>();

    SecretoEnCache(SecretClient cliente, Duration ttl) {
        this.cliente = cliente;
        this.ttl = ttl;
    }

    String obtener(String nombre) {
        Entrada actual = cache.get(nombre);
        if (actual != null && Instant.now().isBefore(actual.vence())) {
            return actual.valor();
        }
        try {
            String nuevo = cliente.getSecret(nombre).getValue();
            cache.put(nombre, new Entrada(nuevo, Instant.now().plus(ttl)));
            return nuevo;
        } catch (HttpResponseException e) {
            if (actual != null) {
                return actual.valor();      // vault con problemas: seguimos con el último valor bueno
            }
            throw e;
        }
    }

    void invalidar(String nombre) {
        cache.remove(nombre);               // úsalo cuando la base rechace la credencial: relee una vez
    }
}
```

## 4. Spring Boot (imperativo)

### 4.1 Cliente como bean y caché declarativa
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

@Configuration
class KeyVaultConfig {
    @Bean
    SecretClient secretClient(@Value("${app.keyvault.url}") String url) {
        return new SecretClientBuilder()
                .vaultUrl(url)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }
}

@Service
class Secretos {
    private final SecretClient cliente;

    Secretos(SecretClient cliente) {
        this.cliente = cliente;
    }

    @Cacheable("secretos")
    public String valor(String nombre) {
        return cliente.getSecret(nombre).getValue();
    }
}
```
```properties
app.keyvault.url=https://kv-modalima-estudio01.vault.azure.net
spring.cache.cache-names=secretos
spring.cache.caffeine.spec=expireAfterWrite=5m
```
Requiere `@EnableCaching` en alguna `@Configuration` y la dependencia `com.github.ben-manes.caffeine:caffeine`.

### 4.2 Que Key Vault sea una fuente de propiedades (sin código)
```xml
<dependency>
  <groupId>com.azure.spring</groupId>
  <artifactId>spring-cloud-azure-starter-keyvault</artifactId>
</dependency>
```
```properties
spring.cloud.azure.keyvault.secret.property-source-enabled=true
spring.cloud.azure.keyvault.secret.property-sources[0].endpoint=https://kv-modalima-estudio01.vault.azure.net
```
Con eso un secreto del vault se puede inyectar como propiedad (`@Value`, `@ConfigurationProperties`). Los nombres de secreto **solo admiten letras, números y guiones**, por eso se usa la convención `spring-datasource-password`; Spring Cloud Azure la expone también como `spring.datasource.password`. *Verifica el mapeo de nombres y la compatibilidad de versión con Spring Boot en la documentación de Spring Cloud Azure.*

> Las propiedades se cargan **al arrancar**. Si rotas el secreto, o reinicias o implementas una relectura (caché de la sección 3, o la opción de refresco que ofrezca tu versión de Spring Cloud Azure).

### 4.3 AKS con CSI: leer los secretos como archivos
El driver monta los secretos en `/mnt/secrets-store` (un archivo por secreto). Spring Boot los lee con `configtree`, sin SDK ni dependencias:
```properties
spring.config.import=optional:configtree:/mnt/secrets-store/
```
Si montas el secreto con `objectAlias: spring.datasource.password`, ya queda como la propiedad que Spring espera. Ver [ejemplos/yaml/secretproviderclass.yaml](ejemplos/yaml/secretproviderclass.yaml).

## 5. Spring Boot (reactivo, WebFlux)
El SDK trae clientes asíncronos basados en Reactor. Nunca bloquees el hilo del event loop con el cliente síncrono.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretAsyncClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import reactor.core.publisher.Mono;

class SecretosReactivos {
    private final SecretAsyncClient cliente;
    private final Duration ttl = Duration.ofMinutes(5);
    private final Map<String, Mono<String>> cache = new ConcurrentHashMap<>();

    SecretosReactivos(String vaultUrl) {
        this.cliente = new SecretClientBuilder()
                .vaultUrl(vaultUrl)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildAsyncClient();
    }

    Mono<String> valor(String nombre) {
        return cache.computeIfAbsent(nombre, n ->
                cliente.getSecret(n)
                        .map(KeyVaultSecret::getValue)
                        .cache(v -> ttl, e -> Duration.ZERO, () -> Duration.ZERO));
    }
}
```
`Mono.cache(...)` memoriza el valor durante el TTL y **no memoriza los errores** (TTL cero), de modo que un fallo puntual no queda pegado.

## 6. Quarkus (imperativo)

### 6.1 Cliente como bean CDI y readiness
```java
import com.azure.core.exception.HttpResponseException;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;

@ApplicationScoped
class KeyVaultProducer {
    @ConfigProperty(name = "app.keyvault.url")
    String url;

    @Produces
    @ApplicationScoped
    SecretClient secretClient() {
        return new SecretClientBuilder()
                .vaultUrl(url)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }
}

@Readiness
@ApplicationScoped
class KeyVaultReadiness implements HealthCheck {
    @Inject
    SecretClient cliente;

    @Override
    public HealthCheckResponse call() {
        try {
            cliente.getSecret("canario");
            return HealthCheckResponse.up("key-vault");
        } catch (HttpResponseException e) {
            return HealthCheckResponse.named("key-vault")
                    .down()
                    .withData("http", e.getResponse().getStatusCode())
                    .build();
        }
    }
}
```
> Existe la extensión de Quarkiverse `quarkus-azure-services` (con soporte de Key Vault). Verifica los módulos y la versión compatible con tu Quarkus; el cliente manual de arriba siempre funciona.

### 6.2 Contraseña de base de datos desde Key Vault (CredentialsProvider)
Quarkus pide la contraseña **cada vez que el pool abre una conexión nueva**, así que la rotación se aplica sola a las conexiones nuevas.

```java
import com.azure.security.keyvault.secrets.SecretClient;
import io.quarkus.arc.Unremovable;
import io.quarkus.credentials.CredentialsProvider;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import java.util.Map;

@ApplicationScoped
@Unremovable
@Named("kv-db")
class KeyVaultCredenciales implements CredentialsProvider {
    @Inject
    SecretClient cliente;

    @Override
    public Map<String, String> getCredentials(String credentialsProviderName) {
        String password = cliente.getSecret("db-password").getValue();
        return Map.of(
                CredentialsProvider.USER_PROPERTY_NAME, "app_pedidos",
                CredentialsProvider.PASSWORD_PROPERTY_NAME, password);
    }
}
```
```properties
quarkus.datasource.credentials-provider=kv-db
quarkus.datasource.credentials-provider-name=kv-db
```
Para no llamar al vault en cada conexión, cachea dentro del proveedor (sección 3).

## 7. Quarkus (reactivo, Mutiny)
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretAsyncClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;
import io.smallrye.mutiny.Uni;
import java.time.Duration;

class SecretosMutiny {
    private final SecretAsyncClient cliente;

    SecretosMutiny(String vaultUrl) {
        this.cliente = new SecretClientBuilder()
                .vaultUrl(vaultUrl)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildAsyncClient();
    }

    Uni<String> valor(String nombre) {
        return Uni.createFrom().completionStage(() -> cliente.getSecret(nombre).toFuture())
                .map(KeyVaultSecret::getValue)
                .ifNoItem().after(Duration.ofSeconds(5)).fail()
                .memoize().atLeast(Duration.ofMinutes(5));
    }
}
```
`memoize().atLeast(...)` hace de caché y `ifNoItem().after(...)` pone un tope de espera. (Si el `Uni` se memoiza por instancia, guarda uno por nombre de secreto.)

## 8. Rotación de la contraseña con un pool (Spring + HikariCP)
Cuando rotas la contraseña de la base, las conexiones nuevas deben usar la nueva y las viejas deben cerrarse con calma.

```java
import com.azure.security.keyvault.secrets.SecretClient;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class RotacionPassword {
    private final HikariDataSource ds;
    private final SecretClient cliente;

    RotacionPassword(HikariDataSource ds, SecretClient cliente) {
        this.ds = ds;
        this.cliente = cliente;
    }

    @Scheduled(fixedDelayString = "PT5M")   // requiere @EnableScheduling
    void refrescar() {
        String actual = cliente.getSecret("db-password").getValue();
        if (!actual.equals(ds.getPassword())) {
            ds.setPassword(actual);                              // las conexiones NUEVAS usarán la nueva
            if (ds.getHikariPoolMXBean() != null) {
                ds.getHikariPoolMXBean().softEvictConnections(); // las viejas se cierran al devolverse
            }
        }
    }
}
```
> HikariCP permite cambiar usuario y contraseña en caliente por su interfaz de gestión. Verifica el comportamiento de tu versión. Para la rotación **sin caída** necesitas la **doble credencial**: la nueva ya debe ser válida cuando el pool empiece a usarla.

## 9. Claves: cifrado de sobre (envelope encryption)
La clave maestra **nunca sale** del vault; solo envuelve claves pequeñas. Guarda **el identificador de la versión de la clave** junto al dato: después de rotar, necesitas la versión correcta para desenvolver.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.keys.cryptography.CryptographyClient;
import com.azure.security.keyvault.keys.cryptography.CryptographyClientBuilder;
import com.azure.security.keyvault.keys.cryptography.models.KeyWrapAlgorithm;
import com.azure.security.keyvault.keys.cryptography.models.WrapResult;
import java.security.SecureRandom;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

class CifradoSobre {
    record Paquete(byte[] iv, byte[] cifrado, byte[] claveEnvuelta, String idClave) {}

    private final String urlClave;   // https://kv-modalima.vault.azure.net/keys/k-reportes

    CifradoSobre(String urlClave) {
        this.urlClave = urlClave;
    }

    private CryptographyClient cliente(String identificador) {
        return new CryptographyClientBuilder()
                .keyIdentifier(identificador)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }

    Paquete cifrar(byte[] datos) throws Exception {
        // 1) clave de datos AES local, nueva para cada archivo
        KeyGenerator generador = KeyGenerator.getInstance("AES");
        generador.init(256);
        SecretKey claveDatos = generador.generateKey();

        // 2) cifrar los datos localmente (AES-GCM)
        byte[] iv = new byte[12];
        new SecureRandom().nextBytes(iv);
        Cipher aes = Cipher.getInstance("AES/GCM/NoPadding");
        aes.init(Cipher.ENCRYPT_MODE, claveDatos, new GCMParameterSpec(128, iv));
        byte[] cifrado = aes.doFinal(datos);

        // 3) envolver la clave de datos con la clave maestra del vault
        WrapResult envuelta = cliente(urlClave)
                .wrapKey(KeyWrapAlgorithm.RSA_OAEP_256, claveDatos.getEncoded());

        return new Paquete(iv, cifrado, envuelta.getEncryptedKey(), envuelta.getKeyId());
    }

    byte[] descifrar(Paquete p) throws Exception {
        // la versión exacta de la clave viene en el paquete
        byte[] claveBytes = cliente(p.idClave())
                .unwrapKey(KeyWrapAlgorithm.RSA_OAEP_256, p.claveEnvuelta())
                .getKey();

        Cipher aes = Cipher.getInstance("AES/GCM/NoPadding");
        aes.init(Cipher.DECRYPT_MODE, new SecretKeySpec(claveBytes, "AES"), new GCMParameterSpec(128, p.iv()));
        return aes.doFinal(p.cifrado());
    }
}
```
Rol necesario: **Key Vault Crypto User** sobre la clave. En producción, reutiliza el `CryptographyClient` (no lo crees en cada llamada) y guarda el paquete como un solo objeto/archivo.

## 10. Certificados
Un certificado con clave privada se descarga **como secreto** (mismo nombre). El contenido es un PKCS12 en Base64 sin contraseña.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.certificates.CertificateClient;
import com.azure.security.keyvault.certificates.CertificateClientBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import java.io.ByteArrayInputStream;
import java.security.KeyStore;
import java.time.OffsetDateTime;
import java.util.Base64;

class Certificados {
    private final SecretClient secretos;
    private final CertificateClient certificados;

    Certificados(String vaultUrl) {
        var credencial = new DefaultAzureCredentialBuilder().build();
        this.secretos = new SecretClientBuilder().vaultUrl(vaultUrl).credential(credencial).buildClient();
        this.certificados = new CertificateClientBuilder().vaultUrl(vaultUrl).credential(credencial).buildClient();
    }

    KeyStore cargarKeyStore(String nombre) throws Exception {
        byte[] pfx = Base64.getDecoder().decode(secretos.getSecret(nombre).getValue());
        KeyStore ks = KeyStore.getInstance("PKCS12");
        ks.load(new ByteArrayInputStream(pfx), new char[0]);   // Key Vault lo emite sin contraseña
        return ks;
    }

    OffsetDateTime venceEl(String nombre) {
        return certificados.getCertificate(nombre).getProperties().getExpiresOn();
    }
}
```
Roles: *Key Vault Certificate User* o *Secrets User* para descargar con clave privada; *Certificates Officer* para crear/renovar. Para exponer HTTPS con ese `KeyStore`, configura el servidor TLS de tu framework y **vuelve a cargarlo** cuando cambie la versión.

## 11. Reintentos y tiempos de espera
El SDK ya reintenta (backoff exponencial), pero conviene fijar topes para que un vault lento no cuelgue tu servicio.

```java
import com.azure.core.http.HttpClient;
import com.azure.core.http.netty.NettyAsyncHttpClientBuilder;
import com.azure.core.http.policy.ExponentialBackoffOptions;
import com.azure.core.http.policy.RetryOptions;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import java.time.Duration;

class ClienteConTopes {
    static SecretClient crear(String url) {
        HttpClient http = new NettyAsyncHttpClientBuilder()
                .connectTimeout(Duration.ofSeconds(3))
                .responseTimeout(Duration.ofSeconds(5))
                .build();

        return new SecretClientBuilder()
                .vaultUrl(url)
                .credential(new DefaultAzureCredentialBuilder().build())
                .httpClient(http)
                .retryOptions(new RetryOptions(new ExponentialBackoffOptions()
                        .setMaxRetries(3)
                        .setBaseDelay(Duration.ofMillis(500))
                        .setMaxDelay(Duration.ofSeconds(5))))
                .buildClient();
    }
}
```
Un `429` respeta el encabezado `Retry-After`; la solución duradera es **cachear**, no reintentar más.

## 12. Errores comunes
```java
import com.azure.core.exception.HttpResponseException;
import com.azure.core.exception.ResourceNotFoundException;
import com.azure.identity.CredentialUnavailableException;
import com.azure.security.keyvault.secrets.SecretClient;

class LecturaSegura {
    String leer(SecretClient cliente, String nombre) {
        try {
            return cliente.getSecret(nombre).getValue();
        } catch (CredentialUnavailableException e) {
            // Sin identidad: en local falta `az login`; en Azure no está asignada la identidad al recurso
            throw new IllegalStateException("No hay credencial de Azure disponible", e);
        } catch (ResourceNotFoundException e) {
            throw new IllegalStateException("El secreto no existe o está deshabilitado: " + nombre, e);
        } catch (HttpResponseException e) {
            int estado = e.getResponse().getStatusCode();
            // 401: token/audiencia. 403: falta rol de datos, o firewall/red del vault. 429: demasiadas lecturas
            throw new IllegalStateException("Key Vault respondió " + estado, e);
        }
    }
}
```

| Respuesta | Qué revisar |
|---|---|
| 401 | Token inválido; reloj desfasado; audiencia equivocada |
| 403 `ForbiddenByRbac` | Falta rol de datos (*Secrets User*) o aún no se propagó |
| 403 `ForbiddenByFirewall` | La red de origen no está permitida (firewall/Private Endpoint/DNS) |
| 404 | Nombre o vault equivocado; secreto deshabilitado; secreto en *soft delete* |
| 429 | Demasiadas lecturas: cachea |
| `CredentialUnavailableException` | La identidad no está disponible en este entorno |

## 13. Health check en Spring Boot 4
```java
import com.azure.core.exception.HttpResponseException;
import com.azure.security.keyvault.secrets.SecretClient;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

@Component("keyVault")
class KeyVaultHealth implements HealthIndicator {
    private final SecretClient cliente;

    KeyVaultHealth(SecretClient cliente) {
        this.cliente = cliente;
    }

    @Override
    public Health health() {
        try {
            cliente.getSecret("canario");     // un secreto de prueba dedicado y sin valor real
            return Health.up().build();
        } catch (HttpResponseException e) {
            return Health.down().withDetail("http", e.getResponse().getStatusCode()).build();
        } catch (RuntimeException e) {
            return Health.down().withDetail("error", e.getClass().getSimpleName()).build();
        }
    }
}
```
> Los chequeos de salud corren muy seguido: limita su frecuencia (`management.endpoint.health.cache.time-to-live`) para no gastar el cupo de peticiones del vault.

## 14. Qué NO hacer
- No crear un `SecretClient` por petición (pide tokens sin parar).
- No leer el secreto en cada petición HTTP.
- No imprimir el valor ni el token en logs, excepciones o `toString()`.
- No dejar `AZURE_CLIENT_SECRET` en las variables del contenedor: cambia el orden de credenciales sin avisar.
- No bloquear hilos del event loop (WebFlux/Vert.x) con el cliente síncrono.
- No guardar el secreto en campos `static` que nunca se refrescan.
