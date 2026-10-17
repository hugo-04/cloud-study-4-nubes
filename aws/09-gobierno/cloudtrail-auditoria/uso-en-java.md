# AWS · CloudTrail · Uso desde Java

Desde Java, CloudTrail es una **fuente de verdad que lees**: no escribes eventos (AWS los genera), sino que **buscas**, **interpretas** y **detectas patrones**. Las alarmas de CloudWatch cubren lo clásico (raíz, MFA, cambios de trazas); tu código cubre lo que necesita contexto: ráfagas por principal, informes, enriquecimiento. El núcleo común son cinco piezas: **modelo de evento y lector**, **detector de sospechas**, **rutas de la traza**, **búsqueda con `LookupEvents`** y **lector de archivos en S3**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56, `cloudtrail` + `s3`).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  auditoria:
    bucket: ${BUCKET_AUDITORIA}          # bucket de la traza (cuenta de archivo de registros)
    rafaga-minima: 20                     # rechazos por principal dentro de la ventana
    ventana-minutos: 5
```
```properties
# Quarkus (application.properties)
app.auditoria.bucket=${BUCKET_AUDITORIA}
app.auditoria.rafaga-minima=20
app.auditoria.ventana-minutos=5
```
`LookupEvents` solo ve **administración** de los **últimos 90 días** y **una región**; para rechazos (`errorCode`) y para más historia se leen los archivos de la traza en S3 (o Athena/Lake).

## 2. Núcleo común

### 2.1 Modelo de evento y lector
Extrae solo lo necesario del JSON de CloudTrail y **tolera campos ausentes o `null`** (`responseElements` suele ser `null` en eventos fallidos). Sirve para un evento suelto (`LookupEvents`) y para un archivo completo (`{"Records":[…]}`, normalmente comprimido).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;

public record Evento(
        String id,
        Instant tiempo,
        String fuente,
        String nombre,
        String region,
        String ip,
        String tipoIdentidad,
        String principal,
        String invocadoPor,
        String mfaConsola,
        String resultadoConsola,
        String codigoError,
        String tipoEvento,
        boolean soloLectura) {}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.zip.GZIPInputStream;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;

public final class LectorCloudTrail {
    private LectorCloudTrail() {}

    /** Un archivo de la traza: {"Records":[...]} */
    public static List<Evento> leerArchivo(String json) {
        JsonNode raiz = JsonNodeParser.create().parse(json);
        List<Evento> eventos = new ArrayList<>();
        JsonNode registros = raiz.isObject() ? raiz.asObject().get("Records") : null;
        if (registros != null && registros.isArray()) {
            for (JsonNode r : registros.asArray()) {
                eventos.add(aEvento(r));
            }
        }
        return eventos;
    }

    /** El texto que devuelve LookupEvents en Event.cloudTrailEvent(). */
    public static Evento leerEvento(String json) {
        return aEvento(JsonNodeParser.create().parse(json));
    }

    /** Un archivo .json.gz tal como está en S3. */
    public static List<Evento> leerGzip(byte[] bytes) {
        try (GZIPInputStream in = new GZIPInputStream(new ByteArrayInputStream(bytes))) {
            return leerArchivo(new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    static Evento aEvento(JsonNode n) {
        Map<String, JsonNode> o = n.asObject();
        Map<String, JsonNode> identidad = objeto(o.get("userIdentity"));
        Map<String, JsonNode> respuesta = objeto(o.get("responseElements"));
        Map<String, JsonNode> adicional = objeto(o.get("additionalEventData"));
        String arn = texto(identidad.get("arn"));
        String usuario = texto(identidad.get("userName"));
        String invocadoPor = texto(identidad.get("invokedBy"));
        String tipo = texto(identidad.get("type"));
        String principal = arn != null ? arn : usuario != null ? usuario : invocadoPor != null ? invocadoPor : tipo;
        return new Evento(
                texto(o.get("eventID")),
                Instant.parse(texto(o.get("eventTime"))),
                texto(o.get("eventSource")),
                texto(o.get("eventName")),
                texto(o.get("awsRegion")),
                texto(o.get("sourceIPAddress")),
                tipo,
                principal,
                invocadoPor,
                texto(adicional.get("MFAUsed")),
                texto(respuesta.get("ConsoleLogin")),
                texto(o.get("errorCode")),
                texto(o.get("eventType")),
                booleano(o.get("readOnly")));
    }

    private static Map<String, JsonNode> objeto(JsonNode n) {
        return n != null && n.isObject() ? n.asObject() : Map.of();
    }

    private static String texto(JsonNode n) {
        return n != null && n.isString() ? n.asString() : null;
    }

    private static boolean booleano(JsonNode n) {
        if (n == null) {
            return false;
        }
        return n.isBoolean() ? n.asBoolean() : n.isString() && Boolean.parseBoolean(n.asString());
    }
}
```

### 2.2 Detector de sospechas
Reglas con **contexto**: raíz usado por una persona (no por un servicio), inicio de sesión de consola sin MFA, cambios sobre la propia auditoría y **ráfagas de rechazos por principal** (ventana deslizante: un rechazo aislado es ruido).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

public final class DetectorSospechas {
    public enum Severidad { ALTA, MEDIA }

    public record Alerta(String regla, Severidad severidad, String principal, Instant desde, String detalle, List<String> eventos) {}

    public record Umbrales(int rechazosMinimos, Duration ventana, Set<String> cambiosSensibles) {}

    private DetectorSospechas() {}

    public static Umbrales porDefecto() {
        return new Umbrales(20, Duration.ofMinutes(5), Set.of(
                "StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors",
                "DeleteConfigurationRecorder", "StopConfigurationRecorder", "DeleteDeliveryChannel",
                "DisableKey", "ScheduleKeyDeletion", "DeleteFlowLogs"));
    }

    public static boolean esRechazo(String codigoError) {
        return codigoError != null && (codigoError.startsWith("AccessDenied") || codigoError.contains("Unauthorized"));
    }

    public static List<Alerta> analizar(List<Evento> eventos, Umbrales u) {
        List<Alerta> alertas = new ArrayList<>();
        for (Evento e : eventos) {
            if ("Root".equals(e.tipoIdentidad()) && e.invocadoPor() == null && !"AwsServiceEvent".equals(e.tipoEvento())) {
                alertas.add(new Alerta("USO_RAIZ", Severidad.ALTA, e.principal(), e.tiempo(),
                        "El usuario raíz ejecutó " + e.nombre() + " desde " + e.ip(), List.of(e.id())));
            }
            if ("ConsoleLogin".equals(e.nombre()) && "Success".equals(e.resultadoConsola())
                    && !"Yes".equals(e.mfaConsola()) && "IAMUser".equals(e.tipoIdentidad())) {
                alertas.add(new Alerta("CONSOLA_SIN_MFA", Severidad.MEDIA, e.principal(), e.tiempo(),
                        "Inicio de sesión de consola sin MFA desde " + e.ip(), List.of(e.id())));
            }
            if (u.cambiosSensibles().contains(e.nombre())) {
                String estado = e.codigoError() == null ? "ejecutado" : "intento rechazado (" + e.codigoError() + ")";
                alertas.add(new Alerta("CAMBIO_SENSIBLE", Severidad.ALTA, e.principal(), e.tiempo(),
                        e.nombre() + " " + estado + " desde " + e.ip(), List.of(e.id())));
            }
        }
        alertas.addAll(rafagas(eventos, u));
        alertas.sort(Comparator.comparing(Alerta::desde).thenComparing(Alerta::regla));
        return alertas;
    }

    /** Ventana deslizante por principal: marca cada evento que cae en alguna ventana con >= N rechazos y funde las rachas contiguas. */
    static List<Alerta> rafagas(List<Evento> eventos, Umbrales u) {
        Map<String, List<Evento>> porPrincipal = new LinkedHashMap<>();
        for (Evento e : eventos) {
            if (esRechazo(e.codigoError())) {
                porPrincipal.computeIfAbsent(e.principal(), k -> new ArrayList<>()).add(e);
            }
        }
        List<Alerta> alertas = new ArrayList<>();
        porPrincipal.forEach((principal, lista) -> {
            lista.sort(Comparator.comparing(Evento::tiempo));
            int n = lista.size();
            boolean[] marcado = new boolean[n];
            int j = 0;
            for (int i = 0; i < n; i++) {
                j = Math.max(j, i);
                while (j + 1 < n && Duration.between(lista.get(i).tiempo(), lista.get(j + 1).tiempo()).compareTo(u.ventana()) <= 0) {
                    j++;
                }
                if (j - i + 1 >= u.rechazosMinimos()) {
                    for (int k = i; k <= j; k++) {
                        marcado[k] = true;
                    }
                }
            }
            int i = 0;
            while (i < n) {
                if (!marcado[i]) {
                    i++;
                    continue;
                }
                int fin = i;
                while (fin + 1 < n && marcado[fin + 1]) {
                    fin++;
                }
                List<Evento> racha = lista.subList(i, fin + 1);
                Set<String> servicios = new TreeSet<>();
                racha.forEach(e -> servicios.add(e.fuente()));
                alertas.add(new Alerta("RAFAGA_ACCESO_DENEGADO", Severidad.MEDIA, principal, racha.get(0).tiempo(),
                        racha.size() + " rechazos entre " + racha.get(0).tiempo() + " y " + racha.get(racha.size() - 1).tiempo()
                                + " sobre " + String.join(", ", servicios),
                        racha.stream().map(Evento::id).toList()));
                i = fin + 1;
            }
        });
        return alertas;
    }
}
```

### 2.3 Rutas de la traza en S3
El nombre de los archivos es predecible: se calcula el prefijo del día y solo se leen esos archivos (no el bucket entero).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;

public final class RutasTraza {
    private static final DateTimeFormatter DIA = DateTimeFormatter.ofPattern("yyyy/MM/dd");

    private RutasTraza() {}

    /** AWSLogs/<cuenta>/CloudTrail/<region>/yyyy/MM/dd/  (si la traza es de organización: AWSLogs/<org>/<cuenta>/...) */
    public static String prefijoDelDia(String idOrganizacion, String cuenta, String region, LocalDate dia) {
        if (!cuenta.matches("\\d{12}")) {
            throw new IllegalArgumentException("cuenta inválida: " + cuenta);
        }
        if (!region.matches("[a-z]{2}(-gov)?-[a-z]+-\\d")) {
            throw new IllegalArgumentException("región inválida: " + region);
        }
        String base = idOrganizacion == null || idOrganizacion.isBlank() ? "AWSLogs/" : "AWSLogs/" + idOrganizacion + "/";
        return base + cuenta + "/CloudTrail/" + region + "/" + DIA.format(dia) + "/";
    }
}
```

### 2.4 Búsqueda con `LookupEvents`
Un atributo por llamada, 50 eventos por página y **unas 2 solicitudes por segundo**: se pagina con pausa y con tope.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.LongConsumer;
import software.amazon.awssdk.services.cloudtrail.CloudTrailClient;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttribute;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttributeKey;
import software.amazon.awssdk.services.cloudtrail.model.LookupEventsResponse;

public final class BusquedaCloudTrail {
    private final CloudTrailClient cloudTrail;
    private final LongConsumer pausa;

    public BusquedaCloudTrail(CloudTrailClient cloudTrail, LongConsumer pausa) {
        this.cloudTrail = cloudTrail;
        this.pausa = pausa;
    }

    public List<Evento> buscar(LookupAttributeKey clave, String valor, Instant desde, Instant hasta, int maximo) {
        Map<String, Evento> porId = new LinkedHashMap<>();
        String token = null;
        do {
            String siguiente = token;
            LookupEventsResponse r = cloudTrail.lookupEvents(b -> b
                    .lookupAttributes(LookupAttribute.builder().attributeKey(clave).attributeValue(valor).build())
                    .startTime(desde).endTime(hasta).maxResults(50).nextToken(siguiente));
            r.events().forEach(e -> {
                Evento ev = LectorCloudTrail.leerEvento(e.cloudTrailEvent());
                porId.putIfAbsent(ev.id(), ev);
            });
            token = r.nextToken();
            if (token != null && porId.size() < maximo) {
                pausa.accept(550);   // respeta ~2 solicitudes por segundo
            }
        } while (token != null && porId.size() < maximo);
        List<Evento> lista = new ArrayList<>(porId.values());
        return lista.size() > maximo ? lista.subList(0, maximo) : lista;
    }
}
```

### 2.5 Lector de archivos de la traza en S3
Para lo que `LookupEvents` no ve (rechazos, eventos de datos, más de 90 días).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.S3Object;

public final class LectorLogsS3 {
    private final S3Client s3;
    private final String bucket;

    public LectorLogsS3(S3Client s3, String bucket) {
        this.s3 = s3;
        this.bucket = bucket;
    }

    public List<String> archivosDelDia(String idOrganizacion, String cuenta, String region, LocalDate dia) {
        String prefijo = RutasTraza.prefijoDelDia(idOrganizacion, cuenta, region, dia);
        List<String> claves = new ArrayList<>();
        for (ListObjectsV2Response pagina : s3.listObjectsV2Paginator(b -> b.bucket(bucket).prefix(prefijo))) {
            for (S3Object o : pagina.contents()) {
                if (o.key().endsWith(".json.gz")) {
                    claves.add(o.key());
                }
            }
        }
        return claves;
    }

    public List<Evento> leer(String clave) {
        return LectorCloudTrail.leerGzip(s3.getObjectAsBytes(b -> b.bucket(bucket).key(clave)).asByteArray());
    }

    /** Todos los eventos de un día. Para días de mucho volumen, procesa archivo por archivo en lugar de acumular. */
    public List<Evento> eventosDelDia(String idOrganizacion, String cuenta, String region, LocalDate dia) {
        List<Evento> todos = new ArrayList<>();
        for (String clave : archivosDelDia(idOrganizacion, cuenta, region, dia)) {
            todos.addAll(leer(clave));
        }
        return todos;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.cloudtrail.CloudTrailClient;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttributeKey;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
class AuditoriaConfig {
    @Bean(destroyMethod = "close")
    CloudTrailClient cloudTrail() {
        return CloudTrailClient.create();
    }

    @Bean(destroyMethod = "close")
    S3Client s3() {
        return S3Client.create();
    }

    @Bean
    BusquedaCloudTrail busqueda(CloudTrailClient cloudTrail) {
        return new BusquedaCloudTrail(cloudTrail, ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });
    }

    @Bean
    LectorLogsS3 lectorLogs(S3Client s3, @Value("${app.auditoria.bucket}") String bucket) {
        return new LectorLogsS3(s3, bucket);
    }

    @Bean
    DetectorSospechas.Umbrales umbrales(@Value("${app.auditoria.rafaga-minima}") int minimo,
                                        @Value("${app.auditoria.ventana-minutos}") int minutos) {
        DetectorSospechas.Umbrales base = DetectorSospechas.porDefecto();
        return new DetectorSospechas.Umbrales(minimo, Duration.ofMinutes(minutos), base.cambiosSensibles());
    }
}

@RestController
@RequestMapping("/auditoria")
class AuditoriaController {
    private final BusquedaCloudTrail busqueda;
    private final LectorLogsS3 logs;
    private final DetectorSospechas.Umbrales umbrales;

    AuditoriaController(BusquedaCloudTrail busqueda, LectorLogsS3 logs, DetectorSospechas.Umbrales umbrales) {
        this.busqueda = busqueda;
        this.logs = logs;
        this.umbrales = umbrales;
    }

    /** ¿Quién ejecutó X en las últimas N horas? (administración, 90 días, esta región) */
    @GetMapping("/eventos")
    List<Evento> eventos(@RequestParam String nombre, @RequestParam(defaultValue = "24") int horas) {
        Instant ahora = Instant.now();
        return busqueda.buscar(LookupAttributeKey.EVENT_NAME, nombre, ahora.minus(Duration.ofHours(Math.min(horas, 24 * 90))), ahora, 200);
    }

    /** Sospechas rápidas con LookupEvents: raíz, inicios de sesión y cambios sobre la auditoría. */
    @GetMapping("/sospechas")
    List<DetectorSospechas.Alerta> sospechas(@RequestParam(defaultValue = "24") int horas) {
        Instant ahora = Instant.now();
        Instant desde = ahora.minus(Duration.ofHours(Math.min(horas, 24 * 90)));
        Map<String, Evento> porId = new LinkedHashMap<>();
        busqueda.buscar(LookupAttributeKey.USERNAME, "root", desde, ahora, 200).forEach(e -> porId.putIfAbsent(e.id(), e));
        for (String nombre : List.of("ConsoleLogin", "StopLogging", "DeleteTrail", "UpdateTrail", "PutEventSelectors")) {
            busqueda.buscar(LookupAttributeKey.EVENT_NAME, nombre, desde, ahora, 200).forEach(e -> porId.putIfAbsent(e.id(), e));
        }
        return DetectorSospechas.analizar(new ArrayList<>(porId.values()), umbrales);
    }

    /** Ráfagas de rechazos: requiere los archivos de la traza (LookupEvents no filtra por errorCode). */
    @GetMapping("/sospechas-dia")
    List<DetectorSospechas.Alerta> sospechasDelDia(@RequestParam String cuenta, @RequestParam String region,
                                                    @RequestParam LocalDate fecha, @RequestParam(required = false) String organizacion) {
        return DetectorSospechas.analizar(logs.eventosDelDia(organizacion, cuenta, region, fecha), umbrales);
    }
}
```

## 4. Spring WebFlux (reactivo)
El cliente asíncrono entrega un paginador reactivo; cada evento se interpreta al pasar. El tope protege memoria y costo.
```java
import java.time.Duration;
import java.time.Instant;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import software.amazon.awssdk.services.cloudtrail.CloudTrailAsyncClient;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttribute;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttributeKey;
import software.amazon.awssdk.services.cloudtrail.model.LookupEventsResponse;

@Configuration
class AuditoriaReactivaConfig {
    @Bean(destroyMethod = "close")
    CloudTrailAsyncClient cloudTrailAsync() {
        return CloudTrailAsyncClient.create();
    }
}

@RestController
class EventosReactivoController {
    private final CloudTrailAsyncClient cloudTrail;

    EventosReactivoController(CloudTrailAsyncClient cloudTrail) {
        this.cloudTrail = cloudTrail;
    }

    @GetMapping("/r/auditoria/eventos")
    Flux<Evento> eventos(@RequestParam String nombre, @RequestParam(defaultValue = "24") int horas) {
        Instant ahora = Instant.now();
        return Flux.from(cloudTrail.lookupEventsPaginator(b -> b
                        .lookupAttributes(LookupAttribute.builder().attributeKey(LookupAttributeKey.EVENT_NAME).attributeValue(nombre).build())
                        .startTime(ahora.minus(Duration.ofHours(Math.min(horas, 24 * 90)))).endTime(ahora).maxResults(50)))
                .concatMapIterable(LookupEventsResponse::events)
                .map(e -> LectorCloudTrail.leerEvento(e.cloudTrailEvent()))
                .take(200);
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.cloudtrail.CloudTrailAsyncClient;
import software.amazon.awssdk.services.cloudtrail.CloudTrailClient;
import software.amazon.awssdk.services.s3.S3Client;

@ApplicationScoped
class AuditoriaProductores {
    @Produces
    @Singleton
    CloudTrailClient cloudTrail() {
        return CloudTrailClient.create();
    }

    void cerrar(@Disposes CloudTrailClient c) {
        c.close();
    }

    @Produces
    @Singleton
    CloudTrailAsyncClient cloudTrailAsync() {
        return CloudTrailAsyncClient.create();
    }

    void cerrarAsync(@Disposes CloudTrailAsyncClient c) {
        c.close();
    }

    @Produces
    @Singleton
    S3Client s3() {
        return S3Client.create();
    }

    void cerrarS3(@Disposes S3Client c) {
        c.close();
    }

    @Produces
    @Singleton
    BusquedaCloudTrail busqueda(CloudTrailClient cloudTrail) {
        return new BusquedaCloudTrail(cloudTrail, Pausa::dormir);
    }

    @Produces
    @Singleton
    LectorLogsS3 lectorLogs(S3Client s3, @ConfigProperty(name = "app.auditoria.bucket") String bucket) {
        return new LectorLogsS3(s3, bucket);
    }
}

final class Pausa {
    private Pausa() {}

    static void dormir(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttributeKey;

@Path("/auditoria")
@Produces(MediaType.APPLICATION_JSON)
class AuditoriaRecurso {
    @Inject
    BusquedaCloudTrail busqueda;

    @Inject
    LectorLogsS3 logs;

    @ConfigProperty(name = "app.auditoria.rafaga-minima")
    int rafagaMinima;

    @ConfigProperty(name = "app.auditoria.ventana-minutos")
    int ventanaMinutos;

    @GET
    @Path("/eventos")
    public List<Evento> eventos(@QueryParam("nombre") String nombre, @QueryParam("horas") @DefaultValue("24") int horas) {
        Instant ahora = Instant.now();
        return busqueda.buscar(LookupAttributeKey.EVENT_NAME, nombre, ahora.minus(Duration.ofHours(Math.min(horas, 24 * 90))), ahora, 200);
    }

    @GET
    @Path("/sospechas-dia")
    public List<DetectorSospechas.Alerta> sospechasDelDia(@QueryParam("cuenta") String cuenta, @QueryParam("region") String region,
                                                           @QueryParam("fecha") String fecha, @QueryParam("organizacion") String organizacion) {
        DetectorSospechas.Umbrales base = DetectorSospechas.porDefecto();
        DetectorSospechas.Umbrales umbrales = new DetectorSospechas.Umbrales(rafagaMinima, Duration.ofMinutes(ventanaMinutos), base.cambiosSensibles());
        return DetectorSospechas.analizar(logs.eventosDelDia(organizacion, cuenta, region, LocalDate.parse(fecha)), umbrales);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Multi;
import jakarta.inject.Inject;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.time.Duration;
import java.time.Instant;
import org.reactivestreams.FlowAdapters;
import software.amazon.awssdk.services.cloudtrail.CloudTrailAsyncClient;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttribute;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttributeKey;
import software.amazon.awssdk.services.cloudtrail.model.LookupEventsResponse;

@Path("/m/auditoria")
class EventosMutinyRecurso {
    @Inject
    CloudTrailAsyncClient cloudTrail;

    @GET
    @Path("/eventos")
    @Produces(MediaType.APPLICATION_JSON)
    public Multi<Evento> eventos(@QueryParam("nombre") String nombre, @QueryParam("horas") @DefaultValue("24") int horas) {
        Instant ahora = Instant.now();
        return Multi.createFrom().publisher(FlowAdapters.toFlowPublisher(cloudTrail.lookupEventsPaginator(b -> b
                        .lookupAttributes(LookupAttribute.builder().attributeKey(LookupAttributeKey.EVENT_NAME).attributeValue(nombre).build())
                        .startTime(ahora.minus(Duration.ofHours(Math.min(horas, 24 * 90)))).endTime(ahora).maxResults(50))))
                .onItem().transformToIterable(LookupEventsResponse::events)
                .map(e -> LectorCloudTrail.leerEvento(e.cloudTrailEvent()))
                .select().first(200);
    }
}
```

## 7. Permisos
Investigador/aplicación: [`ejemplos/json/politica-investigador.json`](ejemplos/json/politica-investigador.json) — `cloudtrail:LookupEvents` y lectura (`s3:GetObject`, `s3:ListBucket` con prefijo `AWSLogs/`) del bucket de la traza, que normalmente vive en **otra cuenta** (cuenta de archivo de registros): la política del bucket debe permitir ese rol, y si el bucket usa KMS, la clave también (`kms:Decrypt`). **Esta herramienta solo lee**: no necesita permisos de escritura ni de administración de trazas.

## 8. Qué NO hacer desde Java
- **No** busques rechazos con `LookupEvents`: no filtra por `errorCode`; usa los archivos de la traza (§2.5) o Athena.
- **No** hagas más de ~2 solicitudes por segundo a `LookupEvents`: pausa y tope (§2.4).
- **No** alertes por cada `AccessDenied`: usa ventana y umbral por principal (§2.2).
- **No** asumas que los campos existen: `responseElements` y otros pueden ser `null` (§2.1).
- **No** leas el bucket entero: calcula el prefijo del día (§2.3).
- **No** acumules días enteros en memoria en cuentas muy activas: procesa archivo por archivo.
- **No** des permisos de escritura sobre el bucket de auditoría a esta herramienta.
