# Oracle OCI · Terraform · Autenticación y pipelines · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **vigilante de rotación de llaves** de los usuarios de servicio que usan los runners externos: lee sus API keys con `IdentityClient.listApiKeys` y decide por usuario: la más nueva se evalúa por edad (aviso a los 75 días, rotación obligatoria a los 90) y cualquier otra llave activa debe borrarse. Los runners dentro de OCI no necesitan esto: usan instance principal.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
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

### 2.2 Política de rotación (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Política de rotación de API keys de usuarios de servicio. Puro: reloj inyectado. */
public class PoliticaDeRotacion {

    public record Llave(String usuario, String huella, Instant creada, boolean activa) { }

    public enum Accion { OK, ROTAR_PRONTO, ROTAR_YA, BORRAR_VIEJA }

    public record Veredicto(Llave llave, Accion accion, long dias) { }

    private final Clock reloj;
    private final Duration aviso;
    private final Duration maximo;

    public PoliticaDeRotacion(Clock reloj, Duration aviso, Duration maximo) {
        this.reloj = reloj;
        this.aviso = aviso;
        this.maximo = maximo;
    }

    /** Por usuario: la más nueva es la vigente; las demás activas deberían borrarse tras la rotación. */
    public List<Veredicto> evaluar(List<Llave> llaves) {
        var out = new ArrayList<Veredicto>();
        Instant ahora = reloj.instant();
        llaves.stream().filter(Llave::activa).map(Llave::usuario).distinct().forEach(u -> {
            var delUsuario = llaves.stream().filter(l -> l.usuario().equals(u) && l.activa())
                .sorted(Comparator.comparing(Llave::creada).reversed()).toList();
            for (int i = 0; i < delUsuario.size(); i++) {
                var l = delUsuario.get(i);
                long dias = Duration.between(l.creada(), ahora).toDays();
                Accion a;
                if (i > 0) {
                    a = Accion.BORRAR_VIEJA;
                } else if (dias >= maximo.toDays()) {
                    a = Accion.ROTAR_YA;
                } else if (dias >= aviso.toDays()) {
                    a = Accion.ROTAR_PRONTO;
                } else {
                    a = Accion.OK;
                }
                out.add(new Veredicto(l, a, dias));
            }
        });
        return out;
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.ApiKey;
import com.oracle.bmc.identity.requests.ListApiKeysRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: API keys de los usuarios de servicio indicados. */
public class LlavesOci implements AutoCloseable {

    private final IdentityClient cliente;

    public LlavesOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public List<PoliticaDeRotacion.Llave> llaves(List<String> usuarios) {
        var out = new ArrayList<PoliticaDeRotacion.Llave>();
        for (String u : usuarios) {
            for (ApiKey k : cliente.listApiKeys(ListApiKeysRequest.builder().userId(u).build()).getItems()) {
                out.add(new PoliticaDeRotacion.Llave(u, k.getFingerprint(), k.getTimeCreated().toInstant(),
                    k.getLifecycleState() == ApiKey.LifecycleState.Active));
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
import java.time.Clock;
import java.time.Duration;
import java.util.List;

public class ServicioDeRotacion {

    private final LlavesOci llaves;
    private final PoliticaDeRotacion politica = new PoliticaDeRotacion(Clock.systemUTC(), Duration.ofDays(75), Duration.ofDays(90));

    public ServicioDeRotacion(LlavesOci llaves) {
        this.llaves = llaves;
    }

    public List<PoliticaDeRotacion.Veredicto> revisar(List<String> usuariosDeServicio) {
        return politica.evaluar(llaves.llaves(usuariosDeServicio)).stream()
            .filter(v -> v.accion() != PoliticaDeRotacion.Accion.OK)
            .toList();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class RotacionConfiguracion {

    @Bean(destroyMethod = "close")
    LlavesOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new LlavesOci(IdentityClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    @Bean
    ServicioDeRotacion servicio(LlavesOci a) {
        return new ServicioDeRotacion(a);
    }
}

@RestController
@RequestMapping("/terraform/llaves")
class RotacionControlador {

    private final ServicioDeRotacion s;

    RotacionControlador(ServicioDeRotacion s) {
        this.s = s;
    }

    @PostMapping("/revision")
    List<PoliticaDeRotacion.Veredicto> revisar(@RequestBody List<String> usuarios) {
        return s.revisar(usuarios);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/terraform/llaves")
class RotacionReactivoControlador {

    private final ServicioDeRotacion s;

    RotacionReactivoControlador(ServicioDeRotacion s) {
        this.s = s;
    }

    @PostMapping("/revision")
    Mono<List<PoliticaDeRotacion.Veredicto>> revisar(@RequestBody List<String> usuarios) {
        return Mono.fromCallable(() -> s.revisar(usuarios)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
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
class RotacionProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    LlavesOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new LlavesOci(IdentityClient.builder().region(Region.fromRegionId(region)).build(auth));
    }

    void cerrar(@Disposes LlavesOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeRotacion servicio(LlavesOci a) {
        return new ServicioDeRotacion(a);
    }
}

@Path("/terraform/llaves")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class RotacionRecurso {

    @Inject
    ServicioDeRotacion s;

    @POST
    @Path("/revision")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<PoliticaDeRotacion.Veredicto> revisar(List<String> usuarios) {
        return s.revisar(usuarios);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identity.IdentityClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/terraform/llaves")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class RotacionRecursoReactivo {

    @Inject
    ServicioDeRotacion s;

    @POST
    @Path("/revision")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<PoliticaDeRotacion.Veredicto>> revisar(List<String> usuarios) {
        return Uni.createFrom().item(() -> s.revisar(usuarios)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Listar API keys de usuarios | `Allow dynamic-group auditoria to inspect users in tenancy` *(verifica el permiso exacto para listar llaves)* |

## 8. Qué NO hacer desde Java
- No crees ni borres llaves automáticamente sin un procedimiento de rotación probado (nueva → desplegar → borrar vieja).
- No registres huellas junto con nombres de usuario en canales abiertos.
- No uses API keys en runners que corren dentro de OCI.
