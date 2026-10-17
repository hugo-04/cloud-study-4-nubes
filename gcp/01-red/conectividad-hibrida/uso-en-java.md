# Google Cloud · Red · Conectividad entre redes e híbrida · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **verificador de peering**: lee los peerings de ambos lados con `NetworksClient.get` y los rangos de subred (primarios y secundarios) con `SubnetworksClient.aggregatedList`; reporta peerings no activos, rutas personalizadas exportadas que el otro lado no importa y solapes de rangos. Si no puede leer la red par, lo dice.

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

/** Verifica peerings: estado, coherencia de rutas personalizadas entre ambos lados y solapes. Puro. */
public class VerificadorDePeering {

    public record Peering(String red, String nombre, String redPar, String estado, boolean exporta, boolean importa) { }

    public record Hallazgo(String peering, String severidad, String mensaje) { }

    public List<Hallazgo> verificar(List<Peering> peerings, List<String> rangosLocales, List<String> rangosPar) {
        var h = new ArrayList<Hallazgo>();
        for (Peering p : peerings) {
            if (!"ACTIVE".equals(p.estado())) {
                h.add(new Hallazgo(p.nombre(), "ALTA", "estado " + p.estado() + ": falta el otro lado o hay conflicto"));
            }
            var inverso = peerings.stream().filter(q -> q.red().equals(p.redPar()) && q.redPar().equals(p.red())).findFirst();
            if (inverso.isPresent() && p.exporta() && !inverso.get().importa()) {
                h.add(new Hallazgo(p.nombre(), "MEDIA", "exporta rutas personalizadas pero el otro lado no las importa"));
            }
        }
        for (String a : rangosLocales) {
            for (String b : rangosPar) {
                if (solapan(a, b)) {
                    h.add(new Hallazgo("-", "ALTA", a + " se solapa con " + b));
                }
            }
        }
        return h;
    }

    static boolean solapan(String a, String b) {
        long[] x = limites(a);
        long[] y = limites(b);
        return x[0] <= y[1] && y[0] <= x[1];
    }

    static long[] limites(String cidr) {
        String[] p = cidr.split("/");
        long ip = 0;
        for (String o : p[0].split("\\.")) {
            ip = (ip << 8) | Integer.parseInt(o);
        }
        long tam = 1L << (32 - Integer.parseInt(p[1]));
        long ini = ip & ~(tam - 1) & 0xFFFFFFFFL;
        return new long[] {ini, ini + tam - 1};
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.NetworksClient;
import com.google.cloud.compute.v1.NetworksSettings;
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: peerings de una red y rangos de subred de un proyecto/red. */
public class PeeringGcp implements AutoCloseable {

    private final NetworksClient redes;
    private final SubnetworksClient subredes;

    public PeeringGcp(GoogleCredentials cred) {
        try {
            var cp = FixedCredentialsProvider.create(cred);
            this.redes = NetworksClient.create(NetworksSettings.newBuilder().setCredentialsProvider(cp).build());
            this.subredes = SubnetworksClient.create(SubnetworksSettings.newBuilder().setCredentialsProvider(cp).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<VerificadorDePeering.Peering> peerings(String proyecto, String red) {
        var n = redes.get(proyecto, red);
        return n.getPeeringsList().stream().map(p -> new VerificadorDePeering.Peering(n.getSelfLink(), p.getName(),
            p.getNetwork(), p.getState(), p.getExportCustomRoutes(), p.getImportCustomRoutes())).toList();
    }

    public List<String> rangos(String proyecto, String red) {
        var out = new ArrayList<String>();
        for (var e : subredes.aggregatedList(proyecto).iterateAll()) {
            e.getValue().getSubnetworksList().stream().filter(s -> s.getNetwork().endsWith("/" + red)).forEach(s -> {
                out.add(s.getIpCidrRange());
                s.getSecondaryIpRangesList().forEach(r -> out.add(r.getIpCidrRange()));
            });
        }
        return out;
    }

    @Override
    public void close() {
        redes.close();
        subredes.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

public class ServicioDePeering {

    public record Pedido(String proyecto, String red, String proyectoPar, String redPar) { }

    private final PeeringGcp gcp;
    private final VerificadorDePeering verificador = new VerificadorDePeering();

    public ServicioDePeering(PeeringGcp gcp) {
        this.gcp = gcp;
    }

    public List<VerificadorDePeering.Hallazgo> verificar(Pedido p) {
        var peerings = new ArrayList<VerificadorDePeering.Peering>(gcp.peerings(p.proyecto(), p.red()));
        List<String> rangosPar;
        try {
            peerings.addAll(gcp.peerings(p.proyectoPar(), p.redPar()));
            rangosPar = gcp.rangos(p.proyectoPar(), p.redPar());
        } catch (RuntimeException sinPermiso) {
            // no poder leer el otro lado es un hallazgo, no un «todo bien»
            var h = new ArrayList<>(verificador.verificar(peerings, List.of(), List.of()));
            h.add(new VerificadorDePeering.Hallazgo("-", "MEDIA", "no se pudo leer la red par: " + sinPermiso.getClass().getSimpleName()));
            return h;
        }
        return verificador.verificar(peerings, gcp.rangos(p.proyecto(), p.red()), rangosPar);
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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class PeeringConfiguracion {

    @Bean(destroyMethod = "close")
    PeeringGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PeeringGcp(cred);
    }

    @Bean
    ServicioDePeering servicio(PeeringGcp a) {
        return new ServicioDePeering(a);
    }
}

@RestController
@RequestMapping("/red/peering")
class PeeringControlador {

    private final ServicioDePeering s;

    PeeringControlador(ServicioDePeering s) {
        this.s = s;
    }

    @PostMapping("/verificacion")
    List<VerificadorDePeering.Hallazgo> verificar(@RequestBody ServicioDePeering.Pedido p) {
        return s.verificar(p);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/peering")
class PeeringReactivoControlador {

    private final ServicioDePeering s;

    PeeringReactivoControlador(ServicioDePeering s) {
        this.s = s;
    }

    @PostMapping("/verificacion")
    Mono<List<VerificadorDePeering.Hallazgo>> verificar(@RequestBody ServicioDePeering.Pedido p) {
        return Mono.fromCallable(() -> s.verificar(p)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class PeeringProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PeeringGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new PeeringGcp(cred);
    }

    void cerrar(@Disposes PeeringGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDePeering servicio(PeeringGcp a) {
        return new ServicioDePeering(a);
    }
}

@Path("/red/peering")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class PeeringRecurso {

    @Inject
    ServicioDePeering s;

    @POST
    @Path("/verificacion")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<VerificadorDePeering.Hallazgo> verificar(ServicioDePeering.Pedido p) {
        return s.verificar(p);
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
import java.util.List;

@Path("/reactivo/red/peering")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class PeeringRecursoReactivo {

    @Inject
    ServicioDePeering s;

    @POST
    @Path("/verificacion")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<VerificadorDePeering.Hallazgo>> verificar(ServicioDePeering.Pedido p) {
        return Uni.createFrom().item(() -> s.verificar(p)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer redes y subredes de ambos proyectos | `roles/compute.networkViewer` en ambos proyectos |

## 8. Qué NO hacer desde Java
- No trates un error de permisos al leer la red par como «sin hallazgos».
- No olvides los rangos secundarios (pods/servicios de GKE): también chocan.
- No crees peerings desde la app.
