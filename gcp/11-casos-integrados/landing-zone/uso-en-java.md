# Google Cloud · Caso integrado · Landing zone · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

El **planificador de direcciones** de la landing zone: lee las subredes de los proyectos host con `SubnetworksClient.aggregatedList` (todas las regiones), suma **rangos primarios y secundarios** (pods y servicios de GKE) y las redes locales conectadas, y propone el primer /16 libre de `10.0.0.0/8`; el verificador reporta solapes existentes. La propuesta alimenta `cidr_unidad` del Terraform del caso.

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

### 2.2 Planificador de CIDR (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/** Planificador de direcciones: propone el primer bloque libre del tamaño pedido dentro de un rango. Puro. */
public class PlanificadorDeCidr {

    public record Bloque(long inicio, int prefijo) {
        public long fin() {
            return inicio + (1L << (32 - prefijo)) - 1;
        }

        public boolean solapa(Bloque o) {
            return inicio <= o.fin() && o.inicio() <= fin();
        }

        public static Bloque de(String cidr) {
            String[] p = cidr.split("/");
            String[] o = p[0].split("\\.");
            if (o.length != 4) {
                throw new IllegalArgumentException("CIDR inválido: " + cidr);
            }
            long ip = 0;
            for (String x : o) {
                int v = Integer.parseInt(x);
                if (v < 0 || v > 255) {
                    throw new IllegalArgumentException("CIDR inválido: " + cidr);
                }
                ip = (ip << 8) | v;
            }
            int pre = Integer.parseInt(p[1]);
            long mascara = pre == 0 ? 0 : (0xFFFFFFFFL << (32 - pre)) & 0xFFFFFFFFL;
            return new Bloque(ip & mascara, pre);
        }

        @Override
        public String toString() {
            return ((inicio >> 24) & 255) + "." + ((inicio >> 16) & 255) + "." + ((inicio >> 8) & 255) + "." + (inicio & 255) + "/" + prefijo;
        }
    }

    public Optional<String> proponer(String rangoPadre, int prefijo, List<String> ocupados) {
        Bloque padre = Bloque.de(rangoPadre);
        if (prefijo < padre.prefijo() || prefijo > 28) {
            throw new IllegalArgumentException("prefijo fuera de rango");
        }
        List<Bloque> usados = new ArrayList<>(ocupados.stream().map(Bloque::de).toList());
        long paso = 1L << (32 - prefijo);
        for (long ini = padre.inicio(); ini + paso - 1 <= padre.fin(); ini += paso) {
            Bloque candidato = new Bloque(ini, prefijo);
            if (usados.stream().noneMatch(candidato::solapa)) {
                return Optional.of(candidato.toString());
            }
        }
        return Optional.empty();
    }

    /** Pares solapados entre los rangos dados (para el verificador). */
    public List<String> solapes(List<String> cidrs) {
        var out = new ArrayList<String>();
        for (int i = 0; i < cidrs.size(); i++) {
            for (int j = i + 1; j < cidrs.size(); j++) {
                if (Bloque.de(cidrs.get(i)).solapa(Bloque.de(cidrs.get(j)))) {
                    out.add(cidrs.get(i) + " ∩ " + cidrs.get(j));
                }
            }
        }
        return out;
    }
}
```

### 2.3 Adaptador de Compute
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.SubnetworksClient;
import com.google.cloud.compute.v1.SubnetworksSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: rangos primarios y secundarios de todas las subredes de los proyectos host. */
public class RedesGcp implements AutoCloseable {

    private final SubnetworksClient subredes;

    public RedesGcp(GoogleCredentials cred) {
        try {
            this.subredes = SubnetworksClient.create(SubnetworksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<String> cidrsEnUso(List<String> proyectosHost) {
        var out = new ArrayList<String>();
        for (String p : proyectosHost) {
            for (var region : subredes.aggregatedList(p).iterateAll()) {
                for (var s : region.getValue().getSubnetworksList()) {
                    out.add(s.getIpCidrRange());
                    s.getSecondaryIpRangesList().forEach(r -> out.add(r.getIpCidrRange()));   // pods y servicios de GKE
                }
            }
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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class ServicioDeLandingZone {

    public record Propuesta(String cidr, List<String> enUso) { }

    private final RedesGcp redes;
    private final PlanificadorDeCidr planificador = new PlanificadorDeCidr();

    public ServicioDeLandingZone(RedesGcp redes) {
        this.redes = redes;
    }

    private static List<String> lista(String csv) {
        return Arrays.stream(csv.split(",")).map(String::trim).filter(x -> !x.isEmpty()).toList();
    }

    /** hosts: proyectos host separados por coma; redesLocales: rangos de oficinas conectadas (no visibles en la VPC). */
    public Propuesta proponer(String hosts, List<String> redesLocales) {
        var enUso = new ArrayList<>(redes.cidrsEnUso(lista(hosts)));
        enUso.addAll(redesLocales);
        String cidr = planificador.proponer("10.0.0.0/8", 16, enUso)
            .orElseThrow(() -> new IllegalStateException("no quedan /16 libres en 10.0.0.0/8"));
        return new Propuesta(cidr, enUso);
    }

    public List<String> verificarSolapes(String hosts) {
        return planificador.solapes(redes.cidrsEnUso(lista(hosts)));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.google.auth.oauth2.GoogleCredentials;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class LandingZoneConfiguracion {

    @Bean(destroyMethod = "close")
    RedesGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new RedesGcp(cred);
    }

    @Bean
    ServicioDeLandingZone servicio(RedesGcp a) {
        return new ServicioDeLandingZone(a);
    }
}

@RestController
@RequestMapping("/plataforma/landing-zone")
class LandingZoneControlador {

    private final ServicioDeLandingZone s;

    LandingZoneControlador(ServicioDeLandingZone s) {
        this.s = s;
    }

    @PostMapping("/cidr")
    ServicioDeLandingZone.Propuesta proponer(@RequestParam String hosts, @RequestBody java.util.List<String> redesLocales) {
        return s.proponer(hosts, redesLocales);
    }

    @GetMapping("/solapes")
    java.util.List<String> solapes(@RequestParam String hosts) {
        return s.verificarSolapes(hosts);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/plataforma/landing-zone")
class LandingZoneReactivoControlador {

    private final ServicioDeLandingZone s;

    LandingZoneReactivoControlador(ServicioDeLandingZone s) {
        this.s = s;
    }

    @PostMapping("/cidr")
    Mono<ServicioDeLandingZone.Propuesta> proponer(@RequestParam String hosts, @RequestBody java.util.List<String> redesLocales) {
        return Mono.fromCallable(() -> s.proponer(hosts, redesLocales)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/solapes")
    Mono<java.util.List<String>> solapes(@RequestParam String hosts) {
        return Mono.fromCallable(() -> s.verificarSolapes(hosts)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class LandingZoneProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    RedesGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new RedesGcp(cred);
    }

    void cerrar(@Disposes RedesGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeLandingZone servicio(RedesGcp a) {
        return new ServicioDeLandingZone(a);
    }
}

@Path("/plataforma/landing-zone")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class LandingZoneRecurso {

    @Inject
    ServicioDeLandingZone s;

    @POST
    @Path("/cidr")
    @Consumes(MediaType.APPLICATION_JSON)
    public ServicioDeLandingZone.Propuesta proponer(@QueryParam("hosts") String hosts, java.util.List<String> redesLocales) {
        return s.proponer(hosts, redesLocales);
    }

    @GET
    @Path("/solapes")
    public java.util.List<String> solapes(@QueryParam("hosts") String hosts) {
        return s.verificarSolapes(hosts);
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/plataforma/landing-zone")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class LandingZoneRecursoReactivo {

    @Inject
    ServicioDeLandingZone s;

    @POST
    @Path("/cidr")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<ServicioDeLandingZone.Propuesta> proponer(@QueryParam("hosts") String hosts, java.util.List<String> redesLocales) {
        return Uni.createFrom().item(() -> s.proponer(hosts, redesLocales)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/solapes")
    public Uni<java.util.List<String>> solapes(@QueryParam("hosts") String hosts) {
        return Uni.createFrom().item(() -> s.verificarSolapes(hosts)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer subredes | `roles/compute.networkViewer` en los proyectos host |

## 8. Qué NO hacer desde Java
- No olvides los rangos secundarios.
- No asumas que la VPC muestra todo: pide las redes locales.
- No apliques la propuesta sin el `plan` revisado.
- No uses la SA del pipeline para leer.
