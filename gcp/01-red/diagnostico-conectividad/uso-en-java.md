# Google Cloud · Red · Diagnóstico de conectividad · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **simulador de firewall** para pruebas automatizadas de configuración: lee las reglas de entrada de una red (allow y deny) con `FirewallsClient` y decide si un paquete concreto (IP de origen, cuenta de servicio/etiquetas del destino, protocolo, puerto) pasa, con la regla responsable o la denegación implícita. No reemplaza a Connectivity Tests (no ve políticas jerárquicas ni rutas), pero sirve en el pipeline.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
gcp:
  proyecto: modalima-prod
  suplantar: ninguna
```
```properties
# Quarkus (application.properties)
gcp.proyecto=modalima-prod
gcp.suplantar=ninguna
```

## 2. Núcleo común

### 2.1 Credenciales según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ImpersonatedCredentials;
import java.io.IOException;
import java.util.List;

public final class Credenciales {

    private static final List<String> ALCANCE = List.of("https://www.googleapis.com/auth/cloud-platform");

    private Credenciales() { }

    /**
     * ADC (Application Default Credentials): en la laptop, «gcloud auth application-default login»;
     * en GKE, Cloud Run, Functions o Compute Engine, la cuenta de servicio adjunta (sin llaves).
     * suplantar = correo de una cuenta de servicio para actuar como ella, o "ninguna".
     */
    public static GoogleCredentials crear(String suplantar) {
        try {
            var base = GoogleCredentials.getApplicationDefault().createScoped(ALCANCE);
            if (suplantar == null || suplantar.isBlank() || "ninguna".equals(suplantar)) {
                return base;
            }
            return ImpersonatedCredentials.create(base, suplantar, null, ALCANCE, 3600);
        } catch (IOException e) {
            throw new IllegalStateException("no hay credenciales ADC disponibles", e);
        }
    }
}
```

### 2.2 Simulador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

/** Simula reglas de firewall de VPC para un paquete de entrada. Puro (no evalúa políticas jerárquicas). */
public class SimuladorDeFirewall {

    public record Regla(String nombre, int prioridad, boolean permite, List<String> origenes, List<String> cuentasObjetivo,
                        List<String> etiquetasObjetivo, String protocolo, List<String> puertos, boolean deshabilitada) { }

    public record Paquete(String ipOrigen, String cuentaDestino, List<String> etiquetasDestino, String protocolo, int puerto) { }

    public record Veredicto(boolean permitido, String regla) { }

    public Veredicto evaluar(List<Regla> reglas, Paquete p) {
        Optional<Regla> primera = reglas.stream()
            .filter(r -> !r.deshabilitada() && aplica(r, p))
            // menor prioridad primero; a igual prioridad, deny gana
            .min(Comparator.comparingInt(Regla::prioridad).thenComparing(Regla::permite));
        return primera.map(r -> new Veredicto(r.permite(), r.nombre()))
            .orElse(new Veredicto(false, "implícita: entrada denegada"));
    }

    static boolean aplica(Regla r, Paquete p) {
        boolean objetivo = (r.cuentasObjetivo().isEmpty() && r.etiquetasObjetivo().isEmpty())
            || r.cuentasObjetivo().contains(p.cuentaDestino())
            || r.etiquetasObjetivo().stream().anyMatch(p.etiquetasDestino()::contains);
        boolean protocolo = "all".equals(r.protocolo()) || r.protocolo().equals(p.protocolo());
        boolean puerto = r.puertos().isEmpty() || r.puertos().stream().anyMatch(x -> enRango(x, p.puerto()));
        boolean origen = r.origenes().stream().anyMatch(c -> contiene(c, p.ipOrigen()));
        return objetivo && protocolo && puerto && origen;
    }

    static boolean enRango(String rango, int puerto) {
        String[] x = rango.split("-");
        int a = Integer.parseInt(x[0]);
        int b = x.length > 1 ? Integer.parseInt(x[1]) : a;
        return puerto >= a && puerto <= b;
    }

    static boolean contiene(String cidr, String ip) {
        String[] c = cidr.split("/");
        long red = aLong(c[0]);
        long tam = 1L << (32 - Integer.parseInt(c[1]));
        long ini = red & ~(tam - 1) & 0xFFFFFFFFL;
        long v = aLong(ip);
        return v >= ini && v < ini + tam;
    }

    static long aLong(String ip) {
        long v = 0;
        for (String o : ip.split("\\.")) {
            v = (v << 8) | Integer.parseInt(o);
        }
        return v;
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.FirewallsClient;
import com.google.cloud.compute.v1.FirewallsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: reglas de entrada de una red convertidas al modelo del simulador (allow y deny). */
public class ReglasGcp implements AutoCloseable {

    private final FirewallsClient cliente;
    private final String proyecto;

    public ReglasGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = FirewallsClient.create(FirewallsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<SimuladorDeFirewall.Regla> deEntrada(String red) {
        var out = new ArrayList<SimuladorDeFirewall.Regla>();
        for (var f : cliente.list(proyecto).iterateAll()) {
            if (!"INGRESS".equals(f.getDirection()) || !f.getNetwork().endsWith("/" + red)) {
                continue;
            }
            List<String> origenes = f.getSourceRangesList().isEmpty() ? List.of("0.0.0.0/0") : List.copyOf(f.getSourceRangesList());
            f.getAllowedList().forEach(a -> out.add(new SimuladorDeFirewall.Regla(f.getName(), f.getPriority(), true, origenes,
                List.copyOf(f.getTargetServiceAccountsList()), List.copyOf(f.getTargetTagsList()), a.getIPProtocol(),
                List.copyOf(a.getPortsList()), f.getDisabled())));
            f.getDeniedList().forEach(d -> out.add(new SimuladorDeFirewall.Regla(f.getName(), f.getPriority(), false, origenes,
                List.copyOf(f.getTargetServiceAccountsList()), List.copyOf(f.getTargetTagsList()), d.getIPProtocol(),
                List.copyOf(d.getPortsList()), f.getDisabled())));
        }
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
public class ServicioDeDiagnostico {

    private final ReglasGcp reglas;
    private final SimuladorDeFirewall simulador = new SimuladorDeFirewall();

    public ServicioDeDiagnostico(ReglasGcp reglas) {
        this.reglas = reglas;
    }

    public SimuladorDeFirewall.Veredicto simular(String red, SimuladorDeFirewall.Paquete p) {
        return simulador.evaluar(reglas.deEntrada(red), p);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class DiagnosticoConfiguracion {

    @Bean(destroyMethod = "close")
    ReglasGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ReglasGcp(cred, proyecto);
    }

    @Bean
    ServicioDeDiagnostico servicio(ReglasGcp a) {
        return new ServicioDeDiagnostico(a);
    }
}

@RestController
@RequestMapping("/red/diagnostico")
class DiagnosticoControlador {

    private final ServicioDeDiagnostico s;

    DiagnosticoControlador(ServicioDeDiagnostico s) {
        this.s = s;
    }

    @PostMapping("/simulacion")
    SimuladorDeFirewall.Veredicto simular(@RequestParam String red, @RequestBody SimuladorDeFirewall.Paquete p) {
        return s.simular(red, p);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/diagnostico")
class DiagnosticoReactivoControlador {

    private final ServicioDeDiagnostico s;

    DiagnosticoReactivoControlador(ServicioDeDiagnostico s) {
        this.s = s;
    }

    @PostMapping("/simulacion")
    Mono<SimuladorDeFirewall.Veredicto> simular(@RequestParam String red, @RequestBody SimuladorDeFirewall.Paquete p) {
        return Mono.fromCallable(() -> s.simular(red, p)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.google.auth.oauth2.GoogleCredentials;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class DiagnosticoProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ReglasGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new ReglasGcp(cred, proyecto);
    }

    void cerrar(@Disposes ReglasGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeDiagnostico servicio(ReglasGcp a) {
        return new ServicioDeDiagnostico(a);
    }
}

@Path("/red/diagnostico")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class DiagnosticoRecurso {

    @Inject
    ServicioDeDiagnostico s;

    @POST
    @Path("/simulacion")
    @Consumes(MediaType.APPLICATION_JSON)
    public SimuladorDeFirewall.Veredicto simular(@QueryParam("red") String red, SimuladorDeFirewall.Paquete p) {
        return s.simular(red, p);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/red/diagnostico")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class DiagnosticoRecursoReactivo {

    @Inject
    ServicioDeDiagnostico s;

    @POST
    @Path("/simulacion")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<SimuladorDeFirewall.Veredicto> simular(@QueryParam("red") String red, SimuladorDeFirewall.Paquete p) {
        return Uni.createFrom().item(() -> s.simular(red, p)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer reglas | `roles/compute.networkViewer` |

## 8. Qué NO hacer desde Java
- No confíes solo en esta simulación: confirma con Connectivity Tests (rutas, NAT, políticas jerárquicas).
- No abras reglas para «probar»: simula primero.
- No olvides que una regla sin `sourceRanges` ni orígenes por SA aplica a cualquier origen.
