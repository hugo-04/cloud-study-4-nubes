# Oracle OCI · Storage · File Storage · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **auditor de exports NFS**: recorre todos los exports del compartimento con `FileStorageClient` (paginando) y marca orígenes abiertos o demasiado amplios, lectura-escritura sin *root squash*, falta de puerto privilegiado y acceso anónimo. En NFS esas opciones **son** la política de acceso a los datos.

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
import java.util.ArrayList;
import java.util.List;

/** Revisa las export options de NFS. Puro: recibe opciones simplificadas. */
public class AuditorDeExports {

    public record Opcion(String origen, boolean lecturaEscritura, String squash, boolean puertoPrivilegiado, boolean anonimo) { }

    public record Hallazgo(String ruta, String origen, String severidad, String mensaje) { }

    public List<Hallazgo> auditar(String ruta, List<Opcion> opciones) {
        var h = new ArrayList<Hallazgo>();
        for (Opcion o : opciones) {
            int prefijo = Integer.parseInt(o.origen().substring(o.origen().indexOf('/') + 1));
            if (prefijo == 0) {
                h.add(new Hallazgo(ruta, o.origen(), "ALTA", "abierto a cualquier origen"));
            } else if (prefijo < 16) {
                h.add(new Hallazgo(ruta, o.origen(), "MEDIA", "rango de origen muy amplio (/" + prefijo + ")"));
            }
            if (o.lecturaEscritura() && "NONE".equals(o.squash())) {
                h.add(new Hallazgo(ruta, o.origen(), "ALTA", "lectura-escritura sin root squash"));
            }
            if (!o.puertoPrivilegiado()) {
                h.add(new Hallazgo(ruta, o.origen(), "BAJA", "no exige puerto privilegiado"));
            }
            if (o.anonimo()) {
                h.add(new Hallazgo(ruta, o.origen(), "MEDIA", "permite acceso anónimo"));
            }
        }
        return h;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.filestorage.FileStorageClient;
import com.oracle.bmc.filestorage.model.ClientOptions;
import com.oracle.bmc.filestorage.model.ExportSummary;
import com.oracle.bmc.filestorage.requests.GetExportRequest;
import com.oracle.bmc.filestorage.requests.ListExportsRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Adaptador del SDK: lee todos los exports del compartimento con sus opciones. */
public class ExportsOci implements AutoCloseable {

    private final FileStorageClient cliente;

    public ExportsOci(FileStorageClient cliente) {
        this.cliente = cliente;
    }

    public List<Map.Entry<String, List<AuditorDeExports.Opcion>>> exports(String compartimentoId) {
        var out = new ArrayList<Map.Entry<String, List<AuditorDeExports.Opcion>>>();
        String pagina = null;
        do {
            var r = cliente.listExports(ListExportsRequest.builder().compartmentId(compartimentoId)
                .lifecycleState(ListExportsRequest.LifecycleState.Active).page(pagina).build());
            for (ExportSummary s : r.getItems()) {
                var e = cliente.getExport(GetExportRequest.builder().exportId(s.getId()).build()).getExport();
                out.add(Map.entry(e.getPath(), e.getExportOptions().stream().map(ExportsOci::aOpcion).toList()));
            }
            pagina = r.getOpcNextPage();
        } while (pagina != null);
        return out;
    }

    private static AuditorDeExports.Opcion aOpcion(ClientOptions c) {
        return new AuditorDeExports.Opcion(c.getSource(), c.getAccess() == ClientOptions.Access.ReadWrite,
            c.getIdentitySquash().getValue(), Boolean.TRUE.equals(c.getRequirePrivilegedSourcePort()),
            Boolean.TRUE.equals(c.getIsAnonymousAccessAllowed()));
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
import java.util.List;

public class ServicioDeAuditoriaNfs {

    private final ExportsOci exports;
    private final AuditorDeExports auditor = new AuditorDeExports();

    public ServicioDeAuditoriaNfs(ExportsOci exports) {
        this.exports = exports;
    }

    public List<AuditorDeExports.Hallazgo> auditar(String compartimentoId) {
        return exports.exports(compartimentoId).stream()
            .flatMap(e -> auditor.auditar(e.getKey(), e.getValue()).stream())
            .toList();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.filestorage.FileStorageClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class NfsConfiguracion {

    @Bean(destroyMethod = "close")
    ExportsOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ExportsOci(FileStorageClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeAuditoriaNfs servicio(ExportsOci a) {
        return new ServicioDeAuditoriaNfs(a);
    }
}

@RestController
@RequestMapping("/storage/nfs")
class NfsControlador {

    private final ServicioDeAuditoriaNfs s;

    NfsControlador(ServicioDeAuditoriaNfs s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeExports.Hallazgo> auditar(@RequestParam String compartimento) {
        return s.auditar(compartimento);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.filestorage.FileStorageClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/storage/nfs")
class NfsReactivoControlador {

    private final ServicioDeAuditoriaNfs s;

    NfsReactivoControlador(ServicioDeAuditoriaNfs s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeExports.Hallazgo>> auditar(@RequestParam String compartimento) {
        return Mono.fromCallable(() -> s.auditar(compartimento)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.filestorage.FileStorageClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class NfsProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ExportsOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ExportsOci(FileStorageClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes ExportsOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeAuditoriaNfs servicio(ExportsOci a) {
        return new ServicioDeAuditoriaNfs(a);
    }
}

@Path("/storage/nfs")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class NfsRecurso {

    @Inject
    ServicioDeAuditoriaNfs s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeExports.Hallazgo> auditar(@QueryParam("compartimento") String compartimento) {
        return s.auditar(compartimento);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.filestorage.FileStorageClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/storage/nfs")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class NfsRecursoReactivo {

    @Inject
    ServicioDeAuditoriaNfs s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeExports.Hallazgo>> auditar(@QueryParam("compartimento") String compartimento) {
        return Uni.createFrom().item(() -> s.auditar(compartimento)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Listar y leer exports | `Allow dynamic-group auditoria to read file-family in compartment tienda-prod` |

## 8. Qué NO hacer desde Java
- No uses la API de OCI para leer o escribir archivos: el plano de datos es NFS (monta y usa `java.nio.file`).
- No escribas el mismo archivo desde varias réplicas sin coordinación: usa nombres únicos y renombrado atómico.
- No hagas `Files.walk` sobre millones de archivos en cada petición.
- No corras el contenedor como root para «arreglar» permisos.
