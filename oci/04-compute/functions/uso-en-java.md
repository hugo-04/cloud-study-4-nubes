# Oracle OCI · Compute · Functions · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Dos lados de una función: **el cuerpo** (un manejador Java puro que la FDK invoca, declarado en `func.yaml`) y **el cliente** que la llama con `FunctionsInvokeClient`, con reintentos de espera exponencial y *jitter* solo ante fallas transitorias.

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

### 2.2 El cuerpo de la función
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Locale;

/** El cuerpo de la función (se declara en func.yaml: com.modalima.NormalizadorDePedido::handleRequest). */
public class NormalizadorDePedido {

    /** Entrada: «idPedido|monto|moneda». Salida: «ID|monto con 2 decimales|MONEDA». */
    public String handleRequest(String entrada) {
        if (entrada == null || entrada.length() > 200) {
            throw new IllegalArgumentException("entrada vacía o demasiado grande");
        }
        String[] p = entrada.strip().split("\\|");
        if (p.length != 3) {
            throw new IllegalArgumentException("formato esperado: idPedido|monto|moneda");
        }
        BigDecimal monto = new BigDecimal(p[1].strip()).setScale(2, RoundingMode.HALF_UP);
        if (monto.signum() <= 0) {
            throw new IllegalArgumentException("el monto debe ser positivo");
        }
        return p[0].strip().toUpperCase(Locale.ROOT) + "|" + monto.toPlainString() + "|" + p[2].strip().toUpperCase(Locale.ROOT);
    }
}
```

### 2.3 Reintentos con jitter
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.function.DoubleSupplier;
import java.util.function.Supplier;

/** Reintentos con espera exponencial y «full jitter». Puro: el sueño y el azar se inyectan. */
public class Reintentador {

    /** Falla que vale la pena reintentar (429, 502, 503, 504, cortes de red). */
    public static class FallaTransitoria extends RuntimeException {
        public FallaTransitoria(String mensaje, Throwable causa) {
            super(mensaje, causa);
        }
    }

    public interface Durmiente {
        void dormir(Duration d);
    }

    private final int maxIntentos;
    private final Duration base;
    private final Duration tope;
    private final DoubleSupplier azar;
    private final Durmiente durmiente;

    public Reintentador(int maxIntentos, Duration base, Duration tope, DoubleSupplier azar, Durmiente durmiente) {
        this.maxIntentos = maxIntentos;
        this.base = base;
        this.tope = tope;
        this.azar = azar;
        this.durmiente = durmiente;
    }

    public Duration espera(int intento) {
        long techo = Math.min(tope.toMillis(), base.toMillis() * (1L << Math.min(intento, 20)));
        return Duration.ofMillis((long) (azar.getAsDouble() * techo));
    }

    public <T> T ejecutar(Supplier<T> operacion) {
        for (int intento = 0; ; intento++) {
            try {
                return operacion.get();
            } catch (FallaTransitoria e) {
                if (intento + 1 >= maxIntentos) {
                    throw e;
                }
                durmiente.dormir(espera(intento));
            }
        }
    }
}
```

### 2.4 Invocación con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.functions.FunctionsInvokeClient;
import com.oracle.bmc.functions.FunctionsManagementClient;
import com.oracle.bmc.functions.requests.GetFunctionRequest;
import com.oracle.bmc.functions.requests.InvokeFunctionRequest;
import com.oracle.bmc.model.BmcException;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Invoca funciones: cada función tiene su propio endpoint de invocación. */
public class FuncionesOci implements AutoCloseable {

    private static final Set<Integer> TRANSITORIOS = Set.of(429, 502, 503, 504);

    private final BasicAuthenticationDetailsProvider auth;
    private final FunctionsManagementClient gestion;
    private final Map<String, FunctionsInvokeClient> invocadores = new ConcurrentHashMap<>();

    public FuncionesOci(BasicAuthenticationDetailsProvider auth, FunctionsManagementClient gestion) {
        this.auth = auth;
        this.gestion = gestion;
    }

    public String invocar(String functionId, String cuerpo) {
        var cliente = invocadores.computeIfAbsent(functionId, id -> {
            String endpoint = gestion.getFunction(GetFunctionRequest.builder().functionId(id).build()).getFunction().getInvokeEndpoint();
            return FunctionsInvokeClient.builder().endpoint(endpoint).build(auth);
        });
        var req = InvokeFunctionRequest.builder()
            .functionId(functionId)
            .fnInvokeType(InvokeFunctionRequest.FnInvokeType.Sync)
            .invokeFunctionBody(new ByteArrayInputStream(cuerpo.getBytes(StandardCharsets.UTF_8)))
            .build();
        try (var in = cliente.invokeFunction(req).getInputStream()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (BmcException e) {
            if (TRANSITORIOS.contains(e.getStatusCode())) {
                throw new Reintentador.FallaTransitoria("función no disponible (" + e.getStatusCode() + ")", e);
            }
            throw e;
        } catch (IOException e) {
            throw new Reintentador.FallaTransitoria("corte al leer la respuesta", e);
        }
    }

    @Override
    public void close() {
        invocadores.values().forEach(FunctionsInvokeClient::close);
        gestion.close();
    }
}
```

### 2.5 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.concurrent.ThreadLocalRandom;

public class ServicioDeFunciones {

    private final FuncionesOci funciones;
    private final Reintentador reintentos;

    public ServicioDeFunciones(FuncionesOci funciones) {
        this.funciones = funciones;
        this.reintentos = new Reintentador(4, Duration.ofMillis(200), Duration.ofSeconds(3),
            () -> ThreadLocalRandom.current().nextDouble(), d -> {
                try {
                    Thread.sleep(d.toMillis());
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException("interrumpido", e);
                }
            });
    }

    public record Solicitud(String functionId, String cuerpo) { }

    public String normalizar(Solicitud s) {
        return reintentos.ejecutar(() -> funciones.invocar(s.functionId(), s.cuerpo()));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.functions.FunctionsManagementClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class FuncionesConfiguracion {

    @Bean(destroyMethod = "close")
    FuncionesOci funcionesOci(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        var gestion = FunctionsManagementClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new FuncionesOci(auth, gestion);
    }

    @Bean
    ServicioDeFunciones servicioDeFunciones(FuncionesOci funciones) {
        return new ServicioDeFunciones(funciones);
    }
}

@RestController
@RequestMapping("/compute/funciones")
class FuncionesControlador {

    private final ServicioDeFunciones s;

    FuncionesControlador(ServicioDeFunciones s) {
        this.s = s;
    }

    @PostMapping("/normalizar")
    String normalizar(@RequestBody ServicioDeFunciones.Solicitud s2) {
        return s.normalizar(s2);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.functions.FunctionsManagementClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/compute/funciones")
class FuncionesReactivoControlador {

    private final ServicioDeFunciones s;

    FuncionesReactivoControlador(ServicioDeFunciones s) {
        this.s = s;
    }

    @PostMapping("/normalizar")
    Mono<String> normalizar(@RequestBody ServicioDeFunciones.Solicitud s2) {
        return Mono.fromCallable(() -> s.normalizar(s2)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.functions.FunctionsManagementClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class FuncionesProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    FuncionesOci funcionesOci() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        var gestion = FunctionsManagementClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new FuncionesOci(auth, gestion);
    }

    void cerrar(@Disposes FuncionesOci f) {
        f.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeFunciones servicioDeFunciones(FuncionesOci funciones) {
        return new ServicioDeFunciones(funciones);
    }
}

@Path("/compute/funciones")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class FuncionesRecurso {

    @Inject
    ServicioDeFunciones s;

    @POST
    @Path("/normalizar")
    @Consumes(MediaType.APPLICATION_JSON)
    public String normalizar(ServicioDeFunciones.Solicitud s2) {
        return s.normalizar(s2);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.functions.FunctionsManagementClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

@Path("/reactivo/compute/funciones")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class FuncionesRecursoReactivo {

    @Inject
    ServicioDeFunciones s;

    @POST
    @Path("/normalizar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<String> normalizar(ServicioDeFunciones.Solicitud s2) {
        return Uni.createFrom().item(() -> s.normalizar(s2)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Invocar una función | `Allow dynamic-group app-pedidos to use fn-invocation in compartment tienda-prod` |
| `GetFunction` (descubrir el endpoint) | `Allow dynamic-group app-pedidos to read fn-function in compartment tienda-prod` |
| Dentro de la función (resource principal) | `Allow dynamic-group funciones-tienda to read objects in compartment tienda-prod where target.bucket.name = 'comprobantes'` |

## 8. Qué NO hacer desde Java
- No reintentes errores definitivos (400, 404, 401): solo 429/502/503/504 y cortes de red.
- No reintentes funciones no idempotentes sin una clave de idempotencia en el cuerpo.
- No pongas secretos en la configuración de la función: léelos de Vault.
- No uses `Thread.sleep` en el bucle de eventos (en WebFlux/Mutiny el SDK ya corre en un hilo aparte).
- No registres el cuerpo completo de las solicitudes.
