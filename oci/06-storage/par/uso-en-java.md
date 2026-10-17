# Oracle OCI · Storage · PAR · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **emisor de PAR con reglas**: la lógica pura solo acepta un objeto concreto bajo prefijos permitidos, una operación (leer o escribir) y vencimientos cortos; el adaptador llama a `createPreauthenticatedRequest`, devuelve la URL **una sola vez** y permite revocar por id.

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

### 2.2 Política de emisión (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;

/** Reglas de emisión de PAR: un objeto, una operación, poco tiempo y solo bajo prefijos permitidos. Puro. */
public class PoliticaDePar {

    public enum Operacion { LEER, ESCRIBIR }

    public record Plan(String nombrePar, String objeto, Operacion operacion, Instant vence) { }

    private final Clock reloj;
    private final List<String> prefijosPermitidos;

    public PoliticaDePar(Clock reloj, List<String> prefijosPermitidos) {
        this.reloj = reloj;
        this.prefijosPermitidos = List.copyOf(prefijosPermitidos);
    }

    public Plan planificar(String objeto, Operacion op, int minutos) {
        if (objeto == null || objeto.contains("..") || objeto.startsWith("/") || objeto.endsWith("/")) {
            throw new IllegalArgumentException("nombre de objeto inválido");
        }
        if (prefijosPermitidos.stream().noneMatch(objeto::startsWith)) {
            throw new IllegalArgumentException("prefijo no permitido para PAR");
        }
        int max = op == Operacion.LEER ? 15 : 30;
        if (minutos < 1 || minutos > max) {
            throw new IllegalArgumentException("vencimiento entre 1 y " + max + " minutos");
        }
        Instant ahora = reloj.instant();
        String nombre = (op == Operacion.LEER ? "lee-" : "escribe-") + Integer.toHexString(objeto.hashCode()) + "-" + ahora.getEpochSecond();
        return new Plan(nombre, objeto, op, ahora.plus(Duration.ofMinutes(minutos)));
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.model.CreatePreauthenticatedRequestDetails;
import com.oracle.bmc.objectstorage.requests.CreatePreauthenticatedRequestRequest;
import com.oracle.bmc.objectstorage.requests.DeletePreauthenticatedRequestRequest;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;
import java.util.Date;

/** Adaptador del SDK: crea y revoca PAR. La URL solo existe en la respuesta de creación. */
public class ParOci implements AutoCloseable {

    public record Emitida(String id, String url, String vence) { }

    private final ObjectStorageClient cliente;
    private final String bucket;
    private final String namespace;

    public ParOci(ObjectStorageClient cliente, String bucket) {
        this.cliente = cliente;
        this.bucket = bucket;
        this.namespace = cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    public Emitida crear(PoliticaDePar.Plan p) {
        var tipo = p.operacion() == PoliticaDePar.Operacion.LEER
            ? CreatePreauthenticatedRequestDetails.AccessType.ObjectRead
            : CreatePreauthenticatedRequestDetails.AccessType.ObjectWrite;
        var par = cliente.createPreauthenticatedRequest(CreatePreauthenticatedRequestRequest.builder()
            .namespaceName(namespace).bucketName(bucket)
            .createPreauthenticatedRequestDetails(CreatePreauthenticatedRequestDetails.builder()
                .name(p.nombrePar()).objectName(p.objeto()).accessType(tipo)
                .timeExpires(Date.from(p.vence())).build())
            .build()).getPreauthenticatedRequest();
        return new Emitida(par.getId(), par.getFullPath(), p.vence().toString());
    }

    public void revocar(String parId) {
        cliente.deletePreauthenticatedRequest(DeletePreauthenticatedRequestRequest.builder()
            .namespaceName(namespace).bucketName(bucket).parId(parId).build());
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
import java.util.List;

public class ServicioDePar {

    public record Pedido(String objeto, PoliticaDePar.Operacion operacion, int minutos) { }

    private final ParOci par;
    private final PoliticaDePar politica = new PoliticaDePar(Clock.systemUTC(), List.of("pedidos/", "fotos/"));

    public ServicioDePar(ParOci par) {
        this.par = par;
    }

    public ParOci.Emitida emitir(Pedido p) {
        // aquí iría la regla de negocio: ¿este usuario es dueño del pedido?
        return par.crear(politica.planificar(p.objeto(), p.operacion(), p.minutos()));
    }

    public String revocar(String id) {
        par.revocar(id);
        return "revocada";
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
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ParConfiguracion {

    @Bean(destroyMethod = "close")
    ParOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${almacen.bucket}") String bucket) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ParOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);
    }

    @Bean
    ServicioDePar servicio(ParOci a) {
        return new ServicioDePar(a);
    }
}

@RestController
@RequestMapping("/storage/par")
class ParControlador {

    private final ServicioDePar s;

    ParControlador(ServicioDePar s) {
        this.s = s;
    }

    @PostMapping("")
    ParOci.Emitida emitir(@RequestBody ServicioDePar.Pedido p) {
        return s.emitir(p);
    }

    @DeleteMapping("/{id}")
    String revocar(@PathVariable String id) {
        return s.revocar(id);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/storage/par")
class ParReactivoControlador {

    private final ServicioDePar s;

    ParReactivoControlador(ServicioDePar s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<ParOci.Emitida> emitir(@RequestBody ServicioDePar.Pedido p) {
        return Mono.fromCallable(() -> s.emitir(p)).subscribeOn(Schedulers.boundedElastic());
    }

    @DeleteMapping("/{id}")
    Mono<String> revocar(@PathVariable String id) {
        return Mono.fromCallable(() -> s.revocar(id)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ParProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "almacen.bucket")
    String bucket;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ParOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ParOci(ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth), bucket);
    }

    void cerrar(@Disposes ParOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePar servicio(ParOci a) {
        return new ServicioDePar(a);
    }
}

@Path("/storage/par")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ParRecurso {

    @Inject
    ServicioDePar s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public ParOci.Emitida emitir(ServicioDePar.Pedido p) {
        return s.emitir(p);
    }

    @DELETE
    @Path("/{id}")
    public String revocar(@PathParam("id") String id) {
        return s.revocar(id);
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
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/storage/par")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ParRecursoReactivo {

    @Inject
    ServicioDePar s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ParOci.Emitida> emitir(ServicioDePar.Pedido p) {
        return Uni.createFrom().item(() -> s.emitir(p)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @DELETE
    @Path("/{id}")
    public Uni<String> revocar(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> s.revocar(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Crear y borrar PAR + delegar lectura/escritura | `Allow dynamic-group app-pedidos to manage objects in compartment tienda-prod where all {target.bucket.name = 'comprobantes', any {request.permission = 'PAR_MANAGE', request.permission = 'OBJECT_READ', request.permission = 'OBJECT_CREATE'}}` |

## 8. Qué NO hacer desde Java
- No registres la URL (`fullPath`/`accessUri`): registra el id.
- No permitas que el cliente elija el nombre del objeto a escribir.
- No emitas PAR `Any*` desde la app: si hace falta, que sea infraestructura revisada.
- No cachees URLs de PAR para reutilizarlas: emite una nueva cuando se necesite.
- No te saltes la autorización de negocio: verifica que el usuario es dueño del objeto.
