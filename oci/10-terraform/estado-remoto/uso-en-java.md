# Oracle OCI · Terraform · Estado remoto · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Desde Java **no ejecutas `apply` ni editas el estado**: eso lo hacen los pipelines. Lo que sí construyes es un **auditor de solo lectura** del bucket del estado: ¿es privado, versionado y con llave propia? ¿Hay bloqueos viejos (runner muerto)? ¿Estados fuera de la convención o demasiado grandes? Usa `ObjectStorageClient.getBucket` y `listObjects` paginando con `nextStartWith`.

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

### 2.2 Auditor (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/** Revisa el bucket del estado y sus objetos: protección, convenciones, tamaños y bloqueos viejos. Puro. */
public class AuditorDeEstado {

    public record Bucket(String nombre, boolean versionado, boolean publico, boolean conLlavePropia) { }

    public record Objeto(String nombre, long bytes, Instant modificado) { }

    public record Hallazgo(String severidad, String objeto, String mensaje) { }

    private static final Pattern CLAVE = Pattern.compile("[a-z0-9-]+/(prod|no-prod)/[a-z0-9-]+\\.tfstate");

    private final Clock reloj;
    private final Duration bloqueoMaximo;
    private final long bytesMaximo;

    public AuditorDeEstado(Clock reloj, Duration bloqueoMaximo, long bytesMaximo) {
        this.reloj = reloj;
        this.bloqueoMaximo = bloqueoMaximo;
        this.bytesMaximo = bytesMaximo;
    }

    public List<Hallazgo> auditar(Bucket b, List<Objeto> objetos) {
        var h = new ArrayList<Hallazgo>();
        if (b.publico()) {
            h.add(new Hallazgo("CRITICA", b.nombre(), "bucket del estado con acceso público"));
        }
        if (!b.versionado()) {
            h.add(new Hallazgo("ALTA", b.nombre(), "sin versionado: un estado corrupto no se recupera"));
        }
        if (!b.conLlavePropia()) {
            h.add(new Hallazgo("MEDIA", b.nombre(), "sin llave propia (CMK)"));
        }
        Instant ahora = reloj.instant();
        for (Objeto o : objetos) {
            String n = o.nombre();
            if (n.endsWith(".lock") || n.endsWith(".tflock")) {
                if (o.modificado().isBefore(ahora.minus(bloqueoMaximo))) {
                    h.add(new Hallazgo("ALTA", n, "bloqueo con más de " + bloqueoMaximo.toMinutes() + " min: ¿runner muerto?"));
                }
            } else if (n.endsWith(".tfstate")) {
                if (!CLAVE.matcher(n).matches()) {
                    h.add(new Hallazgo("BAJA", n, "clave fuera de la convención unidad/entorno/componente.tfstate"));
                }
                if (o.bytes() > bytesMaximo) {
                    h.add(new Hallazgo("MEDIA", n, "estado muy grande (" + o.bytes() / 1024 + " KB): divide el componente"));
                }
            }
        }
        return h;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.model.Bucket;
import com.oracle.bmc.objectstorage.requests.GetBucketRequest;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import com.oracle.bmc.objectstorage.requests.ListObjectsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: lectura del bucket del estado (solo lectura). */
public class EstadoOci implements AutoCloseable {

    private final ObjectStorageClient cliente;
    private final String namespace;

    public EstadoOci(ObjectStorageClient cliente) {
        this.cliente = cliente;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public AuditorDeEstado.Bucket bucket(String nombre) {
        var b = cliente.getBucket(GetBucketRequest.builder().namespaceName(namespace).bucketName(nombre).build()).getBucket();
        return new AuditorDeEstado.Bucket(nombre, b.getVersioning() == Bucket.Versioning.Enabled,
            b.getPublicAccessType() != Bucket.PublicAccessType.NoPublicAccess, b.getKmsKeyId() != null);
    }

    public List<AuditorDeEstado.Objeto> objetos(String bucket) {
        var out = new ArrayList<AuditorDeEstado.Objeto>();
        String inicio = null;
        do {
            var r = cliente.listObjects(ListObjectsRequest.builder().namespaceName(namespace).bucketName(bucket)
                .fields("name,size,timeModified").start(inicio).build()).getListObjects();
            r.getObjects().forEach(o -> out.add(new AuditorDeEstado.Objeto(o.getName(),
                o.getSize() == null ? 0 : o.getSize(), o.getTimeModified().toInstant())));
            inicio = r.getNextStartWith();
        } while (inicio != null);
        return out;
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
import java.time.Duration;
import java.util.List;

public class ServicioDeEstado {

    private final EstadoOci estado;
    private final AuditorDeEstado auditor = new AuditorDeEstado(Clock.systemUTC(), Duration.ofMinutes(60), 5L * 1024 * 1024);

    public ServicioDeEstado(EstadoOci estado) {
        this.estado = estado;
    }

    public List<AuditorDeEstado.Hallazgo> auditar(String bucket) {
        return auditor.auditar(estado.bucket(bucket), estado.objetos(bucket));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EstadoConfiguracion {

    @Bean(destroyMethod = "close")
    EstadoOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new EstadoOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeEstado servicio(EstadoOci a) {
        return new ServicioDeEstado(a);
    }
}

@RestController
@RequestMapping("/terraform/estado")
class EstadoControlador {

    private final ServicioDeEstado s;

    EstadoControlador(ServicioDeEstado s) {
        this.s = s;
    }

    @GetMapping("/{bucket}")
    List<AuditorDeEstado.Hallazgo> auditar(@PathVariable String bucket) {
        return s.auditar(bucket);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/terraform/estado")
class EstadoReactivoControlador {

    private final ServicioDeEstado s;

    EstadoReactivoControlador(ServicioDeEstado s) {
        this.s = s;
    }

    @GetMapping("/{bucket}")
    Mono<List<AuditorDeEstado.Hallazgo>> auditar(@PathVariable String bucket) {
        return Mono.fromCallable(() -> s.auditar(bucket)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class EstadoProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    EstadoOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new EstadoOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes EstadoOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEstado servicio(EstadoOci a) {
        return new ServicioDeEstado(a);
    }
}

@Path("/terraform/estado")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EstadoRecurso {

    @Inject
    ServicioDeEstado s;

    @GET
    @Path("/{bucket}")
    public List<AuditorDeEstado.Hallazgo> auditar(@PathParam("bucket") String bucket) {
        return s.auditar(bucket);
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.List;

@Path("/reactivo/terraform/estado")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EstadoRecursoReactivo {

    @Inject
    ServicioDeEstado s;

    @GET
    @Path("/{bucket}")
    public Uni<List<AuditorDeEstado.Hallazgo>> auditar(@PathParam("bucket") String bucket) {
        return Uni.createFrom().item(() -> s.auditar(bucket)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer bucket y listar objetos (sin leer contenido) | `Allow dynamic-group auditoria to read buckets in compartment plataforma where target.bucket.name = 'tfstate-modalima'` y `Allow dynamic-group auditoria to inspect objects in compartment plataforma where target.bucket.name = 'tfstate-modalima'` |

## 8. Qué NO hacer desde Java
- No leas el contenido del estado desde una app: contiene secretos.
- No borres bloqueos desde código: avisa y que una persona haga `force-unlock`.
- No le des a la app permisos de escritura sobre el bucket del estado.
- No olvides paginar `listObjects` con `nextStartWith`.
