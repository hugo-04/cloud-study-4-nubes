# Google Cloud · Red · Firewall, rutas y Cloud NAT · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **auditor de reglas de firewall**: lee las reglas de VPC con `FirewallsClient.list` y marca las de entrada que abren puertos sensibles o todos los puertos a `0.0.0.0/0`, las que aplican a todas las instancias, las que usan etiquetas en vez de cuentas de servicio y las abiertas a Internet sin logs.

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

### 2.2 Auditor (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Señala reglas de firewall peligrosas o difíciles de gobernar. Puro. */
public class AuditorDeFirewall {

    public record Permiso(String protocolo, List<String> puertos) { }

    public record Regla(String nombre, String direccion, int prioridad, List<String> origenes, List<Permiso> permitidos,
                        List<String> cuentasObjetivo, List<String> etiquetasObjetivo, boolean deshabilitada, boolean conLogs) { }

    public record Hallazgo(String regla, String severidad, String mensaje) { }

    private static final Set<Integer> SENSIBLES = Set.of(22, 3389, 3306, 5432, 6379, 9200, 27017);

    public List<Hallazgo> auditar(List<Regla> reglas) {
        var h = new ArrayList<Hallazgo>();
        for (Regla r : reglas) {
            if (r.deshabilitada() || !"INGRESS".equals(r.direccion()) || r.permitidos().isEmpty()) {
                continue;
            }
            boolean desdeInternet = r.origenes().contains("0.0.0.0/0");
            boolean sinObjetivo = r.cuentasObjetivo().isEmpty() && r.etiquetasObjetivo().isEmpty();
            for (Permiso p : r.permitidos()) {
                boolean todos = "all".equals(p.protocolo()) || p.puertos().isEmpty();
                if (desdeInternet && (todos || p.puertos().stream().anyMatch(AuditorDeFirewall::esSensible))) {
                    h.add(new Hallazgo(r.nombre(), "ALTA", "abre " + (todos ? "todos los puertos" : p.puertos()) + " a Internet"));
                }
            }
            if (sinObjetivo) {
                h.add(new Hallazgo(r.nombre(), "MEDIA", "aplica a todas las instancias de la red"));
            } else if (r.cuentasObjetivo().isEmpty()) {
                h.add(new Hallazgo(r.nombre(), "BAJA", "usa etiquetas de red en lugar de cuentas de servicio"));
            }
            if (desdeInternet && !r.conLogs()) {
                h.add(new Hallazgo(r.nombre(), "BAJA", "regla abierta a Internet sin logs"));
            }
        }
        return h;
    }

    static boolean esSensible(String puertos) {
        String[] p = puertos.split("-");
        int desde = Integer.parseInt(p[0]);
        int hasta = p.length > 1 ? Integer.parseInt(p[1]) : desde;
        return SENSIBLES.stream().anyMatch(s -> s >= desde && s <= hasta);
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

/** Adaptador: reglas de firewall de VPC del proyecto. */
public class FirewallGcp implements AutoCloseable {

    private final FirewallsClient cliente;
    private final String proyecto;

    public FirewallGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = FirewallsClient.create(FirewallsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeFirewall.Regla> reglas() {
        var out = new ArrayList<AuditorDeFirewall.Regla>();
        for (var f : cliente.list(proyecto).iterateAll()) {
            var permitidos = f.getAllowedList().stream()
                .map(a -> new AuditorDeFirewall.Permiso(a.getIPProtocol(), List.copyOf(a.getPortsList()))).toList();
            out.add(new AuditorDeFirewall.Regla(f.getName(), f.getDirection(), f.getPriority(), List.copyOf(f.getSourceRangesList()),
                permitidos, List.copyOf(f.getTargetServiceAccountsList()), List.copyOf(f.getTargetTagsList()),
                f.getDisabled(), f.hasLogConfig() && f.getLogConfig().getEnable()));
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
import java.util.Comparator;
import java.util.List;

public class ServicioDeFirewall {

    private final FirewallGcp firewall;
    private final AuditorDeFirewall auditor = new AuditorDeFirewall();

    public ServicioDeFirewall(FirewallGcp firewall) {
        this.firewall = firewall;
    }

    public List<AuditorDeFirewall.Hallazgo> auditar() {
        return auditor.auditar(firewall.reglas()).stream()
            .sorted(Comparator.comparing(AuditorDeFirewall.Hallazgo::severidad))
            .toList();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class FirewallConfiguracion {

    @Bean(destroyMethod = "close")
    FirewallGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FirewallGcp(cred, proyecto);
    }

    @Bean
    ServicioDeFirewall servicio(FirewallGcp a) {
        return new ServicioDeFirewall(a);
    }
}

@RestController
@RequestMapping("/red/firewall")
class FirewallControlador {

    private final ServicioDeFirewall s;

    FirewallControlador(ServicioDeFirewall s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeFirewall.Hallazgo> auditar() {
        return s.auditar();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/firewall")
class FirewallReactivoControlador {

    private final ServicioDeFirewall s;

    FirewallReactivoControlador(ServicioDeFirewall s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeFirewall.Hallazgo>> auditar() {
        return Mono.fromCallable(() -> s.auditar()).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class FirewallProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    FirewallGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new FirewallGcp(cred, proyecto);
    }

    void cerrar(@Disposes FirewallGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeFirewall servicio(FirewallGcp a) {
        return new ServicioDeFirewall(a);
    }
}

@Path("/red/firewall")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class FirewallRecurso {

    @Inject
    ServicioDeFirewall s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeFirewall.Hallazgo> auditar() {
        return s.auditar();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.google.auth.oauth2.GoogleCredentials;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/red/firewall")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class FirewallRecursoReactivo {

    @Inject
    ServicioDeFirewall s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeFirewall.Hallazgo>> auditar() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar reglas | `roles/compute.networkViewer` (o `roles/compute.securityAdmin` solo si además corrige) |

## 8. Qué NO hacer desde Java
- No corrijas reglas desde la app: reporta y corrige en Terraform.
- No olvides las políticas jerárquicas: este auditor solo ve reglas de VPC (léelas aparte con `FirewallPoliciesClient`).
- No asumas que una regla deshabilitada es inofensiva: alguien puede habilitarla.
