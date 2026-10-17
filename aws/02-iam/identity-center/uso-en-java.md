# AWS · IAM Identity Center · Uso desde Java

Dos usos desde Java: (1) que **tu código local use el perfil SSO** (la persona desarrolladora entra con `aws sso login` y el SDK obtiene credenciales temporales), y (2) un **informe de accesos** («quién tiene qué en qué cuenta») que detecta asignaciones peligrosas con funciones puras. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Que el SDK use tu sesión SSO (desarrollo local)
```bash
aws sso login --sso-session modalima
export AWS_PROFILE=dev-desarrollo
```
```xml
<!-- El perfil SSO necesita estos dos módulos en el classpath (si no, el SDK dice que no encuentra el proveedor) -->
<dependency>
  <groupId>software.amazon.awssdk</groupId>
  <artifactId>sso</artifactId>
</dependency>
<dependency>
  <groupId>software.amazon.awssdk</groupId>
  <artifactId>ssooidc</artifactId>
</dependency>
```
```java
import software.amazon.awssdk.auth.credentials.ProfileCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sts.StsClient;

class QuienSoy {
    static String arn() {
        try (StsClient sts = StsClient.builder()
                .region(Region.US_EAST_1)
                .credentialsProvider(ProfileCredentialsProvider.create("dev-desarrollo"))
                .build()) {
            return sts.getCallerIdentity().arn();   // arn:aws:sts::111122223333:assumed-role/AWSReservedSSO_Desarrollo_xxxx/persona
        }
    }
}
```
> En **producción** no se usa SSO: la aplicación usa su rol (ECS, IRSA, Pod Identity). El perfil SSO es solo para personas.

## 2. Informe de accesos (quién tiene qué)

### Núcleo común (reglas puras + lector)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import software.amazon.awssdk.services.identitystore.IdentitystoreClient;
import software.amazon.awssdk.services.identitystore.model.DescribeGroupRequest;
import software.amazon.awssdk.services.identitystore.model.DescribeUserRequest;
import software.amazon.awssdk.services.ssoadmin.SsoAdminClient;
import software.amazon.awssdk.services.ssoadmin.model.DescribePermissionSetRequest;
import software.amazon.awssdk.services.ssoadmin.model.InstanceMetadata;
import software.amazon.awssdk.services.ssoadmin.model.ListInstancesRequest;
import software.amazon.awssdk.services.ssoadmin.model.ListAccountAssignmentsRequest;
import software.amazon.awssdk.services.ssoadmin.model.ListAccountsForProvisionedPermissionSetRequest;
import software.amazon.awssdk.services.ssoadmin.model.ListPermissionSetsRequest;

enum Gravedad { BAJA, MEDIA, ALTA }

record Asignacion(String cuenta, String conjunto, String tipoPrincipal, String principal) {}

record HallazgoAcceso(Gravedad gravedad, String principal, String motivo) {}

final class RevisionAccesos {
    private RevisionAccesos() {}

    static List<HallazgoAcceso> evaluar(List<Asignacion> asignaciones, Set<String> cuentasProd, int maxCuentasAdmin) {
        List<HallazgoAcceso> r = new ArrayList<>();
        Map<String, Integer> cuentasAdminPorPrincipal = new HashMap<>();
        for (Asignacion a : asignaciones) {
            boolean admin = a.conjunto().toLowerCase().contains("admin");
            if ("USER".equals(a.tipoPrincipal())) {
                r.add(new HallazgoAcceso(Gravedad.MEDIA, a.principal(), "Asignación directa a una persona en " + a.cuenta() + ": usa grupos"));
            }
            if (admin && cuentasProd.contains(a.cuenta())) {
                r.add(new HallazgoAcceso(Gravedad.ALTA, a.principal(), "Administrador permanente en producción (" + a.cuenta() + ")"));
            }
            if (admin) cuentasAdminPorPrincipal.merge(a.principal(), 1, Integer::sum);
        }
        cuentasAdminPorPrincipal.forEach((p, n) -> {
            if (n > maxCuentasAdmin) r.add(new HallazgoAcceso(Gravedad.ALTA, p, "Administrador en " + n + " cuentas (máximo " + maxCuentasAdmin + ")"));
        });
        return r.stream().sorted((x, y) -> y.gravedad().compareTo(x.gravedad())).toList();
    }
}

final class LectorIdentityCenter {
    private final SsoAdminClient sso;
    private final IdentitystoreClient almacen;
    private final Map<String, String> nombres = new HashMap<>();

    LectorIdentityCenter(SsoAdminClient sso, IdentitystoreClient almacen) {
        this.sso = sso;
        this.almacen = almacen;
    }

    List<Asignacion> leer() {
        InstanceMetadata inst = sso.listInstances(ListInstancesRequest.builder().build()).instances().get(0);
        String instanciaArn = inst.instanceArn();
        String almacenId = inst.identityStoreId();
        List<Asignacion> r = new ArrayList<>();

        sso.listPermissionSetsPaginator(ListPermissionSetsRequest.builder().instanceArn(instanciaArn).build())
                .permissionSets().forEach(psArn -> {
                    String nombreConjunto = sso.describePermissionSet(DescribePermissionSetRequest.builder()
                            .instanceArn(instanciaArn).permissionSetArn(psArn).build()).permissionSet().name();
                    sso.listAccountsForProvisionedPermissionSetPaginator(ListAccountsForProvisionedPermissionSetRequest.builder()
                                    .instanceArn(instanciaArn).permissionSetArn(psArn).build())
                            .accountIds().forEach(cuenta ->
                                    sso.listAccountAssignmentsPaginator(ListAccountAssignmentsRequest.builder()
                                                    .instanceArn(instanciaArn).accountId(cuenta).permissionSetArn(psArn).build())
                                            .accountAssignments().forEach(asig -> r.add(new Asignacion(cuenta, nombreConjunto,
                                                    asig.principalTypeAsString(),
                                                    nombre(almacenId, asig.principalTypeAsString(), asig.principalId())))));
                });
        return r;
    }

    private String nombre(String almacenId, String tipo, String id) {
        return nombres.computeIfAbsent(tipo + ":" + id, k -> "GROUP".equals(tipo)
                ? almacen.describeGroup(DescribeGroupRequest.builder().identityStoreId(almacenId).groupId(id).build()).displayName()
                : almacen.describeUser(DescribeUserRequest.builder().identityStoreId(almacenId).userId(id).build()).userName());
    }
}
```
Notas del SDK: `listInstances` es la puerta de entrada (devuelve el ARN de la instancia y el id del almacén); casi todo está **paginado**; los nombres de grupos/usuarios se resuelven aparte y conviene **cachearlos**.

### Spring MVC (imperativo)
```java
import java.util.List;
import java.util.Set;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.identitystore.IdentitystoreClient;
import software.amazon.awssdk.services.ssoadmin.SsoAdminClient;

@Configuration
class IdentityCenterConfig {
    // Identity Center vive en su región de origen: configúrala explícitamente
    @Bean(destroyMethod = "close")
    SsoAdminClient ssoAdmin() {
        return SsoAdminClient.builder().region(Region.of(System.getenv().getOrDefault("IDC_REGION", "us-east-1"))).build();
    }

    @Bean(destroyMethod = "close")
    IdentitystoreClient identityStore() {
        return IdentitystoreClient.builder().region(Region.of(System.getenv().getOrDefault("IDC_REGION", "us-east-1"))).build();
    }
}

@RestController
public class AccesosController {
    private final LectorIdentityCenter lector;

    AccesosController(SsoAdminClient sso, IdentitystoreClient almacen) { this.lector = new LectorIdentityCenter(sso, almacen); }

    @GetMapping("/iam/accesos/revision")
    List<HallazgoAcceso> revisar(@RequestParam Set<String> cuentasProd, @RequestParam(defaultValue = "3") int maxAdmin) {
        return RevisionAccesos.evaluar(lector.leer(), cuentasProd, maxAdmin);
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import java.util.Set;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import software.amazon.awssdk.services.identitystore.IdentitystoreClient;
import software.amazon.awssdk.services.ssoadmin.SsoAdminClient;

@RestController
public class AccesosReactivoController {
    private final LectorIdentityCenter lector;

    AccesosReactivoController(SsoAdminClient sso, IdentitystoreClient almacen) { this.lector = new LectorIdentityCenter(sso, almacen); }

    @GetMapping("/iam/reactivo/accesos/revision")
    Mono<List<HallazgoAcceso>> revisar(@RequestParam Set<String> cuentasProd, @RequestParam(defaultValue = "3") int maxAdmin) {
        return Mono.fromCallable(() -> RevisionAccesos.evaluar(lector.leer(), cuentasProd, maxAdmin))
                .subscribeOn(Schedulers.boundedElastic());   // muchas llamadas paginadas: nunca en el bucle de eventos
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import java.util.Set;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.identitystore.IdentitystoreClient;
import software.amazon.awssdk.services.ssoadmin.SsoAdminClient;

@ApplicationScoped
class IdentityCenterProductores {
    @Produces
    @ApplicationScoped
    SsoAdminClient ssoAdmin() {
        return SsoAdminClient.builder().region(Region.of(System.getenv().getOrDefault("IDC_REGION", "us-east-1"))).build();
    }

    @Produces
    @ApplicationScoped
    IdentitystoreClient identityStore() {
        return IdentitystoreClient.builder().region(Region.of(System.getenv().getOrDefault("IDC_REGION", "us-east-1"))).build();
    }
}

@Path("/iam/accesos/revision")
public class AccesosResource {
    @Inject
    SsoAdminClient sso;
    @Inject
    IdentitystoreClient almacen;

    @GET
    public List<HallazgoAcceso> revisar(@QueryParam("cuentasProd") Set<String> cuentasProd, @QueryParam("maxAdmin") Integer maxAdmin) {
        return RevisionAccesos.evaluar(new LectorIdentityCenter(sso, almacen).leer(), cuentasProd, maxAdmin == null ? 3 : maxAdmin);
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import java.util.Set;
import software.amazon.awssdk.services.identitystore.IdentitystoreClient;
import software.amazon.awssdk.services.ssoadmin.SsoAdminClient;

@Path("/iam/reactivo/accesos/revision")
public class AccesosReactivoResource {
    @Inject
    SsoAdminClient sso;
    @Inject
    IdentitystoreClient almacen;

    @GET
    public Uni<List<HallazgoAcceso>> revisar(@QueryParam("cuentasProd") Set<String> cuentasProd) {
        return Uni.createFrom().item(() -> RevisionAccesos.evaluar(new LectorIdentityCenter(sso, almacen).leer(), cuentasProd, 3))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```
> Permisos del informe (cuenta de administración o delegada): `sso:ListInstances`, `sso:ListPermissionSets`, `sso:DescribePermissionSet`, `sso:ListAccountsForProvisionedPermissionSet`, `sso:ListAccountAssignments`, `identitystore:DescribeGroup`, `identitystore:DescribeUser`. Es una **herramienta interna** de seguridad.

## 3. Cómo se usa
- **Mensual/semanal:** se ejecuta, se publica un informe y se abren tareas por cada hallazgo `ALTA`.
- **En el pipeline de asignaciones:** el plan de Terraform se evalúa antes del `apply`.
- **No** se llama desde el camino de una petición de usuario.

## 4. Qué NO hacer desde Java
- No guardar el token de `~/.aws/sso/cache` ni copiarlo a otro lugar.
- No usar un perfil SSO en servidores o contenedores: allí va el rol del servicio.
- No automatizar «quitar acceso» sin un humano que confirme.
