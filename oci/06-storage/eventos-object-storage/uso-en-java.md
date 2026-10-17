# Oracle OCI · Storage · Eventos de Object Storage · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **consumidor de eventos** de Object Storage (la misma lógica sirve dentro de una función o detrás de un endpoint HTTP de Notifications): el núcleo puro filtra por tipo, bucket, prefijo y extensión y **deduplica por `eventID`**; el adaptador hace `headObject` para confirmar que el objeto sigue ahí con el mismo ETag antes de procesarlo.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
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

### 2.2 Procesador de eventos (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** Decide qué hacer con un evento de Object Storage: filtra, deduplica por eventID. Puro. */
public class ProcesadorDeEventos {

    /** Forma del evento (CloudEvents de OCI); el framework lo deserializa desde JSON. */
    public record Evento(String eventType, String eventID, String eventTime, Datos data) { }

    public record Datos(String resourceName, Detalles additionalDetails) { }

    public record Detalles(String bucketName, String namespace, String eTag) { }

    public enum Accion { PROCESAR, DUPLICADO, IGNORAR }

    public record Decision(Accion accion, String motivo) { }

    private final String bucketEsperado;
    private final String prefijo;
    private final Set<String> extensiones;
    private final Set<String> vistos;

    public ProcesadorDeEventos(String bucketEsperado, String prefijo, Set<String> extensiones, int memoria) {
        this.bucketEsperado = bucketEsperado;
        this.prefijo = prefijo;
        this.extensiones = Set.copyOf(extensiones);
        // conjunto acotado (LRU): en producción usa una tabla con expiración compartida entre réplicas
        this.vistos = Collections.synchronizedSet(Collections.newSetFromMap(new LinkedHashMap<String, Boolean>(16, 0.75f, true) {
            @Override
            protected boolean removeEldestEntry(Map.Entry<String, Boolean> e) {
                return size() > memoria;
            }
        }));
    }

    public Decision decidir(Evento e) {
        if (e == null || e.data() == null || e.data().additionalDetails() == null || e.eventID() == null) {
            return new Decision(Accion.IGNORAR, "evento incompleto");
        }
        if (!e.eventType().endsWith(".createobject") && !e.eventType().endsWith(".updateobject")) {
            return new Decision(Accion.IGNORAR, "tipo no relevante");
        }
        if (!bucketEsperado.equals(e.data().additionalDetails().bucketName())) {
            return new Decision(Accion.IGNORAR, "otro bucket");
        }
        String nombre = e.data().resourceName();
        if (nombre == null || !nombre.startsWith(prefijo) || nombre.contains("..")) {
            return new Decision(Accion.IGNORAR, "fuera del prefijo");
        }
        String ext = nombre.substring(nombre.lastIndexOf('.') + 1).toLowerCase(java.util.Locale.ROOT);
        if (!extensiones.contains(ext)) {
            return new Decision(Accion.IGNORAR, "extensión no admitida");
        }
        if (!vistos.add(e.eventID())) {
            return new Decision(Accion.DUPLICADO, "eventID ya procesado");
        }
        return new Decision(Accion.PROCESAR, nombre);
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.model.BmcException;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.HeadObjectRequest;
import java.util.Optional;

/** Adaptador del SDK: comprueba que el objeto sigue existiendo y con el mismo ETag. */
public class ObjetosOci implements AutoCloseable {

    public record Info(long bytes, String tipo, String etag) { }

    private final ObjectStorageClient cliente;

    public ObjetosOci(ObjectStorageClient cliente) {
        this.cliente = cliente;
    }

    public Optional<Info> head(String namespace, String bucket, String nombre) {
        try {
            var r = cliente.headObject(HeadObjectRequest.builder()
                .namespaceName(namespace).bucketName(bucket).objectName(nombre).build());
            return Optional.of(new Info(r.getContentLength(), r.getContentType(), r.getETag()));
        } catch (BmcException e) {
            if (e.getStatusCode() == 404) {
                return Optional.empty();
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
import java.util.Set;

public class ServicioDeEventos {

    public record Resultado(String accion, String detalle) { }

    private final ObjetosOci objetos;
    private final ProcesadorDeEventos procesador = new ProcesadorDeEventos("fotos-productos", "fotos/", Set.of("jpg", "png"), 10_000);

    public ServicioDeEventos(ObjetosOci objetos) {
        this.objetos = objetos;
    }

    public Resultado recibir(ProcesadorDeEventos.Evento e) {
        var d = procesador.decidir(e);
        if (d.accion() != ProcesadorDeEventos.Accion.PROCESAR) {
            return new Resultado(d.accion().name(), d.motivo());
        }
        var det = e.data().additionalDetails();
        return objetos.head(det.namespace(), det.bucketName(), e.data().resourceName())
            .filter(i -> det.eTag() == null || det.eTag().equals(i.etag()))
            .map(i -> new Resultado("PROCESAR", e.data().resourceName() + " (" + i.bytes() + " bytes)"))
            .orElse(new Resultado("IGNORAR", "el objeto ya no existe o cambió"));
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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EventosConfiguracion {

    @Bean(destroyMethod = "close")
    ObjetosOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ObjetosOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeEventos servicio(ObjetosOci a) {
        return new ServicioDeEventos(a);
    }
}

@RestController
@RequestMapping("/storage/eventos")
class EventosControlador {

    private final ServicioDeEventos s;

    EventosControlador(ServicioDeEventos s) {
        this.s = s;
    }

    @PostMapping("")
    ServicioDeEventos.Resultado recibir(@RequestBody ProcesadorDeEventos.Evento e) {
        return s.recibir(e);
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
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/storage/eventos")
class EventosReactivoControlador {

    private final ServicioDeEventos s;

    EventosReactivoControlador(ServicioDeEventos s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<ServicioDeEventos.Resultado> recibir(@RequestBody ProcesadorDeEventos.Evento e) {
        return Mono.fromCallable(() -> s.recibir(e)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EventosProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ObjetosOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ObjetosOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes ObjetosOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEventos servicio(ObjetosOci a) {
        return new ServicioDeEventos(a);
    }
}

@Path("/storage/eventos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EventosRecurso {

    @Inject
    ServicioDeEventos s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeEventos.Resultado recibir(ProcesadorDeEventos.Evento e) {
        return s.recibir(e);
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

@Path("/reactivo/storage/eventos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EventosRecursoReactivo {

    @Inject
    ServicioDeEventos s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeEventos.Resultado> recibir(ProcesadorDeEventos.Evento e) {
        return Uni.createFrom().item(() -> s.recibir(e)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `headObject` en el bucket de origen | `Allow dynamic-group consumidores to read objects in compartment tienda-prod where target.bucket.name = 'fotos-productos'` |
| Escribir el resultado | `Allow dynamic-group consumidores to manage objects in compartment tienda-prod where target.bucket.name = 'miniaturas'` |

## 8. Qué NO hacer desde Java
- No supongas que cada evento llega una sola vez ni en orden.
- No escribas el resultado en el bucket/prefijo que dispara la regla.
- No uses la deduplicación en memoria con varias réplicas: compártela (tabla con expiración o caché distribuida).
- No descargues el objeto antes de filtrar: decide primero con los metadatos del evento.
