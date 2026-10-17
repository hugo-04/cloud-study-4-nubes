# Oracle OCI · IAM · Compartimentos, grupos y políticas · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Dos herramientas: un **linter de frases** (puro, sin red: detecta `any-user` sin condición y `manage all-resources`) y un **auditor** que lee las políticas reales de un compartimento con el SDK y las pasa por el linter.

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

### 2.2 Hallazgo
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public record Hallazgo(String severidad, String frase, String motivo) {

    public static final String ALTA = "ALTA";
    public static final String MEDIA = "MEDIA";
    public static final String ERROR = "ERROR";

    public static List<String> orden() {
        return List.of(ERROR, ALTA, MEDIA);
    }
}
```

### 2.3 El linter de frases
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

/** Revisa frases de políticas OCI sin llamar a la red. */
public final class LinterDePoliticas {

    private static final Pattern FRASE = Pattern.compile(
        "^allow\\s+(any-user|(?:group|dynamic-group|service)\\s+.+?)\\s+to\\s+(inspect|read|use|manage)\\s+(\\S+)\\s+in\\s+(tenancy|compartment\\s+(?:id\\s+)?\\S+)(?:\\s+where\\s+(.+))?$",
        Pattern.CASE_INSENSITIVE);

    public List<Hallazgo> revisar(List<String> frases) {
        var salida = new ArrayList<Hallazgo>();
        for (String frase : frases) {
            String f = frase == null ? "" : frase.strip();
            var m = FRASE.matcher(f);
            if (!m.matches()) {
                salida.add(new Hallazgo(Hallazgo.ERROR, f, "no sigue la forma «Allow <quién> to <verbo> <recurso> in <dónde>»"));
                continue;
            }
            String quien = m.group(1).toLowerCase(Locale.ROOT);
            String verbo = m.group(2).toLowerCase(Locale.ROOT);
            String recurso = m.group(3).toLowerCase(Locale.ROOT);
            boolean tenancy = m.group(4).equalsIgnoreCase("tenancy");
            boolean condicion = m.group(5) != null && !m.group(5).isBlank();
            boolean manage = verbo.equals("manage");
            boolean todo = recurso.equals("all-resources");
            if (quien.equals("any-user") && !condicion) {
                salida.add(new Hallazgo(Hallazgo.ALTA, f, "any-user sin condición abre el recurso a cualquier principal"));
            }
            if (manage && todo && tenancy) {
                salida.add(new Hallazgo(Hallazgo.ALTA, f, "manage all-resources en todo el tenancy es el poder del administrador"));
            } else if (manage && todo) {
                salida.add(new Hallazgo(Hallazgo.MEDIA, f, "manage all-resources: ¿basta con una familia de recursos o con use/read?"));
            } else if (manage && tenancy) {
                salida.add(new Hallazgo(Hallazgo.MEDIA, f, "manage en todo el tenancy: acota a un compartimento"));
            }
        }
        return salida;
    }
}
```

### 2.4 Lectura de políticas con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.Policy;
import com.oracle.bmc.identity.requests.ListPoliciesRequest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Lee las políticas de un compartimento con paginación del SDK. */
public class PoliticasOci {

    private final IdentityClient cliente;

    public PoliticasOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public Map<String, List<String>> frasesPorPolitica(String compartimentoId) {
        var req = ListPoliciesRequest.builder().compartmentId(compartimentoId).build();
        var salida = new LinkedHashMap<String, List<String>>();
        for (Policy p : cliente.getPaginators().listPoliciesRecordIterator(req)) {
            salida.put(p.getName(), new ArrayList<>(p.getStatements()));
        }
        return salida;
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class ServicioDePoliticas {

    private final LinterDePoliticas linter;
    private final PoliticasOci politicas;

    public ServicioDePoliticas(LinterDePoliticas linter, PoliticasOci politicas) {
        this.linter = linter;
        this.politicas = politicas;
    }

    public record HallazgoDePolitica(String politica, Hallazgo hallazgo) { }

    public List<HallazgoDePolitica> auditar(String compartimentoId) {
        var salida = new ArrayList<HallazgoDePolitica>();
        for (Map.Entry<String, List<String>> e : politicas.frasesPorPolitica(compartimentoId).entrySet()) {
            for (Hallazgo h : linter.revisar(e.getValue())) {
                salida.add(new HallazgoDePolitica(e.getKey(), h));
            }
        }
        return salida;
    }

    public List<Hallazgo> revisar(List<String> frases) {
        return linter.revisar(frases);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class PoliticasConfiguracion {

    @Bean(destroyMethod = "close")
    IdentityClient identidadCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDePoliticas servicioDePoliticas(IdentityClient cliente) {
        return new ServicioDePoliticas(new LinterDePoliticas(), new PoliticasOci(cliente));
    }
}

@RestController
@RequestMapping("/iam/politicas")
class PoliticasControlador {

    private final ServicioDePoliticas s;

    PoliticasControlador(ServicioDePoliticas s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<ServicioDePoliticas.HallazgoDePolitica> auditoria(@RequestParam String compartimento) {
        return s.auditar(compartimento);
    }

    @PostMapping("/revisar")
    List<Hallazgo> revisar(@RequestBody List<String> frases) {
        return s.revisar(frases);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/iam/politicas")
class PoliticasReactivoControlador {

    private final ServicioDePoliticas s;

    PoliticasReactivoControlador(ServicioDePoliticas s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<ServicioDePoliticas.HallazgoDePolitica>> auditoria(@RequestParam String compartimento) {
        return Mono.fromCallable(() -> s.auditar(compartimento)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/revisar")
    Mono<List<Hallazgo>> revisar(@RequestBody List<String> frases) {
        return Mono.fromCallable(() -> s.revisar(frases));
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class PoliticasProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePoliticas servicioDePoliticas() {
        var cliente = IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDePoliticas(new LinterDePoliticas(), new PoliticasOci(cliente));
    }
}

@Path("/iam/politicas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class PoliticasRecurso {

    @Inject
    ServicioDePoliticas s;

    @GET
    @Path("/auditoria")
    public List<ServicioDePoliticas.HallazgoDePolitica> auditoria(@QueryParam("compartimento") String compartimento) {
        return s.auditar(compartimento);
    }

    @POST
    @Path("/revisar")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<Hallazgo> revisar(List<String> frases) {
        return s.revisar(frases);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/iam/politicas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class PoliticasRecursoReactivo {

    @Inject
    ServicioDePoliticas s;

    @GET
    @Path("/auditoria")
    public Uni<List<ServicioDePoliticas.HallazgoDePolitica>> auditoria(@QueryParam("compartimento") String compartimento) {
        return Uni.createFrom().item(() -> s.auditar(compartimento)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/revisar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<Hallazgo>> revisar(List<String> frases) {
        return Uni.createFrom().item(() -> s.revisar(frases));
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `ListPolicies` | `Allow dynamic-group auditor-iam to inspect policies in tenancy` *(verifica si necesitas `read policies` para ver las frases)* |
| El linter | Ninguna: no llama a la red |

## 8. Qué NO hacer desde Java
- No apliques políticas desde la aplicación: el auditor **lee y avisa**; los cambios van por Terraform y revisión.
- No trates el linter como prueba de seguridad: detecta patrones conocidos, no entiende tu negocio.
- No registres frases con datos de clientes en etiquetas ni condiciones.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
