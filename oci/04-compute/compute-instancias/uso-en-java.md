# Oracle OCI · Compute · Instancias · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **planificador de horarios**: lee la etiqueta `horario` (`lv-08-19`) de cada instancia, decide con un reloj inyectable qué encender o apagar en la zona `America/Lima` y lo ejecuta con `ComputeClient`. El endpoint `plan` simula; `aplicar` ejecuta.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
horarios:
  zona: America/Lima
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

### 2.2 Etiqueta de horario
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.DayOfWeek;
import java.time.ZonedDateTime;
import java.util.Set;

/** Etiqueta «horario»: dias-inicio-fin, por ejemplo lv-08-19 (lunes a viernes de 08:00 a 19:00). */
public record Horario(Set<DayOfWeek> dias, int inicio, int fin) {

    public static Horario analizar(String texto) {
        String[] p = texto.strip().toLowerCase().split("-");
        if (p.length != 3) {
            throw new IllegalArgumentException("formato esperado: dias-inicio-fin (lv-08-19)");
        }
        Set<DayOfWeek> dias = switch (p[0]) {
            case "lv" -> Set.of(DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY, DayOfWeek.THURSDAY, DayOfWeek.FRIDAY);
            case "ls" -> Set.of(DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY, DayOfWeek.THURSDAY, DayOfWeek.FRIDAY, DayOfWeek.SATURDAY);
            case "td" -> Set.of(DayOfWeek.values());
            default -> throw new IllegalArgumentException("días desconocidos: " + p[0]);
        };
        int ini = Integer.parseInt(p[1]);
        int fin = Integer.parseInt(p[2]);
        if (ini < 0 || fin > 24 || ini >= fin) {
            throw new IllegalArgumentException("horas inválidas: " + ini + "-" + fin);
        }
        return new Horario(dias, ini, fin);
    }

    public boolean debeEstarEncendida(ZonedDateTime ahora) {
        return dias.contains(ahora.getDayOfWeek()) && ahora.getHour() >= inicio && ahora.getHour() < fin;
    }
}
```

### 2.3 Planificador
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

/** Decide qué instancias encender o apagar ahora. Puro: no llama a la red. */
public final class PlanificadorDeEncendido {

    public record Instancia(String id, String nombre, String estado, String horario) { }

    public record Accion(String id, String nombre, String accion) { }

    private final ZoneId zona;

    public PlanificadorDeEncendido(ZoneId zona) {
        this.zona = zona;
    }

    public List<Accion> planificar(List<Instancia> instancias, Instant ahora) {
        var salida = new ArrayList<Accion>();
        var local = ahora.atZone(zona);
        for (Instancia i : instancias) {
            if (i.horario() == null || i.horario().isBlank()) {
                continue;
            }
            Horario h;
            try {
                h = Horario.analizar(i.horario());
            } catch (RuntimeException e) {
                continue;
            }
            boolean encendida = h.debeEstarEncendida(local);
            if (encendida && i.estado().equals("STOPPED")) {
                salida.add(new Accion(i.id(), i.nombre(), "START"));
            } else if (!encendida && i.estado().equals("RUNNING")) {
                salida.add(new Accion(i.id(), i.nombre(), "SOFTSTOP"));
            }
        }
        return salida;
    }
}
```

### 2.4 Instancias con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.requests.InstanceActionRequest;
import com.oracle.bmc.core.requests.ListInstancesRequest;
import java.util.ArrayList;
import java.util.List;

/** Lista instancias y ejecuta acciones con el SDK. */
public class InstanciasOci {

    private final ComputeClient cliente;

    public InstanciasOci(ComputeClient cliente) {
        this.cliente = cliente;
    }

    public List<PlanificadorDeEncendido.Instancia> listar(String compartimentoId) {
        var req = ListInstancesRequest.builder().compartmentId(compartimentoId).build();
        var salida = new ArrayList<PlanificadorDeEncendido.Instancia>();
        for (Instance i : cliente.getPaginators().listInstancesRecordIterator(req)) {
            String horario = i.getFreeformTags() == null ? null : i.getFreeformTags().get("horario");
            salida.add(new PlanificadorDeEncendido.Instancia(i.getId(), i.getDisplayName(), i.getLifecycleState().getValue(), horario));
        }
        return salida;
    }

    public void ejecutar(PlanificadorDeEncendido.Accion a) {
        cliente.instanceAction(InstanceActionRequest.builder().instanceId(a.id()).action(a.accion()).build());
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.ZoneId;
import java.util.List;

public class ServicioDeHorarios {

    private final InstanciasOci instancias;
    private final PlanificadorDeEncendido planificador;
    private final Clock reloj;

    public ServicioDeHorarios(InstanciasOci instancias, ZoneId zona, Clock reloj) {
        this.instancias = instancias;
        this.planificador = new PlanificadorDeEncendido(zona);
        this.reloj = reloj;
    }

    /** Simulación: devuelve lo que se haría, sin ejecutarlo. */
    public List<PlanificadorDeEncendido.Accion> plan(String compartimentoId) {
        return planificador.planificar(instancias.listar(compartimentoId), reloj.instant());
    }

    /** Ejecuta el plan. Una acción fallida no detiene las demás. */
    public List<PlanificadorDeEncendido.Accion> aplicar(String compartimentoId) {
        var plan = plan(compartimentoId);
        for (var a : plan) {
            try {
                instancias.ejecutar(a);
            } catch (RuntimeException e) {
                // registra el id (no datos sensibles) y sigue con la siguiente
            }
        }
        return plan;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.ComputeClient;
import java.time.Clock;
import java.time.ZoneId;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class HorariosConfiguracion {

    @Bean(destroyMethod = "close")
    ComputeClient computeCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return ComputeClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDeHorarios servicioDeHorarios(ComputeClient cliente, @Value("${horarios.zona:America/Lima}") String zona) {
        return new ServicioDeHorarios(new InstanciasOci(cliente), ZoneId.of(zona), Clock.systemUTC());
    }
}

@RestController
@RequestMapping("/compute/horarios")
class HorariosControlador {

    private final ServicioDeHorarios s;

    HorariosControlador(ServicioDeHorarios s) {
        this.s = s;
    }

    @GetMapping("/plan")
    List<PlanificadorDeEncendido.Accion> plan(@RequestParam String compartimento) {
        return s.plan(compartimento);
    }

    @PostMapping("/aplicar")
    List<PlanificadorDeEncendido.Accion> aplicar(@RequestParam String compartimento) {
        return s.aplicar(compartimento);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.ComputeClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/compute/horarios")
class HorariosReactivoControlador {

    private final ServicioDeHorarios s;

    HorariosReactivoControlador(ServicioDeHorarios s) {
        this.s = s;
    }

    @GetMapping("/plan")
    Mono<List<PlanificadorDeEncendido.Accion>> plan(@RequestParam String compartimento) {
        return Mono.fromCallable(() -> s.plan(compartimento)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/aplicar")
    Mono<List<PlanificadorDeEncendido.Accion>> aplicar(@RequestParam String compartimento) {
        return Mono.fromCallable(() -> s.aplicar(compartimento)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.core.ComputeClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.time.Clock;
import java.time.ZoneId;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class HorariosProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeHorarios servicioDeHorarios() {
        var cliente = ComputeClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDeHorarios(new InstanciasOci(cliente), ZoneId.of("America/Lima"), Clock.systemUTC());
    }
}

@Path("/compute/horarios")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class HorariosRecurso {

    @Inject
    ServicioDeHorarios s;

    @GET
    @Path("/plan")
    public List<PlanificadorDeEncendido.Accion> plan(@QueryParam("compartimento") String compartimento) {
        return s.plan(compartimento);
    }

    @POST
    @Path("/aplicar")
    public List<PlanificadorDeEncendido.Accion> aplicar(@QueryParam("compartimento") String compartimento) {
        return s.aplicar(compartimento);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.ComputeClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/compute/horarios")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class HorariosRecursoReactivo {

    @Inject
    ServicioDeHorarios s;

    @GET
    @Path("/plan")
    public Uni<List<PlanificadorDeEncendido.Accion>> plan(@QueryParam("compartimento") String compartimento) {
        return Uni.createFrom().item(() -> s.plan(compartimento)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/aplicar")
    public Uni<List<PlanificadorDeEncendido.Accion>> aplicar(@QueryParam("compartimento") String compartimento) {
        return Uni.createFrom().item(() -> s.aplicar(compartimento)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `ListInstances` | `Allow dynamic-group planificador to inspect instances in compartment tienda-dev` |
| `InstanceAction` (START/SOFTSTOP) | `Allow dynamic-group planificador to use instances in compartment tienda-dev where request.operation = 'InstanceAction'` *(verifica el verbo mínimo)* |

## 8. Qué NO hacer desde Java
- No apliques el plan en producción sin una lista explícita de compartimentos y una etiqueta de opt-in.
- No expongas `/aplicar` sin autenticación: apaga máquinas.
- No confundas `SOFTSTOP` (apagado ordenado) con `STOP` (corte inmediato).
- No uses la hora local del servidor: usa la zona explícita y un reloj inyectable.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
