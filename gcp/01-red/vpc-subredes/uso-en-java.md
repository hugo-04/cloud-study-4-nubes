# Google Cloud · Red · VPC y subredes · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **auditor de subredes**: lee todas las subredes del proyecto en todas las regiones con `SubnetworksClient.aggregatedList` y marca solapes entre rangos primarios y secundarios, subredes sin Private Google Access y sin flow logs. Útil antes de emparejar redes o crear clústeres.

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

/** Audita subredes: solapes entre todos los rangos, Private Google Access y flow logs. Puro. */
public class AuditorDeSubredes {

    public record Subred(String nombre, String region, String primario, List<String> secundarios, boolean pga, boolean flowLogs) { }

    public record Hallazgo(String subred, String severidad, String mensaje) { }

    record Rango(String duenio, long inicio, long fin) { }

    static Rango rango(String duenio, String cidr) {
        String[] p = cidr.split("/");
        long ip = 0;
        for (String o : p[0].split("\\.")) {
            ip = (ip << 8) | Integer.parseInt(o);
        }
        int pre = Integer.parseInt(p[1]);
        long tam = 1L << (32 - pre);
        long ini = ip & ~(tam - 1) & 0xFFFFFFFFL;
        return new Rango(duenio, ini, ini + tam - 1);
    }

    public List<Hallazgo> auditar(List<Subred> subredes) {
        var h = new ArrayList<Hallazgo>();
        var rangos = new ArrayList<Rango>();
        for (Subred s : subredes) {
            rangos.add(rango(s.nombre() + "@" + s.region(), s.primario()));
            s.secundarios().forEach(c -> rangos.add(rango(s.nombre() + "@" + s.region() + " (secundario)", c)));
            if (!s.pga()) {
                h.add(new Hallazgo(s.nombre(), "MEDIA", "sin Private Google Access"));
            }
            if (!s.flowLogs()) {
                h.add(new Hallazgo(s.nombre(), "BAJA", "sin flow logs"));
            }
        }
        for (int i = 0; i < rangos.size(); i++) {
            for (int j = i + 1; j < rangos.size(); j++) {
                var a = rangos.get(i);
                var b = rangos.get(j);
                if (a.inicio() <= b.fin() && b.inicio() <= a.fin()) {
                    h.add(new Hallazgo(a.duenio(), "ALTA", "se solapa con " + b.duenio()));
                }
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
import com.google.cloud.compute.v1.SubnetworkSecondaryRange;
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: todas las subredes del proyecto en todas las regiones (aggregatedList). */
public class SubredesGcp implements AutoCloseable {

    private final SubnetworksClient cliente;
    private final String proyecto;

    public SubredesGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = SubnetworksClient.create(SubnetworksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<AuditorDeSubredes.Subred> todas() {
        var out = new ArrayList<AuditorDeSubredes.Subred>();
        for (var entrada : cliente.aggregatedList(proyecto).iterateAll()) {
            for (var s : entrada.getValue().getSubnetworksList()) {
                out.add(new AuditorDeSubredes.Subred(s.getName(), s.getRegion().substring(s.getRegion().lastIndexOf('/') + 1),
                    s.getIpCidrRange(), s.getSecondaryIpRangesList().stream().map(SubnetworkSecondaryRange::getIpCidrRange).toList(),
                    s.getPrivateIpGoogleAccess(), s.hasLogConfig() && s.getLogConfig().getEnable()));
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

public class ServicioDeRed {

    private final SubredesGcp subredes;
    private final AuditorDeSubredes auditor = new AuditorDeSubredes();

    public ServicioDeRed(SubredesGcp subredes) {
        this.subredes = subredes;
    }

    public List<AuditorDeSubredes.Hallazgo> auditar() {
        return auditor.auditar(subredes.todas());
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
class RedConfiguracion {

    @Bean(destroyMethod = "close")
    SubredesGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SubredesGcp(cred, proyecto);
    }

    @Bean
    ServicioDeRed servicio(SubredesGcp a) {
        return new ServicioDeRed(a);
    }
}

@RestController
@RequestMapping("/red/subredes")
class RedControlador {

    private final ServicioDeRed s;

    RedControlador(ServicioDeRed s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeSubredes.Hallazgo> auditar() {
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
@RequestMapping("/reactivo/red/subredes")
class RedReactivoControlador {

    private final ServicioDeRed s;

    RedReactivoControlador(ServicioDeRed s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeSubredes.Hallazgo>> auditar() {
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
class RedProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SubredesGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new SubredesGcp(cred, proyecto);
    }

    void cerrar(@Disposes SubredesGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeRed servicio(SubredesGcp a) {
        return new ServicioDeRed(a);
    }
}

@Path("/red/subredes")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class RedRecurso {

    @Inject
    ServicioDeRed s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeSubredes.Hallazgo> auditar() {
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

@Path("/reactivo/red/subredes")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class RedRecursoReactivo {

    @Inject
    ServicioDeRed s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeSubredes.Hallazgo>> auditar() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Listar subredes | `roles/compute.networkViewer` en el proyecto host |

## 8. Qué NO hacer desde Java
- No crees un cliente por petición: son pesados (gRPC/HTTP); uno por aplicación y ciérralo al apagar.
- No uses llaves JSON para autenticar: ADC con la cuenta de servicio adjunta.
- No modifiques la red desde la app: eso es Terraform.
