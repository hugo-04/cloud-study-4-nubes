# AWS · IAM · Roles y políticas · Uso desde Java

Para una aplicación, IAM es sobre todo **recibir credenciales temporales sin código** (el SDK las encuentra solo; ver [IRSA y Pod Identity](../irsa-pod-identity/README.md) y [STS](../sts-asumir-roles/README.md)). Lo que sí construyes desde Java: (1) un **linter de políticas** que se corre en el pipeline y (2) un **probador** con el simulador de IAM. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Lo que NO escribes: credenciales
```java
// Correcto: sin claves en el código. La cadena de proveedores del SDK busca, en orden:
// variables de entorno -> propiedades -> web identity (IRSA) -> perfil/SSO -> contenedor (ECS / Pod Identity) -> IMDS (EC2)
import software.amazon.awssdk.services.sqs.SqsClient;

SqsClient sqs = SqsClient.create();   // región y credenciales salen del entorno
```
Nunca `AwsBasicCredentials.create("AKIA…", "…")` con claves de verdad.

## 2. Linter de políticas (funciones puras) y simulador

### Núcleo común
Trabaja sobre `Map<String,Object>` (lo que produce cualquier librería JSON), así no depende de la versión de Jackson de Spring o Quarkus.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import software.amazon.awssdk.services.iam.IamClient;
import software.amazon.awssdk.services.iam.model.SimulatePrincipalPolicyRequest;

enum Gravedad { BAJA, MEDIA, ALTA, CRITICA }

record HallazgoPolitica(String sentencia, Gravedad gravedad, String motivo) {}

final class LinterPoliticas {
    private LinterPoliticas() {}

    /** Acciones que permiten escalar privilegios si se combinan con Resource "*". */
    static final Set<String> ESCALADA = Set.of("iam:passrole", "iam:createaccesskey", "iam:attachrolepolicy",
            "iam:putrolepolicy", "iam:attachuserpolicy", "iam:putuserpolicy", "iam:createpolicyversion",
            "iam:updateassumerolepolicy", "sts:assumerole");

    @SuppressWarnings("unchecked")
    static List<HallazgoPolitica> revisar(Map<String, Object> politica) {
        List<HallazgoPolitica> r = new ArrayList<>();
        for (Map<String, Object> s : sentencias(politica.get("Statement"))) {
            String id = String.valueOf(s.getOrDefault("Sid", "(sin Sid)"));
            if (!"Allow".equals(s.get("Effect"))) continue;
            List<String> acciones = comoLista(s.get("Action"));
            List<String> recursos = comoLista(s.get("Resource"));
            boolean tieneCondicion = s.get("Condition") instanceof Map<?, ?> c && !c.isEmpty();

            if (s.containsKey("NotAction") || s.containsKey("NotResource")) {
                r.add(new HallazgoPolitica(id, Gravedad.ALTA, "Usa NotAction/NotResource con Allow: concede casi todo"));
            }
            if (acciones.contains("*")) {
                r.add(new HallazgoPolitica(id, Gravedad.CRITICA, "Action \"*\": administrador completo"));
            }
            for (String a : acciones) {
                if (a.endsWith(":*") && !a.equals("*")) {
                    r.add(new HallazgoPolitica(id, Gravedad.ALTA, "Comodín de servicio: " + a));
                }
                if (ESCALADA.contains(a.toLowerCase()) && (recursos.contains("*") || recursos.isEmpty())) {
                    r.add(new HallazgoPolitica(id, Gravedad.CRITICA, "Acción de escalada " + a + " sobre Resource \"*\""));
                }
            }
            if (recursos.contains("*") && !acciones.isEmpty() && !acciones.contains("*")
                    && acciones.stream().anyMatch(a -> !a.toLowerCase().matches(".*:(get|list|describe).*"))) {
                r.add(new HallazgoPolitica(id, Gravedad.MEDIA, "Resource \"*\" con acciones de escritura: acota los ARN"));
            }
            Object principal = s.get("Principal");
            if (("*".equals(principal) || (principal instanceof Map<?, ?> p && "*".equals(p.get("AWS")))) && !tieneCondicion) {
                r.add(new HallazgoPolitica(id, Gravedad.CRITICA, "Principal \"*\" sin condiciones: acceso público"));
            }
        }
        return r.stream().sorted((a, b) -> b.gravedad().compareTo(a.gravedad())).toList();
    }

    private static List<String> comoLista(Object o) {
        if (o == null) return List.of();
        if (o instanceof String s) return List.of(s);
        if (o instanceof List<?> l) return l.stream().map(String::valueOf).toList();
        return List.of();
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> sentencias(Object o) {
        if (o instanceof Map<?, ?> m) return List.of((Map<String, Object>) m);
        if (o instanceof List<?> l) return l.stream().filter(x -> x instanceof Map<?, ?>).map(x -> (Map<String, Object>) x).toList();
        return List.of();
    }
}

final class SimuladorIam {
    private final IamClient iam;

    SimuladorIam(IamClient iam) { this.iam = iam; }

    /** Pregunta al simulador de IAM qué decide para un rol/usuario sobre un recurso. No ejecuta nada. */
    Map<String, String> probar(String arnPrincipal, List<String> acciones, String recursoArn) {
        Map<String, String> r = new LinkedHashMap<>();
        iam.simulatePrincipalPolicyPaginator(SimulatePrincipalPolicyRequest.builder()
                        .policySourceArn(arnPrincipal).actionNames(acciones).resourceArns(recursoArn).build())
                .evaluationResults()
                .forEach(e -> r.put(e.evalActionName(), e.evalDecisionAsString()));
        return r;
    }
}
```
IAM es un servicio **global**: se crea con `Region.AWS_GLOBAL`.

### Spring MVC (imperativo)
```java
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.iam.IamClient;

@Configuration
class IamConfig {
    @Bean(destroyMethod = "close")
    IamClient iam() {
        return IamClient.builder().region(Region.AWS_GLOBAL).build();
    }
}

@RestController
public class PoliticasController {
    private final SimuladorIam simulador;

    PoliticasController(IamClient iam) { this.simulador = new SimuladorIam(iam); }

    /** En el pipeline: falla el cambio si hay hallazgos CRITICA. */
    @PostMapping("/iam/politicas/revisar")
    List<HallazgoPolitica> revisar(@RequestBody Map<String, Object> politica) {
        return LinterPoliticas.revisar(politica);
    }

    @PostMapping("/iam/simular")
    Map<String, String> simular(@RequestParam String rol, @RequestParam String recurso, @RequestBody List<String> acciones) {
        return simulador.probar(rol, acciones, recurso);
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import software.amazon.awssdk.services.iam.IamClient;

@RestController
public class PoliticasReactivoController {
    private final SimuladorIam simulador;

    PoliticasReactivoController(IamClient iam) { this.simulador = new SimuladorIam(iam); }

    @PostMapping("/iam/reactivo/politicas/revisar")
    Mono<List<HallazgoPolitica>> revisar(@RequestBody Mono<Map<String, Object>> politica) {
        return politica.map(LinterPoliticas::revisar);   // función pura
    }

    @PostMapping("/iam/reactivo/simular")
    Mono<Map<String, String>> simular(@RequestParam String rol, @RequestParam String recurso, @RequestBody List<String> acciones) {
        return Mono.fromCallable(() -> simulador.probar(rol, acciones, recurso))
                .subscribeOn(Schedulers.boundedElastic());
    }
}
```

### Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.iam.IamClient;

@ApplicationScoped
class IamProductor {
    @Produces
    @ApplicationScoped
    IamClient iam() {
        return IamClient.builder().region(Region.AWS_GLOBAL).build();
    }
}

@Path("/iam")
@Consumes("application/json")
public class PoliticasResource {
    @Inject
    IamClient iam;

    @POST
    @Path("/politicas/revisar")
    public List<HallazgoPolitica> revisar(Map<String, Object> politica) {
        return LinterPoliticas.revisar(politica);
    }

    @POST
    @Path("/simular")
    public Map<String, String> simular(@QueryParam("rol") String rol, @QueryParam("recurso") String recurso, List<String> acciones) {
        return new SimuladorIam(iam).probar(rol, acciones, recurso);
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.iam.IamClient;

@Path("/iam/reactivo")
@Consumes("application/json")
public class PoliticasReactivoResource {
    @Inject
    IamClient iam;

    @POST
    @Path("/simular")
    public Uni<Map<String, String>> simular(@QueryParam("rol") String rol, @QueryParam("recurso") String recurso, List<String> acciones) {
        return Uni.createFrom().item(() -> new SimuladorIam(iam).probar(rol, acciones, recurso))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```
> Permisos del probador: `iam:SimulatePrincipalPolicy` (lectura). Es una **herramienta interna** de plataforma, no un endpoint público.

## 3. Cómo se usa en la práctica
- **Linter en el pipeline:** antes de aplicar un cambio de IAM, se convierte el JSON de la política en `Map` y se llama a `revisar`; si aparece un hallazgo `CRITICA`, el cambio falla.
- **Pruebas de regresión de permisos:** una lista de pares *(rol, acción, recurso, decisión esperada)* corrida con el simulador tras cada cambio.
- **En la propia aplicación:** nada de IAM; la app solo usa sus credenciales temporales.

## 4. Qué NO hacer desde Java
- No guardar claves de acceso en `application.properties` ni en variables de entorno de larga vida.
- No dar a la aplicación `iam:*` «para crear sus roles»: eso lo hace Terraform.
- No mezclar el linter con decisiones automáticas de borrado: informa; las personas deciden.
