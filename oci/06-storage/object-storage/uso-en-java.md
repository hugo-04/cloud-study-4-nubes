# Oracle OCI · Storage · Object Storage · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **guardado idempotente de comprobantes**: la lógica pura valida tipo y tamaño y arma un nombre determinista (`pedidos/AAAA/MM/DD/<id>.pdf`); el adaptador hace `putObject` con `If-None-Match: *`, así un reintento nunca pisa el comprobante ya enviado (un `412` significa «ya existía»).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
almacen:
  bucket: comprobantes
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
almacen.bucket=comprobantes
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

### 2.2 Nombres y validación (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/** Reglas de nombre, tipo y tamaño de los comprobantes. Puro: reloj inyectado. */
public class NombradorDeComprobantes {

    private static final Map<String, String> EXTENSIONES = Map.of("application/pdf", "pdf", "image/png", "png", "image/jpeg", "jpg");
    private static final DateTimeFormatter RUTA = DateTimeFormatter.ofPattern("yyyy/MM/dd");

    private final Clock reloj;
    private final long maxBytes;

    public NombradorDeComprobantes(Clock reloj, long maxBytes) {
        this.reloj = reloj;
        this.maxBytes = maxBytes;
    }

    /** Mismo pedido y mismo día ⇒ mismo nombre: los reintentos no crean copias. */
    public String nombre(String idPedido, String tipo, long bytes) {
        if (idPedido == null || !idPedido.matches("P-[0-9]{1,12}")) {
            throw new IllegalArgumentException("idPedido inválido");
        }
        String ext = EXTENSIONES.get(tipo);
        if (ext == null) {
            throw new IllegalArgumentException("tipo no permitido: " + tipo);
        }
        if (bytes <= 0 || bytes > maxBytes) {
            throw new IllegalArgumentException("tamaño fuera de rango (máx. " + maxBytes + " bytes)");
        }
        return "pedidos/" + LocalDate.now(reloj).format(RUTA) + "/" + idPedido + "." + ext;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.model.BmcException;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.PutObjectRequest;
import java.io.ByteArrayInputStream;
import java.util.Map;

/** Adaptador del SDK: escribe solo si el objeto no existe (If-None-Match: *). */
public class AlmacenOci implements AutoCloseable {

    public record Guardado(String nombre, boolean nuevo, String etag) { }

    private final ObjectStorageClient cliente;
    private final String bucket;
    private final String namespace;

    public AlmacenOci(ObjectStorageClient cliente, String bucket) {
        this.cliente = cliente;
        this.bucket = bucket;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public Guardado guardarSiNoExiste(String nombre, byte[] datos, String tipo, Map<String, String> meta) {
        try {
            var r = cliente.putObject(PutObjectRequest.builder()
                .namespaceName(namespace).bucketName(bucket).objectName(nombre)
                .contentType(tipo).contentLength((long) datos.length)
                .putObjectBody(new ByteArrayInputStream(datos))
                .opcMeta(meta)
                .ifNoneMatch("*")
                .build());
            return new Guardado(nombre, true, r.getETag());
        } catch (BmcException e) {
            if (e.getStatusCode() == 412) {
                return new Guardado(nombre, false, null); // ya existía: el reintento es inocuo
            }
            throw e;
        }
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
import java.time.Clock;
import java.util.Base64;
import java.util.Map;

public class ServicioDeComprobantes {

    public record Subida(String tipo, String contenidoBase64) { }

    private final AlmacenOci almacen;
    private final NombradorDeComprobantes nombrador = new NombradorDeComprobantes(Clock.systemUTC(), 5 * 1024 * 1024);

    public ServicioDeComprobantes(AlmacenOci almacen) {
        this.almacen = almacen;
    }

    public AlmacenOci.Guardado subir(String idPedido, Subida s) {
        byte[] datos = Base64.getDecoder().decode(s.contenidoBase64());
        String nombre = nombrador.nombre(idPedido, s.tipo(), datos.length);
        return almacen.guardarSiNoExiste(nombre, datos, s.tipo(), Map.of("pedido", idPedido));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ComprobantesConfiguracion {

    @Bean(destroyMethod = "close")
    AlmacenOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${almacen.bucket}") String bucket) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new AlmacenOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);
    }

    @Bean
    ServicioDeComprobantes servicio(AlmacenOci a) {
        return new ServicioDeComprobantes(a);
    }
}

@RestController
@RequestMapping("/storage/comprobantes")
class ComprobantesControlador {

    private final ServicioDeComprobantes s;

    ComprobantesControlador(ServicioDeComprobantes s) {
        this.s = s;
    }

    @PostMapping("/{id}")
    AlmacenOci.Guardado subir(@PathVariable String id, @RequestBody ServicioDeComprobantes.Subida sub) {
        return s.subir(id, sub);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/storage/comprobantes")
class ComprobantesReactivoControlador {

    private final ServicioDeComprobantes s;

    ComprobantesReactivoControlador(ServicioDeComprobantes s) {
        this.s = s;
    }

    @PostMapping("/{id}")
    Mono<AlmacenOci.Guardado> subir(@PathVariable String id, @RequestBody ServicioDeComprobantes.Subida sub) {
        return Mono.fromCallable(() -> s.subir(id, sub)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
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
class ComprobantesProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "almacen.bucket")
    String bucket;

    @jakarta.enterprise.inject.Produces
    @Singleton
    AlmacenOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new AlmacenOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);
    }

    void cerrar(@Disposes AlmacenOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeComprobantes servicio(AlmacenOci a) {
        return new ServicioDeComprobantes(a);
    }
}

@Path("/storage/comprobantes")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ComprobantesRecurso {

    @Inject
    ServicioDeComprobantes s;

    @POST
    @Path("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public AlmacenOci.Guardado subir(@PathParam("id") String id, ServicioDeComprobantes.Subida sub) {
        return s.subir(id, sub);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/storage/comprobantes")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ComprobantesRecursoReactivo {

    @Inject
    ServicioDeComprobantes s;

    @POST
    @Path("/{id}")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<AlmacenOci.Guardado> subir(@PathParam("id") String id, ServicioDeComprobantes.Subida sub) {
        return Uni.createFrom().item(() -> s.subir(id, sub)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Escribir objetos del bucket | `Allow dynamic-group app-pedidos to manage objects in compartment tienda-prod where all {target.bucket.name = 'comprobantes', any {request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_INSPECT'}}` |
| `getNamespace` | No requiere política adicional |

## 8. Qué NO hacer desde Java
- No cargues archivos de varios GB en memoria: usa `UploadManager` (multipart) con un `InputStream`.
- No crees un `ObjectStorageClient` por petición: es caro; uno por aplicación.
- No confíes en el `Content-Type` que envía el usuario sin validarlo.
- No registres el contenido ni los metadatos personales.
- No uses buckets públicos para servir archivos: PAR o un backend que valide.
