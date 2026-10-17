# Oracle OCI · IAM · Identity Domains · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **auditor de higiene de usuarios** (puro: activos sin grupo, exceso de privilegiados) alimentado por la API **SCIM** del dominio con `IdentityDomainsClient`, que usa la **URL del dominio** como endpoint.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  dominio-url: https://idcs-xxxx.identity.oraclecloud.com:443
iam:
  max-privilegiados: 3
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.dominio-url=https://idcs-xxxx.identity.oraclecloud.com:443
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

### 2.2 Datos del usuario
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Set;

public record UsuarioResumen(String id, String usuario, boolean activo, Set<String> grupos) { }
```

### 2.3 El auditor
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Reglas de higiene sobre usuarios del dominio. Puro: no llama a la red. */
public final class AuditorDeUsuarios {

    public record Hallazgo(String usuario, String motivo) { }

    private final Set<String> gruposPrivilegiados;
    private final int maxPrivilegiados;

    public AuditorDeUsuarios(Set<String> gruposPrivilegiados, int maxPrivilegiados) {
        this.gruposPrivilegiados = gruposPrivilegiados;
        this.maxPrivilegiados = maxPrivilegiados;
    }

    public List<Hallazgo> revisar(List<UsuarioResumen> usuarios) {
        var salida = new ArrayList<Hallazgo>();
        int privilegiados = 0;
        for (UsuarioResumen u : usuarios) {
            if (!u.activo()) {
                continue;
            }
            if (u.grupos().isEmpty()) {
                salida.add(new Hallazgo(u.usuario(), "activo y sin grupo: o sobra o falta un permiso"));
            }
            if (u.grupos().stream().anyMatch(gruposPrivilegiados::contains)) {
                privilegiados++;
            }
        }
        if (privilegiados > maxPrivilegiados) {
            salida.add(new Hallazgo("(global)", privilegiados + " usuarios activos en grupos privilegiados; el máximo acordado es " + maxPrivilegiados));
        }
        return salida;
    }
}
```

### 2.4 Lectura SCIM con paginación
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.User;
import com.oracle.bmc.identitydomains.model.UserGroups;
import com.oracle.bmc.identitydomains.requests.ListUsersRequest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;

/** Lee usuarios del dominio por SCIM (paginación con startIndex base 1). */
public class UsuariosDeDominio implements AutoCloseable {

    private static final int PAGINA = 100;

    private final IdentityDomainsClient cliente;

    public UsuariosDeDominio(BasicAuthenticationDetailsProvider auth, String urlDelDominio) {
        this.cliente = IdentityDomainsClient.builder().endpoint(urlDelDominio).build(auth);
    }

    public List<UsuarioResumen> todos() {
        var salida = new ArrayList<UsuarioResumen>();
        int inicio = 1;
        while (true) {
            var req = ListUsersRequest.builder().startIndex(inicio).count(PAGINA).build();
            var users = cliente.listUsers(req).getUsers();
            List<User> pagina = users.getResources();
            if (pagina == null || pagina.isEmpty()) {
                break;
            }
            for (User u : pagina) {
                var grupos = new HashSet<String>();
                if (u.getGroups() != null) {
                    for (UserGroups g : u.getGroups()) {
                        grupos.add(g.getDisplay());
                    }
                }
                salida.add(new UsuarioResumen(u.getId(), u.getUserName(), Boolean.TRUE.equals(u.getActive()), grupos));
            }
            inicio += pagina.size();
            if (users.getTotalResults() != null && inicio > users.getTotalResults()) {
                break;
            }
        }
        return salida;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.function.Supplier;

public class ServicioDeDominio {

    private final Supplier<List<UsuarioResumen>> usuarios;
    private final AuditorDeUsuarios auditor;

    public ServicioDeDominio(Supplier<List<UsuarioResumen>> usuarios, AuditorDeUsuarios auditor) {
        this.usuarios = usuarios;
        this.auditor = auditor;
    }

    public List<AuditorDeUsuarios.Hallazgo> auditar() {
        return auditor.revisar(usuarios.get());
    }

    public List<AuditorDeUsuarios.Hallazgo> auditarLista(List<UsuarioResumen> lista) {
        return auditor.revisar(lista);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.List;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class DominioConfiguracion {

    @Bean(destroyMethod = "close")
    UsuariosDeDominio usuariosDeDominio(@Value("${oci.auth}") String modo, @Value("${oci.dominio-url}") String url) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new UsuariosDeDominio(auth, url);
    }

    @Bean
    ServicioDeDominio servicioDeDominio(UsuariosDeDominio usuarios, @Value("${iam.max-privilegiados:3}") int max) {
        return new ServicioDeDominio(usuarios::todos, new AuditorDeUsuarios(Set.of("Administrators", "Domain_Administrators"), max));
    }
}

@RestController
@RequestMapping("/iam/dominio")
class DominioControlador {

    private final ServicioDeDominio s;

    DominioControlador(ServicioDeDominio s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<AuditorDeUsuarios.Hallazgo> auditoria() {
        return s.auditar();
    }

    @PostMapping("/revisar")
    List<AuditorDeUsuarios.Hallazgo> revisar(@RequestBody List<UsuarioResumen> usuarios) {
        return s.auditarLista(usuarios);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.List;
import java.util.Set;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/iam/dominio")
class DominioReactivoControlador {

    private final ServicioDeDominio s;

    DominioReactivoControlador(ServicioDeDominio s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<AuditorDeUsuarios.Hallazgo>> auditoria() {
        return Mono.fromCallable(() -> s.auditar()).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/revisar")
    Mono<List<AuditorDeUsuarios.Hallazgo>> revisar(@RequestBody List<UsuarioResumen> usuarios) {
        return Mono.fromCallable(() -> s.auditarLista(usuarios));
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
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
import java.util.Set;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class DominioProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.dominio-url")
    String url;

    @jakarta.enterprise.inject.Produces
    @Singleton
    UsuariosDeDominio usuariosDeDominio() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new UsuariosDeDominio(auth, url);
    }

    void cerrar(@Disposes UsuariosDeDominio u) {
        u.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeDominio servicioDeDominio(UsuariosDeDominio usuarios) {
        return new ServicioDeDominio(usuarios::todos, new AuditorDeUsuarios(Set.of("Administrators", "Domain_Administrators"), 3));
    }
}

@Path("/iam/dominio")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class DominioRecurso {

    @Inject
    ServicioDeDominio s;

    @GET
    @Path("/auditoria")
    public List<AuditorDeUsuarios.Hallazgo> auditoria() {
        return s.auditar();
    }

    @POST
    @Path("/revisar")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<AuditorDeUsuarios.Hallazgo> revisar(List<UsuarioResumen> usuarios) {
        return s.auditarLista(usuarios);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.util.List;
import java.util.Set;

@Path("/reactivo/iam/dominio")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class DominioRecursoReactivo {

    @Inject
    ServicioDeDominio s;

    @GET
    @Path("/auditoria")
    public Uni<List<AuditorDeUsuarios.Hallazgo>> auditoria() {
        return Uni.createFrom().item(() -> s.auditar()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @POST
    @Path("/revisar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<AuditorDeUsuarios.Hallazgo>> revisar(List<UsuarioResumen> usuarios) {
        return Uni.createFrom().item(() -> s.auditarLista(usuarios));
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Listar usuarios del dominio | Pertenecer a un rol de administrador del dominio con lectura de usuarios (por ejemplo *User Administrator*) *(verifica el rol mínimo)* |
| El auditor | Ninguna: es lógica pura |

## 8. Qué NO hacer desde Java
- No uses la URL de otro dominio: la lista saldrá vacía sin error.
- No guardes la salida de la auditoría con correos de personas en registros públicos.
- No desactives usuarios automáticamente desde esta herramienta: reporta y que una persona decida.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
