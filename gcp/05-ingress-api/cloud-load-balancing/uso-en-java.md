# Google Cloud · Ingress y API · Cloud Load Balancing · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.

Un **simulador del URL map** para pruebas de enrutamiento en el pipeline: lee el URL map real con `UrlMapsClient.get`, lo convierte a un modelo simple (reglas de host, path matchers, reglas de ruta) y resuelve host + ruta al servicio de backend (exacta antes que prefijo, prefijo más largo gana). Complementa a `gcloud compute url-maps validate` y a los `test` del propio URL map.

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

### 2.2 Simulador (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Optional;

/** Simula el URL map: host → path matcher → regla de ruta más específica → servicio. Puro. */
public class SimuladorDeUrlMap {

    public record ReglaHost(List<String> hosts, String matcher) { }

    public record ReglaRuta(List<String> rutas, String servicio) { }

    public record Matcher(String nombre, String servicioPorDefecto, List<ReglaRuta> reglas) { }

    public record Mapa(String servicioPorDefecto, List<ReglaHost> hosts, List<Matcher> matchers) { }

    public record Prueba(String host, String ruta, String servicioEsperado) { }

    public record ResultadoPrueba(Prueba prueba, String obtenido, boolean ok) { }

    public String resolver(Mapa m, String host, String ruta) {
        Optional<String> matcher = m.hosts().stream()
            .filter(h -> h.hosts().stream().anyMatch(x -> coincideHost(x, host)))
            .map(ReglaHost::matcher).findFirst();
        if (matcher.isEmpty()) {
            return m.servicioPorDefecto();
        }
        Matcher pm = m.matchers().stream().filter(x -> x.nombre().equals(matcher.get())).findFirst().orElseThrow();
        String mejor = null;
        int largo = -1;
        for (ReglaRuta r : pm.reglas()) {
            for (String p : r.rutas()) {
                int l = coincideRuta(p, ruta);
                if (l > largo) {
                    largo = l;
                    mejor = r.servicio();
                }
            }
        }
        return mejor != null ? mejor : pm.servicioPorDefecto();
    }

    public List<ResultadoPrueba> probar(Mapa m, List<Prueba> pruebas) {
        return pruebas.stream().map(p -> {
            String s = resolver(m, p.host(), p.ruta());
            return new ResultadoPrueba(p, s, s.endsWith(p.servicioEsperado()));
        }).toList();
    }

    static boolean coincideHost(String patron, String host) {
        return patron.equals("*") || patron.equals(host) || (patron.startsWith("*.") && host.endsWith(patron.substring(1)));
    }

    /** Devuelve la longitud de coincidencia (o -1). «/api/*» coincide con «/api/...»; sin «*», exacta. */
    static int coincideRuta(String patron, String ruta) {
        if (patron.endsWith("/*")) {
            String base = patron.substring(0, patron.length() - 1);
            return ruta.startsWith(base) || ruta.equals(base.substring(0, base.length() - 1)) ? base.length() : -1;
        }
        return patron.equals(ruta) ? patron.length() + 1000 : -1; // exacta gana a prefijo
    }
}
```

### 2.3 Adaptador de la biblioteca
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.UrlMapsClient;
import com.google.cloud.compute.v1.UrlMapsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador: convierte el URL map real (global) al modelo del simulador. */
public class UrlMapsGcp implements AutoCloseable {

    private final UrlMapsClient cliente;
    private final String proyecto;

    public UrlMapsGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = UrlMapsClient.create(UrlMapsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public SimuladorDeUrlMap.Mapa leer(String nombre) {
        var u = cliente.get(proyecto, nombre);
        var hosts = u.getHostRulesList().stream()
            .map(h -> new SimuladorDeUrlMap.ReglaHost(List.copyOf(h.getHostsList()), h.getPathMatcher())).toList();
        var matchers = u.getPathMatchersList().stream().map(pm -> new SimuladorDeUrlMap.Matcher(pm.getName(), pm.getDefaultService(),
            pm.getPathRulesList().stream().map(r -> new SimuladorDeUrlMap.ReglaRuta(List.copyOf(r.getPathsList()), r.getService())).toList()))
            .toList();
        return new SimuladorDeUrlMap.Mapa(u.getDefaultService(), hosts, matchers);
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
import java.util.List;

public class ServicioDeRutas {

    private final UrlMapsGcp urlMaps;
    private final SimuladorDeUrlMap simulador = new SimuladorDeUrlMap();

    public ServicioDeRutas(UrlMapsGcp urlMaps) {
        this.urlMaps = urlMaps;
    }

    /** Pruebas de enrutamiento para el pipeline: fallan si una ruta crítica cambia de destino. */
    public List<SimuladorDeUrlMap.ResultadoPrueba> probar(String urlMap, List<SimuladorDeUrlMap.Prueba> pruebas) {
        return simulador.probar(urlMaps.leer(urlMap), pruebas);
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
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class RutasConfiguracion {

    @Bean(destroyMethod = "close")
    UrlMapsGcp adaptador(@Value("${gcp.proyecto}") String proyecto, @Value("${gcp.suplantar}") String suplantar) {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new UrlMapsGcp(cred, proyecto);
    }

    @Bean
    ServicioDeRutas servicio(UrlMapsGcp a) {
        return new ServicioDeRutas(a);
    }
}

@RestController
@RequestMapping("/ingress/rutas")
class RutasControlador {

    private final ServicioDeRutas s;

    RutasControlador(ServicioDeRutas s) {
        this.s = s;
    }

    @PostMapping("/{urlMap}/pruebas")
    List<SimuladorDeUrlMap.ResultadoPrueba> probar(@PathVariable String urlMap, @RequestBody List<SimuladorDeUrlMap.Prueba> pruebas) {
        return s.probar(urlMap, pruebas);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.google.auth.oauth2.GoogleCredentials;
import java.util.List;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/ingress/rutas")
class RutasReactivoControlador {

    private final ServicioDeRutas s;

    RutasReactivoControlador(ServicioDeRutas s) {
        this.s = s;
    }

    @PostMapping("/{urlMap}/pruebas")
    Mono<List<SimuladorDeUrlMap.ResultadoPrueba>> probar(@PathVariable String urlMap, @RequestBody List<SimuladorDeUrlMap.Prueba> pruebas) {
        return Mono.fromCallable(() -> s.probar(urlMap, pruebas)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class RutasProductores {

    @ConfigProperty(name = "gcp.proyecto")
    String proyecto;

    @ConfigProperty(name = "gcp.suplantar")
    String suplantar;

    @jakarta.enterprise.inject.Produces
    @Singleton
    UrlMapsGcp adaptador() {
        GoogleCredentials cred = Credenciales.crear(suplantar);
        return new UrlMapsGcp(cred, proyecto);
    }

    void cerrar(@Disposes UrlMapsGcp a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeRutas servicio(UrlMapsGcp a) {
        return new ServicioDeRutas(a);
    }
}

@Path("/ingress/rutas")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class RutasRecurso {

    @Inject
    ServicioDeRutas s;

    @POST
    @Path("/{urlMap}/pruebas")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<SimuladorDeUrlMap.ResultadoPrueba> probar(@PathParam("urlMap") String urlMap, List<SimuladorDeUrlMap.Prueba> pruebas) {
        return s.probar(urlMap, pruebas);
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
import jakarta.ws.rs.PathParam;
import java.util.List;

@Path("/reactivo/ingress/rutas")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class RutasRecursoReactivo {

    @Inject
    ServicioDeRutas s;

    @POST
    @Path("/{urlMap}/pruebas")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<SimuladorDeUrlMap.ResultadoPrueba>> probar(@PathParam("urlMap") String urlMap, List<SimuladorDeUrlMap.Prueba> pruebas) {
        return Uni.createFrom().item(() -> s.probar(urlMap, pruebas)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Rol de IAM (mínimo) |
|---|---|
| Leer URL maps | `roles/compute.loadBalancerAdmin` o `roles/compute.viewer` |

## 8. Qué NO hacer desde Java
- No reemplaces la validación oficial: el simulador no cubre `routeRules` avanzadas (cabeceras, pesos).
- No modifiques el URL map desde la app.
- No olvides probar el host por defecto y rutas sin barra final.
