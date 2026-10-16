# Azure · Ingress en AKS · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40**. Verifica las vigentes.

El ingress es infraestructura: no se "programa" desde Java. Lo que **sí** haces en Java es **portarte bien detrás de él**: confiar en las cabeceras correctas, leer la IP real del cliente, apagarte sin cortar peticiones, mantener vivas las conexiones largas y no generar enlaces equivocados.

## 1. Confiar en las cabeceras del proxy

El controlador termina el TLS y reenvía por HTTP con `X-Forwarded-Proto`, `X-Forwarded-Host`, `X-Forwarded-For` y `X-Forwarded-Prefix`.

```properties
# Spring Boot (MVC o WebFlux)
server.port=8080
server.forward-headers-strategy=framework          # procesa X-Forwarded-* en la capa de Spring
# Alternativa para Tomcat embebido: server.forward-headers-strategy=native
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
management.endpoint.health.probes.enabled=true
management.endpoint.health.probes.add-additional-paths=true
```
```properties
# Quarkus
quarkus.http.port=8080
quarkus.http.host=0.0.0.0
quarkus.http.proxy.proxy-address-forwarding=true
quarkus.http.proxy.allow-x-forwarded=true
quarkus.http.proxy.enable-forwarded-host=true
quarkus.shutdown.timeout=30s
```

> **Seguridad:** solo confía en esas cabeceras si **todo** el tráfico pasa por tu proxy (NetworkPolicy + servicio no expuesto). Si la app es alcanzable directamente, cualquiera puede mandar `X-Forwarded-For: 1.2.3.4`.

### Comprobar que funciona
```java
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
class EcoController {

    @GetMapping("/debug/eco")
    Map<String, String> eco(HttpServletRequest req) {
        return Map.of(
                "esquema", req.getScheme(),            // debe ser https si el cliente usó https
                "host", req.getServerName(),
                "ipRemota", req.getRemoteAddr(),
                "xff", String.valueOf(req.getHeader("X-Forwarded-For")));
    }
}
```
Protege (o elimina) esta ruta en producción: revela cómo está tu red.

## 2. Generar enlaces correctos (`Location`, HATEOAS, redirecciones)

Con `forward-headers-strategy=framework`, `ServletUriComponentsBuilder` ya usa `https` y el host público:

```java
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.UUID;

@RestController
@RequestMapping("/pedidos")
class PedidosController {

    @PostMapping
    ResponseEntity<Void> crear() {
        UUID id = UUID.randomUUID();
        URI ubicacion = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(id)
                .toUri();                       // https://api.modalima.example/pedidos/<id>
        return ResponseEntity.created(ubicacion).build();
    }
}
```
Si el ingress **reescribe** la ruta (`/api/pedidos` → `/pedidos`), la app debe conocer el prefijo: el controlador debe enviar `X-Forwarded-Prefix` (Spring lo respeta con `framework`) o configurar `server.servlet.context-path`.

## 3. Leer la IP real del cliente (con confianza explícita)

Para límites por IP o auditoría. Solo se acepta `X-Forwarded-For` si la conexión **directa** viene de una dirección de confianza (el controlador).

```java
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
class IpCliente {

    // CIDR simplificado: prefijos de la subred de pods/ingress. En real, cárgalos de configuración.
    private final List<String> proxysDeConfianza = List.of("10.244.", "10.240.");

    String de(HttpServletRequest req) {
        String directa = req.getRemoteAddr();
        String xff = req.getHeader("X-Forwarded-For");
        if (xff == null || !esDeConfianza(directa)) {
            return directa;                       // nadie de confianza: ignora la cabecera
        }
        // X-Forwarded-For: cliente, proxy1, proxy2 → el cliente real es el primero
        // que NO es un proxy de confianza, leyendo de derecha a izquierda.
        String[] partes = xff.split(",");
        for (int i = partes.length - 1; i >= 0; i--) {
            String ip = partes[i].trim();
            if (!esDeConfianza(ip)) {
                return ip;
            }
        }
        return directa;
    }

    private boolean esDeConfianza(String ip) {
        return proxysDeConfianza.stream().anyMatch(ip::startsWith);
    }
}
```
Detrás de Application Gateway, la IP puede llegar con puerto (`1.2.3.4:51234`); límpiala antes de usarla ([Application Gateway](../application-gateway/README.md)).

## 4. Conexiones largas: SSE con *heartbeat*

El balanceador de Azure corta conexiones inactivas (~4 min) y NGINX lee 60 s por defecto. Manda un comentario de latido cada 20–30 s.

### Spring MVC (imperativo)
```java
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

@RestController
class NotificacionesController {

    private final Suscriptores suscriptores;

    NotificacionesController(Suscriptores suscriptores) {
        this.suscriptores = suscriptores;
    }

    @GetMapping("/notificaciones")
    SseEmitter suscribir() {
        SseEmitter emitter = new SseEmitter(0L);          // sin límite del lado de Spring
        suscriptores.agregar(emitter);
        return emitter;
    }
}

@Component
@EnableScheduling
class Suscriptores {

    private final List<SseEmitter> emisores = new CopyOnWriteArrayList<>();

    void agregar(SseEmitter e) {
        emisores.add(e);
        e.onCompletion(() -> emisores.remove(e));
        e.onTimeout(() -> emisores.remove(e));
        e.onError(x -> emisores.remove(e));
    }

    @Scheduled(fixedRate = 25_000)
    void latido() {
        for (SseEmitter e : emisores) {
            try {
                e.send(SseEmitter.event().comment("hb"));  // línea ":hb" que el cliente ignora
            } catch (IOException ex) {
                emisores.remove(e);
            }
        }
    }
}
```

### Spring WebFlux (reactivo)
```java
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

import java.time.Duration;

@RestController
class NotificacionesReactivas {

    private final Sinks.Many<String> eventos = Sinks.many().multicast().onBackpressureBuffer();

    @GetMapping(value = "/notificaciones-r", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    Flux<ServerSentEvent<String>> flujo() {
        Flux<ServerSentEvent<String>> datos = eventos.asFlux()
                .map(d -> ServerSentEvent.builder(d).build());
        Flux<ServerSentEvent<String>> latidos = Flux.interval(Duration.ofSeconds(25))
                .map(i -> ServerSentEvent.<String>builder().comment("hb").build());
        return Flux.merge(datos, latidos);
    }

    void publicar(String mensaje) {
        eventos.tryEmitNext(mensaje);
    }
}
```

### Quarkus (reactivo con Mutiny)
```java
import io.smallrye.mutiny.Multi;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.jboss.resteasy.reactive.RestStreamElementType;

import java.time.Duration;

@Path("/notificaciones")
public class NotificacionesResource {

    @GET
    @Produces(MediaType.SERVER_SENT_EVENTS)
    @RestStreamElementType(MediaType.TEXT_PLAIN)
    public Multi<String> flujo() {
        // En real: fusiona con tu fuente de eventos usando Multi.createBy().merging()
        return Multi.createFrom().ticks().every(Duration.ofSeconds(25))
                .map(t -> "latido");
    }
}
```

**Regla:** el latido debe ser **menor** que el menor tiempo de inactividad de cualquier salto (cliente → WAF → ingress → app).

## 5. Apagado ordenado detrás del ingress

Cuando Kubernetes retira un pod, hay una carrera: el pod recibe `SIGTERM`, pero el controlador tarda unos segundos en dejar de enviarle tráfico. Solución en dos capas:

1. En el YAML: `lifecycle.preStop: sleep 10` y `terminationGracePeriodSeconds: 45` ([AKS · YAML](../../04-compute/aks/ejemplos/yaml/)).
2. En Java: apagado graceful (arriba) para terminar las peticiones en vuelo.

```java
import org.springframework.boot.availability.AvailabilityChangeEvent;
import org.springframework.boot.availability.ReadinessState;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.ContextClosedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
class AlCerrar {

    private final ApplicationEventPublisher publisher;

    AlCerrar(ApplicationEventPublisher publisher) {
        this.publisher = publisher;
    }

    @EventListener(ContextClosedEvent.class)
    void marcarNoListo() {
        // Deja de estar "Ready" antes de que Tomcat deje de aceptar: el controlador saca el pod del reparto.
        AvailabilityChangeEvent.publish(publisher, this, ReadinessState.REFUSING_TRAFFIC);
    }
}
```
(Spring ya hace esto con `server.shutdown=graceful`; este ejemplo muestra el mecanismo para que lo reconozcas.)

## 6. Límites de tamaño coherentes con la entrada

Si subes el límite del ingress a 10 MB, súbelo también en la app; si no, el error aparecerá un salto más adentro.

```properties
spring.servlet.multipart.max-file-size=10MB
spring.servlet.multipart.max-request-size=10MB
```
```properties
quarkus.http.limits.max-body-size=10M
```
> Para archivos grandes no los subas por el ingress: entrega al cliente una **SAS** y que suba directo a Blob Storage ([SAS](../../06-storage/sas-tokens/README.md)).

## 7. Sondas de salud para el ingress

El controlador envía tráfico solo a pods *Ready*.

```java
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicBoolean;

@Component("cacheCaliente")
class CacheCaliente implements HealthIndicator {

    private final AtomicBoolean lista = new AtomicBoolean(false);

    void marcarLista() {
        lista.set(true);
    }

    @Override
    public Health health() {
        return lista.get() ? Health.up().build() : Health.outOfService().withDetail("motivo", "precalentando").build();
    }
}
```
Inclúyelo en el grupo `readiness` (`management.endpoint.health.group.readiness.include=readinessState,cacheCaliente`) y **no** en `liveness`.

## 8. Imperativo vs reactivo detrás del ingress

| | Imperativo (MVC / Quarkus clásico) | Reactivo (WebFlux / Quarkus REST + Mutiny) |
|---|---|---|
| Conexiones largas (SSE) | Un hilo (o hilo virtual) por conexión | Miles de conexiones con pocos hilos |
| Efecto del ingress | Igual | Igual: los tiempos de inactividad aplican igual |
| Hilos virtuales (Java 21) | `spring.threads.virtual.enabled=true` simplifica el modelo | No necesarios |

Elige por el patrón de trabajo, no por el ingress.

## 9. Qué NO hacer en el código
- Leer `X-Forwarded-For` sin comprobar quién lo envía.
- Construir URLs a mano con `"http://" + host`.
- Hacer `System.exit` en una sonda fallida: deja que Kubernetes reinicie.
- Mantener sesiones en memoria sin afinidad ni almacén compartido si hay varias réplicas.
