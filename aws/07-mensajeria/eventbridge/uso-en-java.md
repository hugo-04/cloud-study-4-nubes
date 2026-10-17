# AWS · EventBridge · Uso desde Java

Cuatro piezas puras (probables sin red) y una con SDK: **escribir el `detail` sin dependencias** (sirve igual en Spring y Quarkus), **evaluar patrones** en local, **leer el evento recibido** (validando la fuente) y **publicar en lotes** con reintento *por entrada*. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40 (`quarkus-amazon-eventbridge`), AWS SDK v2 (BOM 2.56). Spring Cloud AWS no trae módulo de EventBridge: se usa el SDK directamente.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  bus-ordenes: prod-ordenes
  cola-facturacion: prod-eb-facturacion
```
```properties
# Quarkus (application.properties)
quarkus.eventbridge.aws.region=us-east-1
app.bus-ordenes=prod-ordenes
```
> En Spring, `EventBridgeClient.create()` toma región y credenciales de la cadena por defecto (variables `AWS_REGION`, rol del pod/tarea…). La propiedad `spring.cloud.aws.region.static` solo afecta a los clientes que Spring Cloud AWS autoconfigura.

## 2. Núcleo común

### 2.1 Escribir el `detail` (JSON mínimo, sin Jackson)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;

public final class JsonDetalle {
    private JsonDetalle() {}

    public static String escribir(Object valor) {
        StringBuilder sb = new StringBuilder();
        escribir(valor, sb);
        return sb.toString();
    }

    private static void escribir(Object v, StringBuilder sb) {
        if (v == null) {
            sb.append("null");
        } else if (v instanceof String s) {
            texto(s, sb);
        } else if (v instanceof Boolean b) {
            sb.append(b);
        } else if (v instanceof BigDecimal d) {
            sb.append(d.toPlainString());
        } else if (v instanceof Double || v instanceof Float) {
            double d = ((Number) v).doubleValue();
            if (Double.isNaN(d) || Double.isInfinite(d)) {
                throw new IllegalArgumentException("número no representable en JSON: " + v);
            }
            sb.append(v);
        } else if (v instanceof Number n) {
            sb.append(n);
        } else if (v instanceof Instant t) {
            texto(t.toString(), sb);
        } else if (v instanceof Map<?, ?> m) {
            sb.append('{');
            boolean primero = true;
            for (var e : m.entrySet()) {
                if (!(e.getKey() instanceof String k)) {
                    throw new IllegalArgumentException("las claves deben ser texto: " + e.getKey());
                }
                if (!primero) {
                    sb.append(',');
                }
                primero = false;
                texto(k, sb);
                sb.append(':');
                escribir(e.getValue(), sb);
            }
            sb.append('}');
        } else if (v instanceof List<?> l) {
            sb.append('[');
            for (int i = 0; i < l.size(); i++) {
                if (i > 0) {
                    sb.append(',');
                }
                escribir(l.get(i), sb);
            }
            sb.append(']');
        } else {
            throw new IllegalArgumentException("tipo no soportado: " + v.getClass().getName());
        }
    }

    private static void texto(String s, StringBuilder sb) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                case '\b' -> sb.append("\\b");
                case '\f' -> sb.append("\\f");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        sb.append('"');
    }
}
```

### 2.2 Evaluador de patrones de evento (subconjunto)
Soporta valor exacto (texto, número, booleano, `null`), `prefix`, `suffix`, `equals-ignore-case`, `wildcard`, `anything-but` (valor, lista u operador), `numeric`, `exists`, `$or`, anidamiento y campos que son listas. **Sirve para probar patrones con eventos reales antes de desplegar**; la fuente de verdad es EventBridge (`aws events test-event-pattern`).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

public final class PatronEventBridge {
    private PatronEventBridge() {}

    public static boolean coincide(Map<String, Object> patron, Map<String, Object> evento) {
        for (var e : patron.entrySet()) {
            if (e.getKey().equals("$or")) {
                boolean alguna = false;
                for (Object sub : lista(e.getValue())) {
                    if (sub instanceof Map<?, ?> m && coincide(mapa(m), evento)) {
                        alguna = true;
                    }
                }
                if (!alguna) {
                    return false;
                }
            } else if (!campo(e.getValue(), evento, e.getKey())) {
                return false;
            }
        }
        return true;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> mapa(Map<?, ?> m) {
        return (Map<String, Object>) m;
    }

    private static List<?> lista(Object o) {
        if (o instanceof List<?> l) {
            return l;
        }
        throw new IllegalArgumentException("se esperaba una lista en el patrón: " + o);
    }

    private static boolean campo(Object regla, Map<String, Object> evento, String clave) {
        boolean existe = evento.containsKey(clave);
        Object valor = evento.get(clave);
        if (regla instanceof Map<?, ?> anidado) {
            if (valor instanceof Map<?, ?> hijo) {
                return coincide(mapa(anidado), mapa(hijo));
            }
            if (valor instanceof List<?> l) {
                return l.stream().anyMatch(x -> x instanceof Map<?, ?> h && coincide(mapa(anidado), mapa(h)));
            }
            return false;
        }
        for (Object c : lista(regla)) {
            if (c instanceof Map<?, ?> m && m.size() == 1 && m.containsKey("exists")) {
                if (Boolean.TRUE.equals(m.get("exists")) == existe) {
                    return true;
                }
                continue;
            }
            if (!existe) {
                continue;
            }
            boolean ok = valor instanceof List<?> l ? l.stream().anyMatch(x -> condicion(c, x)) : condicion(c, valor);
            if (ok) {
                return true;
            }
        }
        return false;
    }

    private static boolean condicion(Object c, Object v) {
        if (c == null) {
            return v == null;
        }
        if (c instanceof String s) {
            return v instanceof String t && t.equals(s);
        }
        if (c instanceof Boolean b) {
            return b.equals(v);
        }
        if (c instanceof Number n) {
            return v instanceof Number x && num(x).compareTo(num(n)) == 0;
        }
        if (!(c instanceof Map<?, ?> m) || m.size() != 1) {
            throw new IllegalArgumentException("condición no soportada: " + c);
        }
        String op = String.valueOf(m.keySet().iterator().next());
        Object arg = m.get(op);
        return switch (op) {
            case "prefix" -> v instanceof String t && t.startsWith(String.valueOf(arg));
            case "suffix" -> v instanceof String t && t.endsWith(String.valueOf(arg));
            case "equals-ignore-case" -> v instanceof String t && t.equalsIgnoreCase(String.valueOf(arg));
            case "wildcard" -> v instanceof String t && glob(String.valueOf(arg), t);
            case "anything-but" -> v != null && !excluido(arg, v);
            case "numeric" -> v instanceof Number x && numerico(lista(arg), num(x));
            default -> throw new IllegalArgumentException("operador no soportado: " + op);
        };
    }

    private static boolean excluido(Object arg, Object v) {
        if (arg instanceof List<?> l) {
            return l.stream().anyMatch(x -> condicion(x, v));
        }
        return condicion(arg, v);
    }

    private static BigDecimal num(Number n) {
        return new BigDecimal(n.toString());
    }

    private static boolean glob(String patron, String valor) {
        String regex = String.join(".*", Arrays.stream(patron.split("\\*", -1)).map(Pattern::quote).toList());
        return Pattern.compile(regex, Pattern.DOTALL).matcher(valor).matches();
    }

    /** ["=", 5] | [">", 100] | [">", 100, "<=", 200] */
    private static boolean numerico(List<?> t, BigDecimal v) {
        if (t.size() != 2 && t.size() != 4) {
            throw new IllegalArgumentException("numeric requiere 2 o 4 elementos");
        }
        for (int i = 0; i < t.size(); i += 2) {
            int cmp = v.compareTo(new BigDecimal(t.get(i + 1).toString()));
            boolean ok = switch (String.valueOf(t.get(i))) {
                case "=" -> cmp == 0;
                case ">" -> cmp > 0;
                case ">=" -> cmp >= 0;
                case "<" -> cmp < 0;
                case "<=" -> cmp <= 0;
                default -> throw new IllegalArgumentException("operador numérico no soportado: " + t.get(i));
            };
            if (!ok) {
                return false;
            }
        }
        return true;
    }
}
```

### 2.3 Leer el evento recibido (entrada no confiable)
Úsalo cuando el destino recibe el **evento completo** (sin transformador). Si usas transformador, recibes el JSON que tú definiste.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import java.util.Set;

public final class SobreEventBridge {
    public record Recibido(String id, String fuente, String tipo, String hora, Map<String, Object> detalle) {}

    private SobreEventBridge() {}

    @SuppressWarnings("unchecked")
    public static Recibido leer(Map<String, Object> evento, Set<String> fuentesPermitidas) {
        Object id = evento.get("id");
        Object fuente = evento.get("source");
        Object tipo = evento.get("detail-type");
        if (!(id instanceof String i) || !(fuente instanceof String f) || !(tipo instanceof String t)) {
            throw new IllegalArgumentException("no es un evento de EventBridge");
        }
        if (!fuentesPermitidas.contains(f)) {
            throw new SecurityException("fuente no permitida: " + f);
        }
        Map<String, Object> detalle = evento.get("detail") instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
        Object hora = evento.get("time");
        return new Recibido(i, f, t, hora == null ? null : String.valueOf(hora), detalle);
    }
}
```

### 2.4 Publicar en lotes con reintento por entrada
`PutEvents` admite hasta 10 entradas y un tamaño total acotado; la respuesta trae **un resultado por entrada**, en el mismo orden. Se reintentan solo las reintentables (`ThrottlingException`, `InternalFailure`) y el resto se devuelve a quien llama (por ejemplo, para guardarlo en una tabla *outbox*).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.LongConsumer;
import software.amazon.awssdk.services.eventbridge.EventBridgeClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequestEntry;
import software.amazon.awssdk.services.eventbridge.model.PutEventsResponse;
import software.amazon.awssdk.services.eventbridge.model.PutEventsResultEntry;

public final class PublicadorEventBridge {
    public record Evento(String fuente, String tipo, String detalleJson, List<String> recursos) {
        public Evento {
            recursos = recursos == null ? List.of() : List.copyOf(recursos);
        }

        public static Evento de(String fuente, String tipo, Map<String, Object> detalle) {
            return new Evento(fuente, tipo, JsonDetalle.escribir(detalle), List.of());
        }
    }

    public static final class PublicacionParcialException extends RuntimeException {
        private final List<Evento> fallidos;

        PublicacionParcialException(List<Evento> fallidos) {
            super("no se pudieron publicar " + fallidos.size() + " evento(s)");
            this.fallidos = List.copyOf(fallidos);
        }

        public List<Evento> fallidos() {
            return fallidos;
        }
    }

    static final int MAX_ENTRADAS = 10;
    private static final Set<String> REINTENTABLES = Set.of("ThrottlingException", "InternalFailure");

    private final EventBridgeClient eb;
    private final String bus;
    private final int reintentos;
    private final int maxBytes;
    private final LongConsumer pausaMs;

    public PublicadorEventBridge(EventBridgeClient eb, String bus, int reintentos, int maxBytes, LongConsumer pausaMs) {
        this.eb = eb;
        this.bus = bus;
        this.reintentos = reintentos;
        this.maxBytes = maxBytes;
        this.pausaMs = pausaMs;
    }

    /** maxBytes = 1_000_000 es conservador respecto al límite vigente (verifica en la doc: 1 MiB desde 2025, antes 256 KiB). */
    public PublicadorEventBridge(EventBridgeClient eb, String bus) {
        this(eb, bus, 3, 1_000_000, ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException(e);
            }
        });
    }

    /** Tamaño según la regla de EventBridge: 14 bytes de la hora + fuente + tipo + detalle + recursos (UTF-8). */
    static int bytes(Evento e) {
        int n = 14 + e.fuente().getBytes(StandardCharsets.UTF_8).length + e.tipo().getBytes(StandardCharsets.UTF_8).length
                + e.detalleJson().getBytes(StandardCharsets.UTF_8).length;
        for (String r : e.recursos()) {
            n += r.getBytes(StandardCharsets.UTF_8).length;
        }
        return n;
    }

    static List<List<Evento>> partir(List<Evento> eventos, int maxBytes) {
        List<List<Evento>> lotes = new ArrayList<>();
        List<Evento> actual = new ArrayList<>();
        int acumulado = 0;
        for (Evento e : eventos) {
            int b = bytes(e);
            if (b > maxBytes) {
                throw new IllegalArgumentException("evento de " + b + " bytes supera " + maxBytes + ": usa Claim Check");
            }
            if (actual.size() == MAX_ENTRADAS || acumulado + b > maxBytes) {
                lotes.add(actual);
                actual = new ArrayList<>();
                acumulado = 0;
            }
            actual.add(e);
            acumulado += b;
        }
        if (!actual.isEmpty()) {
            lotes.add(actual);
        }
        return lotes;
    }

    public static PutEventsRequestEntry entrada(String bus, Evento e) {
        return PutEventsRequestEntry.builder().eventBusName(bus).source(e.fuente()).detailType(e.tipo())
                .detail(e.detalleJson()).resources(e.recursos()).build();
    }

    public void publicar(List<Evento> eventos) {
        List<Evento> fallidos = new ArrayList<>();
        for (List<Evento> lote : partir(eventos, maxBytes)) {
            List<Evento> pendientes = lote;
            for (int intento = 0; intento <= reintentos && !pendientes.isEmpty(); intento++) {
                if (intento > 0) {
                    pausaMs.accept(Math.min(5_000L, 100L << (intento - 1)));
                }
                PutEventsResponse r = eb.putEvents(PutEventsRequest.builder()
                        .entries(pendientes.stream().map(e -> entrada(bus, e)).toList()).build());
                int fallas = r.failedEntryCount() == null ? 0 : r.failedEntryCount();
                if (fallas == 0) {
                    pendientes = List.of();
                    break;
                }
                List<Evento> siguientes = new ArrayList<>();
                for (int i = 0; i < pendientes.size(); i++) {
                    PutEventsResultEntry re = r.entries().get(i);
                    if (re.errorCode() == null) {
                        continue;
                    }
                    if (REINTENTABLES.contains(re.errorCode())) {
                        siguientes.add(pendientes.get(i));
                    } else {
                        fallidos.add(pendientes.get(i));
                    }
                }
                pendientes = siguientes;
            }
            fallidos.addAll(pendientes);
        }
        if (!fallidos.isEmpty()) {
            throw new PublicacionParcialException(fallidos);
        }
    }
}
```

## 3. Spring MVC (imperativo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.eventbridge.EventBridgeClient;
import tools.jackson.databind.json.JsonMapper;

@Configuration
class EventBridgeConfig {
    @Bean(destroyMethod = "close")
    EventBridgeClient eventBridgeClient() {
        return EventBridgeClient.create();
    }

    @Bean
    PublicadorEventBridge publicador(EventBridgeClient eb, @Value("${app.bus-ordenes}") String bus) {
        return new PublicadorEventBridge(eb, bus);
    }
}

record OrdenEbDto(String idOrden, BigDecimal total, String envio, String direccion) {}

@RestController
class OrdenesEbController {
    private final PublicadorEventBridge publicador;

    OrdenesEbController(PublicadorEventBridge publicador) {
        this.publicador = publicador;
    }

    static Map<String, Object> detalle(OrdenEbDto o) {
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("version", 1);
        d.put("idOrden", o.idOrden());
        d.put("total", o.total());
        d.put("envio", o.envio());
        d.put("direccion", o.direccion());
        return d;
    }

    @PostMapping("/ordenes-eb")
    Map<String, Object> publicar(@RequestBody List<OrdenEbDto> ordenes) {
        var eventos = ordenes.stream()
                .map(o -> PublicadorEventBridge.Evento.de("modalima.ordenes", "OrdenCreada", detalle(o))).toList();
        publicador.publicar(eventos);
        return Map.of("publicados", eventos.size());
    }

    /** 207: algunos eventos no se publicaron; el cliente reintenta solo esos (o van a una tabla outbox). */
    @ExceptionHandler(PublicadorEventBridge.PublicacionParcialException.class)
    ResponseEntity<Map<String, Object>> parcial(PublicadorEventBridge.PublicacionParcialException e) {
        return ResponseEntity.status(207).body(Map.of("fallidos", e.fallidos().size()));
    }
}

/** Cola destino de la regla de facturación (sin transformador: llega el evento completo). */
@Component
class FacturacionEbListener {
    private final JsonMapper json;

    FacturacionEbListener(JsonMapper json) {
        this.json = json;
    }

    @SqsListener("${app.cola-facturacion}")
    @SuppressWarnings("unchecked")
    void recibir(String cuerpo) {
        Map<String, Object> evento = json.readValue(cuerpo, Map.class);
        var r = SobreEventBridge.leer(evento, Set.of("modalima.ordenes"));
        System.out.println("orden " + r.detalle().get("idOrden") + " evento " + r.id());   // tu negocio (idempotente por idOrden)
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

record OrdenEbReactivaDto(String idOrden, BigDecimal total, String envio) {}

@RestController
class OrdenesEbReactivoController {
    private final PublicadorEventBridge publicador;

    OrdenesEbReactivoController(PublicadorEventBridge publicador) {
        this.publicador = publicador;
    }

    /** El SDK síncrono bloquea (y el reintento duerme): se aísla en boundedElastic. */
    @PostMapping("/ordenes-eb-r")
    Mono<Map<String, Object>> publicar(@RequestBody Mono<List<OrdenEbReactivaDto>> cuerpo) {
        return cuerpo.flatMap(ordenes -> Mono.fromCallable(() -> {
            var eventos = ordenes.stream().map(o -> {
                Map<String, Object> d = new LinkedHashMap<>();
                d.put("version", 1);
                d.put("idOrden", o.idOrden());
                d.put("total", o.total());
                d.put("envio", o.envio());
                return PublicadorEventBridge.Evento.de("modalima.ordenes", "OrdenCreada", d);
            }).toList();
            publicador.publicar(eventos);
            return Map.<String, Object>of("publicados", eventos.size());
        }).subscribeOn(Schedulers.boundedElastic()));
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.eventbridge.EventBridgeClient;

@ApplicationScoped
class EventBridgeProductores {
    @Produces
    @Singleton
    PublicadorEventBridge publicador(EventBridgeClient eb, @ConfigProperty(name = "app.bus-ordenes") String bus) {
        return new PublicadorEventBridge(eb, bus);
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Path("/ordenes-eb")
class OrdenesEbRecurso {
    public record OrdenDto(String idOrden, BigDecimal total, String envio, String direccion) {}

    @Inject
    PublicadorEventBridge publicador;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response publicar(List<OrdenDto> ordenes) {
        var eventos = new ArrayList<PublicadorEventBridge.Evento>();
        for (OrdenDto o : ordenes) {
            Map<String, Object> d = new LinkedHashMap<>();
            d.put("version", 1);
            d.put("idOrden", o.idOrden());
            d.put("total", o.total());
            d.put("envio", o.envio());
            d.put("direccion", o.direccion());
            eventos.add(PublicadorEventBridge.Evento.de("modalima.ordenes", "OrdenCreada", d));
        }
        try {
            publicador.publicar(eventos);
            return Response.ok(Map.of("publicados", eventos.size())).build();
        } catch (PublicadorEventBridge.PublicacionParcialException e) {
            return Response.status(207).entity(Map.of("fallidos", e.fallidos().size())).build();
        }
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
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.eventbridge.EventBridgeAsyncClient;
import software.amazon.awssdk.services.eventbridge.model.PutEventsRequest;

@Path("/ordenes-eb-r")
class OrdenesEbMutinyRecurso {
    @Inject
    EventBridgeAsyncClient eb;

    @ConfigProperty(name = "app.bus-ordenes")
    String bus;

    /** Un evento con el cliente asíncrono: no bloquea el hilo de eventos. El cuerpo ya es el detail en JSON. */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Map<String, String>> publicar(String detalleJson) {
        var e = new PublicadorEventBridge.Evento("modalima.ordenes", "OrdenCreada", detalleJson, null);
        PutEventsRequest rq = PutEventsRequest.builder().entries(PublicadorEventBridge.entrada(bus, e)).build();
        return Uni.createFrom().completionStage(() -> eb.putEvents(rq)).map(r -> {
            var res = r.entries().get(0);
            if (res.errorCode() != null) {
                throw new IllegalStateException("EventBridge rechazó el evento: " + res.errorCode());
            }
            return Map.of("eventId", res.eventId());
        });
    }
}
```

## 7. Permisos
Productor: `events:PutEvents` sobre el **ARN del bus** ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) genera la política). Cada cola destino: política con `aws:SourceArn` de la regla.

## 8. Qué NO hacer desde Java
- **No** asumas que `PutEvents` con 200 publicó todo: revisa `failedEntryCount` y las entradas.
- **No** reintentes errores definitivos (formato, tamaño).
- **No** olvides `EventBusName`: sin él, el evento va al bus **predeterminado**.
- **No** construyas el `detail` concatenando texto: usa un escritor JSON (escapa comillas y saltos de línea).
- **No** confíes en el evento recibido: valida `source`.
- **No** proceses sin idempotencia: hay duplicados por reintentos y *replay*.
- **No** llames a `publicar` desde un hilo de eventos reactivo sin aislarlo.
