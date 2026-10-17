# AWS · Organizations y SCP · Uso desde Java

Desde Java casi nunca *ejecutas* una SCP: lo que haces es **herramientas de plataforma** — validar políticas antes de aplicarlas (un error aquí bloquea a toda una OU), generar la SCP de regiones sin errores de transcripción, inventariar el árbol de cuentas y crear políticas de forma idempotente desde un pipeline. Por eso el núcleo común son tres piezas puras y una pequeña fachada del SDK: **validador (`ScpLinter`)**, **generador de la SCP de regiones**, **árbol de la organización** y **`Organizaciones`**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56, `organizations`).

## 1. Configuración
```yaml
# Spring Boot (application.yml) — Organizations es global: región us-east-1, credenciales de la cuenta de administración
# (o del administrador delegado) por la cadena por defecto; nunca claves en archivos.
app:
  gobierno:
    habilitado: true
```
```properties
# Quarkus (application.properties)
# El cliente se crea en un productor (no hay extensión específica): la región se fija en código (us-east-1).
quarkus.arc.remove-unused-beans=false
app.gobierno.habilitado=true
```
Dependencia: `software.amazon.awssdk:organizations` (y `protocol-core`/`json-utils` ya vienen con el SDK). **Esta herramienta corre en la cuenta de administración (o en un administrador delegado) desde un pipeline, no en las cargas de producción.**

## 2. Núcleo común

### 2.1 Validador de SCP
Revisa lo que más duele: estructura, tamaño, `Principal` (no admitido en SCP), `Deny *` sin condición (bloquea a todos), falta de excepción para el rol de emergencia y la SCP de regiones escrita con `Action` en vez de `NotAction`.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;

public final class ScpLinter {
    public enum Nivel { ERROR, AVISO }

    public record Hallazgo(Nivel nivel, String sentencia, String mensaje) {}

    public static final int MAX_CARACTERES = 5_120;

    private ScpLinter() {}

    public static boolean hayErrores(List<Hallazgo> hallazgos) {
        return hallazgos.stream().anyMatch(h -> h.nivel() == Nivel.ERROR);
    }

    public static List<Hallazgo> validar(String documento) {
        List<Hallazgo> r = new ArrayList<>();
        if (documento == null || documento.isBlank()) {
            r.add(new Hallazgo(Nivel.ERROR, "documento", "está vacío"));
            return r;
        }
        int minimo = documento.replaceAll("\\s+", "").length();
        if (minimo > MAX_CARACTERES) {
            r.add(new Hallazgo(Nivel.ERROR, "documento", "excede " + MAX_CARACTERES + " caracteres incluso sin espacios (" + minimo + ")"));
        } else if (documento.length() > MAX_CARACTERES) {
            r.add(new Hallazgo(Nivel.AVISO, "documento", "con espacios supera " + MAX_CARACTERES + ": minimiza el JSON"));
        }
        JsonNode raiz;
        try {
            raiz = JsonNodeParser.create().parse(documento);
        } catch (RuntimeException e) {
            r.add(new Hallazgo(Nivel.ERROR, "documento", "no es JSON válido"));
            return r;
        }
        if (!raiz.isObject()) {
            r.add(new Hallazgo(Nivel.ERROR, "documento", "la raíz debe ser un objeto"));
            return r;
        }
        Map<String, JsonNode> o = raiz.asObject();
        if (texto(o.get("Version")) == null || !texto(o.get("Version")).equals("2012-10-17")) {
            r.add(new Hallazgo(Nivel.ERROR, "documento", "Version debe ser 2012-10-17"));
        }
        JsonNode st = o.get("Statement");
        if (st == null) {
            r.add(new Hallazgo(Nivel.ERROR, "documento", "falta Statement"));
            return r;
        }
        List<JsonNode> sentencias = st.isArray() ? st.asArray() : List.of(st);
        if (sentencias.isEmpty()) {
            r.add(new Hallazgo(Nivel.ERROR, "documento", "Statement está vacío"));
        }
        int n = 0;
        for (JsonNode s : sentencias) {
            revisar(s, ++n, r);
        }
        return r;
    }

    private static void revisar(JsonNode s, int n, List<Hallazgo> r) {
        if (!s.isObject()) {
            r.add(new Hallazgo(Nivel.ERROR, "#" + n, "la sentencia debe ser un objeto"));
            return;
        }
        Map<String, JsonNode> o = s.asObject();
        String id = texto(o.get("Sid")) != null ? texto(o.get("Sid")) : "#" + n;
        if (o.containsKey("Principal") || o.containsKey("NotPrincipal")) {
            r.add(new Hallazgo(Nivel.ERROR, id, "las SCP no admiten Principal ni NotPrincipal"));
        }
        String efecto = texto(o.get("Effect"));
        if (!"Allow".equals(efecto) && !"Deny".equals(efecto)) {
            r.add(new Hallazgo(Nivel.ERROR, id, "Effect debe ser Allow o Deny"));
        }
        boolean tieneAction = o.containsKey("Action");
        if (tieneAction == o.containsKey("NotAction")) {
            r.add(new Hallazgo(Nivel.ERROR, id, "usa Action o NotAction (exactamente uno)"));
        }
        if (!o.containsKey("Resource") && !o.containsKey("NotResource")) {
            r.add(new Hallazgo(Nivel.ERROR, id, "falta Resource"));
        }
        JsonNode cond = o.get("Condition");
        boolean hayCondicion = cond != null && cond.isObject() && !cond.asObject().isEmpty();
        List<String> claves = clavesDeCondicion(cond);
        if ("Allow".equals(efecto) && hayCondicion) {
            r.add(new Hallazgo(Nivel.AVISO, id, "Allow con Condition: verifica que tu organización lo admita"));
        }
        if ("Deny".equals(efecto) && valores(o.get("Action")).contains("*") && !hayCondicion) {
            r.add(new Hallazgo(Nivel.ERROR, id, "Deny sobre todas las acciones sin condición: bloquea a TODOS"));
        }
        if ("Deny".equals(efecto) && !claves.contains("aws:principalarn") && !claves.contains("aws:principaltag")) {
            r.add(new Hallazgo(Nivel.AVISO, id, "sin excepción por aws:PrincipalArn para el rol de emergencia"));
        }
        if (claves.contains("aws:requestedregion") && tieneAction) {
            r.add(new Hallazgo(Nivel.AVISO, id, "filtra por región con Action: usa NotAction para no romper IAM, STS, Route 53…"));
        }
    }

    private static String texto(JsonNode n) {
        return n != null && n.isString() ? n.asString() : null;
    }

    /** Un valor que puede ser texto o lista de textos. */
    private static List<String> valores(JsonNode n) {
        List<String> salida = new ArrayList<>();
        if (n == null) {
            return salida;
        }
        if (n.isString()) {
            salida.add(n.asString());
        } else if (n.isArray()) {
            for (JsonNode e : n.asArray()) {
                if (e.isString()) {
                    salida.add(e.asString());
                }
            }
        }
        return salida;
    }

    private static List<String> clavesDeCondicion(JsonNode cond) {
        List<String> claves = new ArrayList<>();
        if (cond != null && cond.isObject()) {
            for (JsonNode operador : cond.asObject().values()) {
                if (operador.isObject()) {
                    operador.asObject().keySet().forEach(k -> claves.add(k.toLowerCase(java.util.Locale.ROOT)));
                }
            }
        }
        return claves;
    }
}
```

### 2.2 Generador de la SCP de regiones
Escribirla a mano es la fuente clásica de errores (una región mal escrita, un servicio global olvidado). El generador **valida las entradas** y produce el mismo documento que [`ejemplos/json/scp-region-deny.json`](ejemplos/json/scp-region-deny.json).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

public final class RegionDeny {
    /** Servicios sin región: si no se excluyen, la SCP rompe IAM, STS, Route 53, CloudFront… */
    public static final List<String> SERVICIOS_GLOBALES = List.of(
            "account:*", "acm:*", "aws-marketplace:*", "billing:*", "budgets:*", "ce:*", "cloudfront:*",
            "config:*", "cur:*", "directconnect:*", "health:*", "iam:*", "kms:*", "organizations:*",
            "pricing:*", "route53:*", "route53domains:*", "shield:*", "sts:*", "support:*",
            "trustedadvisor:*", "waf:*", "wafv2:*");

    private static final Pattern REGION = Pattern.compile("^[a-z]{2}(-gov)?-[a-z]+-\\d$");
    private static final Pattern ROL = Pattern.compile("^arn:aws:iam::(\\*|\\d{12}):role/[\\w+=,.@/-]+$");

    private RegionDeny() {}

    public static String generar(List<String> regiones, String arnRolEmergencia) {
        if (regiones == null || regiones.isEmpty()) {
            throw new IllegalArgumentException("indica al menos una región aprobada");
        }
        for (String r : regiones) {
            if (!REGION.matcher(r).matches()) {
                throw new IllegalArgumentException("región inválida: " + r);
            }
        }
        if (arnRolEmergencia == null || !ROL.matcher(arnRolEmergencia).matches()) {
            throw new IllegalArgumentException("ARN del rol de emergencia inválido: " + arnRolEmergencia);
        }
        return "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"SoloRegionesAprobadas\",\"Effect\":\"Deny\","
                + "\"NotAction\":" + lista(SERVICIOS_GLOBALES) + ",\"Resource\":\"*\",\"Condition\":{"
                + "\"StringNotEquals\":{\"aws:RequestedRegion\":" + lista(regiones) + "},"
                + "\"ArnNotLike\":{\"aws:PrincipalArn\":[\"" + arnRolEmergencia + "\"]}}}]}";
    }

    private static String lista(List<String> valores) {
        return valores.stream().map(v -> "\"" + v + "\"").collect(Collectors.joining(",", "[", "]"));
    }
}
```

### 2.3 Árbol de la organización
Una vista de texto de OU y cuentas, útil en un reporte semanal o en un portal interno.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Comparator;
import java.util.List;

public final class ArbolOrganizacion {
    public record Nodo(String id, String nombre, String tipo, List<Nodo> hijos) {}

    private ArbolOrganizacion() {}

    public static String texto(Nodo raiz) {
        StringBuilder sb = new StringBuilder(etiqueta(raiz)).append('\n');
        dibujar(raiz.hijos(), "", sb);
        return sb.toString();
    }

    public static int contarCuentas(Nodo n) {
        int total = "CUENTA".equals(n.tipo()) ? 1 : 0;
        for (Nodo h : n.hijos()) {
            total += contarCuentas(h);
        }
        return total;
    }

    private static void dibujar(List<Nodo> hijos, String prefijo, StringBuilder sb) {
        List<Nodo> orden = hijos.stream()
                .sorted(Comparator.comparing((Nodo x) -> "CUENTA".equals(x.tipo())).thenComparing(Nodo::nombre))
                .toList();
        for (int i = 0; i < orden.size(); i++) {
            boolean ultimo = i == orden.size() - 1;
            Nodo h = orden.get(i);
            sb.append(prefijo).append(ultimo ? "└─ " : "├─ ").append(etiqueta(h)).append('\n');
            dibujar(h.hijos(), prefijo + (ultimo ? "   " : "│  "), sb);
        }
    }

    private static String etiqueta(Nodo n) {
        return switch (n.tipo()) {
            case "CUENTA" -> "[cuenta] " + n.nombre() + " (" + n.id() + ")";
            case "OU" -> "[OU] " + n.nombre();
            default -> "[raíz] " + n.id();
        };
    }
}
```

### 2.4 Fachada del SDK: inventario y políticas idempotentes
**Valida antes de crear** (si hay errores no se envía nada), crea o actualiza por nombre y adjunta sin fallar si ya estaba adjunta: el pipeline puede ejecutarse mil veces.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import software.amazon.awssdk.services.organizations.OrganizationsClient;
import software.amazon.awssdk.services.organizations.model.Account;
import software.amazon.awssdk.services.organizations.model.CreatePolicyRequest;
import software.amazon.awssdk.services.organizations.model.DuplicatePolicyAttachmentException;
import software.amazon.awssdk.services.organizations.model.ListAccountsForParentResponse;
import software.amazon.awssdk.services.organizations.model.ListOrganizationalUnitsForParentResponse;
import software.amazon.awssdk.services.organizations.model.ListPoliciesResponse;
import software.amazon.awssdk.services.organizations.model.OrganizationalUnit;
import software.amazon.awssdk.services.organizations.model.PolicySummary;
import software.amazon.awssdk.services.organizations.model.PolicyType;
import software.amazon.awssdk.services.organizations.model.Root;

public final class Organizaciones {
    public static final class PoliticaInvalida extends RuntimeException {
        private final List<ScpLinter.Hallazgo> hallazgos;

        public PoliticaInvalida(List<ScpLinter.Hallazgo> hallazgos) {
            super("la política tiene errores: " + hallazgos);
            this.hallazgos = hallazgos;
        }

        public List<ScpLinter.Hallazgo> hallazgos() {
            return hallazgos;
        }
    }

    private final OrganizationsClient org;

    public Organizaciones(OrganizationsClient org) {
        this.org = org;
    }

    public ArbolOrganizacion.Nodo arbol() {
        Root raiz = org.listRoots().roots().get(0);
        return construir(raiz.id(), "RAIZ", raiz.name());
    }

    private ArbolOrganizacion.Nodo construir(String id, String tipo, String nombre) {
        List<ArbolOrganizacion.Nodo> hijos = new ArrayList<>();
        for (ListOrganizationalUnitsForParentResponse pagina : org.listOrganizationalUnitsForParentPaginator(r -> r.parentId(id))) {
            for (OrganizationalUnit ou : pagina.organizationalUnits()) {
                hijos.add(construir(ou.id(), "OU", ou.name()));
            }
        }
        for (ListAccountsForParentResponse pagina : org.listAccountsForParentPaginator(r -> r.parentId(id))) {
            for (Account c : pagina.accounts()) {
                hijos.add(new ArbolOrganizacion.Nodo(c.id(), c.name(), "CUENTA", List.of()));
            }
        }
        return new ArbolOrganizacion.Nodo(id, nombre, tipo, hijos);
    }

    /** Devuelve el id de la política (creada o actualizada). Lanza PoliticaInvalida si el validador encuentra errores. */
    public String crearOActualizar(String nombre, String descripcion, String contenido) {
        List<ScpLinter.Hallazgo> hallazgos = ScpLinter.validar(contenido);
        if (ScpLinter.hayErrores(hallazgos)) {
            throw new PoliticaInvalida(hallazgos);
        }
        Optional<PolicySummary> existente = Optional.empty();
        for (ListPoliciesResponse pagina : org.listPoliciesPaginator(r -> r.filter(PolicyType.SERVICE_CONTROL_POLICY))) {
            existente = pagina.policies().stream().filter(p -> p.name().equals(nombre)).findFirst();
            if (existente.isPresent()) {
                break;
            }
        }
        if (existente.isPresent()) {
            String id = existente.get().id();
            org.updatePolicy(r -> r.policyId(id).description(descripcion).content(contenido));
            return id;
        }
        return org.createPolicy(CreatePolicyRequest.builder()
                .name(nombre).description(descripcion).type(PolicyType.SERVICE_CONTROL_POLICY).content(contenido).build())
                .policy().policySummary().id();
    }

    public void adjuntar(String politicaId, String destinoId) {
        try {
            org.attachPolicy(r -> r.policyId(politicaId).targetId(destinoId));
        } catch (DuplicatePolicyAttachmentException e) {
            // ya estaba adjunta: nada que hacer
        }
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.organizations.OrganizationsClient;

@Configuration
class OrgConfig {
    @Bean(destroyMethod = "close")
    OrganizationsClient organizations() {
        return OrganizationsClient.builder().region(Region.US_EAST_1).build();
    }

    @Bean
    Organizaciones organizaciones(OrganizationsClient org) {
        return new Organizaciones(org);
    }
}

@RestController
@RequestMapping("/gobierno")
class GobiernoController {
    record Resultado(boolean valido, List<ScpLinter.Hallazgo> hallazgos) {}

    private final Organizaciones organizaciones;

    GobiernoController(Organizaciones organizaciones) {
        this.organizaciones = organizaciones;
    }

    @GetMapping(value = "/arbol", produces = MediaType.TEXT_PLAIN_VALUE)
    String arbol() {
        return ArbolOrganizacion.texto(organizaciones.arbol());
    }

    /** Valida una SCP SIN tocar la organización: se usa en la revisión del pull request. */
    @PostMapping(value = "/scp/validar", consumes = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<Resultado> validar(@RequestBody String documento) {
        List<ScpLinter.Hallazgo> hallazgos = ScpLinter.validar(documento);
        return ResponseEntity.ok(new Resultado(!ScpLinter.hayErrores(hallazgos), hallazgos));
    }
}
```

## 4. Spring WebFlux (reactivo)
El cliente asíncrono entrega un paginador reactivo: se convierte en `Flux` sin bloquear ningún hilo.
```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.organizations.OrganizationsAsyncClient;
import software.amazon.awssdk.services.organizations.model.ListAccountsResponse;

@Configuration
class OrgReactivoConfig {
    @Bean(destroyMethod = "close")
    OrganizationsAsyncClient organizationsAsync() {
        return OrganizationsAsyncClient.builder().region(Region.US_EAST_1).build();
    }
}

@RestController
class CuentasReactivoController {
    record CuentaDto(String id, String nombre, String estado) {}

    private final OrganizationsAsyncClient org;

    CuentasReactivoController(OrganizationsAsyncClient org) {
        this.org = org;
    }

    @GetMapping("/r/gobierno/cuentas")
    Flux<CuentaDto> cuentas() {
        return Flux.from(org.listAccountsPaginator())
                .concatMapIterable(ListAccountsResponse::accounts)
                .map(a -> new CuentaDto(a.id(), a.name(), a.statusAsString()));
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.organizations.OrganizationsAsyncClient;
import software.amazon.awssdk.services.organizations.OrganizationsClient;

@ApplicationScoped
class OrgProductores {
    @Produces
    @Singleton
    OrganizationsClient organizations() {
        return OrganizationsClient.builder().region(Region.US_EAST_1).build();
    }

    void cerrar(@Disposes OrganizationsClient cliente) {
        cliente.close();
    }

    @Produces
    @Singleton
    OrganizationsAsyncClient organizationsAsync() {
        return OrganizationsAsyncClient.builder().region(Region.US_EAST_1).build();
    }

    void cerrarAsync(@Disposes OrganizationsAsyncClient cliente) {
        cliente.close();
    }

    @Produces
    @Singleton
    Organizaciones organizaciones(OrganizationsClient org) {
        return new Organizaciones(org);
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
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Map;

@Path("/gobierno")
class GobiernoRecurso {
    @Inject
    Organizaciones organizaciones;

    @GET
    @Path("/arbol")
    @Produces(MediaType.TEXT_PLAIN)
    public String arbol() {
        return ArbolOrganizacion.texto(organizaciones.arbol());
    }

    @POST
    @Path("/scp/validar")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response validar(String documento) {
        List<ScpLinter.Hallazgo> hallazgos = ScpLinter.validar(documento);
        return Response.ok(Map.of("valido", !ScpLinter.hayErrores(hallazgos), "hallazgos", hallazgos)).build();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Multi;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.reactivestreams.FlowAdapters;
import software.amazon.awssdk.services.organizations.OrganizationsAsyncClient;
import software.amazon.awssdk.services.organizations.model.ListAccountsResponse;

@Path("/m/gobierno")
class CuentasMutinyRecurso {
    @Inject
    OrganizationsAsyncClient org;

    /** El paginador del SDK es un Publisher de Reactive Streams; se adapta al Flow que usa Mutiny. */
    @GET
    @Path("/cuentas")
    @Produces(MediaType.APPLICATION_JSON)
    public Multi<String> cuentas() {
        return Multi.createFrom().publisher(FlowAdapters.toFlowPublisher(org.listAccountsPaginator()))
                .onItem().transformToIterable(ListAccountsResponse::accounts)
                .map(a -> a.id() + " " + a.name());
    }
}
```

## 7. Permisos
La herramienta corre en la cuenta de administración (o en un administrador delegado) con un rol de pipeline que tenga solo lo que usa: `organizations:ListRoots`, `ListOrganizationalUnitsForParent`, `ListAccountsForParent`, `ListAccounts`, `ListPolicies`, `CreatePolicy`, `UpdatePolicy`, `AttachPolicy`. **No** necesita `DeletePolicy` ni `DetachPolicy` salvo en el procedimiento de recuperación, que debe estar en otra identidad con aprobación.

## 8. Qué NO hacer desde Java
- **No** apliques una SCP sin pasarla por `ScpLinter` y probarla antes en la OU de ensayo (§2.1).
- **No** escribas a mano la SCP de regiones: genérala (§2.2).
- **No** ejecutes esta herramienta en las cargas de producción: es una herramienta de plataforma con permisos sobre toda la organización.
- **No** guardes credenciales de la cuenta de administración en archivos: usa la cadena por defecto y un rol de pipeline.
- **No** hagas cambios de organización en paralelo (`ConcurrentModificationException`): serializa el pipeline.
- **No** dependas de que el cambio se vea de inmediato: espera unos minutos antes de validar.
