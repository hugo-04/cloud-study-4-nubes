# AWS · Terraform · Autenticación y pipelines · Uso desde Java

Desde Java **no despliegas infraestructura**: eso lo hace el pipeline con su rol. Lo que sí construyes son las **herramientas de control alrededor del pipeline**:

- un **analizador de planes** (`terraform show -json`) que decide si un cambio se aprueba solo, requiere revisión o se bloquea;
- un **validador de políticas de confianza OIDC** que detecta un `sub` peligroso antes de que llegue a producción;
- un **ejecutor aislado** de `terraform show` (sin credenciales, con tiempo y tamaño límite);
- el servicio que los une, expuesto a un portal de autoservicio o a un paso del pipeline.

Todo el núcleo son funciones puras (se prueban sin red ni Terraform). Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40; el JSON se lee con el analizador del AWS SDK v2 (sin dependencias extra).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  planes:
    terraform: /usr/local/bin/terraform      # ruta absoluta, nunca desde la petición
    raiz: /var/lib/revision-planes           # solo se permiten directorios debajo de esta raíz
spring:
  codec:
    max-in-memory-size: 25MB                 # WebFlux: tamaño máximo del plan recibido
```
```properties
# Quarkus (application.properties)
app.planes.terraform=/usr/local/bin/terraform
app.planes.raiz=/var/lib/revision-planes
quarkus.http.limits.max-body-size=25M
```

## 2. Núcleo común

### 2.1 Utilidades de JSON
Lectura tolerante: lo que falta es «ausente», no una excepción.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;

final class Json {
    private Json() {}

    static JsonNode parse(String json) {
        try {
            return JsonNodeParser.create().parse(json);
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("JSON inválido", e);
        }
    }

    static JsonNode campo(JsonNode nodo, String nombre) {
        return nodo != null && nodo.isObject() ? nodo.asObject().get(nombre) : null;
    }

    static Map<String, JsonNode> objeto(JsonNode nodo) {
        return nodo != null && nodo.isObject() ? nodo.asObject() : Map.of();
    }

    static String texto(JsonNode nodo) {
        return nodo != null && nodo.isString() ? nodo.asString() : null;
    }

    /** Un texto o una lista de textos → lista de textos. */
    static List<String> textos(JsonNode nodo) {
        List<String> valores = new ArrayList<>();
        if (nodo == null) {
            return valores;
        }
        if (nodo.isString()) {
            valores.add(nodo.asString());
        } else if (nodo.isArray()) {
            for (JsonNode n : nodo.asArray()) {
                if (n.isString()) {
                    valores.add(n.asString());
                }
            }
        }
        return valores;
    }

    /** Un objeto o una lista de objetos → lista de nodos. */
    static List<JsonNode> lista(JsonNode nodo) {
        if (nodo == null) {
            return List.of();
        }
        if (nodo.isArray()) {
            return nodo.asArray();
        }
        return nodo.isObject() ? List.of(nodo) : List.of();
    }

    static Boolean booleano(JsonNode nodo) {
        if (nodo == null || !nodo.isBoolean()) {
            return null;
        }
        return nodo.asBoolean();
    }

    static Integer entero(JsonNode nodo) {
        if (nodo == null || !nodo.isNumber()) {
            return null;
        }
        try {
            return Integer.valueOf(nodo.asNumber());
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
```

### 2.2 El analizador de planes
Entrada: la salida de `terraform show -json plan`. Salida: resumen, hallazgos y una **decisión**: `APROBAR` (nada de riesgo), `REVISAR` (una persona mira) o `BLOQUEAR` (hay riesgo alto y se necesita una excepción documentada). **Falla cerrado**: un formato desconocido es un error, no un «todo bien».
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;

public final class AnalizadorDePlan {
    public enum Severidad { ALTA, MEDIA, BAJA }

    public enum Decision { APROBAR, REVISAR, BLOQUEAR }

    public record Hallazgo(Severidad severidad, String recurso, String regla, String detalle) {}

    public record Resumen(int crear, int actualizar, int borrar, int reemplazar) {}

    public record Informe(Resumen resumen, List<Hallazgo> hallazgos, Decision decision) {}

    public static final class PlanInvalido extends IllegalArgumentException {
        public PlanInvalido(String mensaje) {
            super(mensaje);
        }
    }

    private enum Accion { NADA, CREAR, ACTUALIZAR, BORRAR, REEMPLAZAR }

    static final Set<String> TIPOS_CON_DATOS = Set.of(
            "aws_db_instance", "aws_rds_cluster", "aws_dynamodb_table", "aws_s3_bucket", "aws_kms_key",
            "aws_efs_file_system", "aws_elasticache_replication_group", "aws_msk_cluster",
            "aws_kinesis_stream", "aws_secretsmanager_secret", "aws_sqs_queue");
    static final Set<String> POLITICAS_EN_LINEA = Set.of(
            "aws_iam_policy", "aws_iam_role_policy", "aws_iam_user_policy", "aws_iam_group_policy");
    static final Set<String> ADJUNTOS = Set.of(
            "aws_iam_role_policy_attachment", "aws_iam_user_policy_attachment", "aws_iam_group_policy_attachment", "aws_iam_policy_attachment");

    private AnalizadorDePlan() {}

    public static Informe analizar(String planJson) {
        JsonNode raiz;
        try {
            raiz = Json.parse(planJson);
        } catch (IllegalArgumentException e) {
            throw new PlanInvalido("El plan no es JSON válido");
        }
        String formato = Json.texto(Json.campo(raiz, "format_version"));
        if (formato == null || !formato.startsWith("1.")) {
            throw new PlanInvalido("Formato de plan no soportado: " + formato);
        }
        int crear = 0;
        int actualizar = 0;
        int borrar = 0;
        int reemplazar = 0;
        List<Hallazgo> hallazgos = new ArrayList<>();

        for (JsonNode rc : Json.lista(Json.campo(raiz, "resource_changes"))) {
            Map<String, JsonNode> o = Json.objeto(rc);
            if (!"managed".equals(Json.texto(o.get("mode")))) {
                continue;
            }
            String direccion = Json.texto(o.get("address"));
            String tipo = Json.texto(o.get("type"));
            Map<String, JsonNode> cambio = Json.objeto(o.get("change"));
            Accion accion = clasificar(Json.textos(cambio.get("actions")));
            if (accion == Accion.NADA) {
                continue;
            }
            switch (accion) {
                case CREAR -> crear++;
                case ACTUALIZAR -> actualizar++;
                case BORRAR -> borrar++;
                case REEMPLAZAR -> reemplazar++;
                default -> { }
            }
            if (accion == Accion.BORRAR || accion == Accion.REEMPLAZAR) {
                if (TIPOS_CON_DATOS.contains(tipo)) {
                    hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "DESTRUCCION_DE_DATOS",
                            (accion == Accion.REEMPLAZAR ? "Se reemplaza " : "Se borra ") + tipo + ": los datos se perderían"));
                } else if (accion == Accion.REEMPLAZAR) {
                    hallazgos.add(new Hallazgo(Severidad.MEDIA, direccion, "REEMPLAZO", "El recurso se destruye y se vuelve a crear"));
                } else {
                    hallazgos.add(new Hallazgo(Severidad.BAJA, direccion, "BORRADO", "El recurso se elimina"));
                }
            }
            if (accion != Accion.BORRAR) {
                reglasDeContenido(tipo, direccion, Json.objeto(cambio.get("after")), Json.objeto(cambio.get("after_unknown")), hallazgos);
            }
        }

        hallazgos.sort(Comparator.comparing(Hallazgo::severidad).thenComparing(Hallazgo::recurso).thenComparing(Hallazgo::regla));
        Decision decision;
        if (hallazgos.stream().anyMatch(h -> h.severidad() == Severidad.ALTA)) {
            decision = Decision.BLOQUEAR;
        } else if (hallazgos.stream().anyMatch(h -> h.severidad() == Severidad.MEDIA) || borrar + reemplazar > 0) {
            decision = Decision.REVISAR;
        } else {
            decision = Decision.APROBAR;
        }
        return new Informe(new Resumen(crear, actualizar, borrar, reemplazar), List.copyOf(hallazgos), decision);
    }

    private static Accion clasificar(List<String> acciones) {
        if (acciones.isEmpty() || acciones.equals(List.of("no-op")) || acciones.equals(List.of("read")) || acciones.equals(List.of("forget"))) {
            return Accion.NADA;
        }
        if (acciones.contains("delete") && acciones.contains("create")) {
            return Accion.REEMPLAZAR;
        }
        if (acciones.equals(List.of("create"))) {
            return Accion.CREAR;
        }
        if (acciones.equals(List.of("delete"))) {
            return Accion.BORRAR;
        }
        return Accion.ACTUALIZAR;   // update y cualquier combinación desconocida: se revisa como cambio
    }

    private static void reglasDeContenido(String tipo, String direccion, Map<String, JsonNode> despues,
                                          Map<String, JsonNode> desconocido, List<Hallazgo> hallazgos) {
        if (POLITICAS_EN_LINEA.contains(tipo)) {
            String politica = Json.texto(despues.get("policy"));
            if (politica != null) {
                analizarPolitica(direccion, politica, hallazgos);
            } else if (Boolean.TRUE.equals(Json.booleano(desconocido.get("policy")))) {
                hallazgos.add(new Hallazgo(Severidad.BAJA, direccion, "POLITICA_DESCONOCIDA", "El contenido se conocerá al aplicar: no se puede revisar en el plan"));
            }
        }
        if (ADJUNTOS.contains(tipo)) {
            String arn = Json.texto(despues.get("policy_arn"));
            if (arn != null && arn.endsWith("/AdministratorAccess")) {
                hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "ADMINISTRADOR_ASIGNADO", "Se adjunta AdministratorAccess"));
            }
        }
        if (tipo.equals("aws_security_group_rule") && "ingress".equals(Json.texto(despues.get("type"))) && abiertoAlMundo(despues)) {
            hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "PUERTO_ABIERTO_AL_MUNDO", "Ingreso desde 0.0.0.0/0 en puertos distintos de 80/443"));
        }
        if (tipo.equals("aws_vpc_security_group_ingress_rule") && abiertoAlMundo(despues)) {
            hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "PUERTO_ABIERTO_AL_MUNDO", "Ingreso desde 0.0.0.0/0 en puertos distintos de 80/443"));
        }
        if (tipo.equals("aws_security_group")) {
            for (JsonNode regla : Json.lista(despues.get("ingress"))) {
                if (abiertoAlMundo(Json.objeto(regla))) {
                    hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "PUERTO_ABIERTO_AL_MUNDO", "Regla de ingreso desde 0.0.0.0/0 en puertos distintos de 80/443"));
                    break;
                }
            }
        }
        if (tipo.equals("aws_s3_bucket_public_access_block")) {
            for (String clave : List.of("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")) {
                if (Boolean.FALSE.equals(Json.booleano(despues.get(clave)))) {
                    hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "ACCESO_PUBLICO_S3", clave + " = false"));
                }
            }
        }
        if (tipo.equals("aws_s3_bucket_acl") || tipo.equals("aws_s3_bucket")) {
            String acl = Json.texto(despues.get("acl"));
            if ("public-read".equals(acl) || "public-read-write".equals(acl)) {
                hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "ACCESO_PUBLICO_S3", "ACL " + acl));
            }
        }
        if (tipo.equals("aws_db_instance") || tipo.equals("aws_rds_cluster_instance")) {
            if (Boolean.TRUE.equals(Json.booleano(despues.get("publicly_accessible")))) {
                hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "BASE_PUBLICA", "publicly_accessible = true"));
            }
            if (Boolean.FALSE.equals(Json.booleano(despues.get("storage_encrypted")))) {
                hallazgos.add(new Hallazgo(Severidad.MEDIA, direccion, "SIN_CIFRADO", "storage_encrypted = false"));
            }
        }
        if (tipo.equals("aws_ebs_volume") && Boolean.FALSE.equals(Json.booleano(despues.get("encrypted")))) {
            hallazgos.add(new Hallazgo(Severidad.MEDIA, direccion, "SIN_CIFRADO", "encrypted = false"));
        }
    }

    /** ¿Admite 0.0.0.0/0 (o ::/0) en algún puerto distinto de 80/443? */
    static boolean abiertoAlMundo(Map<String, JsonNode> regla) {
        boolean mundo = Json.textos(regla.get("cidr_blocks")).contains("0.0.0.0/0")
                || Json.textos(regla.get("ipv6_cidr_blocks")).contains("::/0")
                || "0.0.0.0/0".equals(Json.texto(regla.get("cidr_ipv4")))
                || "::/0".equals(Json.texto(regla.get("cidr_ipv6")));
        if (!mundo) {
            return false;
        }
        Integer desde = Json.entero(regla.get("from_port"));
        Integer hasta = Json.entero(regla.get("to_port"));
        boolean todosLosProtocolos = "-1".equals(Json.texto(regla.get("protocol"))) || "-1".equals(Json.texto(regla.get("ip_protocol")));
        if (todosLosProtocolos || desde == null || hasta == null) {
            return true;
        }
        return !(desde.equals(hasta) && (desde == 80 || desde == 443));
    }

    private static void analizarPolitica(String direccion, String politicaJson, List<Hallazgo> hallazgos) {
        JsonNode raiz;
        try {
            raiz = Json.parse(politicaJson);
        } catch (IllegalArgumentException e) {
            hallazgos.add(new Hallazgo(Severidad.MEDIA, direccion, "POLITICA_ILEGIBLE", "El contenido de la política no es JSON válido"));
            return;
        }
        for (JsonNode s : Json.lista(Json.campo(raiz, "Statement"))) {
            if (!"Allow".equals(Json.texto(Json.campo(s, "Effect")))) {
                continue;
            }
            List<String> acciones = Json.textos(Json.campo(s, "Action"));
            List<String> recursos = Json.textos(Json.campo(s, "Resource"));
            if (Json.campo(s, "NotAction") != null) {
                hallazgos.add(new Hallazgo(Severidad.MEDIA, direccion, "NOTACTION_PERMISIVO", "Allow con NotAction concede todo lo demás"));
            }
            if (acciones.contains("*")) {
                hallazgos.add(new Hallazgo(Severidad.ALTA, direccion, "IAM_AMPLIA", "Allow con Action \"*\""));
            } else if (recursos.contains("*") && acciones.stream().anyMatch(a -> a.endsWith(":*"))) {
                hallazgos.add(new Hallazgo(Severidad.MEDIA, direccion, "IAM_COMODIN", "Allow con servicio:* sobre Resource \"*\""));
            }
        }
    }
}
```

### 2.3 El validador de la política de confianza OIDC
Revisa la política de confianza de un rol **antes** de crearlo (o la de los roles existentes, leída con `iam:GetRole`). Es el control contra el `sub` con comodín.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;

public final class ValidadorConfianzaOidc {
    public enum Nivel { ERROR, AVISO }

    public record Hallazgo(Nivel nivel, String regla, String detalle) {}

    static final String EMISOR = "token.actions.githubusercontent.com";

    private ValidadorConfianzaOidc() {}

    public static List<Hallazgo> validar(String politicaJson, String organizacion, boolean exigirEntorno) {
        List<Hallazgo> r = new ArrayList<>();
        JsonNode raiz = Json.parse(politicaJson);
        boolean hayOidc = false;
        for (JsonNode s : Json.lista(Json.campo(raiz, "Statement"))) {
            if (!"Allow".equals(Json.texto(Json.campo(s, "Effect")))) {
                continue;
            }
            JsonNode principal = Json.campo(s, "Principal");
            if (principal != null && principal.isString() && "*".equals(principal.asString())) {
                r.add(new Hallazgo(Nivel.ERROR, "PRINCIPAL_ABIERTO", "Principal \"*\": cualquiera podría intentar asumir el rol"));
                continue;
            }
            List<String> federados = Json.textos(Json.campo(principal, "Federated"));
            if (federados.stream().noneMatch(f -> f.contains("oidc-provider/" + EMISOR))) {
                continue;
            }
            hayOidc = true;
            if (!Json.textos(Json.campo(s, "Action")).contains("sts:AssumeRoleWithWebIdentity")) {
                r.add(new Hallazgo(Nivel.AVISO, "ACCION_INESPERADA", "Con un proveedor OIDC la acción debe ser sts:AssumeRoleWithWebIdentity"));
            }
            JsonNode condicion = Json.campo(s, "Condition");
            boolean audOk = false;
            boolean haySub = false;
            for (Map.Entry<String, JsonNode> operador : Json.objeto(condicion).entrySet()) {
                boolean literal = operador.getKey().startsWith("StringEquals");
                for (Map.Entry<String, JsonNode> clave : Json.objeto(operador.getValue()).entrySet()) {
                    List<String> valores = Json.textos(clave.getValue());
                    if (clave.getKey().equals(EMISOR + ":aud")) {
                        audOk |= valores.contains("sts.amazonaws.com");
                    } else if (clave.getKey().equals(EMISOR + ":sub")) {
                        haySub = true;
                        for (String sub : valores) {
                            validarSub(sub, literal, organizacion, exigirEntorno, r);
                        }
                    }
                }
            }
            if (!audOk) {
                r.add(new Hallazgo(Nivel.ERROR, "SIN_AUDIENCIA", "Falta la condición aud = sts.amazonaws.com"));
            }
            if (!haySub) {
                r.add(new Hallazgo(Nivel.ERROR, "SIN_SUB", "Sin condición sobre sub: cualquier repositorio de GitHub podría asumir el rol"));
            }
        }
        if (!hayOidc) {
            r.add(new Hallazgo(Nivel.AVISO, "SIN_SENTENCIA_OIDC", "No hay una sentencia Allow para el proveedor " + EMISOR));
        }
        return r;
    }

    private static void validarSub(String sub, boolean literal, String org, boolean exigirEntorno, List<Hallazgo> r) {
        if (sub.equals("*") || sub.startsWith("repo:*")) {
            r.add(new Hallazgo(Nivel.ERROR, "SUB_COMODIN_TOTAL", "El sub \"" + sub + "\" acepta repositorios de cualquier organización"));
            return;
        }
        if (!sub.startsWith("repo:" + org + "/")) {
            r.add(new Hallazgo(Nivel.ERROR, "ORGANIZACION_AJENA", "El sub \"" + sub + "\" no pertenece a la organización " + org));
            return;
        }
        String despuesDeOrg = sub.substring(("repo:" + org + "/").length());
        if (despuesDeOrg.startsWith("*")) {
            r.add(new Hallazgo(Nivel.ERROR, "SUB_TODA_LA_ORGANIZACION", "El sub \"" + sub + "\" acepta todos los repositorios de la organización"));
            return;
        }
        if (sub.contains("*")) {
            if (literal) {
                r.add(new Hallazgo(Nivel.AVISO, "COMODIN_EN_STRINGEQUALS", "StringEquals toma \"*\" como texto: el sub \"" + sub + "\" nunca coincidirá; usa StringLike"));
            } else {
                r.add(new Hallazgo(Nivel.AVISO, "ACEPTA_CUALQUIER_REF", "El sub \"" + sub + "\" acepta cualquier rama, entorno o pull request"));
            }
        }
        if (exigirEntorno && !sub.contains(":environment:")) {
            r.add(new Hallazgo(Nivel.ERROR, "SIN_ENTORNO", "Un rol de apply debe exigir un entorno protegido (…:environment:<nombre>), no \"" + sub + "\""));
        }
    }
}
```

### 2.4 El ejecutor aislado de `terraform show`
`terraform show -json` sobre un plan guardado **no necesita credenciales ni red**. Por eso corre con el entorno **vacío**, en un directorio permitido, con tiempo límite y salida acotada.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Pattern;

public final class EjecutorDeTerraform {
    private static final Pattern ARCHIVO = Pattern.compile("^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$");

    private final java.nio.file.Path binario;
    private final java.nio.file.Path raizPermitida;
    private final Duration limite;
    private final int maxBytes;

    public EjecutorDeTerraform(java.nio.file.Path binario, java.nio.file.Path raizPermitida, Duration limite, int maxBytes) {
        this.binario = binario;
        this.raizPermitida = raizPermitida.toAbsolutePath().normalize();
        this.limite = limite;
        this.maxBytes = maxBytes;
    }

    public String planComoJson(java.nio.file.Path directorio, String archivoDePlan) {
        java.nio.file.Path dir = directorio.toAbsolutePath().normalize();
        if (!dir.startsWith(raizPermitida)) {
            throw new IllegalArgumentException("Directorio fuera de la raíz permitida");
        }
        if (!ARCHIVO.matcher(archivoDePlan).matches()) {
            throw new IllegalArgumentException("Nombre de archivo de plan inválido");
        }
        ProcessBuilder pb = new ProcessBuilder(binario.toString(), "show", "-json", "-no-color", archivoDePlan);
        pb.directory(dir.toFile());
        Map<String, String> entorno = pb.environment();
        entorno.clear();                                   // sin credenciales, sin variables heredadas
        entorno.put("PATH", "/usr/bin:/bin");
        entorno.put("TF_IN_AUTOMATION", "1");
        entorno.put("TF_INPUT", "0");
        entorno.put("CHECKPOINT_DISABLE", "1");
        pb.redirectError(ProcessBuilder.Redirect.DISCARD);

        Process proceso;
        try {
            proceso = pb.start();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        CompletableFuture<byte[]> salida = CompletableFuture.supplyAsync(() -> leerAcotado(proceso.getInputStream(), maxBytes));
        try {
            byte[] bytes = salida.get(limite.toMillis(), TimeUnit.MILLISECONDS);
            if (!proceso.waitFor(5, TimeUnit.SECONDS)) {
                proceso.destroyForcibly();
                throw new IllegalStateException("terraform no terminó tras entregar la salida");
            }
            if (proceso.exitValue() != 0) {
                throw new IllegalStateException("terraform show terminó con código " + proceso.exitValue());
            }
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (TimeoutException e) {
            proceso.destroyForcibly();
            throw new IllegalStateException("Tiempo agotado (" + limite.toMillis() + " ms)", e);
        } catch (ExecutionException e) {
            proceso.destroyForcibly();
            throw new IllegalStateException(e.getCause().getMessage(), e.getCause());
        } catch (InterruptedException e) {
            proceso.destroyForcibly();
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrumpido", e);
        }
    }

    private static byte[] leerAcotado(InputStream entrada, int max) {
        try (entrada; ByteArrayOutputStream salida = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int n;
            while ((n = entrada.read(buffer)) != -1) {
                if (salida.size() + n > max) {
                    throw new IllegalStateException("La salida supera " + max + " bytes");
                }
                salida.write(buffer, 0, n);
            }
            return salida.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
```

### 2.5 El servicio de revisión
Une las piezas y limita el tamaño del plan recibido.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public final class ServicioDeRevisionDePlanes {
    static final int MAX_CARACTERES = 25_000_000;

    private final EjecutorDeTerraform ejecutor;

    public ServicioDeRevisionDePlanes(EjecutorDeTerraform ejecutor) {
        this.ejecutor = ejecutor;
    }

    public AnalizadorDePlan.Informe revisar(String planJson) {
        if (planJson == null || planJson.isBlank() || planJson.length() > MAX_CARACTERES) {
            throw new AnalizadorDePlan.PlanInvalido("Plan vacío o demasiado grande");
        }
        return AnalizadorDePlan.analizar(planJson);
    }

    public AnalizadorDePlan.Informe revisarArchivo(java.nio.file.Path directorio, String archivoDePlan) {
        return revisar(ejecutor.planComoJson(directorio, archivoDePlan));
    }

    public List<ValidadorConfianzaOidc.Hallazgo> validarConfianza(String politicaJson, String organizacion, boolean exigirEntorno) {
        return ValidadorConfianzaOidc.validar(politicaJson, organizacion, exigirEntorno);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class PlanesConfig {
    @Bean
    EjecutorDeTerraform ejecutor(@Value("${app.planes.terraform}") String binario, @Value("${app.planes.raiz}") String raiz) {
        return new EjecutorDeTerraform(Path.of(binario), Path.of(raiz), Duration.ofSeconds(60), 30 * 1024 * 1024);
    }

    @Bean
    ServicioDeRevisionDePlanes servicio(EjecutorDeTerraform ejecutor) {
        return new ServicioDeRevisionDePlanes(ejecutor);
    }
}

@RestController
@RequestMapping("/planes")
class PlanesController {
    private final ServicioDeRevisionDePlanes servicio;

    PlanesController(ServicioDeRevisionDePlanes servicio) {
        this.servicio = servicio;
    }

    /** Recibe el JSON de «terraform show -json» y devuelve la decisión. Úsalo como paso del pipeline. */
    @PostMapping(value = "/revisar", consumes = MediaType.APPLICATION_JSON_VALUE)
    AnalizadorDePlan.Informe revisar(@RequestBody String planJson) {
        return servicio.revisar(planJson);
    }

    @PostMapping(value = "/confianza", consumes = MediaType.APPLICATION_JSON_VALUE)
    List<ValidadorConfianzaOidc.Hallazgo> confianza(@RequestBody String politica, @RequestParam String organizacion,
                                                    @RequestParam(defaultValue = "true") boolean apply) {
        return servicio.validarConfianza(politica, organizacion, apply);
    }

    @ResponseStatus(HttpStatus.BAD_REQUEST)
    @ExceptionHandler(IllegalArgumentException.class)
    String peticionInvalida(IllegalArgumentException e) {
        return e.getMessage();
    }
}
```

## 4. Spring WebFlux (reactivo)
El análisis es trabajo de CPU sobre un JSON que puede pesar megabytes: va a un hilo de trabajo (`boundedElastic`), no al hilo del bucle de eventos.
```java
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/r/planes")
class PlanesReactivoController {
    private final ServicioDeRevisionDePlanes servicio;

    PlanesReactivoController(ServicioDeRevisionDePlanes servicio) {
        this.servicio = servicio;
    }

    @PostMapping(value = "/revisar", consumes = MediaType.APPLICATION_JSON_VALUE)
    Mono<AnalizadorDePlan.Informe> revisar(@RequestBody Mono<String> planJson) {
        return planJson.flatMap(json -> Mono.fromCallable(() -> servicio.revisar(json)).subscribeOn(Schedulers.boundedElastic()));
    }

    @PostMapping(value = "/confianza", consumes = MediaType.APPLICATION_JSON_VALUE)
    Mono<List<ValidadorConfianzaOidc.Hallazgo>> confianza(@RequestBody Mono<String> politica, @RequestParam String organizacion,
                                                          @RequestParam(defaultValue = "true") boolean apply) {
        return politica.map(p -> servicio.validarConfianza(p, organizacion, apply));
    }

    @ResponseStatus(HttpStatus.BAD_REQUEST)
    @ExceptionHandler(IllegalArgumentException.class)
    String peticionInvalida(IllegalArgumentException e) {
        return e.getMessage();
    }
}
```
> Ejecutar `terraform show` (proceso externo) también bloquea: `revisarArchivo` debe correr siempre en `boundedElastic`.

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.nio.file.Path;
import java.time.Duration;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class PlanesProductores {
    @Produces
    @Singleton
    EjecutorDeTerraform ejecutor(@ConfigProperty(name = "app.planes.terraform") String binario,
                                 @ConfigProperty(name = "app.planes.raiz") String raiz) {
        return new EjecutorDeTerraform(Path.of(binario), Path.of(raiz), Duration.ofSeconds(60), 30 * 1024 * 1024);
    }

    @Produces
    @Singleton
    ServicioDeRevisionDePlanes servicio(EjecutorDeTerraform ejecutor) {
        return new ServicioDeRevisionDePlanes(ejecutor);
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import java.util.List;

@Path("/planes")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class PlanesRecurso {
    @Inject
    ServicioDeRevisionDePlanes servicio;

    @POST
    @Path("/revisar")
    public AnalizadorDePlan.Informe revisar(String planJson) {
        return servicio.revisar(planJson);
    }

    @POST
    @Path("/confianza")
    public List<ValidadorConfianzaOidc.Hallazgo> confianza(String politica, @QueryParam("organizacion") String organizacion,
                                                           @QueryParam("apply") @DefaultValue("true") boolean apply) {
        return servicio.validarConfianza(politica, organizacion, apply);
    }
}

@Provider
class PeticionInvalidaMapper implements ExceptionMapper<IllegalArgumentException> {
    @Override
    public Response toResponse(IllegalArgumentException e) {
        return Response.status(Response.Status.BAD_REQUEST).entity(e.getMessage()).type(MediaType.TEXT_PLAIN).build();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/m/planes")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class PlanesMutinyRecurso {
    @Inject
    ServicioDeRevisionDePlanes servicio;

    @POST
    @Path("/revisar")
    public Uni<AnalizadorDePlan.Informe> revisar(String planJson) {
        return Uni.createFrom().item(() -> servicio.revisar(planJson))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 7. Permisos
- **El revisor de planes** no necesita **ningún permiso de AWS**: recibe un JSON o lee un archivo local. Ejecútalo sin credenciales (§2.4).
- **El validador de confianza**, si lee roles existentes, necesita `iam:GetRole` y `iam:ListRoles` de solo lectura.
- **Quien llama** al servicio desde el pipeline se autentica con el mecanismo del servicio (token del pipeline, mTLS); el servicio no aplica nada.

## 8. Qué NO hacer desde Java
- **No** pases credenciales de AWS al proceso de `terraform show`: no las necesita (§2.4).
- **No** construyas el comando con texto de la petición: el binario es de configuración y el nombre del archivo se valida (§2.4).
- **No** ejecutes `terraform apply` desde el servicio: el servicio revisa, el pipeline aplica.
- **No** trates un plan ilegible o de formato desconocido como «aprobado»: falla cerrado (§2.2).
- **No** registres el plan completo: puede contener valores sensibles; registra solo el resumen y los hallazgos.
- **No** aceptes planes de tamaño ilimitado: límite en el servicio y en el servidor HTTP (§1, §2.5).
- **No** uses la decisión `APROBAR` como sustituto de la aprobación humana de producción.
