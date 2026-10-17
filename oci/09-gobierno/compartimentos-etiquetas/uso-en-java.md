# Oracle OCI · Gobierno · Compartimentos, etiquetas y cuotas · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **revisor de gobierno**: recorre todo el árbol de compartimentos con `IdentityClient.listCompartments` (subárbol, paginando) y marca los que superan la profundidad acordada o no tienen las etiquetas definidas obligatorias con valores válidos. Sirve como control nocturno o paso de un pipeline.

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

### 2.2 Validador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Revisa etiquetas obligatorias y profundidad de la jerarquía. Puro. */
public class ValidadorDeGobierno {

    public record Compartimento(String id, String nombre, String padreId, Map<String, Map<String, Object>> etiquetas) { }

    public record Hallazgo(String compartimento, String regla, String detalle) { }

    private final Map<String, Set<String>> obligatorias; // "Gobierno.centro_costo" -> valores válidos
    private final int profundidadMaxima;

    public ValidadorDeGobierno(Map<String, Set<String>> obligatorias, int profundidadMaxima) {
        this.obligatorias = Map.copyOf(obligatorias);
        this.profundidadMaxima = profundidadMaxima;
    }

    public List<Hallazgo> revisar(String raizId, List<Compartimento> todos) {
        var porId = new HashMap<String, Compartimento>();
        todos.forEach(c -> porId.put(c.id(), c));
        var out = new ArrayList<Hallazgo>();
        for (var c : todos) {
            int nivel = 1;
            for (String p = c.padreId(); p != null && !p.equals(raizId) && porId.containsKey(p); p = porId.get(p).padreId()) {
                nivel++;
            }
            if (nivel > profundidadMaxima) {
                out.add(new Hallazgo(c.nombre(), "profundidad", "nivel " + nivel + " > " + profundidadMaxima));
            }
            for (var regla : obligatorias.entrySet()) {
                String[] p = regla.getKey().split("\\.", 2);
                Object valor = c.etiquetas().getOrDefault(p[0], Map.of()).get(p[1]);
                if (valor == null) {
                    out.add(new Hallazgo(c.nombre(), "etiqueta", "falta " + regla.getKey()));
                } else if (!regla.getValue().isEmpty() && !regla.getValue().contains(valor.toString())) {
                    out.add(new Hallazgo(c.nombre(), "etiqueta", regla.getKey() + "='" + valor + "' no es válido"));
                }
            }
        }
        return out;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.Compartment;
import com.oracle.bmc.identity.requests.ListCompartmentsRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: todo el árbol de compartimentos activos con sus etiquetas definidas (paginando). */
public class CompartimentosOci implements AutoCloseable {

    private final IdentityClient cliente;

    public CompartimentosOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public List<ValidadorDeGobierno.Compartimento> arbol(String raizId) {
        var out = new ArrayList<ValidadorDeGobierno.Compartimento>();
        String pagina = null;
        do {
            var r = cliente.listCompartments(ListCompartmentsRequest.builder().compartmentId(raizId)
                .compartmentIdInSubtree(true).accessLevel(ListCompartmentsRequest.AccessLevel.Accessible)
                .lifecycleState(Compartment.LifecycleState.Active).page(pagina).build());
            r.getItems().forEach(c -> out.add(new ValidadorDeGobierno.Compartimento(
                c.getId(), c.getName(), c.getCompartmentId(), c.getDefinedTags())));
            pagina = r.getOpcNextPage();
        } while (pagina != null);
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
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ServicioDeGobierno {

    private final CompartimentosOci compartimentos;
    private final ValidadorDeGobierno validador = new ValidadorDeGobierno(Map.of(
        "Gobierno.centro_costo", Set.of("tienda", "pagos", "logistica", "plataforma"),
        "Gobierno.entorno", Set.of("prod", "no-prod")), 3);

    public ServicioDeGobierno(CompartimentosOci compartimentos) {
        this.compartimentos = compartimentos;
    }

    public List<ValidadorDeGobierno.Hallazgo> revisar(String raizId) {
        return validador.revisar(raizId, compartimentos.arbol(raizId));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class GobiernoConfiguracion {

    @Bean(destroyMethod = "close")
    CompartimentosOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CompartimentosOci(IdentityClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeGobierno servicio(CompartimentosOci a) {
        return new ServicioDeGobierno(a);
    }
}

@RestController
@RequestMapping("/gobierno/compartimentos")
class GobiernoControlador {

    private final ServicioDeGobierno s;

    GobiernoControlador(ServicioDeGobierno s) {
        this.s = s;
    }

    @GetMapping("/revision")
    List<ValidadorDeGobierno.Hallazgo> revisar(@RequestParam String raiz) {
        return s.revisar(raiz);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/compartimentos")
class GobiernoReactivoControlador {

    private final ServicioDeGobierno s;

    GobiernoReactivoControlador(ServicioDeGobierno s) {
        this.s = s;
    }

    @GetMapping("/revision")
    Mono<List<ValidadorDeGobierno.Hallazgo>> revisar(@RequestParam String raiz) {
        return Mono.fromCallable(() -> s.revisar(raiz)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
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
class GobiernoProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CompartimentosOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CompartimentosOci(IdentityClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes CompartimentosOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeGobierno servicio(CompartimentosOci a) {
        return new ServicioDeGobierno(a);
    }
}

@Path("/gobierno/compartimentos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class GobiernoRecurso {

    @Inject
    ServicioDeGobierno s;

    @GET
    @Path("/revision")
    public List<ValidadorDeGobierno.Hallazgo> revisar(@QueryParam("raiz") String raiz) {
        return s.revisar(raiz);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/gobierno/compartimentos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class GobiernoRecursoReactivo {

    @Inject
    ServicioDeGobierno s;

    @GET
    @Path("/revision")
    public Uni<List<ValidadorDeGobierno.Hallazgo>> revisar(@QueryParam("raiz") String raiz) {
        return Uni.createFrom().item(() -> s.revisar(raiz)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Listar compartimentos del árbol | `Allow dynamic-group auditoria to inspect compartments in tenancy` |
| Leer las etiquetas definidas | `Allow dynamic-group auditoria to read tag-namespaces in tenancy` |

## 8. Qué NO hacer desde Java
- No olvides paginar: un árbol grande no cabe en una página.
- No uses etiquetas libres para reglas de gobierno: no se validan.
- No corras auditorías con una identidad que pueda modificar (solo `inspect`/`read`).
- No guardes datos sensibles en etiquetas.
