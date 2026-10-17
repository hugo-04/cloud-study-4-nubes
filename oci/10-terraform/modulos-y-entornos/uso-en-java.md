# Oracle OCI · Terraform · Módulos y entornos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **comparador de entornos**: lee dos stacks de Resource Manager (no-prod y prod del mismo componente) con `ResourceManagerClient.getStack` y reporta diferencias de versión de Terraform, variables que difieren o faltan **fuera de la lista permitida** (tamaño, réplicas, IDs del entorno) y stacks con drift. Sirve como control antes de promover una versión.

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

### 2.2 Comparador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/** Compara dos entornos del mismo componente: solo pueden diferir las variables permitidas. Puro. */
public class ComparadorDeEntornos {

    public record Entorno(String nombre, String versionTerraform, String drift, Map<String, String> variables) { }

    public record Diferencia(String tipo, String clave, String valorA, String valorB) { }

    private final Set<String> permitidas;

    public ComparadorDeEntornos(Set<String> permitidas) {
        this.permitidas = Set.copyOf(permitidas);
    }

    public List<Diferencia> comparar(Entorno a, Entorno b) {
        var out = new ArrayList<Diferencia>();
        if (!a.versionTerraform().equals(b.versionTerraform())) {
            out.add(new Diferencia("version-terraform", "-", a.versionTerraform(), b.versionTerraform()));
        }
        var claves = new TreeSet<String>();
        claves.addAll(a.variables().keySet());
        claves.addAll(b.variables().keySet());
        for (String k : claves) {
            if (permitidas.contains(k)) {
                continue;
            }
            String va = a.variables().get(k);
            String vb = b.variables().get(k);
            if (va == null || vb == null) {
                out.add(new Diferencia("variable-ausente", k, va, vb));
            } else if (!va.equals(vb)) {
                out.add(new Diferencia("variable-distinta", k, va, vb));
            }
        }
        for (Entorno e : List.of(a, b)) {
            if ("DRIFTED".equals(e.drift())) {
                out.add(new Diferencia("drift", e.nombre(), "cambios fuera de Terraform", null));
            }
        }
        return out;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.resourcemanager.ResourceManagerClient;
import com.oracle.bmc.resourcemanager.requests.GetStackRequest;
import java.util.Map;

/** Adaptador del SDK: lee variables, versión de Terraform y estado de drift de un stack. */
public class StacksOci implements AutoCloseable {

    private final ResourceManagerClient cliente;

    public StacksOci(ResourceManagerClient cliente) {
        this.cliente = cliente;
    }

    public ComparadorDeEntornos.Entorno leer(String stackId) {
        var s = cliente.getStack(GetStackRequest.builder().stackId(stackId).build()).getStack();
        return new ComparadorDeEntornos.Entorno(s.getDisplayName(), s.getTerraformVersion(),
            s.getStackDriftStatus() == null ? "NOT_CHECKED" : s.getStackDriftStatus().getValue(),
            s.getVariables() == null ? Map.of() : s.getVariables());
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
import java.util.Set;

public class ServicioDeEntornos {

    private final StacksOci stacks;
    // Lo único que puede variar entre prod y no-prod
    private final ComparadorDeEntornos comparador = new ComparadorDeEntornos(
        Set.of("entorno", "compartimento_id", "replicas", "ocpus", "memoria_gb", "vcn_id", "nsg_lb_id"));

    public ServicioDeEntornos(StacksOci stacks) {
        this.stacks = stacks;
    }

    public List<ComparadorDeEntornos.Diferencia> comparar(String stackNoProd, String stackProd) {
        return comparador.comparar(stacks.leer(stackNoProd), stacks.leer(stackProd));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.resourcemanager.ResourceManagerClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class EntornosConfiguracion {

    @Bean(destroyMethod = "close")
    StacksOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new StacksOci(ResourceManagerClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeEntornos servicio(StacksOci a) {
        return new ServicioDeEntornos(a);
    }
}

@RestController
@RequestMapping("/terraform/entornos")
class EntornosControlador {

    private final ServicioDeEntornos s;

    EntornosControlador(ServicioDeEntornos s) {
        this.s = s;
    }

    @GetMapping("/comparacion")
    List<ComparadorDeEntornos.Diferencia> comparar(@RequestParam String noProd, @RequestParam String prod) {
        return s.comparar(noProd, prod);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.resourcemanager.ResourceManagerClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/terraform/entornos")
class EntornosReactivoControlador {

    private final ServicioDeEntornos s;

    EntornosReactivoControlador(ServicioDeEntornos s) {
        this.s = s;
    }

    @GetMapping("/comparacion")
    Mono<List<ComparadorDeEntornos.Diferencia>> comparar(@RequestParam String noProd, @RequestParam String prod) {
        return Mono.fromCallable(() -> s.comparar(noProd, prod)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.resourcemanager.ResourceManagerClient;
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
class EntornosProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    StacksOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new StacksOci(ResourceManagerClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes StacksOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeEntornos servicio(StacksOci a) {
        return new ServicioDeEntornos(a);
    }
}

@Path("/terraform/entornos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class EntornosRecurso {

    @Inject
    ServicioDeEntornos s;

    @GET
    @Path("/comparacion")
    public List<ComparadorDeEntornos.Diferencia> comparar(@QueryParam("noProd") String noProd, @QueryParam("prod") String prod) {
        return s.comparar(noProd, prod);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.resourcemanager.ResourceManagerClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/terraform/entornos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class EntornosRecursoReactivo {

    @Inject
    ServicioDeEntornos s;

    @GET
    @Path("/comparacion")
    public Uni<List<ComparadorDeEntornos.Diferencia>> comparar(@QueryParam("noProd") String noProd, @QueryParam("prod") String prod) {
        return Uni.createFrom().item(() -> s.comparar(noProd, prod)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer stacks | `Allow dynamic-group plataforma to read orm-stacks in compartment modalima` |

## 8. Qué NO hacer desde Java
- No expongas las variables de los stacks: pueden contener datos sensibles (márcalas como sensibles en Terraform).
- No lances `apply` desde una app de consulta.
- No compares entornos por nombre de stack: usa IDs y convenciones explícitas.
