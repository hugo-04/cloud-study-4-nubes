# AWS · Config · Uso desde Java

En Config, Java aparece en dos lugares: **(1) la regla personalizada** (una función Lambda que Config invoca y que debe responder *siempre* y *por cada recurso*) y **(2) las herramientas que consultan el cumplimiento** (un panel, un reporte, un bot). El núcleo común son cuatro piezas: **evaluador de etiquetas** (puro: lee el evento y decide), **partición en lotes de cien**, **reporte de evaluaciones con reintento de las fallidas** y **resumen de cumplimiento**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56, `config`), `aws-lambda-java-core`.

## 1. Configuración
```yaml
# Spring Boot (application.yml) — herramienta de consulta; la regla Lambda no usa Spring
app:
  cumplimiento:
    max-incumplimientos: 200       # tope por consulta: protege memoria y costo
```
```properties
# Quarkus (application.properties) — el cliente se crea en un productor
app.cumplimiento.max-incumplimientos=200
```
Parámetros de la **regla** (se pasan en `input_parameters`; son un JSON de texto a texto, ver [`ejemplos/json/regla-etiquetas-parametros.json`](ejemplos/json/regla-etiquetas-parametros.json)): `tagKeys` (obligatorias, separadas por comas), `valores.<clave>` (valores permitidos) y `tipos` (tipos de recurso a los que aplica).

## 2. Núcleo común

### 2.1 Evaluador de etiquetas (puro)
Recibe el texto del evento de Config y devuelve **una evaluación** o la orden de **ir a buscar el elemento completo** (las notificaciones «grandes» no traen etiquetas). Cubre los casos que dejan evaluaciones colgadas: recurso eliminado, fuera de alcance, tipo no aplicable.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;

public final class EvaluadorEtiquetas {
    public enum Resultado { COMPLIANT, NON_COMPLIANT, NOT_APPLICABLE }

    public record Evaluacion(String tipoRecurso, String idRecurso, Resultado resultado, String anotacion, Instant momento) {}

    public record Reglas(List<String> etiquetasObligatorias, Map<String, Set<String>> valoresPermitidos, Set<String> tipos) {}

    public sealed interface Interpretacion permits Lista, NecesitaElementoCompleto {}

    public record Lista(Evaluacion evaluacion) implements Interpretacion {}

    public record NecesitaElementoCompleto(String tipoRecurso, String idRecurso, Instant momento) implements Interpretacion {}

    public static final int MAX_ANOTACION = 256;

    private EvaluadorEtiquetas() {}

    /** Parámetros de la regla: JSON de texto a texto. */
    public static Reglas leerParametros(String ruleParameters) {
        Map<String, JsonNode> o = JsonNodeParser.create().parse(ruleParameters).asObject();
        List<String> obligatorias = csv(o.get("tagKeys"));
        if (obligatorias.isEmpty()) {
            throw new IllegalArgumentException("tagKeys es obligatorio");
        }
        Map<String, Set<String>> valores = new LinkedHashMap<>();
        o.forEach((k, v) -> {
            if (k.startsWith("valores.")) {
                valores.put(k.substring("valores.".length()), new LinkedHashSet<>(csv(v)));
            }
        });
        return new Reglas(obligatorias, valores, new LinkedHashSet<>(csv(o.get("tipos"))));
    }

    public static Interpretacion interpretar(String invokingEvent, Reglas reglas, boolean fueraDeAlcance) {
        Map<String, JsonNode> evento = JsonNodeParser.create().parse(invokingEvent).asObject();
        String tipoMensaje = texto(evento.get("messageType"));
        boolean grande = "OversizedConfigurationItemChangeNotification".equals(tipoMensaje);
        if (!grande && !"ConfigurationItemChangeNotification".equals(tipoMensaje)) {
            throw new IllegalArgumentException("esta regla solo se dispara por cambio de configuración, no: " + tipoMensaje);
        }
        Map<String, JsonNode> item = evento.get(grande ? "configurationItemSummary" : "configurationItem").asObject();
        String tipo = texto(item.get("resourceType"));
        String id = texto(item.get("resourceId"));
        String estado = texto(item.get("configurationItemStatus"));
        Instant momento = Instant.parse(texto(item.get("configurationItemCaptureTime")));

        if (fueraDeAlcance || "ResourceDeleted".equals(estado) || "ResourceDeletedNotRecorded".equals(estado)
                || "ResourceNotRecorded".equals(estado)) {
            return new Lista(new Evaluacion(tipo, id, Resultado.NOT_APPLICABLE, "Eliminado o fuera del alcance de la regla", momento));
        }
        if (!reglas.tipos().isEmpty() && !reglas.tipos().contains(tipo)) {
            return new Lista(new Evaluacion(tipo, id, Resultado.NOT_APPLICABLE, "Tipo de recurso no aplicable", momento));
        }
        if (grande) {
            return new NecesitaElementoCompleto(tipo, id, momento);
        }
        Map<String, String> etiquetas = new TreeMap<>();
        JsonNode t = item.get("tags");
        if (t != null && t.isObject()) {
            t.asObject().forEach((k, v) -> etiquetas.put(k, v.isString() ? v.asString() : ""));
        }
        return new Lista(evaluar(tipo, id, etiquetas, reglas, momento));
    }

    /** También se usa con las etiquetas de un elemento recuperado con GetResourceConfigHistory. */
    public static Evaluacion evaluar(String tipo, String id, Map<String, String> etiquetas, Reglas reglas, Instant momento) {
        List<String> faltan = new ArrayList<>();
        for (String clave : reglas.etiquetasObligatorias()) {
            String valor = etiquetas.get(clave);
            if (valor == null || valor.isBlank()) {
                faltan.add(clave);
            }
        }
        List<String> invalidas = new ArrayList<>();
        reglas.valoresPermitidos().forEach((clave, permitidos) -> {
            String valor = etiquetas.get(clave);
            if (valor != null && !valor.isBlank() && !permitidos.contains(valor)) {
                invalidas.add(clave + "=" + valor + " (permitidos: " + String.join("|", permitidos) + ")");
            }
        });
        if (faltan.isEmpty() && invalidas.isEmpty()) {
            return new Evaluacion(tipo, id, Resultado.COMPLIANT, "Etiquetas correctas", momento);
        }
        List<String> partes = new ArrayList<>();
        if (!faltan.isEmpty()) {
            partes.add("Faltan etiquetas: " + String.join(", ", faltan));
        }
        if (!invalidas.isEmpty()) {
            partes.add("Valores no permitidos: " + String.join("; ", invalidas));
        }
        return new Evaluacion(tipo, id, Resultado.NON_COMPLIANT, recortar(String.join(". ", partes)), momento);
    }

    static String recortar(String anotacion) {
        return anotacion.length() <= MAX_ANOTACION ? anotacion : anotacion.substring(0, MAX_ANOTACION - 1) + "…";
    }

    private static String texto(JsonNode n) {
        return n != null && n.isString() ? n.asString() : null;
    }

    private static List<String> csv(JsonNode n) {
        List<String> salida = new ArrayList<>();
        if (n != null && n.isString()) {
            for (String p : n.asString().split(",")) {
                if (!p.isBlank()) {
                    salida.add(p.trim());
                }
            }
        }
        return salida;
    }
}
```

### 2.2 Lotes de cien
`PutEvaluations` acepta hasta 100 evaluaciones por llamada.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

public final class Lotes {
    private Lotes() {}

    public static <T> List<List<T>> partir(List<T> elementos, int tamano) {
        if (tamano < 1) {
            throw new IllegalArgumentException("tamano debe ser >= 1");
        }
        List<List<T>> lotes = new ArrayList<>();
        for (int i = 0; i < elementos.size(); i += tamano) {
            lotes.add(List.copyOf(elementos.subList(i, Math.min(i + tamano, elementos.size()))));
        }
        return lotes;
    }
}
```

### 2.3 Reporte de evaluaciones con reintento de las fallidas
HTTP 200 no significa «todo aceptado»: la respuesta trae `FailedEvaluations`. Se reintentan **solo esas**, unas pocas veces, y si siguen fallando se avisa con una excepción (para que Lambda registre el error y reintente).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import software.amazon.awssdk.services.config.ConfigClient;
import software.amazon.awssdk.services.config.model.ComplianceType;
import software.amazon.awssdk.services.config.model.ConfigurationItem;
import software.amazon.awssdk.services.config.model.Evaluation;
import software.amazon.awssdk.services.config.model.PutEvaluationsResponse;

public final class ReglaConfig {
    private ReglaConfig() {}

    static Evaluation aSdk(EvaluadorEtiquetas.Evaluacion e) {
        return Evaluation.builder()
                .complianceResourceType(e.tipoRecurso())
                .complianceResourceId(e.idRecurso())
                .complianceType(ComplianceType.fromValue(e.resultado().name()))
                .annotation(e.anotacion())
                .orderingTimestamp(e.momento())
                .build();
    }

    public static void reportar(ConfigClient config, String resultToken, List<EvaluadorEtiquetas.Evaluacion> evaluaciones) {
        List<Evaluation> pendientes = evaluaciones.stream().map(ReglaConfig::aSdk).collect(Collectors.toList());
        for (int intento = 1; intento <= 3 && !pendientes.isEmpty(); intento++) {
            List<Evaluation> falladas = new java.util.ArrayList<>();
            for (List<Evaluation> lote : Lotes.partir(pendientes, 100)) {
                PutEvaluationsResponse r = config.putEvaluations(b -> b.resultToken(resultToken).evaluations(lote));
                falladas.addAll(r.failedEvaluations());
            }
            pendientes = falladas;
        }
        if (!pendientes.isEmpty()) {
            throw new IllegalStateException("Config rechazó " + pendientes.size() + " evaluaciones tras 3 intentos");
        }
    }

    /** Etiquetas del último elemento de configuración (para notificaciones «grandes»). */
    public static Map<String, String> etiquetasDe(ConfigClient config, String tipo, String id) {
        List<ConfigurationItem> items = config.getResourceConfigHistory(b -> b.resourceType(tipo).resourceId(id).limit(1)).configurationItems();
        return items.isEmpty() ? Map.of() : items.get(0).tags();
    }
}
```

### 2.4 La función Lambda de la regla
Un solo recurso por invocación. Reutiliza el cliente entre invocaciones (se crea fuera de `handleRequest`).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.services.config.ConfigClient;

public class ReglaEtiquetasHandler implements RequestHandler<Map<String, Object>, String> {
    private final ConfigClient config;

    public ReglaEtiquetasHandler() {
        this(ConfigClient.create());
    }

    ReglaEtiquetasHandler(ConfigClient config) {
        this.config = config;
    }

    @Override
    public String handleRequest(Map<String, Object> evento, Context contexto) {
        EvaluadorEtiquetas.Reglas reglas = EvaluadorEtiquetas.leerParametros((String) evento.get("ruleParameters"));
        boolean fuera = Boolean.TRUE.equals(evento.get("eventLeftScope"));
        EvaluadorEtiquetas.Evaluacion evaluacion = switch (EvaluadorEtiquetas.interpretar((String) evento.get("invokingEvent"), reglas, fuera)) {
            case EvaluadorEtiquetas.Lista l -> l.evaluacion();
            case EvaluadorEtiquetas.NecesitaElementoCompleto n -> EvaluadorEtiquetas.evaluar(
                    n.tipoRecurso(), n.idRecurso(), ReglaConfig.etiquetasDe(config, n.tipoRecurso(), n.idRecurso()), reglas, n.momento());
        };
        ReglaConfig.reportar(config, (String) evento.get("resultToken"), List.of(evaluacion));
        return evaluacion.resultado().name();
    }
}
```

### 2.5 Resumen de cumplimiento y consulta
Un panel debe mostrar **porcentaje de cumplimiento** y **qué incumple**, sin descargar todo. `calcular` es puro; `ConsultaCumplimiento` pagina el SDK con un tope.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public final class ResumenCumplimiento {
    public record Regla(String nombre, String estado) {}

    public record Resumen(int reglas, int cumplen, int incumplen, int sinDatos, double porcentaje, List<String> incumplidas) {}

    private ResumenCumplimiento() {}

    /** Porcentaje = cumplen / (cumplen + incumplen). Las reglas sin datos o no aplicables no cuentan en el porcentaje. */
    public static Resumen calcular(List<Regla> reglas) {
        int cumplen = 0;
        int incumplen = 0;
        int sinDatos = 0;
        for (Regla r : reglas) {
            switch (r.estado()) {
                case "COMPLIANT" -> cumplen++;
                case "NON_COMPLIANT" -> incumplen++;
                default -> sinDatos++;
            }
        }
        double porcentaje = cumplen + incumplen == 0 ? 100.0 : Math.round(1000.0 * cumplen / (cumplen + incumplen)) / 10.0;
        List<String> incumplidas = reglas.stream().filter(r -> r.estado().equals("NON_COMPLIANT")).map(Regla::nombre).sorted().toList();
        return new Resumen(reglas.size(), cumplen, incumplen, sinDatos, porcentaje, incumplidas);
    }
}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import software.amazon.awssdk.services.config.ConfigClient;
import software.amazon.awssdk.services.config.model.ComplianceByConfigRule;
import software.amazon.awssdk.services.config.model.ComplianceType;
import software.amazon.awssdk.services.config.model.DescribeComplianceByConfigRuleResponse;
import software.amazon.awssdk.services.config.model.EvaluationResult;
import software.amazon.awssdk.services.config.model.GetComplianceDetailsByConfigRuleResponse;

public final class ConsultaCumplimiento {
    public record Incumplimiento(String tipo, String id, String anotacion) {}

    private final ConfigClient config;

    public ConsultaCumplimiento(ConfigClient config) {
        this.config = config;
    }

    public ResumenCumplimiento.Resumen resumen() {
        List<ResumenCumplimiento.Regla> reglas = new ArrayList<>();
        for (DescribeComplianceByConfigRuleResponse pagina : config.describeComplianceByConfigRulePaginator()) {
            for (ComplianceByConfigRule c : pagina.complianceByConfigRules()) {
                reglas.add(new ResumenCumplimiento.Regla(c.configRuleName(), c.compliance().complianceTypeAsString()));
            }
        }
        return ResumenCumplimiento.calcular(reglas);
    }

    public List<Incumplimiento> incumplimientos(String regla, int maximo) {
        List<Incumplimiento> salida = new ArrayList<>();
        for (GetComplianceDetailsByConfigRuleResponse pagina : config.getComplianceDetailsByConfigRulePaginator(
                r -> r.configRuleName(regla).complianceTypes(ComplianceType.NON_COMPLIANT).limit(100))) {
            for (EvaluationResult e : pagina.evaluationResults()) {
                var q = e.evaluationResultIdentifier().evaluationResultQualifier();
                salida.add(new Incumplimiento(q.resourceType(), q.resourceId(), e.annotation()));
                if (salida.size() >= maximo) {
                    return salida;
                }
            }
        }
        return salida;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.config.ConfigClient;

@Configuration
class ConfigCfg {
    @Bean(destroyMethod = "close")
    ConfigClient config() {
        return ConfigClient.create();
    }

    @Bean
    ConsultaCumplimiento consulta(ConfigClient config) {
        return new ConsultaCumplimiento(config);
    }
}

@RestController
@RequestMapping("/cumplimiento")
class CumplimientoController {
    private final ConsultaCumplimiento consulta;
    private final int tope;

    CumplimientoController(ConsultaCumplimiento consulta, @Value("${app.cumplimiento.max-incumplimientos}") int tope) {
        this.consulta = consulta;
        this.tope = tope;
    }

    @GetMapping("/resumen")
    ResumenCumplimiento.Resumen resumen() {
        return consulta.resumen();
    }

    @GetMapping("/{regla}/incumplimientos")
    List<ConsultaCumplimiento.Incumplimiento> incumplimientos(@PathVariable String regla, @RequestParam(defaultValue = "50") int max) {
        return consulta.incumplimientos(regla, Math.min(max, tope));
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import software.amazon.awssdk.services.config.ConfigAsyncClient;
import software.amazon.awssdk.services.config.model.ComplianceType;
import software.amazon.awssdk.services.config.model.GetComplianceDetailsByConfigRuleResponse;

@Configuration
class ConfigReactivoCfg {
    @Bean(destroyMethod = "close")
    ConfigAsyncClient configAsync() {
        return ConfigAsyncClient.create();
    }
}

@RestController
class IncumplimientosReactivoController {
    private final ConfigAsyncClient config;
    private final int tope;

    IncumplimientosReactivoController(ConfigAsyncClient config, @Value("${app.cumplimiento.max-incumplimientos}") int tope) {
        this.config = config;
        this.tope = tope;
    }

    /** El paginador del SDK pide la página siguiente solo cuando el consumidor la necesita. */
    @GetMapping("/r/cumplimiento/{regla}/incumplimientos")
    Flux<ConsultaCumplimiento.Incumplimiento> incumplimientos(@PathVariable String regla, @RequestParam(defaultValue = "50") int max) {
        return Flux.from(config.getComplianceDetailsByConfigRulePaginator(
                        r -> r.configRuleName(regla).complianceTypes(ComplianceType.NON_COMPLIANT).limit(100)))
                .concatMapIterable(GetComplianceDetailsByConfigRuleResponse::evaluationResults)
                .map(e -> {
                    var q = e.evaluationResultIdentifier().evaluationResultQualifier();
                    return new ConsultaCumplimiento.Incumplimiento(q.resourceType(), q.resourceId(), e.annotation());
                })
                .take(Math.min(max, tope));
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import software.amazon.awssdk.services.config.ConfigAsyncClient;
import software.amazon.awssdk.services.config.ConfigClient;

@ApplicationScoped
class ConfigProductores {
    @Produces
    @Singleton
    ConfigClient config() {
        return ConfigClient.create();
    }

    void cerrar(@Disposes ConfigClient c) {
        c.close();
    }

    @Produces
    @Singleton
    ConfigAsyncClient configAsync() {
        return ConfigAsyncClient.create();
    }

    void cerrarAsync(@Disposes ConfigAsyncClient c) {
        c.close();
    }

    @Produces
    @Singleton
    ConsultaCumplimiento consulta(ConfigClient config) {
        return new ConsultaCumplimiento(config);
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@Path("/cumplimiento")
@Produces(MediaType.APPLICATION_JSON)
class CumplimientoRecurso {
    @Inject
    ConsultaCumplimiento consulta;

    @ConfigProperty(name = "app.cumplimiento.max-incumplimientos")
    int tope;

    @GET
    @Path("/resumen")
    public ResumenCumplimiento.Resumen resumen() {
        return consulta.resumen();
    }

    @GET
    @Path("/{regla}/incumplimientos")
    public List<ConsultaCumplimiento.Incumplimiento> incumplimientos(@PathParam("regla") String regla,
                                                                      @QueryParam("max") @DefaultValue("50") int max) {
        return consulta.incumplimientos(regla, Math.min(max, tope));
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
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.reactivestreams.FlowAdapters;
import software.amazon.awssdk.services.config.ConfigAsyncClient;
import software.amazon.awssdk.services.config.model.ComplianceType;
import software.amazon.awssdk.services.config.model.GetComplianceDetailsByConfigRuleResponse;

@Path("/m/cumplimiento")
class IncumplimientosMutinyRecurso {
    @Inject
    ConfigAsyncClient config;

    @GET
    @Path("/{regla}/incumplimientos")
    @Produces(MediaType.APPLICATION_JSON)
    public Multi<ConsultaCumplimiento.Incumplimiento> incumplimientos(@PathParam("regla") String regla,
                                                                       @QueryParam("max") @DefaultValue("50") int max) {
        return Multi.createFrom().publisher(FlowAdapters.toFlowPublisher(config.getComplianceDetailsByConfigRulePaginator(
                        r -> r.configRuleName(regla).complianceTypes(ComplianceType.NON_COMPLIANT).limit(100))))
                .onItem().transformToIterable(GetComplianceDetailsByConfigRuleResponse::evaluationResults)
                .map(e -> {
                    var q = e.evaluationResultIdentifier().evaluationResultQualifier();
                    return new ConsultaCumplimiento.Incumplimiento(q.resourceType(), q.resourceId(), e.annotation());
                })
                .select().first(Math.min(max, 200));
    }
}
```

## 7. Permisos
- **Lambda de la regla:** [`ejemplos/json/politica-evaluador.json`](ejemplos/json/politica-evaluador.json) (`config:PutEvaluations`, `config:GetResourceConfigHistory`) más los permisos de registro de la propia función; Config necesita permiso para invocarla (`aws_lambda_permission` en el Terraform).
- **Herramientas de consulta:** [`ejemplos/json/politica-lectura.json`](ejemplos/json/politica-lectura.json), de solo lectura.
- **Pipeline:** `config:Put*` sobre reglas, registrador, remediaciones y agregador, en otra identidad.

## 8. Qué NO hacer desde Java
- **No** dejes una evaluación sin responder: recursos eliminados, fuera de alcance y de otro tipo → `NOT_APPLICABLE` (§2.1).
- **No** envíes más de 100 evaluaciones por llamada ni ignores `FailedEvaluations` (§2.3).
- **No** asumas que la notificación trae las etiquetas: las grandes requieren recuperar el elemento (§2.1, §2.3).
- **No** crees el cliente dentro de `handleRequest`: uno por contenedor de Lambda.
- **No** descargues todos los incumplimientos de una regla: pagina y limita (§2.5).
- **No** reutilices el `resultToken` en varias invocaciones: es de un solo evento.
