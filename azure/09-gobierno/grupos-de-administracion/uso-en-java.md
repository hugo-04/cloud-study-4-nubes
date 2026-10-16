# Azure · Grupos de administración · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3, `azure-core` 1.60, `azure-resourcemanager-resourcegraph` 1.1.0**. Verifica las vigentes.

## La situación del SDK (dicha con honestidad)

El paquete oficial de Java para grupos de administración, `azure-resourcemanager-managementgroups`, **solo existe en versión beta** (`1.0.0-beta.2`, última publicación a finales de 2024). Un servicio de producción no debería depender de una beta. Por eso este documento usa dos piezas estables:

| Necesidad | Qué usamos | Por qué |
|---|---|---|
| **Leer** inventario a escala (suscripciones por grupo, suscripciones bajo la raíz) | **Resource Graph** (`azure-resourcemanager-resourcegraph`, estable) con la tabla `resourcecontainers` | Una consulta devuelve miles de filas, con alcance por grupo |
| **Leer y escribir** la jerarquía (árbol, crear grupo, mover suscripción, ajustes de la raíz) | **REST de ARM con el *pipeline* de `azure-core`** (autenticación, reintentos y registro ya resueltos) | Las operaciones son pocas y bien documentadas; sin depender de una beta |

> Si más adelante el paquete sale de beta, cambiar `GruposDeAdministracionClient` por el SDK no toca al resto del código. Mientras tanto, **no mezcles versiones beta en producción sin una decisión explícita.**

Qué hace tu aplicación Java con los grupos (casos de **plataforma**, no de negocio):

| Caso | Qué haces desde Java |
|---|---|
| **Alta de suscripciones** | Tras crear la suscripción, ubicarla en su grupo (Corp/Online) y verificar que quedó |
| **Movimientos controlados** | Mover una suscripción con ticket aprobado, validando que el destino existe en la jerarquía |
| **Revisión de higiene** | Detectar grupos vacíos, jerarquías demasiado profundas, grupos por entorno, suscripciones bajo la raíz |
| **Panel / métricas** | Contar suscripciones por grupo y hallazgos; exponerlos a Prometheus |
| **Ajustes de la raíz** | Leer (y, con mucho control, cambiar) el grupo predeterminado |

> Son SDK/REST **de administración** (plano de control): latencias de cientos de milisegundos y cuotas de ARM. **No van en el camino caliente** de una API de clientes. Y la jerarquía se cambia **por código y revisión**; un servicio Java que mueve suscripciones debe exigir un ticket aprobado.

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-resources</artifactId></dependency> <!-- trae azure-core-management -->
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-resourcegraph</artifactId><version>1.1.0</version></dependency>
```

**Permisos de la identidad de la aplicación** (identidad administrada, sin claves):

| Operación | Rol mínimo | Alcance |
|---|---|---|
| Leer la jerarquía y Resource Graph | *Management Group Reader* (o *Reader*) | Raíz intermedia |
| Crear grupos | *Management Group Contributor* | Padre del nuevo grupo |
| Mover suscripciones | Permisos de movimiento del [README §2.5](README.md#25-mover-suscripciones-y-grupos) en origen, destino y suscripción | Los tres lugares |
| Leer/cambiar ajustes de la raíz | *Hierarchy Settings Administrator* | Raíz del tenant (solo para el proceso de gobierno; **no** para servicios de lectura) |

## 1. Cliente REST de la jerarquía

Una sola clase, sin marcos, que usa el *pipeline* de `azure-core`:
- **Autenticación:** `ArmChallengeAuthenticationPolicy` con el alcance `https://management.azure.com/.default` (renueva el token sola).
- **Reintentos:** `RetryPolicy` (errores transitorios y limitación de ARM).
- **JSON:** `azure-json` (ya viene con el SDK; evita ligar el código a Jackson 2 o 3, que cambia entre Spring y Quarkus).
- **Errores:** cualquier respuesta fuera de lo esperado se convierte en `ErrorDeGruposDeAdministracion` con estado y código de ARM.

Las API usadas (`api-version=2021-04-01`): `GET …/managementGroups/{id}?$expand=children&$recurse=true`, `PUT …/managementGroups/{id}`, `PUT/DELETE …/managementGroups/{id}/subscriptions/{sub}` y `GET/PUT …/managementGroups/{raíz}/settings`. **Crear un grupo es asíncrono** (ARM responde 202): si lo necesitas de inmediato, vuelve a leer hasta que aparezca.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.credential.TokenCredential;
import com.azure.core.http.HttpMethod;
import com.azure.core.http.HttpPipeline;
import com.azure.core.http.HttpPipelineBuilder;
import com.azure.core.http.HttpRequest;
import com.azure.core.http.HttpResponse;
import com.azure.core.http.policy.RetryPolicy;
import com.azure.core.management.http.policy.ArmChallengeAuthenticationPolicy;
import com.azure.core.util.BinaryData;
import com.azure.core.util.Context;
import com.azure.json.JsonProviders;
import com.azure.json.JsonWriter;

import java.io.IOException;
import java.io.StringWriter;
import java.io.UncheckedIOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

/** Un elemento de la jerarquía: un grupo o una suscripción. */
record Nodo(String tipo, String id, String nombre, String nombreVisible, List<Nodo> hijos) {

    boolean esGrupo() {
        return tipo != null && tipo.toLowerCase(Locale.ROOT).endsWith("/managementgroups");
    }

    boolean esSuscripcion() {
        return tipo != null && tipo.toLowerCase(Locale.ROOT).endsWith("/subscriptions");
    }
}

/** Ajustes de la raíz del tenant. */
record AjustesDeJerarquia(String grupoPredeterminado, boolean exigirAutorizacion) { }

/** Error devuelto por ARM al operar sobre la jerarquía. */
class ErrorDeGruposDeAdministracion extends RuntimeException {

    private final int estado;
    private final String codigo;

    ErrorDeGruposDeAdministracion(int estado, String codigo, String mensaje) {
        super("ARM " + estado + " " + codigo + ": " + mensaje);
        this.estado = estado;
        this.codigo = codigo;
    }

    int estado() {
        return estado;
    }

    String codigo() {
        return codigo;
    }
}

final class GruposDeAdministracionClient {

    private static final String API = "2021-04-01";
    private static final String PREFIJO = "/providers/Microsoft.Management/managementGroups/";

    private final HttpPipeline pipeline;
    private final String endpoint;

    GruposDeAdministracionClient(HttpPipeline pipeline, String endpoint) {
        this.pipeline = pipeline;
        this.endpoint = endpoint;
    }

    /** Cliente real: reintentos y autenticación de ARM. */
    static GruposDeAdministracionClient crear(TokenCredential credencial) {
        HttpPipeline pipeline = new HttpPipelineBuilder()
                .policies(new RetryPolicy(),
                        new ArmChallengeAuthenticationPolicy(credencial, "https://management.azure.com/.default"))
                .build();
        return new GruposDeAdministracionClient(pipeline, "https://management.azure.com");
    }

    /** Árbol completo desde un grupo hacia abajo (grupos y suscripciones). */
    Nodo arbol(String grupoId) {
        Object cuerpo = enviar(HttpMethod.GET, PREFIJO + codificar(grupoId) + "?$expand=children&$recurse=true&api-version=" + API, null, 200);
        Map<String, Object> raiz = mapa(cuerpo);
        Map<String, Object> propiedades = mapa(raiz.get("properties"));
        return new Nodo(texto(raiz, "type"), texto(raiz, "id"), texto(raiz, "name"), texto(propiedades, "displayName"),
                hijos(propiedades.get("children")));
    }

    /** Crea un grupo bajo el padre indicado. ARM responde de forma asíncrona. */
    void crearGrupo(String id, String nombreVisible, String padreId) {
        String cuerpo = json(w -> {
            w.writeStartObject();
            w.writeFieldName("properties").writeStartObject();
            w.writeStringField("displayName", nombreVisible);
            w.writeFieldName("details").writeStartObject();
            w.writeFieldName("parent").writeStartObject();
            w.writeStringField("id", PREFIJO + padreId);
            w.writeEndObject().writeEndObject().writeEndObject().writeEndObject();
        });
        enviar(HttpMethod.PUT, PREFIJO + codificar(id) + "?api-version=" + API, cuerpo, 200, 201, 202);
    }

    /** Mueve una suscripción al grupo (puede tardar hasta 30 minutos en reflejarse en todas partes). */
    void moverSuscripcion(String grupoId, String suscripcionId) {
        enviar(HttpMethod.PUT, PREFIJO + codificar(grupoId) + "/subscriptions/" + codificar(suscripcionId) + "?api-version=" + API, null, 200, 201, 202);
    }

    void quitarSuscripcion(String grupoId, String suscripcionId) {
        enviar(HttpMethod.DELETE, PREFIJO + codificar(grupoId) + "/subscriptions/" + codificar(suscripcionId) + "?api-version=" + API, null, 200, 202, 204);
    }

    /** Ajustes de la raíz del tenant (grupo predeterminado y autorización de creación). */
    Optional<AjustesDeJerarquia> ajustes(String raizDelTenant) {
        Object cuerpo = enviar(HttpMethod.GET, PREFIJO + codificar(raizDelTenant) + "/settings?api-version=" + API, null, 200);
        Object valor = mapa(cuerpo).get("value");
        if (valor instanceof List<?> lista && !lista.isEmpty()) {
            Map<String, Object> propiedades = mapa(mapa(lista.get(0)).get("properties"));
            return Optional.of(new AjustesDeJerarquia(
                    texto(propiedades, "defaultManagementGroup"),
                    Boolean.TRUE.equals(propiedades.get("requireAuthorizationForGroupCreation"))));
        }
        return Optional.empty();
    }

    /** Cambia los ajustes de la raíz. Hazlo solo desde el proceso de gobierno, con revisión. */
    void actualizarAjustes(String raizDelTenant, String grupoPredeterminadoId, boolean exigirAutorizacion) {
        String cuerpo = json(w -> {
            w.writeStartObject();
            w.writeFieldName("properties").writeStartObject();
            w.writeStringField("defaultManagementGroup", PREFIJO + grupoPredeterminadoId);
            w.writeBooleanField("requireAuthorizationForGroupCreation", exigirAutorizacion);
            w.writeEndObject().writeEndObject();
        });
        enviar(HttpMethod.PUT, PREFIJO + codificar(raizDelTenant) + "/settings/default?api-version=" + API, cuerpo, 200, 201);
    }

    // --- Infraestructura -------------------------------------------------------------------------

    private Object enviar(HttpMethod metodo, String ruta, String cuerpo, int... esperados) {
        HttpRequest peticion = new HttpRequest(metodo, endpoint + ruta);
        peticion.setHeader(com.azure.core.http.HttpHeaderName.CONTENT_TYPE, "application/json");
        if (cuerpo != null) {
            peticion.setBody(BinaryData.fromString(cuerpo));
        }
        try (HttpResponse respuesta = pipeline.sendSync(peticion, Context.NONE)) {
            String texto = respuesta.getBodyAsBinaryData().toString();
            for (int esperado : esperados) {
                if (respuesta.getStatusCode() == esperado) {
                    return texto == null || texto.isBlank() ? Map.of() : JsonProviders.createReader(texto).readUntyped();
                }
            }
            throw errorDe(respuesta.getStatusCode(), texto);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static ErrorDeGruposDeAdministracion errorDe(int estado, String texto) {
        String codigo = "Unknown";
        String mensaje = texto == null ? "" : texto;
        try {
            if (texto != null && !texto.isBlank()) {
                Map<String, Object> cuerpo = mapa(JsonProviders.createReader(texto).readUntyped());
                Map<String, Object> error = mapa(cuerpo.getOrDefault("error", cuerpo));
                codigo = texto(error, "code") == null ? codigo : texto(error, "code");
                mensaje = texto(error, "message") == null ? mensaje : texto(error, "message");
            }
        } catch (IOException | RuntimeException ignorado) {
            // el cuerpo no era JSON: se conserva el texto tal cual
        }
        return new ErrorDeGruposDeAdministracion(estado, codigo, mensaje);
    }

    private interface Escritura {
        void escribir(JsonWriter escritor) throws IOException;
    }

    private static String json(Escritura escritura) {
        StringWriter salida = new StringWriter();
        try (JsonWriter escritor = JsonProviders.createWriter(salida)) {
            escritura.escribir(escritor);
            escritor.flush();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return salida.toString();
    }

    private static List<Nodo> hijos(Object valor) {
        List<Nodo> resultado = new ArrayList<>();
        if (valor instanceof List<?> lista) {
            for (Object elemento : lista) {
                Map<String, Object> hijo = mapa(elemento);
                resultado.add(new Nodo(texto(hijo, "type"), texto(hijo, "id"), texto(hijo, "name"), texto(hijo, "displayName"),
                        hijos(hijo.get("children"))));
            }
        }
        return resultado;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> mapa(Object valor) {
        return valor instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
    }

    private static String texto(Map<String, Object> mapa, String clave) {
        Object valor = mapa.get(clave);
        return valor == null ? null : valor.toString();
    }

    private static String codificar(String segmento) {
        return URLEncoder.encode(segmento, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
```

## 2. Revisar la higiene de la jerarquía (función pura y fácil de probar)

Las reglas del [README §2.9](README.md#29-diseño-recomendado) hechas código. Recibe el árbol y devuelve hallazgos; **no llama a Azure**, así que se prueba con un árbol armado a mano.

| Regla | Qué detecta |
|---|---|
| `PROFUNDIDAD` | Grupos a más de 4 niveles (la guía recomienda 3–4; el máximo duro es 6) |
| `GRUPO_VACIO` | Grupos sin hijos ni suscripciones (candidatos a borrar) |
| `PREFIJO` | IDs que no empiezan con el prefijo de la empresa |
| `GRUPO_POR_ENTORNO` | Grupos cuyo nombre indica un entorno (prod, dev, test…): anti-patrón |
| `SUSCRIPCION_EN_LA_RAIZ` | Suscripciones colgando directamente del grupo raíz que se revisa |

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.regex.Pattern;

/** Un problema encontrado en la jerarquía. */
record Hallazgo(String regla, String id, String detalle) { }

final class RevisorDeJerarquia {

    private static final Pattern ENTORNO = Pattern.compile("(?i)(^|[-_ ])(prod|produccion|producción|dev|desarrollo|test|pruebas|qa|uat)([-_ ]|$)");

    private final String prefijo;
    private final int profundidadMaxima;

    RevisorDeJerarquia(String prefijo, int profundidadMaxima) {
        this.prefijo = prefijo;
        this.profundidadMaxima = profundidadMaxima;
    }

    /** Revisa el árbol que empieza en {@code raiz}. Si {@code raiz} es la raíz del tenant, las suscripciones directas se marcan. */
    List<Hallazgo> revisar(Nodo raiz, boolean esRaizDelTenant) {
        List<Hallazgo> hallazgos = new ArrayList<>();
        if (esRaizDelTenant) {
            for (Nodo hijo : raiz.hijos()) {
                if (hijo.esSuscripcion()) {
                    hallazgos.add(new Hallazgo("SUSCRIPCION_EN_LA_RAIZ", hijo.nombre(),
                            "La suscripción '" + hijo.nombreVisible() + "' cuelga de la raíz: muévela a un grupo con reglas"));
                }
            }
        }
        recorrer(raiz, 1, esRaizDelTenant, hallazgos);
        return hallazgos;
    }

    private void recorrer(Nodo grupo, int nivel, boolean esRaiz, List<Hallazgo> hallazgos) {
        if (!esRaiz) {
            if (nivel > profundidadMaxima) {
                hallazgos.add(new Hallazgo("PROFUNDIDAD", grupo.nombre(),
                        "El grupo está en el nivel " + nivel + " (recomendado: hasta " + profundidadMaxima + ")"));
            }
            if (grupo.hijos().isEmpty()) {
                hallazgos.add(new Hallazgo("GRUPO_VACIO", grupo.nombre(), "Sin hijos ni suscripciones: ¿se puede borrar?"));
            }
            if (grupo.nombre() != null && !grupo.nombre().startsWith(prefijo)) {
                hallazgos.add(new Hallazgo("PREFIJO", grupo.nombre(), "El ID no empieza con '" + prefijo + "'"));
            }
            String visible = grupo.nombreVisible() == null ? "" : grupo.nombreVisible();
            if (ENTORNO.matcher(grupo.nombre() == null ? "" : grupo.nombre()).find() || ENTORNO.matcher(visible).find()) {
                hallazgos.add(new Hallazgo("GRUPO_POR_ENTORNO", grupo.nombre(),
                        "Parece un grupo por entorno: separa los entornos en suscripciones dentro del mismo grupo"));
            }
        }
        for (Nodo hijo : grupo.hijos()) {
            if (hijo.esGrupo()) {
                recorrer(hijo, esRaiz ? 1 : nivel + 1, false, hallazgos);
            }
        }
    }
}
```

## 3. Inventario a escala con Resource Graph

Para contar y listar sin recorrer el árbol: una consulta sobre `resourcecontainers`, con el **alcance** en un grupo (`withManagementGroups`). Las filas vuelven como mapas.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.resourcegraph.ResourceGraphManager;
import com.azure.resourcemanager.resourcegraph.models.QueryRequest;
import com.azure.resourcemanager.resourcegraph.models.QueryRequestOptions;
import com.azure.resourcemanager.resourcegraph.models.QueryResponse;
import com.azure.resourcemanager.resourcegraph.models.ResultFormat;

import java.util.LinkedHashMap;

final class InventarioDeGrupos {

    private final ResourceGraphManager grafo;

    InventarioDeGrupos(ResourceGraphManager grafo) {
        this.grafo = grafo;
    }

    /** Suscripciones por grupo directo, dentro del alcance indicado. */
    Map<String, Long> suscripcionesPorGrupo(String grupoDeAlcance) {
        List<Map<String, Object>> filas = consultar(grupoDeAlcance, """
                resourcecontainers
                | where type =~ 'microsoft.resources/subscriptions'
                | extend grupo = tostring(properties.managementGroupAncestorsChain[0].name)
                | summarize total = count() by grupo
                | order by grupo asc
                """, 1000);
        Map<String, Long> resultado = new LinkedHashMap<>();
        for (Map<String, Object> fila : filas) {
            Object total = fila.get("total");
            resultado.put(String.valueOf(fila.get("grupo")), total instanceof Number n ? n.longValue() : 0L);
        }
        return resultado;
    }

    /** Suscripciones que cuelgan directamente del grupo indicado (útil para la raíz del tenant). */
    List<String> suscripcionesDirectas(String grupo) {
        List<Map<String, Object>> filas = consultar(grupo, """
                resourcecontainers
                | where type =~ 'microsoft.resources/subscriptions'
                | extend cadena = properties.managementGroupAncestorsChain
                | where array_length(cadena) >= 1 and tostring(cadena[0].name) == '%s'
                | project subscriptionId, name
                """.formatted(grupo.replace("'", "")), 1000);
        List<String> nombres = new ArrayList<>();
        for (Map<String, Object> fila : filas) {
            nombres.add(fila.get("name") + " (" + fila.get("subscriptionId") + ")");
        }
        return nombres;
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> consultar(String grupoDeAlcance, String kql, int maximo) {
        QueryResponse respuesta = grafo.resourceProviders().resources(new QueryRequest()
                .withQuery(kql)
                .withManagementGroups(List.of(grupoDeAlcance))
                .withOptions(new QueryRequestOptions()
                        .withResultFormat(ResultFormat.OBJECT_ARRAY)
                        .withTop(maximo)));
        return respuesta.data() instanceof List<?> filas ? (List<Map<String, Object>>) filas : List.of();
    }
}
```

## 4. Movimiento controlado de suscripciones

Mover una suscripción **cambia su reglamento** (caso 5 de los [casos reales](casos-reales.md)). El servicio:
1. exige un **ticket aprobado** (`AprobacionDeCambios`: conéctalo a Jira, ServiceNow…);
2. valida que el **destino existe en la jerarquía** (no se fía del texto que llega) y que no es la raíz del tenant;
3. mueve y avisa de la **ventana de 30 minutos** de la caché.

```java
// (clase reutilizada en los bloques siguientes, ambos)

/** Puerta de aprobación de cambios: conéctala a tu herramienta de tickets. */
interface AprobacionDeCambios {
    boolean aprobado(String ticket, String cambio);
}

/** Resultado de un intento de movimiento. */
record ResultadoDeMovimiento(String estado, String suscripcion, String destino, String detalle) { }

final class MovimientoDeSuscripciones {

    private final GruposDeAdministracionClient grupos;
    private final AprobacionDeCambios aprobaciones;
    private final String raizDeLaEmpresa;

    MovimientoDeSuscripciones(GruposDeAdministracionClient grupos, AprobacionDeCambios aprobaciones, String raizDeLaEmpresa) {
        this.grupos = grupos;
        this.aprobaciones = aprobaciones;
        this.raizDeLaEmpresa = raizDeLaEmpresa;
    }

    ResultadoDeMovimiento mover(String suscripcionId, String destinoId, String ticket) {
        if (ticket == null || !aprobaciones.aprobado(ticket, "mover " + suscripcionId + " a " + destinoId)) {
            return new ResultadoDeMovimiento("NO_APROBADO", suscripcionId, destinoId, "El ticket no está aprobado");
        }
        Nodo arbol = grupos.arbol(raizDeLaEmpresa);
        if (buscarGrupo(arbol, destinoId).isEmpty()) {
            return new ResultadoDeMovimiento("DESTINO_INEXISTENTE", suscripcionId, destinoId,
                    "El grupo no existe bajo '" + raizDeLaEmpresa + "'");
        }
        try {
            grupos.moverSuscripcion(destinoId, suscripcionId);
        } catch (ErrorDeGruposDeAdministracion e) {
            return new ResultadoDeMovimiento("RECHAZADO_POR_AZURE", suscripcionId, destinoId, e.codigo() + ": " + e.getMessage());
        }
        return new ResultadoDeMovimiento("MOVIDA", suscripcionId, destinoId,
                "Movimiento enviado. La jerarquía puede tardar hasta 30 minutos en reflejarse y las políticas del nuevo grupo se evalúan después");
    }

    private static Optional<Nodo> buscarGrupo(Nodo nodo, String id) {
        if (nodo.esGrupo() && id.equalsIgnoreCase(nodo.nombre())) {
            return Optional.of(nodo);
        }
        for (Nodo hijo : nodo.hijos()) {
            Optional<Nodo> encontrado = buscarGrupo(hijo, id);
            if (encontrado.isPresent()) {
                return encontrado;
            }
        }
        return Optional.empty();
    }
}
```

## 5. Métrica: hallazgos de la jerarquía (refresco en segundo plano)

El recorrido toca ARM: **no lo hagas en cada solicitud**. Refréscalo cada 30 minutos y expón *gauges* para alertar ("hay suscripciones bajo la raíz", "hay grupos por entorno").

```java
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicInteger;

@Component
@EnableScheduling
class MetricasDeJerarquia {

    private final GruposDeAdministracionClient grupos;
    private final RevisorDeJerarquia revisor;
    private final String raiz;
    private final AtomicInteger hallazgos = new AtomicInteger();
    private final AtomicInteger suscripcionesEnLaRaiz = new AtomicInteger();

    MetricasDeJerarquia(MeterRegistry registro, GruposDeAdministracionClient grupos, RevisorDeJerarquia revisor,
                        org.springframework.core.env.Environment entorno) {
        this.grupos = grupos;
        this.revisor = revisor;
        this.raiz = entorno.getProperty("gobierno.grupos.raiz", "mg-modalima");
        Gauge.builder("modalima.grupos.hallazgos", hallazgos, AtomicInteger::get).register(registro);
        Gauge.builder("modalima.grupos.suscripciones_en_la_raiz", suscripcionesEnLaRaiz, AtomicInteger::get).register(registro);
    }

    @Scheduled(initialDelayString = "PT1M", fixedDelayString = "PT30M")
    void refrescar() {
        try {
            List<Hallazgo> encontrados = revisor.revisar(grupos.arbol(raiz), false);
            hallazgos.set(encontrados.size());
            suscripcionesEnLaRaiz.set((int) encontrados.stream().filter(h -> h.regla().equals("SUSCRIPCION_EN_LA_RAIZ")).count());
        } catch (RuntimeException e) {
            // conserva el último valor: un fallo de ARM no debe borrar la métrica
        }
    }
}
```

## 6. Clientes de Azure (un solo `TokenCredential`)

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class AzureGruposConfig {

    @Bean
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Bean
    GruposDeAdministracionClient grupos(TokenCredential credencial) {
        return GruposDeAdministracionClient.crear(credencial);
    }

    @Bean
    ResourceGraphManager grafo(TokenCredential credencial, @Value("${azure.tenant-id}") String tenant) {
        return ResourceGraphManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE));
    }

    @Bean
    InventarioDeGrupos inventario(ResourceGraphManager grafo) {
        return new InventarioDeGrupos(grafo);
    }

    @Bean
    RevisorDeJerarquia revisor(@Value("${gobierno.grupos.prefijo:mg-modalima}") String prefijo,
                               @Value("${gobierno.grupos.profundidad-maxima:4}") int profundidad) {
        return new RevisorDeJerarquia(prefijo, profundidad);
    }

    @Bean
    MovimientoDeSuscripciones movimientos(GruposDeAdministracionClient grupos, AprobacionDeCambios aprobaciones,
                                          @Value("${gobierno.grupos.raiz:mg-modalima}") String raiz) {
        return new MovimientoDeSuscripciones(grupos, aprobaciones, raiz);
    }
}
```
```yaml
# application.yml
azure:
  tenant-id: ${AZURE_TENANT_ID}
gobierno:
  grupos:
    raiz: mg-modalima
    prefijo: mg-modalima
    profundidad-maxima: 4
```

## 7. Spring MVC: controlador y traducción de errores

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestController
@RequestMapping("/gobierno/jerarquia")
class JerarquiaControlador {

    record PeticionDeMovimiento(String destino, String ticket) { }

    private final GruposDeAdministracionClient grupos;
    private final InventarioDeGrupos inventario;
    private final RevisorDeJerarquia revisor;
    private final MovimientoDeSuscripciones movimientos;

    JerarquiaControlador(GruposDeAdministracionClient grupos, InventarioDeGrupos inventario, RevisorDeJerarquia revisor,
                         MovimientoDeSuscripciones movimientos) {
        this.grupos = grupos;
        this.inventario = inventario;
        this.revisor = revisor;
        this.movimientos = movimientos;
    }

    @GetMapping
    Nodo arbol(@RequestParam(defaultValue = "mg-modalima") String raiz) {
        return grupos.arbol(raiz);
    }

    @GetMapping("/hallazgos")
    List<Hallazgo> hallazgos(@RequestParam(defaultValue = "mg-modalima") String raiz) {
        return revisor.revisar(grupos.arbol(raiz), false);
    }

    @GetMapping("/suscripciones-por-grupo")
    Map<String, Long> porGrupo(@RequestParam(defaultValue = "mg-modalima") String raiz) {
        return inventario.suscripcionesPorGrupo(raiz);
    }

    @PostMapping("/suscripciones/{id}/mover")
    ResponseEntity<ResultadoDeMovimiento> mover(@PathVariable String id, @RequestBody PeticionDeMovimiento peticion) {
        ResultadoDeMovimiento resultado = movimientos.mover(id, peticion.destino(), peticion.ticket());
        HttpStatus estado = switch (resultado.estado()) {
            case "MOVIDA" -> HttpStatus.ACCEPTED;
            case "NO_APROBADO" -> HttpStatus.FORBIDDEN;
            case "DESTINO_INEXISTENTE" -> HttpStatus.NOT_FOUND;
            default -> HttpStatus.CONFLICT;
        };
        return ResponseEntity.status(estado).body(resultado);
    }
}

@RestControllerAdvice
class ErroresDeJerarquiaAdvice {

    @ExceptionHandler(ErrorDeGruposDeAdministracion.class)
    ProblemDetail errorDeAzure(ErrorDeGruposDeAdministracion e) {
        HttpStatus http = switch (e.estado()) {
            case 403 -> HttpStatus.FORBIDDEN;
            case 404 -> HttpStatus.NOT_FOUND;
            case 409 -> HttpStatus.CONFLICT;
            default -> HttpStatus.BAD_GATEWAY;
        };
        ProblemDetail problema = ProblemDetail.forStatusAndDetail(http, "Azure rechazó la operación sobre la jerarquía");
        problema.setProperty("codigoAzure", e.codigo());
        return problema;
    }
}
```

## 8. Spring WebFlux (reactivo): envolver lo bloqueante

`sendSync` y Resource Graph son **bloqueantes**. En WebFlux, envuélvelos con `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`. (Con Java 21 también puedes activar **hilos virtuales** y escribir código imperativo.)

```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/jerarquia")
class JerarquiaReactivoControlador {

    private final GruposDeAdministracionClient grupos;
    private final RevisorDeJerarquia revisor;

    JerarquiaReactivoControlador(GruposDeAdministracionClient grupos, RevisorDeJerarquia revisor) {
        this.grupos = grupos;
        this.revisor = revisor;
    }

    @GetMapping
    Mono<Nodo> arbol(@RequestParam(defaultValue = "mg-modalima") String raiz) {
        return Mono.fromCallable(() -> grupos.arbol(raiz)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/hallazgos")
    Mono<List<Hallazgo>> hallazgos(@RequestParam(defaultValue = "mg-modalima") String raiz) {
        return Mono.fromCallable(() -> revisor.revisar(grupos.arbol(raiz), false)).subscribeOn(Schedulers.boundedElastic());
    }
}
```

## 9. Quarkus · imperativo

Productores CDI y un recurso REST con la misma lógica (las secciones 1 a 4 no dependen de ningún marco).

```java
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AzureGruposProductores {

    @ConfigProperty(name = "azure.tenant-id")
    String tenant;

    @ConfigProperty(name = "gobierno.grupos.prefijo", defaultValue = "mg-modalima")
    String prefijo;

    @ConfigProperty(name = "gobierno.grupos.profundidad-maxima", defaultValue = "4")
    int profundidad;

    @ConfigProperty(name = "gobierno.grupos.raiz", defaultValue = "mg-modalima")
    String raiz;

    @Produces
    @Singleton
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Produces
    @Singleton
    GruposDeAdministracionClient grupos(TokenCredential credencial) {
        return GruposDeAdministracionClient.crear(credencial);
    }

    @Produces
    @Singleton
    InventarioDeGrupos inventario(TokenCredential credencial) {
        return new InventarioDeGrupos(
                ResourceGraphManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE)));
    }

    @Produces
    @Singleton
    RevisorDeJerarquia revisor() {
        return new RevisorDeJerarquia(prefijo, profundidad);
    }

    @Produces
    @Singleton
    MovimientoDeSuscripciones movimientos(GruposDeAdministracionClient grupos, AprobacionDeCambios aprobaciones) {
        return new MovimientoDeSuscripciones(grupos, aprobaciones, raiz);
    }
}
```

```java
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.reactive.server.ServerExceptionMapper;

@Path("/gobierno/jerarquia")
@Produces(MediaType.APPLICATION_JSON)
class JerarquiaRecurso {

    @Inject
    GruposDeAdministracionClient grupos;

    @Inject
    InventarioDeGrupos inventario;

    @Inject
    RevisorDeJerarquia revisor;

    @GET
    Nodo arbol(@QueryParam("raiz") String raiz) {
        return grupos.arbol(raiz == null ? "mg-modalima" : raiz);
    }

    @GET
    @Path("/hallazgos")
    List<Hallazgo> hallazgos(@QueryParam("raiz") String raiz) {
        return revisor.revisar(grupos.arbol(raiz == null ? "mg-modalima" : raiz), false);
    }

    @GET
    @Path("/suscripciones-por-grupo")
    Map<String, Long> porGrupo(@QueryParam("raiz") String raiz) {
        return inventario.suscripcionesPorGrupo(raiz == null ? "mg-modalima" : raiz);
    }

    @ServerExceptionMapper
    Response errorDeAzure(ErrorDeGruposDeAdministracion e) {
        int estado = e.estado() == 403 || e.estado() == 404 || e.estado() == 409 ? e.estado() : 502;
        return Response.status(estado).entity(Map.of(
                "titulo", "Azure rechazó la operación sobre la jerarquía",
                "codigoAzure", e.codigo())).build();
    }
}
```

## 10. Quarkus · reactivo (Mutiny)

```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/reactivo/gobierno/jerarquia")
@Produces(MediaType.APPLICATION_JSON)
class JerarquiaRecursoReactivo {

    @Inject
    GruposDeAdministracionClient grupos;

    @Inject
    RevisorDeJerarquia revisor;

    @GET
    Uni<Nodo> arbol() {
        return Uni.createFrom().item(() -> grupos.arbol("mg-modalima"))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/hallazgos")
    Uni<List<Hallazgo>> hallazgos() {
        return Uni.createFrom().item(() -> revisor.revisar(grupos.arbol("mg-modalima"), false))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 11. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Revisor de higiene** | Árbol armado a mano; una prueba por regla | Sin red; es una función pura |
| **Cliente REST** | Un `HttpClient` falso de azure-core que devuelve respuestas guardadas (el JSON real de un `GET` con `$expand=children`) | Comprueba la ruta, la versión de la API, el cuerpo del `PUT` y la lectura de errores |
| **Movimiento controlado** | Dobles de `GruposDeAdministracionClient` y de `AprobacionDeCambios` | Sin ticket no se llama a Azure; destino inexistente no se mueve |
| **Integración** | Una jerarquía de laboratorio bajo un grupo propio | Única forma de ver los permisos reales y la caché de 30 minutos |

```java
// nocheck — requiere JUnit 5
class RevisorDeJerarquiaTest {

    private final RevisorDeJerarquia revisor = new RevisorDeJerarquia("mg-modalima", 4);

    @Test
    void detectaGruposPorEntornoYVacios() {
        Nodo raiz = grupo("mg-modalima", "ModaLima",
                grupo("mg-modalima-produccion", "Producción"),
                grupo("mg-modalima-corp", "Corp", suscripcion("sub-1")));

        var hallazgos = revisor.revisar(raiz, false);

        assertTrue(hallazgos.stream().anyMatch(h -> h.regla().equals("GRUPO_POR_ENTORNO")));
        assertTrue(hallazgos.stream().anyMatch(h -> h.regla().equals("GRUPO_VACIO")));
    }

    @Test
    void marcaLasSuscripcionesDeLaRaiz() {
        Nodo raiz = grupo("tenant", "Tenant Root Group", suscripcion("sub-huerfana"));

        assertEquals("SUSCRIPCION_EN_LA_RAIZ", revisor.revisar(raiz, true).get(0).regla());
    }

    private static Nodo grupo(String id, String visible, Nodo... hijos) {
        return new Nodo("Microsoft.Management/managementGroups", "/x/" + id, id, visible, List.of(hijos));
    }

    private static Nodo suscripcion(String id) {
        return new Nodo("/subscriptions", "/subscriptions/" + id, id, id, List.of());
    }
}
```

## 12. Buenas prácticas de código

- **Identidad administrada**, nunca claves ni *secrets* en la configuración.
- **No dependas de un paquete beta en producción:** Resource Graph para leer a escala y REST con el *pipeline* de `azure-core` para escribir (con autenticación y reintentos ya resueltos).
- **Valida lo que ARM no valida:** que el grupo de destino exista en tu jerarquía antes de mover o de usarlo como alcance asignable.
- **Mover = cambiar el reglamento:** ticket aprobado, destino validado, aviso de la caché de 30 minutos.
- **Identidades separadas:** lectura (Reader) para inventario; escritura solo para el proceso de gobierno; ajustes de la raíz solo para seguridad.
- **Cachea y refresca en segundo plano** el recorrido de la jerarquía; ARM tiene cuotas de lectura.
- Trata `403`, `404` y `409` de ARM como resultados esperables (con el código de Azure), no como fallos del servidor.
- **Escapa los parámetros:** el ID del grupo va codificado en la ruta y en las consultas KQL se eliminan las comillas.
- En reactivo, **no bloquees** el hilo de eventos: `boundedElastic` / pool de trabajadores / hilos virtuales.
