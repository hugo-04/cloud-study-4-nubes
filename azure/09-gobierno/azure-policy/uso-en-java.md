# Azure · Azure Policy · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3, `azure-resourcemanager-resources` 2.55, `azure-resourcemanager-policyinsights` 1.0.0, `azure-resourcemanager-resourcegraph` 1.1.0**. Verifica las vigentes.

## Qué puede hacer una aplicación Java con Azure Policy (y qué no)

Las reglas **no se evalúan desde tu código**: las evalúa Azure cuando se crea el recurso. Tu código sirve para cuatro cosas **de plataforma**:

| Caso | Qué haces desde Java |
|---|---|
| **Entender los rechazos** | Cuando tu aplicación crea recursos (autoservicio de entornos, aprovisionamiento por cliente), leer el error `RequestDisallowedByPolicy` y devolver un mensaje claro: *qué regla* lo rechazó y *cómo corregirlo* |
| **Medir cumplimiento** | Consultar el resumen y los incumplimientos (PolicyInsights, Resource Graph) para mostrarlos en un panel o exportarlos como métrica |
| **Gestionar excepciones** | Crear exenciones **con caducidad** desde un flujo de aprobación |
| **Disparar evaluaciones** | Forzar un ciclo de evaluación tras un cambio importante |

> Estos SDK son **de administración** (plano de control): síncronos, con latencias de cientos de milisegundos a segundos y cuotas de ARM. **No los pongas en el camino caliente** de una API de clientes: cachea los resultados y refresca en segundo plano.

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-resources</artifactId></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-policyinsights</artifactId><version>1.0.0</version></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-resourcegraph</artifactId><version>1.1.0</version></dependency>
```

**Permisos de la identidad de la aplicación** (identidad administrada, sin claves):

| Operación | Rol mínimo | Alcance |
|---|---|---|
| Leer cumplimiento y Resource Graph | *Reader* (o *Security Reader*) | Suscripción o grupo de administración |
| Crear grupos de recursos y recursos (autoservicio) | *Contributor* acotado a un grupo de recursos o a un rol personalizado | Suscripción de entornos |
| Crear/eliminar **exenciones** | Rol personalizado con `Microsoft.Authorization/policyExemptions/write` y `…/delete` + `Microsoft.Authorization/policyAssignments/exempt/action` | Alcance a eximir |
| Disparar evaluación | Permiso `Microsoft.PolicyInsights/policyStates/triggerEvaluation/action` (incluido en *Resource Policy Contributor*) | Suscripción |

## 1. Clases compartidas: el error de política y los resultados

Cuando una política `Deny` rechaza una solicitud, Azure devuelve HTTP 403 con el código **`RequestDisallowedByPolicy`**, y dentro del error, una sección `additionalInfo` de tipo `PolicyViolation` con la asignación, la definición y el efecto. En **despliegues** (plantillas), el error viene anidado en `details`. El lector recorre el árbol completo y tolera campos ausentes.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.management.exception.AdditionalInfo;
import com.azure.core.management.exception.ManagementError;
import com.azure.core.management.exception.ManagementException;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Una regla que rechazó la solicitud. */
record ViolacionDePolitica(String asignacion, String definicion, String referencia, String efecto, String alcance) { }

/** Resultado de intentar crear algo: creado, o rechazado por reglas concretas. */
record ResultadoDeCreacion(boolean creado, String nombre, List<ViolacionDePolitica> violaciones) {

    static ResultadoDeCreacion ok(String nombre) {
        return new ResultadoDeCreacion(true, nombre, List.of());
    }

    static ResultadoDeCreacion rechazado(String nombre, List<ViolacionDePolitica> violaciones) {
        return new ResultadoDeCreacion(false, nombre, violaciones);
    }
}

final class ErroresDePolitica {

    private ErroresDePolitica() { }

    /** ¿Es un rechazo de Azure Policy (en la raíz o anidado)? */
    static boolean esRechazoDePolitica(ManagementException e) {
        return e.getValue() != null && contieneRechazo(e.getValue());
    }

    private static boolean contieneRechazo(ManagementError error) {
        if ("RequestDisallowedByPolicy".equalsIgnoreCase(error.getCode())) {
            return true;
        }
        if (error.getDetails() != null) {
            for (ManagementError hijo : error.getDetails()) {
                if (contieneRechazo(hijo)) {
                    return true;
                }
            }
        }
        return false;
    }

    /** Extrae todas las violaciones (asignación, definición, efecto) del árbol de errores. */
    static List<ViolacionDePolitica> violaciones(ManagementException e) {
        List<ViolacionDePolitica> resultado = new ArrayList<>();
        if (e.getValue() != null) {
            recorrer(e.getValue(), resultado);
        }
        return resultado;
    }

    static List<ViolacionDePolitica> violaciones(ManagementError error) {
        List<ViolacionDePolitica> resultado = new ArrayList<>();
        recorrer(error, resultado);
        return resultado;
    }

    private static void recorrer(ManagementError error, List<ViolacionDePolitica> salida) {
        if (error.getAdditionalInfo() != null) {
            for (AdditionalInfo info : error.getAdditionalInfo()) {
                if ("PolicyViolation".equalsIgnoreCase(info.getType()) && info.getInfo() instanceof Map<?, ?> campos) {
                    salida.add(new ViolacionDePolitica(
                            texto(campos, "policyAssignmentDisplayName", "policyAssignmentName"),
                            texto(campos, "policyDefinitionDisplayName", "policyDefinitionName"),
                            texto(campos, "policyDefinitionReferenceId"),
                            texto(campos, "policyDefinitionEffect"),
                            texto(campos, "policyAssignmentScope")));
                }
            }
        }
        if (error.getDetails() != null) {
            for (ManagementError hijo : error.getDetails()) {
                recorrer(hijo, salida);
            }
        }
    }

    private static String texto(Map<?, ?> campos, String... nombres) {
        for (String nombre : nombres) {
            Object valor = campos.get(nombre);
            if (valor != null && !valor.toString().isBlank()) {
                return valor.toString();
            }
        }
        return null;
    }
}
```

## 2. Cumplimiento: resumen, incumplimientos y Resource Graph

Dos fuentes con propósitos distintos:
- **PolicyInsights:** el estado de cumplimiento oficial (resumen por asignación, estados por recurso, evaluación bajo demanda).
- **Resource Graph:** consultas flexibles sobre **todo el inventario** y la tabla `policyresources`, a escala de muchas suscripciones (ver [KQL](ejemplos/kql/kql-policy.md)).

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.http.rest.PagedIterable;
import com.azure.core.util.Context;
import com.azure.resourcemanager.policyinsights.PolicyInsightsManager;
import com.azure.resourcemanager.policyinsights.models.PolicyAssignmentSummary;
import com.azure.resourcemanager.policyinsights.models.PolicyState;
import com.azure.resourcemanager.policyinsights.models.PolicyStatesResource;
import com.azure.resourcemanager.policyinsights.models.PolicyStatesSummaryResourceType;
import com.azure.resourcemanager.policyinsights.models.SummarizeResults;
import com.azure.resourcemanager.policyinsights.models.Summary;
import com.azure.resourcemanager.policyinsights.models.SummaryResults;
import com.azure.resourcemanager.resourcegraph.ResourceGraphManager;
import com.azure.resourcemanager.resourcegraph.models.QueryRequest;
import com.azure.resourcemanager.resourcegraph.models.QueryRequestOptions;
import com.azure.resourcemanager.resourcegraph.models.QueryResponse;
import com.azure.resourcemanager.resourcegraph.models.ResultFormat;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

record ResumenDeCumplimiento(int recursosNoConformes, int politicasNoConformes, List<PorAsignacion> asignaciones) {

    record PorAsignacion(String asignacion, int recursosNoConformes) { }
}

record Incumplimiento(String recurso, String tipo, String asignacion, String politica, String referencia) { }

class CumplimientoServicio {

    private final PolicyInsightsManager insights;
    private final ResourceGraphManager grafo;
    private final String suscripcion;

    CumplimientoServicio(PolicyInsightsManager insights, ResourceGraphManager grafo, String suscripcion) {
        this.insights = insights;
        this.grafo = grafo;
        this.suscripcion = suscripcion;
    }

    /** Resumen de la suscripción: totales y por asignación. */
    ResumenDeCumplimiento resumen() {
        SummarizeResults resultados = insights.policyStates()
                .summarizeForSubscription(PolicyStatesSummaryResourceType.LATEST, suscripcion);
        if (resultados.value() == null || resultados.value().isEmpty()) {
            return new ResumenDeCumplimiento(0, 0, List.of());
        }
        Summary resumen = resultados.value().get(0);
        SummaryResults totales = resumen.results();
        List<ResumenDeCumplimiento.PorAsignacion> porAsignacion = new ArrayList<>();
        if (resumen.policyAssignments() != null) {
            for (PolicyAssignmentSummary a : resumen.policyAssignments()) {
                int noConformes = a.results() == null || a.results().nonCompliantResources() == null
                        ? 0 : a.results().nonCompliantResources();
                porAsignacion.add(new ResumenDeCumplimiento.PorAsignacion(ultimoSegmento(a.policyAssignmentId()), noConformes));
            }
        }
        return new ResumenDeCumplimiento(
                valor(totales == null ? null : totales.nonCompliantResources()),
                valor(totales == null ? null : totales.nonCompliantPolicies()),
                porAsignacion);
    }

    /** Los primeros N recursos no conformes (usa el filtro del servicio, no filtres en memoria). */
    List<Incumplimiento> incumplimientos(int maximo) {
        PagedIterable<PolicyState> estados = insights.policyStates().listQueryResultsForSubscription(
                PolicyStatesResource.LATEST, suscripcion,
                maximo, null,
                "resourceId,resourceType,policyAssignmentName,policyDefinitionName,policyDefinitionReferenceId",
                null, null,
                "complianceState eq 'NonCompliant'", null, null, Context.NONE);
        List<Incumplimiento> lista = new ArrayList<>();
        for (PolicyState estado : estados) {
            lista.add(new Incumplimiento(estado.resourceId(), estado.resourceType(), estado.policyAssignmentName(),
                    estado.policyDefinitionName(), estado.policyDefinitionReferenceId()));
            if (lista.size() >= maximo) {
                break;
            }
        }
        return lista;
    }

    /** Consulta de Resource Graph (KQL) y devuelve filas como mapas. */
    @SuppressWarnings("unchecked")
    List<Map<String, Object>> consultar(String kql, int maximo) {
        QueryResponse respuesta = grafo.resourceProviders().resources(new QueryRequest()
                .withQuery(kql)
                .withSubscriptions(List.of(suscripcion))
                .withOptions(new QueryRequestOptions()
                        .withResultFormat(ResultFormat.OBJECT_ARRAY)
                        .withTop(maximo)));
        return respuesta.data() instanceof List<?> filas ? (List<Map<String, Object>>) filas : List.of();
    }

    /** Fuerza una evaluación de toda la suscripción. Puede tardar minutos: no lo llames dentro de una solicitud HTTP. */
    void evaluarAhora() {
        insights.policyStates().triggerSubscriptionEvaluation(suscripcion);
    }

    private static int valor(Integer numero) {
        return numero == null ? 0 : numero;
    }

    private static String ultimoSegmento(String id) {
        return id == null ? null : id.substring(id.lastIndexOf('/') + 1);
    }
}
```
Ejemplos de uso de `consultar`: las consultas A1–B6 del archivo de [KQL](ejemplos/kql/kql-policy.md); por ejemplo, las cuentas de almacenamiento con acceso público: `consultar("resources | where type =~ 'microsoft.storage/storageaccounts' | where tostring(properties.publicNetworkAccess) != 'Disabled' | project name, resourceGroup", 200)`.

## 3. Autoservicio de entornos: convertir `RequestDisallowedByPolicy` en un mensaje útil

El caso más común para un equipo de aplicaciones: un servicio que **crea recursos** (un grupo de recursos por cliente, por ejemplo). Si una política lo rechaza, el usuario debe saber **qué regla** y **qué cambiar**, no ver un 500.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.management.exception.ManagementException;
import com.azure.resourcemanager.resources.ResourceManager;
import com.azure.resourcemanager.resources.models.ResourceGroup;

import java.util.Map;

/** Lo que pide el usuario: nombre del entorno, región y etiquetas. */
record SolicitudDeEntorno(String nombre, String region, Map<String, String> etiquetas) { }

class AutoservicioDeEntornos {

    private final ResourceManager recursos;

    AutoservicioDeEntornos(ResourceManager recursos) {
        this.recursos = recursos;
    }

    /** Crea el grupo de recursos del cliente con las etiquetas obligatorias. */
    ResultadoDeCreacion crearEntorno(String nombre, String region, Map<String, String> etiquetas) {
        try {
            ResourceGroup grupo = recursos.resourceGroups().define(nombre)
                    .withRegion(region)
                    .withTags(etiquetas)
                    .create();
            return ResultadoDeCreacion.ok(grupo.name());
        } catch (ManagementException e) {
            if (ErroresDePolitica.esRechazoDePolitica(e)) {
                return ResultadoDeCreacion.rechazado(nombre, ErroresDePolitica.violaciones(e));
            }
            throw e;      // cualquier otro error (permisos, cuota, red) no es una política
        }
    }
}
```

La conversión a HTTP: **422** con `ProblemDetail` (RFC 9457) que lista las reglas. Así el front puede mostrar "falta la etiqueta `cost-center`" en lugar de un error genérico.

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/gobierno")
class GobiernoControlador {

    private final CumplimientoServicio cumplimiento;
    private final AutoservicioDeEntornos autoservicio;

    GobiernoControlador(CumplimientoServicio cumplimiento, AutoservicioDeEntornos autoservicio) {
        this.cumplimiento = cumplimiento;
        this.autoservicio = autoservicio;
    }

    @GetMapping("/cumplimiento")
    ResumenDeCumplimiento resumen() {
        return cumplimiento.resumen();
    }

    @GetMapping("/incumplimientos")
    List<Incumplimiento> incumplimientos(@RequestParam(defaultValue = "100") int max) {
        return cumplimiento.incumplimientos(Math.min(max, 500));
    }

    @PostMapping("/entornos")
    ResponseEntity<?> crearEntorno(@RequestBody SolicitudDeEntorno solicitud) {
        ResultadoDeCreacion resultado = autoservicio.crearEntorno(solicitud.nombre(), solicitud.region(), solicitud.etiquetas());
        if (resultado.creado()) {
            return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("nombre", resultado.nombre()));
        }
        ProblemDetail problema = ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY,
                "La organización rechazó el entorno por " + resultado.violaciones().size() + " regla(s) de gobierno.");
        problema.setTitle("Rechazado por una política de Azure");
        problema.setProperty("violaciones", resultado.violaciones());
        return ResponseEntity.unprocessableEntity().body(problema);
    }
}
```

## 4. Métrica de cumplimiento en Micrometer (refresco en segundo plano)

El resumen de cumplimiento cambia cada pocas horas. **No lo consultes en cada solicitud**: refréscalo cada 15 minutos y expón un *gauge* para Prometheus/Azure Monitor y para alertas ("más de 20 recursos no conformes").

```java
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicInteger;

@Component
@EnableScheduling
class MetricasDeCumplimiento {

    private final CumplimientoServicio cumplimiento;
    private final AtomicInteger recursosNoConformes = new AtomicInteger();
    private final AtomicInteger politicasNoConformes = new AtomicInteger();

    MetricasDeCumplimiento(MeterRegistry registro, CumplimientoServicio cumplimiento) {
        this.cumplimiento = cumplimiento;
        Gauge.builder("modalima.politicas.recursos_no_conformes", recursosNoConformes, AtomicInteger::get).register(registro);
        Gauge.builder("modalima.politicas.politicas_no_conformes", politicasNoConformes, AtomicInteger::get).register(registro);
    }

    @Scheduled(initialDelayString = "PT30S", fixedDelayString = "PT15M")
    void refrescar() {
        try {
            ResumenDeCumplimiento resumen = cumplimiento.resumen();
            recursosNoConformes.set(resumen.recursosNoConformes());
            politicasNoConformes.set(resumen.politicasNoConformes());
        } catch (RuntimeException e) {
            // conserva el último valor: un fallo de ARM no debe borrar la métrica
        }
    }
}
```

## 5. Exenciones con caducidad desde un flujo de aprobación

Una exención sin fecha es una puerta abierta para siempre. Este servicio **obliga** a poner fecha (máximo 90 días), motivo y solicitante, y limita la exención a **reglas concretas** de la iniciativa.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.resources.ResourceManager;
import com.azure.resourcemanager.resources.fluent.models.PolicyExemptionInner;
import com.azure.resourcemanager.resources.models.ExemptionCategory;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

class ExencionServicio {

    private static final int MAXIMO_DIAS = 90;

    private final ResourceManager recursos;

    ExencionServicio(ResourceManager recursos) {
        this.recursos = recursos;
    }

    /**
     * @param alcance      p. ej. /subscriptions/{id}/resourceGroups/rg-cliente-42
     * @param asignacionId id de la asignación de la iniciativa
     * @param referencias  reglas de la iniciativa a eximir (policyDefinitionReferenceId); no vacío
     */
    PolicyExemptionInner crear(String alcance, String nombre, String asignacionId, List<String> referencias,
                               String motivo, String solicitante, int dias) {
        if (dias < 1 || dias > MAXIMO_DIAS) {
            throw new IllegalArgumentException("La exención debe durar entre 1 y " + MAXIMO_DIAS + " días");
        }
        if (referencias == null || referencias.isEmpty()) {
            throw new IllegalArgumentException("Indica qué reglas se eximen; no se permiten exenciones de toda la iniciativa");
        }
        if (motivo == null || motivo.isBlank()) {
            throw new IllegalArgumentException("El motivo es obligatorio");
        }
        PolicyExemptionInner exencion = new PolicyExemptionInner()
                .withPolicyAssignmentId(asignacionId)
                .withPolicyDefinitionReferenceIds(referencias)
                .withExemptionCategory(ExemptionCategory.WAIVER)
                .withDisplayName("Exención temporal: " + nombre)
                .withDescription(motivo)
                .withExpiresOn(OffsetDateTime.now(ZoneOffset.UTC).plusDays(dias))
                .withMetadata(Map.of("solicitadoPor", solicitante));
        return recursos.policyClient().getPolicyExemptions().createOrUpdate(alcance, nombre, exencion);
    }

    void eliminar(String alcance, String nombre) {
        recursos.policyClient().getPolicyExemptions().delete(alcance, nombre);
    }
}
```

## 6. Clientes de Azure (un solo `TokenCredential` y un solo perfil)

`DefaultAzureCredential` toma la identidad administrada en Azure y tu sesión de `az login` en el computador. Un **perfil** (`AzureProfile`) indica tenant, suscripción y nube. Crea **un administrador por servicio** y reutilízalo.

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.policyinsights.PolicyInsightsManager;
import com.azure.resourcemanager.resourcegraph.ResourceGraphManager;
import com.azure.resourcemanager.resources.ResourceManager;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class AzureGobiernoConfig {

    @Bean
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Bean
    AzureProfile perfil(@Value("${azure.tenant-id}") String tenant,
                        @Value("${azure.subscription-id}") String suscripcion) {
        return new AzureProfile(tenant, suscripcion, AzureEnvironment.AZURE);
    }

    @Bean
    ResourceManager recursos(TokenCredential credencial, AzureProfile perfil) {
        return ResourceManager.authenticate(credencial, perfil).withDefaultSubscription();
    }

    @Bean
    PolicyInsightsManager insights(TokenCredential credencial, AzureProfile perfil) {
        return PolicyInsightsManager.authenticate(credencial, perfil);
    }

    @Bean
    ResourceGraphManager grafo(TokenCredential credencial, AzureProfile perfil) {
        return ResourceGraphManager.authenticate(credencial, perfil);
    }

    @Bean
    CumplimientoServicio cumplimiento(PolicyInsightsManager insights, ResourceGraphManager grafo,
                                      @Value("${azure.subscription-id}") String suscripcion) {
        return new CumplimientoServicio(insights, grafo, suscripcion);
    }

    @Bean
    ExencionServicio exenciones(ResourceManager recursos) {
        return new ExencionServicio(recursos);
    }

    @Bean
    AutoservicioDeEntornos autoservicio(ResourceManager recursos) {
        return new AutoservicioDeEntornos(recursos);
    }
}
```
```yaml
# application.yml
azure:
  tenant-id: ${AZURE_TENANT_ID}
  subscription-id: ${AZURE_SUBSCRIPTION_ID}
```

## 7. Spring WebFlux (reactivo): envolver los SDK bloqueantes

Los SDK de administración son **bloqueantes**. En WebFlux nunca los llames directamente en el hilo de eventos: envuélvelos en `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`. Con Java 21 también puedes usar **hilos virtuales** (`spring.threads.virtual.enabled=true`) y escribir código imperativo.

```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.util.List;

@RestController
@RequestMapping("/reactivo/gobierno")
class GobiernoReactivoControlador {

    private final CumplimientoServicio cumplimiento;
    private final AutoservicioDeEntornos autoservicio;

    GobiernoReactivoControlador(CumplimientoServicio cumplimiento, AutoservicioDeEntornos autoservicio) {
        this.cumplimiento = cumplimiento;
        this.autoservicio = autoservicio;
    }

    @GetMapping("/cumplimiento")
    Mono<ResumenDeCumplimiento> resumen() {
        return Mono.fromCallable(cumplimiento::resumen).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/incumplimientos")
    Mono<List<Incumplimiento>> incumplimientos() {
        return Mono.fromCallable(() -> cumplimiento.incumplimientos(100)).subscribeOn(Schedulers.boundedElastic());
    }

    @PostMapping("/entornos")
    Mono<ResultadoDeCreacion> crear(@RequestBody SolicitudDeEntorno solicitud) {
        return Mono.fromCallable(() -> autoservicio.crearEntorno(solicitud.nombre(), solicitud.region(), solicitud.etiquetas()))
                .subscribeOn(Schedulers.boundedElastic());
    }
}
```

## 8. Quarkus · imperativo

Productores CDI para los administradores de Azure y un recurso REST con la misma lógica compartida (las clases de las secciones 1, 3, 4 y 6 no dependen de ningún marco).

```java
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.policyinsights.PolicyInsightsManager;
import com.azure.resourcemanager.resourcegraph.ResourceGraphManager;
import com.azure.resourcemanager.resources.ResourceManager;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AzureGobiernoProductores {

    @ConfigProperty(name = "azure.tenant-id")
    String tenant;

    @ConfigProperty(name = "azure.subscription-id")
    String suscripcion;

    @Produces
    @Singleton
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Produces
    @Singleton
    AzureProfile perfil() {
        return new AzureProfile(tenant, suscripcion, AzureEnvironment.AZURE);
    }

    @Produces
    @Singleton
    CumplimientoServicio cumplimiento(TokenCredential credencial, AzureProfile perfil) {
        return new CumplimientoServicio(
                PolicyInsightsManager.authenticate(credencial, perfil),
                ResourceGraphManager.authenticate(credencial, perfil),
                suscripcion);
    }

    @Produces
    @Singleton
    AutoservicioDeEntornos autoservicio(TokenCredential credencial, AzureProfile perfil) {
        return new AutoservicioDeEntornos(ResourceManager.authenticate(credencial, perfil).withDefaultSubscription());
    }
}
```

```java
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;
import java.util.Map;

@Path("/gobierno")
@Produces(MediaType.APPLICATION_JSON)
class GobiernoRecurso {

    @Inject
    CumplimientoServicio cumplimiento;

    @Inject
    AutoservicioDeEntornos autoservicio;

    @GET
    @Path("/cumplimiento")
    ResumenDeCumplimiento resumen() {
        return cumplimiento.resumen();
    }

    @GET
    @Path("/incumplimientos")
    List<Incumplimiento> incumplimientos(@QueryParam("max") Integer max) {
        return cumplimiento.incumplimientos(Math.min(max == null ? 100 : max, 500));
    }

    @POST
    @Path("/entornos")
    @Consumes(MediaType.APPLICATION_JSON)
    Response crear(SolicitudDeEntorno peticion) {
        ResultadoDeCreacion resultado = autoservicio.crearEntorno(peticion.nombre(), peticion.region(), peticion.etiquetas());
        return resultado.creado()
                ? Response.status(Response.Status.CREATED).entity(Map.of("nombre", resultado.nombre())).build()
                : Response.status(422).entity(Map.of(
                        "titulo", "Rechazado por una política de Azure",
                        "violaciones", resultado.violaciones())).build();
    }
}
```

## 9. Quarkus · reactivo (Mutiny)

Para no bloquear el hilo de eventos, ejecuta la llamada del SDK en el *pool* de trabajadores y devuelve un `Uni`. (Con Java 21 también está `@RunOnVirtualThread` en recursos imperativos, que suele ser más simple para SDK bloqueantes.)

```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.util.List;

@Path("/reactivo/gobierno")
@Produces(MediaType.APPLICATION_JSON)
class GobiernoRecursoReactivo {

    @Inject
    CumplimientoServicio cumplimiento;

    @GET
    @Path("/cumplimiento")
    Uni<ResumenDeCumplimiento> resumen() {
        return Uni.createFrom().item(cumplimiento::resumen)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/incumplimientos")
    Uni<List<Incumplimiento>> incumplimientos() {
        return Uni.createFrom().item(() -> cumplimiento.incumplimientos(100))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 10. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Lector de errores** | Prueba unitaria con el **JSON real** de un `RequestDisallowedByPolicy` (guárdalo de un rechazo verdadero) | Sin red; valida que tu parser tolera campos ausentes y errores anidados |
| **Servicios** | Doble de `PolicyInsightsManager` o una interfaz delante de `CumplimientoServicio` | Los SDK de administración no tienen emulador |
| **Integración** | Suscripción de laboratorio con una asignación en modo `Deny` y un grupo de recursos sin etiqueta | Comprueba el 422 de extremo a extremo |
| **Política** | Despliegues de prueba que **deben fallar** y otros que **deben pasar** en cada cambio de la iniciativa | Se ejecuta en el *pipeline* de la política como código |

```java
// nocheck — requiere JUnit 5
class ErroresDePoliticaTest {

    @Test
    void leeLaViolacionDeUnRechazoReal() throws Exception {
        String json = """
            {"code":"RequestDisallowedByPolicy","target":"rg-cliente-42","message":"Resource was disallowed by policy.",
             "additionalInfo":[{"type":"PolicyViolation","info":{
               "policyDefinitionDisplayName":"ModaLima - Exigir etiqueta en recursos",
               "policyDefinitionReferenceId":"net12-etiqueta-cost-center",
               "policyDefinitionEffect":"deny",
               "policyAssignmentName":"modalima-guardarrailes",
               "policyAssignmentScope":"/subscriptions/00000000-0000-0000-0000-000000000000"}}]}
            """;
        ManagementError error = ManagementError.fromJson(JsonProviders.createReader(json));

        List<ViolacionDePolitica> violaciones = ErroresDePolitica.violaciones(error);

        assertEquals(1, violaciones.size());
        assertEquals("net12-etiqueta-cost-center", violaciones.get(0).referencia());
    }
}
```

## 11. Buenas prácticas de código

- **Identidad administrada**, nunca claves ni *secrets* de aplicación en la configuración.
- **Un administrador por servicio y por proceso** (singleton); los clientes son seguros entre hilos.
- **Cachea y refresca en segundo plano**: ARM tiene cuotas de lectura y los resultados cambian cada pocas horas.
- **Filtra en el servicio** (`$filter`, Resource Graph), no traigas todo para filtrar en memoria; pagina con `PagedIterable`.
- Trata **`RequestDisallowedByPolicy`** como un resultado esperable (422 con detalle), no como un fallo del servidor; deja pasar los demás errores.
- **Exenciones**: con fecha, motivo, solicitante y reglas concretas; registra quién las pidió y quién las aprobó.
- No intentes "adivinar" una política en tu código para saltarte la validación: si el rechazo es legítimo, corrige la solicitud.
- En reactivo, **no bloquees** el hilo de eventos: `boundedElastic` / pool de trabajadores / hilos virtuales.
- Registra el **identificador de correlación** de la solicitud (`x-ms-correlation-request-id`) para el soporte y el registro de actividad.
