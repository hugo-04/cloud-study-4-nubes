# AWS · Ingress en EKS · Uso desde Java

El Ingress lo crea el controlador, no tu código. Desde Java haces tres cosas útiles: **(1)** que la aplicación se apague sin 502 (cerrar conexiones y dejar de recibir tráfico a tiempo), **(2)** **vigilar quién publica a Internet** con un *webhook de admisión* escrito en Java que aplica las reglas de la guía, y **(3)** leer la IP real del cliente detrás del ALB (ver [ALB y NLB](../alb-nlb/uso-en-java.md), sección 2). Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40.

## 1. Configuración de apagado coordinado

La secuencia en Kubernetes: el pod pasa a `Terminating` → en paralelo se ejecuta el `preStop` **y** el controlador saca la IP del target group → pasado el `preStop` llega SIGTERM → la aplicación termina lo que tiene en curso → SIGKILL a los `terminationGracePeriodSeconds`.

```yaml
# Spring Boot (application.yml) — MVC y WebFlux
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
management:
  endpoint:
    health:
      probes:
        enabled: true            # /actuator/health/readiness y /liveness
```
```properties
# Quarkus (application.properties)
quarkus.shutdown.timeout=30S
quarkus.shutdown.delay=10S         # espera antes de dejar de aceptar (verifica el comportamiento en tu versión)
quarkus.smallrye-health.root-path=/q/health
```
```yaml
# Deployment (fragmento): números coherentes
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 60      # >= preStop + apagado de la app + margen
      containers:
        - name: pedidos
          lifecycle:
            preStop:
              sleep:
                seconds: 15                  # da tiempo al ALB a enterarse (no requiere binario sleep)
          readinessProbe:
            httpGet: { path: /actuator/health/readiness, port: 8080 }
            periodSeconds: 5
```
> Las cuentas de tiempos (ALB, keep-alive, deregistration) las valida `PlanDeTiempos` de [ALB y NLB](../alb-nlb/uso-en-java.md). Aquí solo añadimos lo propio de Kubernetes.

## 2. Núcleo común

### 2.1 Estado del tráfico: avisar a los clientes que cierren conexiones
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.concurrent.atomic.AtomicBoolean;

public final class EstadoTrafico {
    private final AtomicBoolean cerrando = new AtomicBoolean(false);

    public void iniciarCierre() {
        cerrando.set(true);
    }

    public boolean cerrando() {
        return cerrando.get();
    }

    /** Valor de la cabecera Connection que debe llevar cada respuesta, o null si no hay que tocarla. */
    public String cabeceraConnection() {
        return cerrando.get() ? "close" : null;
    }
}
```

### 2.2 Reglas de un Ingress (el mismo código sirve en CI y en el webhook)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class ReglasIngress {
    public record Hallazgo(String regla, boolean bloquea, String mensaje) {}

    private static final String P = "alb.ingress.kubernetes.io/";
    private final Set<String> namespacesPublicos;

    public ReglasIngress(Set<String> namespacesPublicos) {
        this.namespacesPublicos = Set.copyOf(namespacesPublicos);
    }

    private static boolean vacio(String s) {
        return s == null || s.isBlank();
    }

    /** Revisa las anotaciones de un Ingress. Solo evalúa los de clase "alb". */
    public List<Hallazgo> revisar(String namespace, String clase, Map<String, String> anotaciones) {
        List<Hallazgo> r = new ArrayList<>();
        if (!"alb".equals(clase)) {
            return r;
        }
        Map<String, String> a = anotaciones == null ? Map.of() : anotaciones;
        boolean publico = "internet-facing".equals(a.get(P + "scheme"));   // por defecto el scheme es internal

        if (publico && !namespacesPublicos.contains(namespace)) {
            r.add(new Hallazgo("PUBLICACION", true,
                    "scheme internet-facing no está permitido en el namespace '" + namespace + "'"));
        }
        if (!"ip".equals(a.get(P + "target-type"))) {
            r.add(new Hallazgo("TARGET_TYPE", true, "usa target-type: ip (por defecto sería instance)"));
        }
        String puertos = a.getOrDefault(P + "listen-ports", "");
        boolean conHttps = puertos.contains("HTTPS") || !vacio(a.get(P + "certificate-arn"));
        if (publico && !conHttps) {
            r.add(new Hallazgo("TLS", true, "un Ingress público necesita HTTPS (listen-ports o certificate-arn)"));
        }
        if (conHttps && puertos.contains("\"HTTP\"") && vacio(a.get(P + "ssl-redirect"))) {
            r.add(new Hallazgo("REDIRECCION", false, "escucha en HTTP y HTTPS sin ssl-redirect"));
        }
        String politicaTls = a.getOrDefault(P + "ssl-policy", "");
        if (politicaTls.contains("TLS-1-0") || politicaTls.contains("2016-08") || politicaTls.contains("2015")) {
            r.add(new Hallazgo("SSL_POLICY", true, "política TLS antigua: " + politicaTls));
        }
        if (vacio(a.get(P + "group.name"))) {
            r.add(new Hallazgo("AGRUPAR", false, "sin group.name: se creará un ALB propio (más costo)"));
        }
        String ruta = a.get(P + "healthcheck-path");
        if (vacio(ruta) || "/".equals(ruta)) {
            r.add(new Hallazgo("HEALTHCHECK", false, "usa una ruta de readiness, no '/'"));
        }
        if (publico && vacio(a.get(P + "wafv2-acl-arn"))) {
            r.add(new Hallazgo("WAF", false, "Ingress público sin WAF asociado"));
        }
        return r;
    }
}
```

### 2.3 Respuesta del webhook de admisión (`AdmissionReview` v1)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

public final class AdmisionIngress {
    private AdmisionIngress() {}

    @SuppressWarnings("unchecked")
    private static Map<String, Object> mapa(Object o) {
        return o instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    private static Map<String, String> anotaciones(Object o) {
        Map<String, String> r = new LinkedHashMap<>();
        mapa(o).forEach((k, v) -> r.put(k, String.valueOf(v)));
        return r;
    }

    /** Recibe el AdmissionReview ya convertido a Map y devuelve el AdmissionReview de respuesta. */
    public static Map<String, Object> responder(Map<String, Object> review, ReglasIngress reglas) {
        Map<String, Object> req = mapa(review == null ? null : review.get("request"));
        Map<String, Object> resp = new LinkedHashMap<>();
        if (req.isEmpty()) {                                        // petición mal formada: cerrar (fail-closed)
            resp.put("uid", "");
            resp.put("allowed", false);
            resp.put("status", Map.of("code", 400, "message", "AdmissionReview sin request"));
            return envolver(resp);
        }
        resp.put("uid", String.valueOf(req.getOrDefault("uid", "")));
        if ("DELETE".equals(req.get("operation"))) {                // borrar siempre se permite
            resp.put("allowed", true);
            return envolver(resp);
        }
        Map<String, Object> objeto = mapa(req.get("object"));
        Map<String, Object> meta = mapa(objeto.get("metadata"));
        Map<String, Object> spec = mapa(objeto.get("spec"));
        String ns = String.valueOf(req.getOrDefault("namespace", meta.getOrDefault("namespace", "")));
        Map<String, String> anot = anotaciones(meta.get("annotations"));
        String clase = spec.get("ingressClassName") instanceof String s ? s : anot.get("kubernetes.io/ingress.class");

        List<ReglasIngress.Hallazgo> hallazgos = reglas.revisar(ns, clase, anot);
        List<ReglasIngress.Hallazgo> bloqueos = hallazgos.stream().filter(ReglasIngress.Hallazgo::bloquea).toList();
        List<String> avisos = hallazgos.stream().filter(h -> !h.bloquea())
                .map(h -> h.regla() + ": " + h.mensaje()).toList();

        resp.put("allowed", bloqueos.isEmpty());
        if (!bloqueos.isEmpty()) {
            String msg = bloqueos.stream().map(h -> h.regla() + ": " + h.mensaje()).collect(Collectors.joining("; "));
            resp.put("status", Map.of("code", 403, "message", msg));
        }
        if (!avisos.isEmpty()) {
            resp.put("warnings", avisos);
        }
        return envolver(resp);
    }

    private static Map<String, Object> envolver(Map<String, Object> respuesta) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("apiVersion", "admission.k8s.io/v1");
        r.put("kind", "AdmissionReview");
        r.put("response", respuesta);
        return r;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.availability.AvailabilityChangeEvent;
import org.springframework.boot.availability.ReadinessState;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.filter.OncePerRequestFilter;

@Configuration
class IngressConfig {
    @Bean
    EstadoTrafico estadoTrafico() {
        return new EstadoTrafico();
    }

    @Bean
    ReglasIngress reglasIngress(@Value("${gobierno.namespaces-publicos:borde}") Set<String> publicos) {
        return new ReglasIngress(publicos);
    }
}

/** Spring marca la disponibilidad como REFUSING_TRAFFIC al empezar el apagado: lo traducimos a "Connection: close". */
@Component
class EscuchaReadiness {
    private final EstadoTrafico estado;

    EscuchaReadiness(EstadoTrafico estado) {
        this.estado = estado;
    }

    @EventListener
    void alCambiar(AvailabilityChangeEvent<ReadinessState> evento) {
        if (evento.getState() == ReadinessState.REFUSING_TRAFFIC) {
            estado.iniciarCierre();
        }
    }
}

@Component
class ConexionCerradaFilter extends OncePerRequestFilter {
    private final EstadoTrafico estado;

    ConexionCerradaFilter(EstadoTrafico estado) {
        this.estado = estado;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String valor = estado.cabeceraConnection();
        if (valor != null) {
            res.setHeader("Connection", valor);
        }
        chain.doFilter(req, res);
    }
}

@RestController
class AdmisionController {
    private final ReglasIngress reglas;

    AdmisionController(ReglasIngress reglas) {
        this.reglas = reglas;
    }

    /** El API server de Kubernetes llama aquí (HTTPS) antes de guardar cada Ingress. */
    @PostMapping("/validar-ingress")
    Map<String, Object> validar(@RequestBody Map<String, Object> review) {
        return AdmisionIngress.responder(review, reglas);
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.availability.AvailabilityChangeEvent;
import org.springframework.boot.availability.ReadinessState;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;
import java.util.Set;

@Configuration
class IngressReactivoConfig {
    @Bean
    EstadoTrafico estadoTrafico() {
        return new EstadoTrafico();
    }

    @Bean
    ReglasIngress reglasIngress(@Value("${gobierno.namespaces-publicos:borde}") Set<String> publicos) {
        return new ReglasIngress(publicos);
    }
}

@Component
class EscuchaReadinessReactiva {
    private final EstadoTrafico estado;

    EscuchaReadinessReactiva(EstadoTrafico estado) {
        this.estado = estado;
    }

    @EventListener
    void alCambiar(AvailabilityChangeEvent<ReadinessState> evento) {
        if (evento.getState() == ReadinessState.REFUSING_TRAFFIC) {
            estado.iniciarCierre();
        }
    }
}

@Component
class ConexionCerradaWebFilter implements WebFilter {
    private final EstadoTrafico estado;

    ConexionCerradaWebFilter(EstadoTrafico estado) {
        this.estado = estado;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String valor = estado.cabeceraConnection();
        if (valor != null) {
            exchange.getResponse().getHeaders().set("Connection", valor);
        }
        return chain.filter(exchange);
    }
}

@RestController
class AdmisionReactivaController {
    private final ReglasIngress reglas;

    AdmisionReactivaController(ReglasIngress reglas) {
        this.reglas = reglas;
    }

    /** Lógica pura y rápida: no necesita salir del hilo de eventos. */
    @PostMapping("/validar-ingress")
    Mono<Map<String, Object>> validar(@RequestBody Mono<Map<String, Object>> review) {
        return review.map(r -> AdmisionIngress.responder(r, reglas));
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.quarkus.runtime.ShutdownEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.util.Set;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class IngressProductores {
    @Produces
    @Singleton
    EstadoTrafico estadoTrafico() {
        return new EstadoTrafico();
    }

    @Produces
    @Singleton
    ReglasIngress reglasIngress(@ConfigProperty(name = "gobierno.namespaces-publicos", defaultValue = "borde")
                                Set<String> publicos) {
        return new ReglasIngress(publicos);
    }

    /** Al recibir SIGTERM Quarkus emite ShutdownEvent: desde ahí avisamos a los clientes con "Connection: close". */
    void alApagar(@Observes ShutdownEvent evento, EstadoTrafico estado) {
        estado.iniciarCierre();
    }
}
```
```java
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.ext.Provider;
import java.util.Map;

@Provider
class ConexionCerradaFiltro implements ContainerResponseFilter {
    private final EstadoTrafico estado;

    ConexionCerradaFiltro(EstadoTrafico estado) {
        this.estado = estado;
    }

    @Override
    public void filter(ContainerRequestContext req, ContainerResponseContext res) {
        String valor = estado.cabeceraConnection();
        if (valor != null) {
            res.getHeaders().putSingle("Connection", valor);
        }
    }
}

@Path("/validar-ingress")
class AdmisionRecurso {
    private final ReglasIngress reglas;

    AdmisionRecurso(ReglasIngress reglas) {
        this.reglas = reglas;
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, Object> validar(Map<String, Object> review) {
        return AdmisionIngress.responder(review, reglas);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;

@Path("/validar-ingress-reactivo")
class AdmisionReactivaRecurso {
    @Inject
    ReglasIngress reglas;

    /** Cálculo puro y corto: se devuelve en un Uni sin pasar a otro hilo. */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Map<String, Object>> validar(Map<String, Object> review) {
        return Uni.createFrom().item(() -> AdmisionIngress.responder(review, reglas));
    }
}
```

## 7. Cómo se conecta el webhook en el clúster
- El API server exige **HTTPS** hacia el webhook: genera el certificado con *cert-manager* o uno propio y pon su CA en `caBundle` ([`ejemplos/k8s/webhook.yaml`](ejemplos/k8s/webhook.yaml)).
- `failurePolicy: Fail` para publicar solo lo revisado; pero entonces el webhook **debe** ser de alta disponibilidad (2+ réplicas, PodDisruptionBudget) y excluir su propio *namespace* para no bloquearse a sí mismo.
- El mismo `ReglasIngress` puede ejecutarse en el *pipeline* sobre los YAML antes de aplicarlos: falla antes y más barato.

## 8. Qué NO hacer desde Java
- **No** despliegues un webhook con `failurePolicy: Fail` y una sola réplica: si cae, nadie puede crear ni cambiar Ingress.
- **No** confíes solo en el webhook: en `Ignore` o con el webhook caído se puede publicar; combina con RBAC y revisión en el repositorio.
- **No** hagas llamadas a la API de AWS dentro del webhook (latencia y timeouts de 10 s del API server); decide con los datos de la petición.
- **No** cierres la aplicación con SIGTERM sin `preStop`: el ALB aún enviará tráfico unos segundos.
- **No** pongas en el `AdmissionReview` datos de otros recursos sin validar: toda la entrada es no confiable.
