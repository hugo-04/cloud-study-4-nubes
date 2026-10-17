# Oracle OCI · Storage · Claim check · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

El **sobre híbrido** completo: la lógica pura decide si la carga va en línea o por referencia (calculando el crecimiento de base64), serializa el ticket con su huella SHA-256 y verifica al canjear; el adaptador escribe el objeto **antes** de enviar el ticket con `QueueClient.putMessages` y lo canjea con `getObject`.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
cc:
  bucket: cargas
  colaId: ocid1.queue.oc1.sa-saopaulo-1.aaaa
  endpoint: https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
cc.bucket=cargas
cc.colaId=ocid1.queue.oc1.sa-saopaulo-1.aaaa
cc.endpoint=https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com
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

### 2.2 Sobre híbrido (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.HexFormat;

/** Sobre híbrido del claim check: en línea si cabe, por referencia si no. Puro (sin SDK). */
public class SobreClaimCheck {

    public sealed interface Sobre permits EnLinea, Referencia { }

    public record EnLinea(byte[] carga) implements Sobre { }

    public record Referencia(String objeto, String sha256, long bytes) implements Sobre { }

    private final int umbralBytes;

    public SobreClaimCheck(int umbralBytes) {
        this.umbralBytes = umbralBytes;
    }

    /** Decide el sobre. El nombre del objeto es determinista por id de mensaje. */
    public Sobre armar(String idMensaje, byte[] carga) {
        if (!idMensaje.matches("[A-Za-z0-9-]{1,64}")) {
            throw new IllegalArgumentException("id de mensaje inválido");
        }
        // base64 crece ~4/3: se compara con el tamaño que realmente viajará
        if ((carga.length + 2) / 3 * 4 <= umbralBytes) {
            return new EnLinea(carga);
        }
        return new Referencia("cargas/" + idMensaje + ".bin", sha256(carga), carga.length);
    }

    public String serializar(Sobre s) {
        return switch (s) {
            case EnLinea e -> "v1|INL|" + Base64.getEncoder().encodeToString(e.carga());
            case Referencia r -> "v1|REF|" + r.objeto() + "|" + r.sha256() + "|" + r.bytes();
        };
    }

    public Sobre leer(String texto) {
        String[] p = texto.split("\\|");
        if (p.length < 3 || !p[0].equals("v1")) {
            throw new IllegalArgumentException("sobre desconocido");
        }
        return switch (p[1]) {
            case "INL" -> new EnLinea(Base64.getDecoder().decode(p[2]));
            case "REF" -> new Referencia(p[2], p[3], Long.parseLong(p[4]));
            default -> throw new IllegalArgumentException("tipo de sobre desconocido");
        };
    }

    /** Verifica que la carga canjeada es exactamente la enviada. */
    public byte[] verificar(Referencia r, byte[] canjeada) {
        if (canjeada.length != r.bytes() || !MessageDigest.isEqual(
                sha256(canjeada).getBytes(StandardCharsets.US_ASCII), r.sha256().getBytes(StandardCharsets.US_ASCII))) {
            throw new IllegalStateException("la carga no coincide con el ticket");
        }
        return canjeada;
    }

    static String sha256(byte[] datos) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(datos));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.GetObjectRequest;
import com.oracle.bmc.objectstorage.requests.PutObjectRequest;
import com.oracle.bmc.queue.QueueClient;
import com.oracle.bmc.queue.model.PutMessagesDetails;
import com.oracle.bmc.queue.model.PutMessagesDetailsEntry;
import com.oracle.bmc.queue.requests.PutMessagesRequest;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador del SDK: guardarropa (Object Storage) + transporte del ticket (OCI Queue). */
public class ClaimCheckOci implements AutoCloseable {

    private final ObjectStorageClient objetos;
    private final QueueClient cola;
    private final String bucket;
    private final String colaId;
    private final String namespace;

    public ClaimCheckOci(ObjectStorageClient objetos, QueueClient cola, String bucket, String colaId) {
        this.objetos = objetos;
        this.cola = cola;
        this.bucket = bucket;
        this.colaId = colaId;
        this.namespace = objetos.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public void guardar(String objeto, byte[] carga) {
        objetos.putObject(PutObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).contentLength((long) carga.length)
            .putObjectBody(new ByteArrayInputStream(carga)).build());
    }

    public byte[] canjear(String objeto) {
        var r = objetos.getObject(GetObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).build());
        try (var in = r.getInputStream()) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public void enviar(String ticket) {
        cola.putMessages(PutMessagesRequest.builder().queueId(colaId)
            .putMessagesDetails(PutMessagesDetails.builder()
                .messages(List.of(PutMessagesDetailsEntry.builder().content(ticket).build())).build())
            .build());
    }

    @Override
    public void close() {
        objetos.close();
        cola.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;

public class ServicioDeClaimCheck {

    public record Envio(String id, String carga) { }

    private final ClaimCheckOci cc;
    private final SobreClaimCheck sobres = new SobreClaimCheck(64 * 1024);

    public ServicioDeClaimCheck(ClaimCheckOci cc) {
        this.cc = cc;
    }

    /** Productor: primero el objeto, luego el ticket. */
    public String enviar(Envio e) {
        var sobre = sobres.armar(e.id(), e.carga().getBytes(StandardCharsets.UTF_8));
        if (sobre instanceof SobreClaimCheck.Referencia r) {
            cc.guardar(r.objeto(), e.carga().getBytes(StandardCharsets.UTF_8));
        }
        String ticket = sobres.serializar(sobre);
        cc.enviar(ticket);
        return ticket.length() > 80 ? ticket.substring(0, 80) + "…" : ticket;
    }

    /** Consumidor: recibe el texto del mensaje y devuelve la carga verificada. */
    public String canjear(String ticket) {
        return switch (sobres.leer(ticket)) {
            case SobreClaimCheck.EnLinea l -> new String(l.carga(), StandardCharsets.UTF_8);
            case SobreClaimCheck.Referencia r -> new String(sobres.verificar(r, cc.canjear(r.objeto())), StandardCharsets.UTF_8);
        };
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.queue.QueueClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ClaimCheckConfiguracion {

    @Bean(destroyMethod = "close")
    ClaimCheckOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${cc.bucket}") String bucket, @Value("${cc.colaId}") String colaId, @Value("${cc.endpoint}") String endpoint) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        var objetos = ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth);
        // la cola usa su propio endpoint de mensajes (sale en Terraform: messages_endpoint)
        var cola = QueueClient.builder().endpoint(endpoint).build(auth);
        return new ClaimCheckOci(objetos, cola, bucket, colaId);
    }

    @Bean
    ServicioDeClaimCheck servicio(ClaimCheckOci a) {
        return new ServicioDeClaimCheck(a);
    }
}

@RestController
@RequestMapping("/storage/claim-check")
class ClaimCheckControlador {

    private final ServicioDeClaimCheck s;

    ClaimCheckControlador(ServicioDeClaimCheck s) {
        this.s = s;
    }

    @PostMapping("/enviar")
    String enviar(@RequestBody ServicioDeClaimCheck.Envio e) {
        return s.enviar(e);
    }

    @PostMapping("/canjear")
    String canjear(@RequestBody String ticket) {
        return s.canjear(ticket);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.queue.QueueClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/storage/claim-check")
class ClaimCheckReactivoControlador {

    private final ServicioDeClaimCheck s;

    ClaimCheckReactivoControlador(ServicioDeClaimCheck s) {
        this.s = s;
    }

    @PostMapping("/enviar")
    Mono<String> enviar(@RequestBody ServicioDeClaimCheck.Envio e) {
        return Mono.fromCallable(() -> s.enviar(e)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/canjear")
    Mono<String> canjear(@RequestBody String ticket) {
        return Mono.fromCallable(() -> s.canjear(ticket)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.queue.QueueClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ClaimCheckProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "cc.bucket")
    String bucket;

    @ConfigProperty(name = "cc.colaId")
    String colaId;

    @ConfigProperty(name = "cc.endpoint")
    String endpoint;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ClaimCheckOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        var objetos = ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth);
        // la cola usa su propio endpoint de mensajes (sale en Terraform: messages_endpoint)
        var cola = QueueClient.builder().endpoint(endpoint).build(auth);
        return new ClaimCheckOci(objetos, cola, bucket, colaId);
    }

    void cerrar(@Disposes ClaimCheckOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeClaimCheck servicio(ClaimCheckOci a) {
        return new ServicioDeClaimCheck(a);
    }
}

@Path("/storage/claim-check")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ClaimCheckRecurso {

    @Inject
    ServicioDeClaimCheck s;

    @POST
    @Path("/enviar")
    @Consumes(MediaType.APPLICATION_JSON)
    public String enviar(ServicioDeClaimCheck.Envio e) {
        return s.enviar(e);
    }

    @POST
    @Path("/canjear")
    @Consumes(MediaType.APPLICATION_JSON)
    public String canjear(String ticket) {
        return s.canjear(ticket);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.queue.QueueClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

@Path("/reactivo/storage/claim-check")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ClaimCheckRecursoReactivo {

    @Inject
    ServicioDeClaimCheck s;

    @POST
    @Path("/enviar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> enviar(ServicioDeClaimCheck.Envio e) {
        return Uni.createFrom().item(() -> s.enviar(e)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/canjear")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> canjear(String ticket) {
        return Uni.createFrom().item(() -> s.canjear(ticket)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Productor: crear objeto + enviar | `Allow dynamic-group productores to manage objects in compartment tienda-prod where all {target.bucket.name = 'cargas', request.permission = 'OBJECT_CREATE'}` y `Allow dynamic-group productores to use queues in compartment tienda-prod` |
| Consumidor: leer objeto | `Allow dynamic-group consumidores to read objects in compartment tienda-prod where target.bucket.name = 'cargas'` |

## 8. Qué NO hacer desde Java
- No envíes el ticket antes de que `putObject` confirme.
- No borres la carga desde el consumidor: deja que el ciclo de vida lo haga.
- No pongas una PAR en el ticket.
- No leas cargas de varios MB en memoria si puedes procesarlas en *streaming*.
