# Google Cloud · Compute · Compute Engine · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **auditor de VMs**: recorre todas las zonas con `InstancesClient.aggregatedList` y marca VMs con IP externa, con la cuenta de servicio por defecto de Compute, sin arranque seguro, sin las etiquetas obligatorias o detenidas (que siguen cobrando discos e IPs).

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
import java.util.Map;
import java.util.Set;

/** Audita VMs: IP externa, cuenta por defecto, Shielded VM, etiquetas obligatorias, protección de borrado. Puro. */
public class AuditorDeVms {

    public record Vm(String nombre, String zona, String estado, boolean ipExterna, String cuenta, boolean arranqueSeguro,
                     Map<String, String> etiquetas, boolean proteccionBorrado) { }

    public record Hallazgo(String vm, String severidad, String mensaje) { }

    private final Set<String> etiquetasObligatorias;

    public AuditorDeVms(Set<String> etiquetasObligatorias) {
        this.etiquetasObligatorias = Set.copyOf(etiquetasObligatorias);
    }

    public List<Hallazgo> auditar(List<Vm> vms) {
        var h = new ArrayList<Hallazgo>();
        for (Vm v : vms) {
            if (v.ipExterna()) {
                h.add(new Hallazgo(v.nombre(), "ALTA", "tiene IP externa"));
            }
            if (v.cuenta() != null && v.cuenta().endsWith("-compute@developer.gserviceaccount.com")) {
                h.add(new Hallazgo(v.nombre(), "ALTA", "usa la cuenta de servicio por defecto de Compute"));
            }
            if (!v.arranqueSeguro()) {
                h.add(new Hallazgo(v.nombre(), "MEDIA", "sin arranque seguro (Shielded VM)"));
            }
            for (String e : etiquetasObligatorias) {
                if (!v.etiquetas().containsKey(e)) {
                    h.add(new Hallazgo(v.nombre(), "BAJA", "falta la etiqueta " + e));
                }
            }
            if ("TERMINATED".equals(v.estado())) {
                h.add(new Hallazgo(v.nombre(), "BAJA", "detenida: sigue cobrando discos e IPs"));
            }
        }
        return h;
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.InstancesClient;
import com.google.cloud.compute.v1.InstancesSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Adaptador: todas las VMs del proyecto en todas las zonas. */
public class VmsGcp implements AutoCloseable {

    private final InstancesClient cliente;
    private final String proyecto;

    public VmsGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = InstancesClient.create(InstancesSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeVms.Vm> todas() {
        var out = new ArrayList<AuditorDeVms.Vm>();
        for (var zona : cliente.aggregatedList(proyecto).iterateAll()) {
            for (var i : zona.getValue().getInstancesList()) {
                boolean ipExt = i.getNetworkInterfacesList().stream().anyMatch(n -> n.getAccessConfigsCount() > 0);
                String cuenta = i.getServiceAccountsList().isEmpty() ? null : i.getServiceAccountsList().get(0).getEmail();
                boolean seguro = i.hasShieldedInstanceConfig() && i.getShieldedInstanceConfig().getEnableSecureBoot();
                out.add(new AuditorDeVms.Vm(i.getName(), zona.getKey(), i.getStatus(), ipExt, cuenta, seguro,
                    Map.copyOf(i.getLabelsMap()), i.getDeletionProtection()));
            }
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
import java.util.List;
import java.util.Set;

public class ServicioDeVms {

    private final VmsGcp vms;
    private final AuditorDeVms auditor = new AuditorDeVms(Set.of("centro_costo", "entorno"));

    public ServicioDeVms(VmsGcp vms) {
        this.vms = vms;
    }

    public List<AuditorDeVms.Hallazgo> auditar() {
        return auditor.auditar(vms.todas());
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
class VmsConfiguracion {

    @Bean(destroyMethod = "close")
    VmsGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new VmsGcp(cred, proyecto);
    }

    @Bean
    ServicioDeVms servicio(VmsGcp a) {
        return new ServicioDeVms(a);
    }
}

@RestController
@RequestMapping("/compute/vms")
class VmsControlador {

    private final ServicioDeVms s;

    VmsControlador(ServicioDeVms s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeVms.Hallazgo> auditar() {
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
@RequestMapping("/reactivo/compute/vms")
class VmsReactivoControlador {

    private final ServicioDeVms s;

    VmsReactivoControlador(ServicioDeVms s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeVms.Hallazgo>> auditar() {
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
class VmsProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    VmsGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new VmsGcp(cred, proyecto);
    }

    void cerrar(@Disposes VmsGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeVms servicio(VmsGcp a) {
        return new ServicioDeVms(a);
    }
}

@Path("/compute/vms")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class VmsRecurso {

    @Inject
    ServicioDeVms s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeVms.Hallazgo> auditar() {
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

@Path("/reactivo/compute/vms")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class VmsRecursoReactivo {

    @Inject
    ServicioDeVms s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeVms.Hallazgo>> auditar() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar VMs | `roles/compute.viewer` |

## 8. Qué NO hacer desde Java
- No corrijas VMs desde la app: reporta y corrige la plantilla.
- No leas metadatos con secretos: los scripts de inicio no son un cofre.
- No crees un cliente por llamada.
