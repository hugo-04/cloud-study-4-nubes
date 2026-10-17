# Google Cloud · Red · Acceso privado · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **verificador del camino privado** a las APIs: con `SubnetworksClient` revisa Private Google Access en cada subred de la red, y con la biblioteca de Cloud DNS (`Dns.listZones` / `listRecordSets`) comprueba que, si usas un endpoint PSC, exista la zona privada `googleapis.com.` con `*.googleapis.com` apuntando a la IP del endpoint.

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

### 2.2 Verificador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Verifica que el camino privado a las APIs de Google esté completo. Puro. */
public class VerificadorDeAccesoPrivado {

    public enum Modo { PGA, PSC }

    public record Subred(String nombre, boolean pga) { }

    /** zonas: nombre DNS de la zona (con punto final) -> registros "nombre TIPO datos". */
    public record Hallazgo(String severidad, String mensaje) { }

    public List<Hallazgo> verificar(Modo modo, String ipEndpoint, List<Subred> subredes, Map<String, List<String>> zonas) {
        var h = new ArrayList<Hallazgo>();
        subredes.stream().filter(s -> !s.pga()).forEach(s ->
            h.add(new Hallazgo(modo == Modo.PGA ? "ALTA" : "BAJA", "subred " + s.nombre() + " sin Private Google Access")));
        if (modo == Modo.PSC) {
            var registros = zonas.get("googleapis.com.");
            if (registros == null) {
                h.add(new Hallazgo("ALTA", "no hay zona privada googleapis.com.: el endpoint PSC no se usará"));
            } else if (registros.stream().noneMatch(r -> r.startsWith("*.googleapis.com. A") && r.contains(ipEndpoint))) {
                h.add(new Hallazgo("ALTA", "la zona googleapis.com. no apunta *.googleapis.com al endpoint " + ipEndpoint));
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
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import com.google.cloud.dns.Dns;
import com.google.cloud.dns.DnsOptions;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Adaptador: subredes de una red (PGA) y zonas DNS del proyecto con sus registros. */
public class AccesoPrivadoGcp implements AutoCloseable {

    private final SubnetworksClient subredes;
    private final Dns dns;
    private final String proyecto;

    public AccesoPrivadoGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.subredes = SubnetworksClient.create(SubnetworksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.dns = DnsOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.proyecto = proyecto;
    }

    public List<VerificadorDeAccesoPrivado.Subred> subredes(String red) {
        var out = new ArrayList<VerificadorDeAccesoPrivado.Subred>();
        for (var e : subredes.aggregatedList(proyecto).iterateAll()) {
            e.getValue().getSubnetworksList().stream().filter(s -> s.getNetwork().endsWith("/" + red))
                .forEach(s -> out.add(new VerificadorDeAccesoPrivado.Subred(s.getName(), s.getPrivateIpGoogleAccess())));
        }
        return out;
    }

    public Map<String, List<String>> zonas() {
        var out = new HashMap<String, List<String>>();
        for (var z : dns.listZones().iterateAll()) {
            var regs = new ArrayList<String>();
            for (var r : dns.listRecordSets(z.getName()).iterateAll()) {
                regs.add(r.getName() + " " + r.getType() + " " + String.join(",", r.getRecords()));
            }
            out.put(z.getDnsName(), regs);
        }
        return out;
    }

    @Override
    public void close() {
        subredes.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public class ServicioDeAccesoPrivado {

    private final AccesoPrivadoGcp gcp;
    private final VerificadorDeAccesoPrivado verificador = new VerificadorDeAccesoPrivado();

    public ServicioDeAccesoPrivado(AccesoPrivadoGcp gcp) {
        this.gcp = gcp;
    }

    public List<VerificadorDeAccesoPrivado.Hallazgo> verificar(String red, VerificadorDeAccesoPrivado.Modo modo, String ip) {
        return verificador.verificar(modo, ip, gcp.subredes(red), gcp.zonas());
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class AccesoPrivadoConfiguracion {

    @Bean(destroyMethod = "close")
    AccesoPrivadoGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new AccesoPrivadoGcp(cred, proyecto);
    }

    @Bean
    ServicioDeAccesoPrivado servicio(AccesoPrivadoGcp a) {
        return new ServicioDeAccesoPrivado(a);
    }
}

@RestController
@RequestMapping("/red/acceso-privado")
class AccesoPrivadoControlador {

    private final ServicioDeAccesoPrivado s;

    AccesoPrivadoControlador(ServicioDeAccesoPrivado s) {
        this.s = s;
    }

    @GetMapping("/verificacion")
    List<VerificadorDeAccesoPrivado.Hallazgo> verificar(@RequestParam String red, @RequestParam VerificadorDeAccesoPrivado.Modo modo, @RequestParam String ip) {
        return s.verificar(red, modo, ip);
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/acceso-privado")
class AccesoPrivadoReactivoControlador {

    private final ServicioDeAccesoPrivado s;

    AccesoPrivadoReactivoControlador(ServicioDeAccesoPrivado s) {
        this.s = s;
    }

    @GetMapping("/verificacion")
    Mono<List<VerificadorDeAccesoPrivado.Hallazgo>> verificar(@RequestParam String red, @RequestParam VerificadorDeAccesoPrivado.Modo modo, @RequestParam String ip) {
        return Mono.fromCallable(() -> s.verificar(red, modo, ip)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AccesoPrivadoProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    AccesoPrivadoGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new AccesoPrivadoGcp(cred, proyecto);
    }

    void cerrar(@Disposes AccesoPrivadoGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeAccesoPrivado servicio(AccesoPrivadoGcp a) {
        return new ServicioDeAccesoPrivado(a);
    }
}

@Path("/red/acceso-privado")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class AccesoPrivadoRecurso {

    @Inject
    ServicioDeAccesoPrivado s;

    @GET
    @Path("/verificacion")
    public List<VerificadorDeAccesoPrivado.Hallazgo> verificar(@QueryParam("red") String red, @QueryParam("modo") VerificadorDeAccesoPrivado.Modo modo, @QueryParam("ip") String ip) {
        return s.verificar(red, modo, ip);
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
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/red/acceso-privado")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class AccesoPrivadoRecursoReactivo {

    @Inject
    ServicioDeAccesoPrivado s;

    @GET
    @Path("/verificacion")
    public Uni<List<VerificadorDeAccesoPrivado.Hallazgo>> verificar(@QueryParam("red") String red, @QueryParam("modo") VerificadorDeAccesoPrivado.Modo modo, @QueryParam("ip") String ip) {
        return Uni.createFrom().item(() -> s.verificar(red, modo, ip)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer subredes | `roles/compute.networkViewer` |
| Leer zonas y registros | `roles/dns.reader` |

## 8. Qué NO hacer desde Java
- No asumas que el camino privado da permisos: cada API sigue pidiendo su rol.
- No mezcles en la misma red PGA con dominios públicos y una zona privada a medias.
- No pruebes solo desde tu laptop: la resolución se comprueba desde la VM o el pod.
