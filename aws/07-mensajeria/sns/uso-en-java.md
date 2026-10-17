# AWS · SNS · Uso desde Java

Tres piezas puras y una con SDK: **atributos tipados** (si el tipo es incorrecto, el filtro no coincide), un **evaluador de políticas de filtro** para probarlas sin desplegar, el **desempaquetado del sobre** de SNS (cuando no hay entrega cruda) y la **publicación por lotes** con reintento parcial. Versiones: Java 21, Spring Boot 4.1 (Spring Cloud AWS 4.2), Quarkus 3.40 (`quarkus-amazon-sns`), AWS SDK v2 (BOM 2.56).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  cloud:
    aws:
      region:
        static: us-east-1
app:
  topico-ordenes: arn:aws:sns:us-east-1:111122223333:prod-ordenes
  cola-facturacion: prod-facturacion
```
```properties
# Quarkus (application.properties)
quarkus.sns.aws.region=us-east-1
app.topico-ordenes=arn:aws:sns:us-east-1:111122223333:prod-ordenes
```

## 2. Núcleo común

### 2.1 Atributos tipados
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;

public record Atributo(String tipo, String valor) {
    public static Atributo texto(String v) {
        return new Atributo("String", v);
    }

    /** Number: sin esto un filtro numérico (">", 100) nunca coincide. Usa BigDecimal para no perder precisión. */
    public static Atributo numero(BigDecimal v) {
        return new Atributo("Number", v.toPlainString());
    }
}
```

### 2.2 Evaluador de políticas de filtro (subconjunto)
Soporta: valor exacto, `prefix`, `suffix`, `equals-ignore-case`, `anything-but`, `numeric`, `exists`, varias claves (AND), lista de valores (OR) y `$or`. Sirve para **probar una política con mensajes reales antes de aplicarla**; la fuente de verdad sigue siendo SNS.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class FiltroSns {
    private FiltroSns() {}

    /** @param politica JSON de la política ya convertido a Map/List (lo hace Jackson en tu aplicación). */
    public static boolean coincide(Map<String, Object> politica, Map<String, Atributo> atributos) {
        for (var e : politica.entrySet()) {
            if (e.getKey().equals("$or")) {
                boolean alguna = false;
                for (Object sub : lista(e.getValue())) {
                    if (sub instanceof Map<?, ?> m && coincide(castMapa(m), atributos)) {
                        alguna = true;
                    }
                }
                if (!alguna) {
                    return false;
                }
                continue;
            }
            if (!claveCoincide(lista(e.getValue()), atributos.get(e.getKey()))) {
                return false;
            }
        }
        return true;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMapa(Map<?, ?> m) {
        return (Map<String, Object>) m;
    }

    private static List<?> lista(Object o) {
        if (o instanceof List<?> l) {
            return l;
        }
        throw new IllegalArgumentException("se esperaba una lista en la política: " + o);
    }

    private static boolean claveCoincide(List<?> condiciones, Atributo a) {
        for (Object c : condiciones) {
            if (c instanceof Map<?, ?> m && m.size() == 1 && "exists".equals(m.keySet().iterator().next())) {
                boolean debeExistir = Boolean.TRUE.equals(m.get("exists"));
                if (debeExistir == (a != null)) {
                    return true;
                }
                continue;
            }
            if (a != null && condicion(c, a)) {
                return true;
            }
        }
        return false;
    }

    private static boolean condicion(Object c, Atributo a) {
        if (c instanceof String s) {
            return a.tipo().startsWith("String") && a.valor().equals(s);
        }
        if (c instanceof Number n) {
            return a.tipo().equals("Number") && numero(a.valor()).compareTo(new BigDecimal(n.toString())) == 0;
        }
        if (!(c instanceof Map<?, ?> m) || m.size() != 1) {
            throw new IllegalArgumentException("condición no soportada: " + c);
        }
        String op = String.valueOf(m.keySet().iterator().next());
        Object arg = m.get(op);
        switch (op) {
            case "prefix":
                return a.tipo().startsWith("String") && a.valor().startsWith(String.valueOf(arg));
            case "suffix":
                return a.tipo().startsWith("String") && a.valor().endsWith(String.valueOf(arg));
            case "equals-ignore-case":
                return a.tipo().startsWith("String") && a.valor().toLowerCase(Locale.ROOT).equals(String.valueOf(arg).toLowerCase(Locale.ROOT));
            case "anything-but":
                return !excluido(arg, a);
            case "numeric":
                return a.tipo().equals("Number") && numerico(lista(arg), numero(a.valor()));
            default:
                throw new IllegalArgumentException("operador no soportado: " + op);
        }
    }

    private static boolean excluido(Object arg, Atributo a) {
        if (arg instanceof List<?> l) {
            return l.stream().anyMatch(x -> igual(x, a));
        }
        if (arg instanceof Map<?, ?> m && m.containsKey("prefix")) {
            return a.valor().startsWith(String.valueOf(m.get("prefix")));
        }
        return igual(arg, a);
    }

    private static boolean igual(Object x, Atributo a) {
        if (x instanceof Number n) {
            return a.tipo().equals("Number") && numero(a.valor()).compareTo(new BigDecimal(n.toString())) == 0;
        }
        return a.valor().equals(String.valueOf(x));
    }

    private static BigDecimal numero(String s) {
        return new BigDecimal(s);
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

### 2.3 Desempaquetar el sobre de SNS (cuando NO hay entrega cruda)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

public final class SobreSns {
    public record Notificacion(String topicArn, String messageId, String asunto, String mensaje,
                               Map<String, Atributo> atributos) {}

    private SobreSns() {}

    @SuppressWarnings("unchecked")
    private static Map<String, Object> mapa(Object o) {
        return o instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    /** Valida que sea una notificación de un tópico esperado y devuelve sus partes. Entrada no confiable. */
    public static Notificacion desempaquetar(Map<String, Object> sobre, Set<String> topicosPermitidos) {
        if (!"Notification".equals(sobre.get("Type"))) {
            throw new IllegalArgumentException("no es una notificación de SNS (Type=" + sobre.get("Type") + ")");
        }
        String topic = String.valueOf(sobre.get("TopicArn"));
        if (!topicosPermitidos.contains(topic)) {
            throw new SecurityException("tópico no permitido: " + topic);
        }
        if (!(sobre.get("Message") instanceof String mensaje)) {
            throw new IllegalArgumentException("falta Message");
        }
        Map<String, Atributo> atributos = new LinkedHashMap<>();
        mapa(sobre.get("MessageAttributes")).forEach((k, v) -> {
            Map<String, Object> a = mapa(v);
            atributos.put(k, new Atributo(String.valueOf(a.get("Type")), String.valueOf(a.get("Value"))));
        });
        return new Notificacion(topic, String.valueOf(sobre.get("MessageId")),
                sobre.get("Subject") == null ? null : String.valueOf(sobre.get("Subject")), mensaje, atributos);
    }
}
```

### 2.4 Publicar por lotes con reintento parcial
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.BatchResultErrorEntry;
import software.amazon.awssdk.services.sns.model.MessageAttributeValue;
import software.amazon.awssdk.services.sns.model.PublishBatchRequest;
import software.amazon.awssdk.services.sns.model.PublishBatchRequestEntry;
import software.amazon.awssdk.services.sns.model.PublishBatchResponse;

public final class PublicadorSns {
    public record Mensaje(String id, String cuerpo, Map<String, Atributo> atributos, String grupo, String dedup) {}

    public static final class PublicacionParcialException extends RuntimeException {
        private final List<String> fallidos;

        PublicacionParcialException(List<String> fallidos) {
            super("no se pudieron publicar: " + fallidos);
            this.fallidos = List.copyOf(fallidos);
        }

        public List<String> fallidos() {
            return fallidos;
        }
    }

    private final SnsClient sns;
    private final String topicArn;
    private final int reintentos;

    public PublicadorSns(SnsClient sns, String topicArn, int reintentos) {
        this.sns = sns;
        this.topicArn = topicArn;
        this.reintentos = reintentos;
    }

    static Map<String, MessageAttributeValue> convertir(Map<String, Atributo> atributos) {
        Map<String, MessageAttributeValue> r = new HashMap<>();
        atributos.forEach((k, a) -> r.put(k,
                MessageAttributeValue.builder().dataType(a.tipo()).stringValue(a.valor()).build()));
        return r;
    }

    public void publicarLote(List<Mensaje> mensajes) {
        List<String> definitivos = new ArrayList<>();
        for (int i = 0; i < mensajes.size(); i += 10) {
            List<Mensaje> pendientes = mensajes.subList(i, Math.min(i + 10, mensajes.size()));
            for (int intento = 0; intento <= reintentos && !pendientes.isEmpty(); intento++) {
                PublishBatchResponse r = sns.publishBatch(PublishBatchRequest.builder().topicArn(topicArn)
                        .publishBatchRequestEntries(pendientes.stream().map(PublicadorSns::entrada).toList()).build());
                List<Mensaje> siguientes = new ArrayList<>();
                for (BatchResultErrorEntry f : r.failed()) {
                    Mensaje m = pendientes.stream().filter(x -> x.id().equals(f.id())).findFirst().orElseThrow();
                    if (f.senderFault()) {
                        definitivos.add(m.id());
                    } else {
                        siguientes.add(m);
                    }
                }
                pendientes = siguientes;
            }
            pendientes.forEach(m -> definitivos.add(m.id()));
        }
        if (!definitivos.isEmpty()) {
            throw new PublicacionParcialException(definitivos);
        }
    }

    private static PublishBatchRequestEntry entrada(Mensaje m) {
        var b = PublishBatchRequestEntry.builder().id(m.id()).message(m.cuerpo())
                .messageAttributes(convertir(m.atributos()));
        if (m.grupo() != null) {
            b.messageGroupId(m.grupo());
        }
        if (m.dedup() != null) {
            b.messageDeduplicationId(m.dedup());
        }
        return b.build();
    }
}
```

## 3. Spring MVC (imperativo)
```java
import io.awspring.cloud.sqs.annotation.SqsListener;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.sns.SnsClient;
import tools.jackson.databind.json.JsonMapper;

@Configuration
class SnsConfig {
    @Bean
    PublicadorSns publicador(SnsClient sns, @Value("${app.topico-ordenes}") String topico) {
        return new PublicadorSns(sns, topico, 3);
    }

    @Bean
    JsonMapper jsonMapper() {
        return JsonMapper.builder().build();
    }
}

record OrdenDto(String idOrden, BigDecimal total, String envio, String pais) {}

@RestController
class OrdenesSnsController {
    private final PublicadorSns publicador;
    private final JsonMapper json;

    OrdenesSnsController(PublicadorSns publicador, JsonMapper json) {
        this.publicador = publicador;
        this.json = json;
    }

    @PostMapping("/ordenes-sns")
    Map<String, Object> publicar(@RequestBody List<OrdenDto> ordenes) {
        var mensajes = ordenes.stream().map(o -> new PublicadorSns.Mensaje(
                o.idOrden(), json.writeValueAsString(o),
                Map.of("tipo", Atributo.texto("OrdenCreada"), "total", Atributo.numero(o.total()),
                        "envio", Atributo.texto(o.envio()), "pais", Atributo.texto(o.pais())),
                null, null)).toList();
        publicador.publicarLote(mensajes);
        return Map.of("publicados", mensajes.size());
    }
}

/** Cola suscrita SIN entrega cruda: el cuerpo es el sobre de SNS. (Con entrega cruda, el cuerpo es la orden.) */
@Component
class FacturacionListener {
    private final JsonMapper json;
    private final String topico;

    FacturacionListener(JsonMapper json, @Value("${app.topico-ordenes}") String topico) {
        this.json = json;
        this.topico = topico;
    }

    @SqsListener("${app.cola-facturacion}")
    @SuppressWarnings("unchecked")
    void recibir(String cuerpo) {
        Map<String, Object> sobre = json.readValue(cuerpo, Map.class);
        var n = SobreSns.desempaquetar(sobre, Set.of(topico));
        System.out.println("orden " + n.messageId() + " tipo=" + n.atributos().get("tipo"));   // tu negocio (idempotente)
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

record OrdenReactivaDto(String idOrden, BigDecimal total, String envio, String pais) {}

@RestController
class OrdenesSnsReactivoController {
    private final PublicadorSns publicador;

    OrdenesSnsReactivoController(PublicadorSns publicador) {
        this.publicador = publicador;
    }

    /** El SDK síncrono bloquea: se aísla en boundedElastic. */
    @PostMapping("/ordenes-sns-r")
    Mono<Map<String, Object>> publicar(@RequestBody Mono<List<OrdenReactivaDto>> cuerpo) {
        return cuerpo.flatMap(ordenes -> Mono.fromCallable(() -> {
            var mensajes = ordenes.stream().map(o -> new PublicadorSns.Mensaje(
                    o.idOrden(), "{\"idOrden\":\"" + o.idOrden() + "\"}",
                    Map.of("tipo", Atributo.texto("OrdenCreada"), "total", Atributo.numero(o.total()),
                            "envio", Atributo.texto(o.envio()), "pais", Atributo.texto(o.pais())),
                    null, null)).toList();
            publicador.publicarLote(mensajes);
            return Map.<String, Object>of("publicados", mensajes.size());
        }).subscribeOn(Schedulers.boundedElastic()));
    }
}
```

## 5. Quarkus (imperativo)
```java
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.sns.SnsClient;

@ApplicationScoped
class SnsProductores {
    @Produces
    @Singleton
    PublicadorSns publicador(SnsClient sns, @ConfigProperty(name = "app.topico-ordenes") String topico) {
        return new PublicadorSns(sns, topico, 3);
    }
}
```
```java
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@Path("/ordenes-sns")
class OrdenesSnsRecurso {
    public record OrdenDto(String idOrden, BigDecimal total, String envio, String pais) {}

    @Inject
    PublicadorSns publicador;

    @Inject
    ObjectMapper json;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, Object> publicar(List<OrdenDto> ordenes) throws Exception {
        var mensajes = new java.util.ArrayList<PublicadorSns.Mensaje>();
        for (OrdenDto o : ordenes) {
            mensajes.add(new PublicadorSns.Mensaje(o.idOrden(), json.writeValueAsString(o),
                    Map.of("tipo", Atributo.texto("OrdenCreada"), "total", Atributo.numero(o.total()),
                            "envio", Atributo.texto(o.envio()), "pais", Atributo.texto(o.pais())), null, null));
        }
        publicador.publicarLote(mensajes);
        return Map.of("publicados", mensajes.size());
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
import software.amazon.awssdk.services.sns.SnsAsyncClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;

@Path("/ordenes-sns-r")
class OrdenesSnsMutinyRecurso {
    @Inject
    SnsAsyncClient sns;

    @ConfigProperty(name = "app.topico-ordenes")
    String topico;

    /** Publicación individual con el cliente asíncrono: no bloquea el hilo de eventos. */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Map<String, String>> publicar(String cuerpo) {
        PublishRequest rq = PublishRequest.builder().topicArn(topico).message(cuerpo)
                .messageAttributes(PublicadorSns.convertir(Map.of("tipo", Atributo.texto("OrdenCreada")))).build();
        return Uni.createFrom().completionStage(() -> sns.publish(rq)).map(r -> Map.of("messageId", r.messageId()));
    }
}
```

## 7. Permisos
Productor: `sns:Publish` sobre el tópico (+ `kms:GenerateDataKey`/`Decrypt` si el tópico usa KMS). Cada cola suscrita: política con `aws:SourceArn` del tópico ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)).

## 8. Qué NO hacer desde Java
- **No** publiques importes como `String`: usa `Atributo.numero`, o el filtro numérico no coincide.
- **No** pongas datos personales en atributos.
- **No** confíes en el sobre: valida `Type` y `TopicArn` (`SobreSns`).
- **No** reintentes errores del emisor (`senderFault`).
- **No** mezcles entrega cruda y sobre en el mismo consumidor sin saber cuál recibes.
- **No** llames a `publicarLote` desde un hilo de eventos reactivo sin aislarlo.
- **No** uses el evaluador local como sustituto de probar la suscripción real.
