# Oracle OCI · IAM · Grupos dinámicos y principales · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Tres piezas: un **analizador de reglas** (`ALL`/`ANY`, con prueba de pertenencia sin red), un **validador** que avisa de reglas peligrosas y un **auditor** que lee los grupos reales con el SDK. La autenticación de la propia aplicación (sección 2.1) es el uso de los principales.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance   # config | instance | oke | resource
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

### 2.2 Regla de coincidencia
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Regla de coincidencia de un grupo dinámico: ALL { a = 'x', b != 'y' } o ANY { ... }. */
public final class ReglaDinamica {

    public record Condicion(String atributo, boolean igual, String valor) { }

    private final boolean todas;
    private final List<Condicion> condiciones;

    private ReglaDinamica(boolean todas, List<Condicion> condiciones) {
        this.todas = todas;
        this.condiciones = condiciones;
    }

    public static ReglaDinamica analizar(String texto) {
        String t = texto.strip();
        boolean todas;
        if (t.regionMatches(true, 0, "ALL", 0, 3)) {
            todas = true;
        } else if (t.regionMatches(true, 0, "ANY", 0, 3)) {
            todas = false;
        } else {
            throw new IllegalArgumentException("la regla debe empezar con ALL o ANY");
        }
        int abre = t.indexOf('{');
        int cierra = t.lastIndexOf('}');
        if (abre < 0 || cierra < abre) {
            throw new IllegalArgumentException("faltan las llaves { }");
        }
        var lista = new ArrayList<Condicion>();
        for (String trozo : separar(t.substring(abre + 1, cierra))) {
            lista.add(condicion(trozo.strip()));
        }
        if (lista.isEmpty()) {
            throw new IllegalArgumentException("la regla no tiene condiciones");
        }
        return new ReglaDinamica(todas, List.copyOf(lista));
    }

    /** Separa por comas que no estén dentro de comillas simples. */
    private static List<String> separar(String cuerpo) {
        var trozos = new ArrayList<String>();
        var actual = new StringBuilder();
        boolean dentro = false;
        for (char c : cuerpo.toCharArray()) {
            if (c == '\'') {
                dentro = !dentro;
            }
            if (c == ',' && !dentro) {
                trozos.add(actual.toString());
                actual.setLength(0);
            } else {
                actual.append(c);
            }
        }
        if (!actual.toString().isBlank()) {
            trozos.add(actual.toString());
        }
        return trozos;
    }

    private static Condicion condicion(String c) {
        boolean igual = !c.contains("!=");
        String[] partes = c.split(igual ? "=" : "!=", 2);
        if (partes.length != 2) {
            throw new IllegalArgumentException("condición inválida: " + c);
        }
        String valor = partes[1].strip();
        if (valor.length() < 2 || !valor.startsWith("'") || !valor.endsWith("'")) {
            throw new IllegalArgumentException("el valor debe ir entre comillas simples: " + c);
        }
        return new Condicion(partes[0].strip(), igual, valor.substring(1, valor.length() - 1));
    }

    public List<Condicion> condiciones() {
        return condiciones;
    }

    public boolean esTodas() {
        return todas;
    }

    /** ¿Un recurso con estos atributos pertenece al grupo? */
    public boolean coincide(Map<String, String> atributos) {
        for (Condicion c : condiciones) {
            boolean cumple = c.igual() == c.valor().equals(atributos.get(c.atributo()));
            if (todas && !cumple) {
                return false;
            }
            if (!todas && cumple) {
                return true;
            }
        }
        return todas;
    }
}
```

### 2.3 Validador de reglas
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

/** Reglas de seguridad para reglas de grupos dinámicos. */
public final class ValidadorDeReglas {

    public List<String> advertencias(ReglaDinamica regla) {
        var salida = new ArrayList<String>();
        boolean acotaCompartimento = regla.condiciones().stream()
            .anyMatch(c -> c.igual() && (c.atributo().endsWith("compartment.id")));
        boolean soloNegaciones = regla.condiciones().stream().allMatch(c -> !c.igual());
        if (!regla.esTodas()) {
            salida.add("ANY: cada condición ensancha el grupo; ¿de verdad necesitas «o»?");
        }
        if (!acotaCompartimento) {
            salida.add("no acota por compartimento: puede incluir recursos de otros equipos");
        }
        if (soloNegaciones) {
            salida.add("solo tiene negaciones: incluye todo lo demás");
        }
        boolean usaEtiquetas = regla.condiciones().stream().anyMatch(c -> c.atributo().startsWith("tag."));
        if (usaEtiquetas) {
            salida.add("depende de etiquetas: restringe quién puede etiquetar recursos");
        }
        return salida;
    }
}
```

### 2.4 Lectura con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.DynamicGroup;
import com.oracle.bmc.identity.requests.ListDynamicGroupsRequest;
import java.util.LinkedHashMap;
import java.util.Map;

/** Lee los grupos dinámicos del tenancy con paginación del SDK. */
public class GruposDinamicosOci {

    private final IdentityClient cliente;

    public GruposDinamicosOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public Map<String, String> reglasPorGrupo(String tenancyId) {
        var req = ListDynamicGroupsRequest.builder().compartmentId(tenancyId).build();
        var salida = new LinkedHashMap<String, String>();
        for (DynamicGroup g : cliente.getPaginators().listDynamicGroupsRecordIterator(req)) {
            salida.put(g.getName(), g.getMatchingRule());
        }
        return salida;
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class ServicioDeGrupos {

    private final GruposDinamicosOci grupos;
    private final ValidadorDeReglas validador = new ValidadorDeReglas();

    public ServicioDeGrupos(GruposDinamicosOci grupos) {
        this.grupos = grupos;
    }

    public record Revision(String grupo, List<String> advertencias) { }

    public List<Revision> auditar(String tenancyId) {
        var salida = new ArrayList<Revision>();
        for (Map.Entry<String, String> e : grupos.reglasPorGrupo(tenancyId).entrySet()) {
            try {
                var adv = validador.advertencias(ReglaDinamica.analizar(e.getValue()));
                if (!adv.isEmpty()) {
                    salida.add(new Revision(e.getKey(), adv));
                }
            } catch (IllegalArgumentException ex) {
                salida.add(new Revision(e.getKey(), List.of("regla ilegible: " + ex.getMessage())));
            }
        }
        return salida;
    }

    public List<String> revisarRegla(String regla) {
        return validador.advertencias(ReglaDinamica.analizar(regla));
    }

    public boolean pertenece(String regla, Map<String, String> atributos) {
        return ReglaDinamica.analizar(regla).coincide(atributos);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class GruposConfiguracion {

    @Bean(destroyMethod = "close")
    IdentityClient identidadCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDeGrupos servicioDeGrupos(IdentityClient cliente) {
        return new ServicioDeGrupos(new GruposDinamicosOci(cliente));
    }
}

@RestController
@RequestMapping("/iam/grupos-dinamicos")
class GruposControlador {

    private final ServicioDeGrupos s;

    GruposControlador(ServicioDeGrupos s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    List<ServicioDeGrupos.Revision> auditoria(@RequestParam String tenancy) {
        return s.auditar(tenancy);
    }

    @GetMapping("/revisar")
    List<String> revisar(@RequestParam String regla) {
        return s.revisarRegla(regla);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/iam/grupos-dinamicos")
class GruposReactivoControlador {

    private final ServicioDeGrupos s;

    GruposReactivoControlador(ServicioDeGrupos s) {
        this.s = s;
    }

    @GetMapping("/auditoria")
    Mono<List<ServicioDeGrupos.Revision>> auditoria(@RequestParam String tenancy) {
        return Mono.fromCallable(() -> s.auditar(tenancy)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/revisar")
    Mono<List<String>> revisar(@RequestParam String regla) {
        return Mono.fromCallable(() -> s.revisarRegla(regla));
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class GruposProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeGrupos servicioDeGrupos() {
        var cliente = IdentityClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDeGrupos(new GruposDinamicosOci(cliente));
    }
}

@Path("/iam/grupos-dinamicos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class GruposRecurso {

    @Inject
    ServicioDeGrupos s;

    @GET
    @Path("/auditoria")
    public List<ServicioDeGrupos.Revision> auditoria(@QueryParam("tenancy") String tenancy) {
        return s.auditar(tenancy);
    }

    @GET
    @Path("/revisar")
    public List<String> revisar(@QueryParam("regla") String regla) {
        return s.revisarRegla(regla);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.identity.IdentityClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;
import java.util.Map;

@Path("/reactivo/iam/grupos-dinamicos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class GruposRecursoReactivo {

    @Inject
    ServicioDeGrupos s;

    @GET
    @Path("/auditoria")
    public Uni<List<ServicioDeGrupos.Revision>> auditoria(@QueryParam("tenancy") String tenancy) {
        return Uni.createFrom().item(() -> s.auditar(tenancy)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/revisar")
    public Uni<List<String>> revisar(@QueryParam("regla") String regla) {
        return Uni.createFrom().item(() -> s.revisarRegla(regla));
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `ListDynamicGroups` | `Allow dynamic-group auditor-iam to inspect dynamic-groups in tenancy` |
| Analizar y validar reglas | Ninguna: es lógica pura |

## 8. Qué NO hacer desde Java
- No uses `config` (archivo de usuario) en servidores: usa `instance`, `resource` u `oke`.
- No trates «pertenece» como prueba de permisos: además hace falta una política.
- No pongas OCID ni etiquetas de clientes en registros.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
