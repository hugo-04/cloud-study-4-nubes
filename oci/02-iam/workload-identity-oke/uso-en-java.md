# Oracle OCI · IAM · Workload Identity en OKE · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Tres piezas: un **selector de modo de autenticación** (pod, función, VM o laptop), un **generador de la frase de política** del pod (valida cada nombre antes de interpolar) y una **prueba de identidad** con Object Storage que confirma que el proveedor `oke` y la red funcionan.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: oke          # en el Deployment: variable OCI_AUTH
  region: sa-saopaulo-1
```
```properties
# Quarkus (application.properties)
oci.auth=oke
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

### 2.2 Selector de modo
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;

/** Decide qué modo de autenticación usar. Puro: recibe el entorno como mapa. */
public final class SelectorDeAutenticacion {

    /** Orden: configuración explícita > función > pod > VM > archivo local. */
    public String elegir(Map<String, String> entorno, boolean metadatosAlcanzables) {
        String explicito = entorno.get("OCI_AUTH");
        if (explicito != null && !explicito.isBlank()) {
            return explicito;
        }
        if (entorno.containsKey("OCI_RESOURCE_PRINCIPAL_VERSION")) {
            return "resource";
        }
        if (entorno.containsKey("KUBERNETES_SERVICE_HOST")) {
            return "oke";
        }
        return metadatosAlcanzables ? "instance" : "config";
    }
}
```

### 2.3 Generador de la política
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.regex.Pattern;

/** Construye la frase de política para un pod. Valida los nombres antes de interpolar. */
public final class GeneradorDePolitica {

    private static final Pattern NOMBRE_K8S = Pattern.compile("[a-z0-9]([-a-z0-9]*[a-z0-9])?");
    private static final Pattern OCID_CLUSTER = Pattern.compile("ocid1\\.cluster\\.[a-z0-9]+\\.[a-z0-9-]*\\.[a-z0-9]+");
    private static final Pattern NOMBRE_BUCKET = Pattern.compile("[A-Za-z0-9._-]{1,256}");
    private static final Pattern NOMBRE_COMPARTIMENTO = Pattern.compile("[A-Za-z0-9._:-]{1,100}");

    public String lecturaDeBucket(String compartimento, String clusterId, String namespace, String cuenta, String bucket) {
        exigir(NOMBRE_COMPARTIMENTO, compartimento, "compartimento");
        exigir(OCID_CLUSTER, clusterId, "clúster");
        exigir(NOMBRE_K8S, namespace, "namespace");
        exigir(NOMBRE_K8S, cuenta, "cuenta de servicio");
        exigir(NOMBRE_BUCKET, bucket, "bucket");
        if (cuenta.equals("default")) {
            throw new IllegalArgumentException("no des permisos al ServiceAccount default");
        }
        return "Allow any-user to read objects in compartment " + compartimento
            + " where all {request.principal.type = 'workload'"
            + ", request.principal.cluster_id = '" + clusterId + "'"
            + ", request.principal.namespace = '" + namespace + "'"
            + ", request.principal.service_account = '" + cuenta + "'"
            + ", target.bucket.name = '" + bucket + "'}";
    }

    private static void exigir(Pattern patron, String valor, String que) {
        if (valor == null || !patron.matcher(valor).matches()) {
            throw new IllegalArgumentException(que + " con formato inválido");
        }
    }
}
```

### 2.4 Prueba de identidad con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;

/** Prueba de identidad: si puedo pedir el namespace de Object Storage, el proveedor y la red funcionan. */
public class PruebaDeIdentidad implements AutoCloseable {

    private final ObjectStorageClient cliente;

    public PruebaDeIdentidad(BasicAuthenticationDetailsProvider auth, String region) {
        this.cliente = ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth);
    }

    public String namespaceVisible() {
        return cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
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
import java.util.Map;

public class ServicioDeIdentidad {

    public record Estado(String modo, boolean funciona, String detalle) { }

    private final SelectorDeAutenticacion selector = new SelectorDeAutenticacion();
    private final GeneradorDePolitica politicas = new GeneradorDePolitica();
    private final PruebaDeIdentidad prueba;
    private final Map<String, String> entorno;

    public ServicioDeIdentidad(PruebaDeIdentidad prueba, Map<String, String> entorno) {
        this.prueba = prueba;
        this.entorno = entorno;
    }

    public Estado estado() {
        String modo = selector.elegir(entorno, false);
        try {
            prueba.namespaceVisible();
            return new Estado(modo, true, "el proveedor obtuvo credenciales y llegó al servicio");
        } catch (RuntimeException e) {
            return new Estado(modo, false, e.getClass().getSimpleName());
        }
    }

    public String politica(String compartimento, String clusterId, String namespace, String cuenta, String bucket) {
        return politicas.lecturaDeBucket(compartimento, clusterId, namespace, cuenta, bucket);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class IdentidadConfiguracion {

    @Bean(destroyMethod = "close")
    PruebaDeIdentidad pruebaDeIdentidad(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new PruebaDeIdentidad(auth, region);
    }

    @Bean
    ServicioDeIdentidad servicioDeIdentidad(PruebaDeIdentidad prueba) {
        return new ServicioDeIdentidad(prueba, System.getenv());
    }
}

@RestController
@RequestMapping("/iam/identidad")
class IdentidadControlador {

    private final ServicioDeIdentidad s;

    IdentidadControlador(ServicioDeIdentidad s) {
        this.s = s;
    }

    @GetMapping("/estado")
    ServicioDeIdentidad.Estado estado() {
        return s.estado();
    }

    @GetMapping("/politica")
    String politica(@RequestParam String compartimento, @RequestParam String cluster, @RequestParam String namespace, @RequestParam String cuenta, @RequestParam String bucket) {
        return s.politica(compartimento, cluster, namespace, cuenta, bucket);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/iam/identidad")
class IdentidadReactivoControlador {

    private final ServicioDeIdentidad s;

    IdentidadReactivoControlador(ServicioDeIdentidad s) {
        this.s = s;
    }

    @GetMapping("/estado")
    Mono<ServicioDeIdentidad.Estado> estado() {
        return Mono.fromCallable(() -> s.estado()).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/politica")
    Mono<String> politica(@RequestParam String compartimento, @RequestParam String cluster, @RequestParam String namespace, @RequestParam String cuenta, @RequestParam String bucket) {
        return Mono.fromCallable(() -> s.politica(compartimento, cluster, namespace, cuenta, bucket));
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
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class IdentidadProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    PruebaDeIdentidad pruebaDeIdentidad() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new PruebaDeIdentidad(auth, region);
    }

    void cerrar(@Disposes PruebaDeIdentidad p) {
        p.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeIdentidad servicioDeIdentidad(PruebaDeIdentidad prueba) {
        return new ServicioDeIdentidad(prueba, System.getenv());
    }
}

@Path("/iam/identidad")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class IdentidadRecurso {

    @Inject
    ServicioDeIdentidad s;

    @GET
    @Path("/estado")
    public ServicioDeIdentidad.Estado estado() {
        return s.estado();
    }

    @GET
    @Path("/politica")
    public String politica(@QueryParam("compartimento") String compartimento, @QueryParam("cluster") String cluster, @QueryParam("namespace") String namespace, @QueryParam("cuenta") String cuenta, @QueryParam("bucket") String bucket) {
        return s.politica(compartimento, cluster, namespace, cuenta, bucket);
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
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/iam/identidad")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class IdentidadRecursoReactivo {

    @Inject
    ServicioDeIdentidad s;

    @GET
    @Path("/estado")
    public Uni<ServicioDeIdentidad.Estado> estado() {
        return Uni.createFrom().item(() -> s.estado()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/politica")
    public Uni<String> politica(@QueryParam("compartimento") String compartimento, @QueryParam("cluster") String cluster, @QueryParam("namespace") String namespace, @QueryParam("cuenta") String cuenta, @QueryParam("bucket") String bucket) {
        return Uni.createFrom().item(() -> s.politica(compartimento, cluster, namespace, cuenta, bucket));
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `GetNamespace` de Object Storage | Cualquier política del pod sobre Object Storage; si falla con 404, aún no hay permiso suficiente |
| Generar la frase | Ninguna: es lógica pura; la frase se aplica por Terraform |

## 8. Qué NO hacer desde Java
- No hagas público el endpoint `/estado` ni `/politica`: revelan configuración de seguridad.
- No construyas frases de política concatenando texto de usuarios sin validar (el generador valida con patrones).
- No uses el ServiceAccount `default` ni guardes llaves en Secrets de Kubernetes.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
