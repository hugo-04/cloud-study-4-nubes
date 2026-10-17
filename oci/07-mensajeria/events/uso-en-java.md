# Oracle OCI · Mensajería · Events · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **constructor de reglas seguro**: la lógica pura arma la condición JSON (tipos validados con el patrón `com.oraclecloud.<servicio>.<acción>`, filtros de `data` sin caracteres raros, prohibido «sin tipos») y el adaptador crea la regla con acción a un tema usando `EventsClient` con `opcRetryToken` derivado del nombre.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
reglas:
  compartimento: ocid1.compartment.oc1..aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
reglas.compartimento=ocid1.compartment.oc1..aaaa
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

### 2.2 Condición (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/** Construye la condición JSON de una regla de Events y la valida antes de enviarla. Puro. */
public class CondicionDeRegla {

    private static final Pattern TIPO = Pattern.compile("com\\.oraclecloud\\.[a-z0-9]+\\.[a-z0-9.]+");
    private static final Pattern VALOR = Pattern.compile("[A-Za-z0-9_.*-]{1,100}");

    private final List<String> tipos = new ArrayList<>();
    private final Map<String, List<String>> data = new LinkedHashMap<>();

    public CondicionDeRegla tipo(String t) {
        if (!TIPO.matcher(t).matches()) {
            throw new IllegalArgumentException("tipo de evento inválido: " + t);
        }
        tipos.add(t);
        return this;
    }

    /** Filtro sobre data (por ejemplo compartmentName o resourceName). Valores de la lista = O. */
    public CondicionDeRegla dato(String campo, List<String> valores) {
        if (!campo.matches("[a-zA-Z]{1,40}") || valores.isEmpty() || valores.stream().anyMatch(v -> !VALOR.matcher(v).matches())) {
            throw new IllegalArgumentException("filtro inválido: " + campo);
        }
        data.put(campo, List.copyOf(valores));
        return this;
    }

    public String json() {
        if (tipos.isEmpty()) {
            throw new IllegalStateException("una regla sin tipos de evento recibiría demasiado");
        }
        var sb = new StringBuilder("{\"eventType\":").append(lista(tipos));
        if (!data.isEmpty()) {
            sb.append(",\"data\":{");
            int i = 0;
            for (var e : data.entrySet()) {
                sb.append(i++ > 0 ? "," : "").append('"').append(e.getKey()).append("\":").append(lista(e.getValue()));
            }
            sb.append('}');
        }
        return sb.append('}').toString();
    }

    private static String lista(List<String> v) {
        return v.stream().map(s -> "\"" + s + "\"").reduce((a, b) -> a + "," + b).map(s -> "[" + s + "]").orElse("[]");
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.events.EventsClient;
import com.oracle.bmc.events.model.ActionDetailsList;
import com.oracle.bmc.events.model.CreateNotificationServiceActionDetails;
import com.oracle.bmc.events.model.CreateRuleDetails;
import com.oracle.bmc.events.requests.CreateRuleRequest;
import com.oracle.bmc.events.requests.ListRulesRequest;
import java.util.List;
import java.util.UUID;

/** Adaptador del SDK: crea reglas con acción a un tema y lista las existentes. */
public class ReglasOci implements AutoCloseable {

    public record Regla(String id, String nombre, boolean activa, String condicion) { }

    private final EventsClient cliente;
    private final String compartimentoId;

    public ReglasOci(EventsClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public String crear(String nombre, String condicionJson, String temaId) {
        var detalles = CreateRuleDetails.builder()
            .compartmentId(compartimentoId).displayName(nombre).isEnabled(true).condition(condicionJson)
            .actions(ActionDetailsList.builder().actions(List.of(
                CreateNotificationServiceActionDetails.builder().topicId(temaId).isEnabled(true).build())).build())
            .build();
        return cliente.createRule(CreateRuleRequest.builder().createRuleDetails(detalles)
            .opcRetryToken(UUID.nameUUIDFromBytes(nombre.getBytes()).toString()).build()).getRule().getId();
    }

    public List<Regla> listar() {
        return cliente.listRules(ListRulesRequest.builder().compartmentId(compartimentoId).build()).getItems().stream()
            .map(r -> new Regla(r.getId(), r.getDisplayName(), Boolean.TRUE.equals(r.getIsEnabled()), r.getCondition()))
            .toList();
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

public class ServicioDeReglas {

    public record Pedido(String nombre, List<String> tipos, List<String> compartimentos, String temaId) { }

    private final ReglasOci reglas;

    public ServicioDeReglas(ReglasOci reglas) {
        this.reglas = reglas;
    }

    public String crear(Pedido p) {
        var c = new CondicionDeRegla();
        p.tipos().forEach(c::tipo);
        if (p.compartimentos() != null && !p.compartimentos().isEmpty()) {
            c.dato("compartmentName", p.compartimentos());
        }
        return reglas.crear(p.nombre(), c.json(), p.temaId());
    }

    public List<ReglasOci.Regla> listar() {
        return reglas.listar();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.events.EventsClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class ReglasConfiguracion {

    @Bean(destroyMethod = "close")
    ReglasOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${reglas.compartimento}") String compartimento) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ReglasOci(EventsClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    @Bean
    ServicioDeReglas servicio(ReglasOci a) {
        return new ServicioDeReglas(a);
    }
}

@RestController
@RequestMapping("/mensajeria/reglas")
class ReglasControlador {

    private final ServicioDeReglas s;

    ReglasControlador(ServicioDeReglas s) {
        this.s = s;
    }

    @PostMapping("")
    String crear(@RequestBody ServicioDeReglas.Pedido p) {
        return s.crear(p);
    }

    @GetMapping("")
    List<ReglasOci.Regla> listar() {
        return s.listar();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.events.EventsClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/mensajeria/reglas")
class ReglasReactivoControlador {

    private final ServicioDeReglas s;

    ReglasReactivoControlador(ServicioDeReglas s) {
        this.s = s;
    }

    @PostMapping("")
    Mono<String> crear(@RequestBody ServicioDeReglas.Pedido p) {
        return Mono.fromCallable(() -> s.crear(p)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("")
    Mono<List<ReglasOci.Regla>> listar() {
        return Mono.fromCallable(() -> s.listar()).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.events.EventsClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class ReglasProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "reglas.compartimento")
    String compartimento;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ReglasOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new ReglasOci(EventsClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    void cerrar(@Disposes ReglasOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeReglas servicio(ReglasOci a) {
        return new ServicioDeReglas(a);
    }
}

@Path("/mensajeria/reglas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class ReglasRecurso {

    @Inject
    ServicioDeReglas s;

    @POST
    @Path("")
    @Consumes(MediaType.APPLICATION_JSON)
    public String crear(ServicioDeReglas.Pedido p) {
        return s.crear(p);
    }

    @GET
    @Path("")
    public List<ReglasOci.Regla> listar() {
        return s.listar();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.events.EventsClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/mensajeria/reglas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class ReglasRecursoReactivo {

    @Inject
    ServicioDeReglas s;

    @POST
    @Path("")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> crear(ServicioDeReglas.Pedido p) {
        return Uni.createFrom().item(() -> s.crear(p)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("")
    public Uni<List<ReglasOci.Regla>> listar() {
        return Uni.createFrom().item(() -> s.listar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Crear y listar reglas | `Allow group plataforma to manage cloudevents-rules in compartment prod` |
| Events publica en el tema | `Allow service cloudEvents to use ons-topics in compartment prod` *(verifica el nombre del principal de servicio)* |

## 8. Qué NO hacer desde Java
- No construyas la condición concatenando texto del usuario sin validar.
- No crees reglas desde la app en tiempo de ejecución si pueden vivir en Terraform: este ejemplo es para un portal de plataforma.
- No hagas acciones destructivas automáticas sin comprobar el evento contra la API.
- No olvides que la regla ve solo su compartimento y descendientes.
