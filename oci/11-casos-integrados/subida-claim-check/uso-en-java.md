# Oracle OCI · Caso integrado · Subida con claim check · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

El validador de la cuarentena: una **máquina de estados con transiciones condicionales** (un evento duplicado no hace nada), **validación por firma** de los primeros bytes (JPEG, PNG, PDF) y tamaño, y un adaptador que lee solo 16 bytes con un `Range`, mueve con `renameObject` condicionado por ETag (y destino inexistente) o borra el rechazado.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
subidas:
  bucket: subidas
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
subidas.bucket=subidas
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

### 2.2 Estados y validación (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/** Máquina de estados de una subida y validación por firma. Pura. */
public final class Subidas {

    private Subidas() { }

    public enum Estado { PENDIENTE, RECIBIDA, APROBADA, RECHAZADA, EXPIRADA, PROCESADA }

    private static final Map<Estado, Set<Estado>> PERMITIDAS = Map.of(
        Estado.PENDIENTE, Set.of(Estado.RECIBIDA, Estado.EXPIRADA),
        Estado.RECIBIDA, Set.of(Estado.APROBADA, Estado.RECHAZADA),
        Estado.APROBADA, Set.of(Estado.PROCESADA));

    /** Transición condicional: si el estado actual no es el esperado, no se hace nada (evento duplicado). */
    public static Optional<Estado> transicion(Estado actual, Estado esperado, Estado nuevo) {
        if (actual != esperado || !PERMITIDAS.getOrDefault(actual, Set.of()).contains(nuevo)) {
            return Optional.empty();
        }
        return Optional.of(nuevo);
    }

    public record Veredicto(boolean aprobado, String tipo, String motivo) { }

    /** Valida por los primeros bytes (firma), nunca por la extensión. */
    public static Veredicto validar(byte[] cabecera, long bytes, long maxBytes) {
        if (bytes <= 0 || bytes > maxBytes) {
            return new Veredicto(false, null, "tamaño fuera de rango");
        }
        if (empieza(cabecera, 0xFF, 0xD8, 0xFF)) {
            return new Veredicto(true, "image/jpeg", "ok");
        }
        if (empieza(cabecera, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) {
            return new Veredicto(true, "image/png", "ok");
        }
        if (empieza(cabecera, 0x25, 0x50, 0x44, 0x46, 0x2D)) {
            return new Veredicto(true, "application/pdf", "ok");
        }
        return new Veredicto(false, null, "tipo no permitido");
    }

    private static boolean empieza(byte[] b, int... firma) {
        if (b.length < firma.length) {
            return false;
        }
        for (int i = 0; i < firma.length; i++) {
            if ((b[i] & 0xFF) != firma[i]) {
                return false;
            }
        }
        return true;
    }

    public static String destino(String objetoEnCuarentena) {
        if (!objetoEnCuarentena.matches("cuarentena/S-[0-9]{1,20}\\.[a-z]{3,4}")) {
            throw new IllegalArgumentException("nombre fuera de la convención");
        }
        return "aprobados/" + objetoEnCuarentena.substring("cuarentena/".length());
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.model.Range;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.model.RenameObjectDetails;
import com.oracle.bmc.objectstorage.requests.DeleteObjectRequest;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.GetObjectRequest;
import com.oracle.bmc.objectstorage.requests.HeadObjectRequest;
import com.oracle.bmc.objectstorage.requests.RenameObjectRequest;
import java.io.IOException;
import java.io.UncheckedIOException;

/** Adaptador del SDK: leer la cabecera con un rango, mover condicionalmente y borrar rechazados. */
public class SubidasOci implements AutoCloseable {

    public record Info(long bytes, String etag) { }

    private final ObjectStorageClient cliente;
    private final String bucket;
    private final String namespace;

    public SubidasOci(ObjectStorageClient cliente, String bucket) {
        this.cliente = cliente;
        this.bucket = bucket;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public Info info(String objeto) {
        var h = cliente.headObject(HeadObjectRequest.builder().namespaceName(namespace).bucketName(bucket).objectName(objeto).build());
        return new Info(h.getContentLength(), h.getETag());
    }

    public byte[] cabecera(String objeto, int n) {
        var r = cliente.getObject(GetObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).range(new Range(0L, (long) n - 1)).build());
        try (var in = r.getInputStream()) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Mueve solo si el origen no cambió (ETag) y el destino no existe. */
    public void mover(String origen, String destino, String etag) {
        cliente.renameObject(RenameObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .renameObjectDetails(RenameObjectDetails.builder().sourceName(origen).newName(destino)
                .srcObjIfMatchETag(etag).newObjIfNoneMatchETag("*").build()).build());
    }

    public void borrar(String objeto, String etag) {
        cliente.deleteObject(DeleteObjectRequest.builder().namespaceName(namespace).bucketName(bucket)
            .objectName(objeto).ifMatch(etag).build());
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
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDeSubidas {

    public record Resultado(String id, String estado, String detalle) { }

    private final SubidasOci objetos;
    // Demo: estados en memoria; en la app real, NoSQL o la base con actualización condicional.
    private final Map<String, Subidas.Estado> estados = new ConcurrentHashMap<>();

    public ServicioDeSubidas(SubidasOci objetos) {
        this.objetos = objetos;
    }

    /** Lo invoca el consumidor del evento createobject (función o endpoint). */
    public Resultado alLlegar(String objeto) {
        String id = objeto.substring(objeto.indexOf('/') + 1, objeto.lastIndexOf('.'));
        estados.putIfAbsent(id, Subidas.Estado.PENDIENTE);
        if (Subidas.transicion(estados.get(id), Subidas.Estado.PENDIENTE, Subidas.Estado.RECIBIDA).isEmpty()) {
            return new Resultado(id, estados.get(id).name(), "evento duplicado: ignorado");
        }
        estados.put(id, Subidas.Estado.RECIBIDA);
        var info = objetos.info(objeto);
        var v = Subidas.validar(objetos.cabecera(objeto, 16), info.bytes(), 25L * 1024 * 1024);
        if (!v.aprobado()) {
            objetos.borrar(objeto, info.etag());
            estados.put(id, Subidas.Estado.RECHAZADA);
            return new Resultado(id, "RECHAZADA", v.motivo());
        }
        objetos.mover(objeto, Subidas.destino(objeto), info.etag());
        estados.put(id, Subidas.Estado.APROBADA);
        return new Resultado(id, "APROBADA", v.tipo()); // aquí se envía el ticket a la cola
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class SubidasConfiguracion {

    @Bean(destroyMethod = "close")
    SubidasOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${subidas.bucket}") String bucket) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new SubidasOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);
    }

    @Bean
    ServicioDeSubidas servicio(SubidasOci a) {
        return new ServicioDeSubidas(a);
    }
}

@RestController
@RequestMapping("/casos/subidas")
class SubidasControlador {

    private final ServicioDeSubidas s;

    SubidasControlador(ServicioDeSubidas s) {
        this.s = s;
    }

    @PostMapping("/evento")
    ServicioDeSubidas.Resultado alLlegar(@RequestParam String objeto) {
        return s.alLlegar(objeto);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/casos/subidas")
class SubidasReactivoControlador {

    private final ServicioDeSubidas s;

    SubidasReactivoControlador(ServicioDeSubidas s) {
        this.s = s;
    }

    @PostMapping("/evento")
    Mono<ServicioDeSubidas.Resultado> alLlegar(@RequestParam String objeto) {
        return Mono.fromCallable(() -> s.alLlegar(objeto)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class SubidasProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "subidas.bucket")
    String bucket;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SubidasOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new SubidasOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);
    }

    void cerrar(@Disposes SubidasOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeSubidas servicio(SubidasOci a) {
        return new ServicioDeSubidas(a);
    }
}

@Path("/casos/subidas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class SubidasRecurso {

    @Inject
    ServicioDeSubidas s;

    @POST
    @Path("/evento")
    public ServicioDeSubidas.Resultado alLlegar(@QueryParam("objeto") String objeto) {
        return s.alLlegar(objeto);
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
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/casos/subidas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class SubidasRecursoReactivo {

    @Inject
    ServicioDeSubidas s;

    @POST
    @Path("/evento")
    public Uni<ServicioDeSubidas.Resultado> alLlegar(@QueryParam("objeto") String objeto) {
        return Uni.createFrom().item(() -> s.alLlegar(objeto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer, mover y borrar en el bucket de subidas | `Allow dynamic-group funciones-tienda to manage objects in compartment tienda-prod where target.bucket.name = 'subidas'` |

## 8. Qué NO hacer desde Java
- No descargues el archivo completo para validar el tipo: basta un rango.
- No muevas sin condición de ETag.
- No apruebes por extensión o `Content-Type`.
- No proceses archivos fuera de la convención de nombres.
