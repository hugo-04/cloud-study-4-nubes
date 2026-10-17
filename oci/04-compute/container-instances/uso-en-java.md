# Oracle OCI · Compute · Container Instances · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **orquestador de lotes**: recibe una especificación de tarea, la **valida** (imagen de OCIR con etiqueta fija, sin `latest`, sin secretos en variables de entorno, proporción memoria/OCPU razonable) y recién entonces llama a `createContainerInstance` con un `opcRetryToken` determinista, para que un reintento nunca cree dos instancias.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
tareas:
  compartimento: ocid1.compartment.oc1..aaaa
  dominio: "Uocm:SA-SAOPAULO-1-AD-1"
  subred: ocid1.subnet.oc1.sa-saopaulo-1.aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
tareas.compartimento=ocid1.compartment.oc1..aaaa
tareas.dominio=Uocm:SA-SAOPAULO-1-AD-1
tareas.subred=ocid1.subnet.oc1.sa-saopaulo-1.aaaa
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

### 2.2 Validador de la tarea (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/** Revisa una especificación de tarea antes de gastar dinero en crearla. Puro: sin SDK. */
public class ValidadorDeTarea {

    public record Tarea(String idTrabajo, String imagen, double ocpus, double memoriaGb, Map<String, String> entorno) { }

    private static final Pattern OCIR = Pattern.compile("^[a-z0-9-]+\\.ocir\\.io/[a-z0-9]+/[a-z0-9._/-]+(:[A-Za-z0-9._-]+|@sha256:[a-f0-9]{64})$");
    private static final Set<String> SOSPECHOSAS = Set.of("PASSWORD", "PASSWD", "SECRET", "TOKEN", "API_KEY", "PRIVATE_KEY");

    public List<String> errores(Tarea t) {
        var errores = new ArrayList<String>();
        if (t.idTrabajo() == null || !t.idTrabajo().matches("[a-z0-9-]{3,60}")) {
            errores.add("idTrabajo: solo minúsculas, dígitos y guiones (3 a 60)");
        }
        if (t.imagen() == null || !OCIR.matcher(t.imagen()).matches()) {
            errores.add("imagen: debe ser de OCIR con etiqueta fija o digest");
        } else if (t.imagen().endsWith(":latest") || !t.imagen().substring(t.imagen().lastIndexOf('/')).matches(".*[:@].*")) {
            errores.add("imagen: prohibido latest o sin etiqueta");
        }
        if (t.ocpus() < 1 || t.ocpus() > 16) {
            errores.add("ocpus: entre 1 y 16");
        }
        double ratio = t.memoriaGb() / t.ocpus();
        if (ratio < 1 || ratio > 16) {
            errores.add("memoria: entre 1 y 16 GB por OCPU");
        }
        t.entorno().keySet().stream()
            .filter(k -> SOSPECHOSAS.stream().anyMatch(s -> k.toUpperCase(Locale.ROOT).contains(s)))
            .forEach(k -> errores.add("entorno: '" + k + "' parece un secreto; léelo de Vault"));
        return errores;
    }

    /** Clave de idempotencia determinista: el mismo trabajo siempre produce el mismo token. */
    public String tokenDeReintento(Tarea t) {
        return ("tarea-" + t.idTrabajo()).substring(0, Math.min(64, ("tarea-" + t.idTrabajo()).length()));
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.containerinstances.ContainerInstanceClient;
import com.oracle.bmc.containerinstances.model.ContainerInstance;
import com.oracle.bmc.containerinstances.model.CreateContainerDetails;
import com.oracle.bmc.containerinstances.model.CreateContainerInstanceDetails;
import com.oracle.bmc.containerinstances.model.CreateContainerInstanceShapeConfigDetails;
import com.oracle.bmc.containerinstances.model.CreateContainerVnicDetails;
import com.oracle.bmc.containerinstances.requests.CreateContainerInstanceRequest;
import com.oracle.bmc.containerinstances.requests.GetContainerInstanceRequest;
import java.util.List;
import java.util.Map;

/** Adaptador del SDK: traduce la tarea validada a CreateContainerInstance. */
public class LanzadorOci implements AutoCloseable {

    public record Destino(String compartimentoId, String dominio, String subredId) { }

    private final ContainerInstanceClient cliente;
    private final Destino destino;

    public LanzadorOci(ContainerInstanceClient cliente, Destino destino) {
        this.cliente = cliente;
        this.destino = destino;
    }

    public String lanzar(ValidadorDeTarea.Tarea t, String token) {
        var detalles = CreateContainerInstanceDetails.builder()
            .compartmentId(destino.compartimentoId())
            .availabilityDomain(destino.dominio())
            .displayName(t.idTrabajo())
            .shape("CI.Standard.E4.Flex")
            .shapeConfig(CreateContainerInstanceShapeConfigDetails.builder()
                .ocpus((float) t.ocpus()).memoryInGBs((float) t.memoriaGb()).build())
            .containerRestartPolicy(ContainerInstance.ContainerRestartPolicy.Never)
            .gracefulShutdownTimeoutInSeconds(60L)
            .vnics(List.of(CreateContainerVnicDetails.builder()
                .subnetId(destino.subredId()).isPublicIpAssigned(false).build()))
            .containers(List.of(CreateContainerDetails.builder()
                .displayName(t.idTrabajo())
                .imageUrl(t.imagen())
                .environmentVariables(t.entorno())
                .build()))
            .freeformTags(Map.of("trabajo", t.idTrabajo()))
            .build();
        var resp = cliente.createContainerInstance(CreateContainerInstanceRequest.builder()
            .createContainerInstanceDetails(detalles)
            .opcRetryToken(token)
            .build());
        return resp.getContainerInstance().getId();
    }

    public String estado(String id) {
        return cliente.getContainerInstance(GetContainerInstanceRequest.builder().containerInstanceId(id).build())
            .getContainerInstance().getLifecycleState().getValue();
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

public class ServicioDeTareas {

    public record Solicitud(String idTrabajo, String imagen, double ocpus, double memoriaGb, Map<String, String> entorno) { }

    public record Resultado(boolean aceptada, String instanciaId, java.util.List<String> errores) { }

    private final ValidadorDeTarea validador = new ValidadorDeTarea();
    private final LanzadorOci lanzador;

    public ServicioDeTareas(LanzadorOci lanzador) {
        this.lanzador = lanzador;
    }

    public Resultado lanzar(Solicitud s) {
        var t = new ValidadorDeTarea.Tarea(s.idTrabajo(), s.imagen(), s.ocpus(), s.memoriaGb(),
            s.entorno() == null ? Map.of() : s.entorno());
        var errores = validador.errores(t);
        if (!errores.isEmpty()) {
            return new Resultado(false, null, errores);
        }
        return new Resultado(true, lanzador.lanzar(t, validador.tokenDeReintento(t)), java.util.List.of());
    }

    public String estado(String id) {
        return lanzador.estado(id);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.containerinstances.ContainerInstanceClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class TareasConfiguracion {

    @Bean(destroyMethod = "close")
    LanzadorOci lanzadorOci(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region,
                            @Value("${tareas.compartimento}") String compartimento, @Value("${tareas.dominio}") String dominio,
                            @Value("${tareas.subred}") String subred) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        var cliente = ContainerInstanceClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new LanzadorOci(cliente, new LanzadorOci.Destino(compartimento, dominio, subred));
    }

    @Bean
    ServicioDeTareas servicioDeTareas(LanzadorOci lanzador) {
        return new ServicioDeTareas(lanzador);
    }
}

@RestController
@RequestMapping("/compute/tareas")
class TareasControlador {

    private final ServicioDeTareas s;

    TareasControlador(ServicioDeTareas s) {
        this.s = s;
    }

    @PostMapping("/lanzar")
    ServicioDeTareas.Resultado lanzar(@RequestBody ServicioDeTareas.Solicitud s2) {
        return s.lanzar(s2);
    }

    @GetMapping("/{id}")
    String estado(@PathVariable String id) {
        return s.estado(id);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.containerinstances.ContainerInstanceClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/compute/tareas")
class TareasReactivoControlador {

    private final ServicioDeTareas s;

    TareasReactivoControlador(ServicioDeTareas s) {
        this.s = s;
    }

    @PostMapping("/lanzar")
    Mono<ServicioDeTareas.Resultado> lanzar(@RequestBody ServicioDeTareas.Solicitud s2) {
        return Mono.fromCallable(() -> s.lanzar(s2)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/{id}")
    Mono<String> estado(@PathVariable String id) {
        return Mono.fromCallable(() -> s.estado(id)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.containerinstances.ContainerInstanceClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class TareasProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "tareas.compartimento")
    String compartimento;

    @ConfigProperty(name = "tareas.dominio")
    String dominio;

    @ConfigProperty(name = "tareas.subred")
    String subred;

    @jakarta.enterprise.inject.Produces
    @Singleton
    LanzadorOci lanzadorOci() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        var cliente = ContainerInstanceClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new LanzadorOci(cliente, new LanzadorOci.Destino(compartimento, dominio, subred));
    }

    void cerrar(@Disposes LanzadorOci l) {
        l.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeTareas servicioDeTareas(LanzadorOci lanzador) {
        return new ServicioDeTareas(lanzador);
    }
}

@Path("/compute/tareas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class TareasRecurso {

    @Inject
    ServicioDeTareas s;

    @POST
    @Path("/lanzar")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeTareas.Resultado lanzar(ServicioDeTareas.Solicitud s2) {
        return s.lanzar(s2);
    }

    @GET
    @Path("/{id}")
    public String estado(@PathParam("id") String id) {
        return s.estado(id);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.containerinstances.ContainerInstanceClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/compute/tareas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class TareasRecursoReactivo {

    @Inject
    ServicioDeTareas s;

    @POST
    @Path("/lanzar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeTareas.Resultado> lanzar(ServicioDeTareas.Solicitud s2) {
        return Uni.createFrom().item(() -> s.lanzar(s2)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/{id}")
    public Uni<String> estado(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> s.estado(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Crear y consultar instancias | `Allow dynamic-group orquestador to manage compute-container-instances in compartment lotes-prod` |
| Conectar la VNIC | `Allow dynamic-group orquestador to use subnets in compartment red-prod` (+ `use vnics`, `use network-security-groups`) |
| Descargar la imagen de OCIR | `Allow dynamic-group contenedores-reportes to read repos in compartment ocir` |
| Dentro del contenedor | `Allow dynamic-group contenedores-reportes to read secret-bundles in compartment lotes-prod where target.secret.id = 'ocid1.vaultsecret…'` |

## 8. Qué NO hacer desde Java
- No reintentes `createContainerInstance` sin `opcRetryToken`.
- No pases contraseñas ni tokens en `environmentVariables`: se ven en la API y la consola.
- No uses `latest`: valida la etiqueta antes de llamar al SDK.
- No esperes el fin del lote con un bucle de `getContainerInstance` cada segundo: consulta con espera creciente o usa eventos.
- No dejes instancias `INACTIVE` sin borrar.
