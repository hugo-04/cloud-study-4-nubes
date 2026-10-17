# AWS · Terraform · Estado remoto · Uso desde Java

Desde Java **no ejecutas `terraform apply` ni editas el estado**: eso lo hacen los pipelines con permisos propios. Lo que sí construyes es un **auditor de solo lectura** del bucket del estado: ¿está versionado, cifrado, sin acceso público, con TLS obligatorio y protegido contra el borrado de versiones? ¿Hay candados (`.tflock`) colgados? ¿Hay estados fuera de convención, enormes o abandonados? El núcleo son reglas puras (se prueban sin red) y un envoltorio delgado del SDK. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56, `s3`).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  estado:
    bucket: ${BUCKET_ESTADO}          # modalima-tfstate-111122223333
    lock-maximo-minutos: 60           # un candado más viejo se considera colgado
```
```properties
# Quarkus (application.properties)
app.estado.bucket=${BUCKET_ESTADO}
app.estado.lock-maximo-minutos=60
```

## 2. Núcleo común

### 2.1 Modelo
Tipos simples e inmutables. (Aquí van sin `public` por brevedad; si los separas en archivos, hazlos públicos.)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;

record ConfiguracionBucket(String bucket, boolean versionado, String cifrado, boolean bloqueoPublicoCompleto,
                           boolean exigeTls, boolean protegeBorradoDeVersiones) {
    static final String SIN_CIFRADO = "NINGUNO";
}

record ObjetoEstado(String clave, long bytes, Instant modificado) {
    boolean esCandado() {
        return clave.endsWith(".tflock");
    }

    boolean esEstado() {
        return clave.endsWith(".tfstate");
    }
}

record VersionDeEstado(String versionId, Instant modificado, long bytes, boolean actual, boolean marcadorDeBorrado) {}

record Hallazgo(Severidad severidad, String objeto, String regla, String detalle) {
    enum Severidad { ALTA, MEDIA, BAJA }
}
```

### 2.2 Lectura de la política del bucket
Sin Jackson: el analizador de JSON del propio SDK. Tolera sentencias como objeto o lista, y acciones/valores como texto o lista.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import software.amazon.awssdk.protocols.jsoncore.JsonNode;
import software.amazon.awssdk.protocols.jsoncore.JsonNodeParser;

public final class PoliticaDelBucket {
    private PoliticaDelBucket() {}

    /** ¿Hay una sentencia Deny que se activa cuando aws:SecureTransport es false? */
    public static boolean exigeTls(String politicaJson) {
        for (JsonNode s : sentenciasDeny(politicaJson)) {
            JsonNode condicion = campo(s, "Condition");
            for (String operador : List.of("Bool", "BoolIfExists")) {
                JsonNode bool = campo(condicion, operador);
                if (textos(campo(bool, "aws:SecureTransport")).stream().anyMatch(t -> t.equalsIgnoreCase("false"))) {
                    return true;
                }
            }
        }
        return false;
    }

    /** ¿Hay una sentencia Deny específica para el borrado de versiones? (s3:* no cuenta: sería la regla de TLS) */
    public static boolean protegeBorradoDeVersiones(String politicaJson) {
        for (JsonNode s : sentenciasDeny(politicaJson)) {
            if (textos(campo(s, "Action")).stream().anyMatch(a -> a.equalsIgnoreCase("s3:DeleteObjectVersion") || a.equalsIgnoreCase("s3:Delete*"))) {
                return true;
            }
        }
        return false;
    }

    private static List<JsonNode> sentenciasDeny(String json) {
        List<JsonNode> resultado = new ArrayList<>();
        if (json == null || json.isBlank()) {
            return resultado;
        }
        JsonNode sentencias = campo(JsonNodeParser.create().parse(json), "Statement");
        List<JsonNode> todas = new ArrayList<>();
        if (sentencias != null && sentencias.isArray()) {
            todas.addAll(sentencias.asArray());
        } else if (sentencias != null && sentencias.isObject()) {
            todas.add(sentencias);
        }
        for (JsonNode s : todas) {
            if (textos(campo(s, "Effect")).contains("Deny")) {
                resultado.add(s);
            }
        }
        return resultado;
    }

    private static JsonNode campo(JsonNode nodo, String nombre) {
        return nodo != null && nodo.isObject() ? nodo.asObject().get(nombre) : null;
    }

    private static List<String> textos(JsonNode nodo) {
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
}
```

### 2.3 Reglas del estado
Funciones puras: reciben datos, devuelven hallazgos ordenados por gravedad. Aquí viven las decisiones de seguridad.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

public final class ReglasDelEstado {
    static final Pattern CONVENCION = Pattern.compile("^env/(dev|stg|prod)/[a-z0-9-]+/terraform\\.tfstate$");
    static final long ESTADO_GRANDE_BYTES = 10L * 1024 * 1024;
    static final Duration INACTIVO = Duration.ofDays(365);

    private ReglasDelEstado() {}

    public static List<Hallazgo> auditarBucket(ConfiguracionBucket c) {
        List<Hallazgo> r = new ArrayList<>();
        if (!c.versionado()) {
            r.add(new Hallazgo(Hallazgo.Severidad.ALTA, c.bucket(), "SIN_VERSIONADO", "Sin versionado no hay recuperación ante borrados o corrupción"));
        }
        if (ConfiguracionBucket.SIN_CIFRADO.equals(c.cifrado())) {
            r.add(new Hallazgo(Hallazgo.Severidad.ALTA, c.bucket(), "SIN_CIFRADO", "El estado contiene secretos y no hay cifrado por defecto"));
        } else if ("AES256".equals(c.cifrado())) {
            r.add(new Hallazgo(Hallazgo.Severidad.MEDIA, c.bucket(), "CIFRADO_SIN_KMS", "Usa claves de S3; con KMS propio puedes separar permisos y auditar"));
        }
        if (!c.bloqueoPublicoCompleto()) {
            r.add(new Hallazgo(Hallazgo.Severidad.ALTA, c.bucket(), "ACCESO_PUBLICO_NO_BLOQUEADO", "Faltan una o más opciones de bloqueo de acceso público"));
        }
        if (!c.exigeTls()) {
            r.add(new Hallazgo(Hallazgo.Severidad.MEDIA, c.bucket(), "SIN_TLS_OBLIGATORIO", "La política no niega las solicitudes sin TLS"));
        }
        if (!c.protegeBorradoDeVersiones()) {
            r.add(new Hallazgo(Hallazgo.Severidad.MEDIA, c.bucket(), "BORRADO_DE_VERSIONES_SIN_PROTECCION", "Cualquiera con permiso de borrado podría eliminar el historial"));
        }
        return ordenar(r);
    }

    public static List<Hallazgo> auditarObjetos(List<ObjetoEstado> objetos, Instant ahora, Duration lockMaximo) {
        List<Hallazgo> r = new ArrayList<>();
        Set<String> estados = new HashSet<>();
        objetos.stream().filter(ObjetoEstado::esEstado).forEach(o -> estados.add(o.clave()));
        for (ObjetoEstado o : objetos) {
            if (o.esCandado()) {
                Duration edad = Duration.between(o.modificado(), ahora);
                if (edad.compareTo(lockMaximo) > 0) {
                    r.add(new Hallazgo(Hallazgo.Severidad.MEDIA, o.clave(), "CANDADO_COLGADO",
                            "Candado de hace " + edad.toMinutes() + " min: confirma que nadie aplica antes de force-unlock"));
                }
                String estado = o.clave().substring(0, o.clave().length() - ".tflock".length());
                if (!estados.contains(estado)) {
                    r.add(new Hallazgo(Hallazgo.Severidad.BAJA, o.clave(), "CANDADO_SIN_ESTADO", "No existe el estado correspondiente (¿primer apply interrumpido?)"));
                }
            } else if (o.esEstado()) {
                if (!CONVENCION.matcher(o.clave()).matches()) {
                    r.add(new Hallazgo(Hallazgo.Severidad.BAJA, o.clave(), "CLAVE_FUERA_DE_CONVENCION", "Se esperaba env/<dev|stg|prod>/<componente>/terraform.tfstate"));
                }
                if (o.bytes() > ESTADO_GRANDE_BYTES) {
                    r.add(new Hallazgo(Hallazgo.Severidad.MEDIA, o.clave(), "ESTADO_GRANDE", "Más de 10 MiB: planes lentos y mayor radio de explosión; considera dividirlo"));
                }
                if (Duration.between(o.modificado(), ahora).compareTo(INACTIVO) > 0) {
                    r.add(new Hallazgo(Hallazgo.Severidad.BAJA, o.clave(), "ESTADO_INACTIVO", "Sin cambios hace más de un año: ¿sigue existiendo lo que describe?"));
                }
            }
        }
        return ordenar(r);
    }

    private static List<Hallazgo> ordenar(List<Hallazgo> r) {
        r.sort(Comparator.comparing(Hallazgo::severidad).thenComparing(Hallazgo::objeto).thenComparing(Hallazgo::regla));
        return r;
    }
}
```

### 2.4 El auditor (envoltorio del SDK)
Las funciones estáticas de traducción se **comparten** con el cliente asíncrono. «No existe» (sin política, sin cifrado explícito, sin bloqueo de acceso público) es una respuesta válida de S3 que se convierte en un valor, no en una excepción que rompa la auditoría.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletionException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.BucketVersioningStatus;
import software.amazon.awssdk.services.s3.model.DeleteMarkerEntry;
import software.amazon.awssdk.services.s3.model.GetBucketEncryptionResponse;
import software.amazon.awssdk.services.s3.model.GetBucketVersioningResponse;
import software.amazon.awssdk.services.s3.model.GetPublicAccessBlockResponse;
import software.amazon.awssdk.services.s3.model.ListObjectVersionsResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.ObjectVersion;
import software.amazon.awssdk.services.s3.model.PublicAccessBlockConfiguration;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.S3Object;

public final class AuditorDelEstado {
    private static final Set<String> AUSENTES = Set.of(
            "NoSuchBucketPolicy", "ServerSideEncryptionConfigurationNotFoundError", "NoSuchPublicAccessBlockConfiguration");

    private final S3Client s3;

    public AuditorDelEstado(S3Client s3) {
        this.s3 = s3;
    }

    // ---- Traducciones (también las usa el cliente asíncrono)
    public static boolean versionado(GetBucketVersioningResponse r) {
        return r.status() == BucketVersioningStatus.ENABLED;
    }

    public static String cifrado(GetBucketEncryptionResponse r) {
        var reglas = r.serverSideEncryptionConfiguration().rules();
        if (reglas.isEmpty() || reglas.get(0).applyServerSideEncryptionByDefault() == null) {
            return ConfiguracionBucket.SIN_CIFRADO;
        }
        return reglas.get(0).applyServerSideEncryptionByDefault().sseAlgorithmAsString();
    }

    public static boolean bloqueoCompleto(GetPublicAccessBlockResponse r) {
        PublicAccessBlockConfiguration c = r.publicAccessBlockConfiguration();
        return c != null && Boolean.TRUE.equals(c.blockPublicAcls()) && Boolean.TRUE.equals(c.ignorePublicAcls())
                && Boolean.TRUE.equals(c.blockPublicPolicy()) && Boolean.TRUE.equals(c.restrictPublicBuckets());
    }

    public static ObjetoEstado aObjeto(S3Object o) {
        return new ObjetoEstado(o.key(), o.size() == null ? 0L : o.size(), o.lastModified());
    }

    /** ¿El error significa «esta configuración no existe»? (desenvuelve CompletionException del cliente asíncrono) */
    public static boolean esAusente(Throwable t) {
        Throwable causa = t instanceof CompletionException && t.getCause() != null ? t.getCause() : t;
        return causa instanceof S3Exception e && e.awsErrorDetails() != null && AUSENTES.contains(e.awsErrorDetails().errorCode());
    }

    public static boolean claveEsDelEstado(String clave) {
        return clave.endsWith(".tfstate") || clave.endsWith(".tflock");
    }

    // ---- Consultas síncronas
    public ConfiguracionBucket configuracion(String bucket) {
        boolean versionado = versionado(s3.getBucketVersioning(b -> b.bucket(bucket)));
        String cifrado;
        try {
            cifrado = cifrado(s3.getBucketEncryption(b -> b.bucket(bucket)));
        } catch (S3Exception e) {
            if (!esAusente(e)) {
                throw e;
            }
            cifrado = ConfiguracionBucket.SIN_CIFRADO;
        }
        boolean bloqueo;
        try {
            bloqueo = bloqueoCompleto(s3.getPublicAccessBlock(b -> b.bucket(bucket)));
        } catch (S3Exception e) {
            if (!esAusente(e)) {
                throw e;
            }
            bloqueo = false;
        }
        String politica;
        try {
            politica = s3.getBucketPolicy(b -> b.bucket(bucket)).policy();
        } catch (S3Exception e) {
            if (!esAusente(e)) {
                throw e;
            }
            politica = "";
        }
        return new ConfiguracionBucket(bucket, versionado, cifrado, bloqueo,
                PoliticaDelBucket.exigeTls(politica), PoliticaDelBucket.protegeBorradoDeVersiones(politica));
    }

    public List<ObjetoEstado> objetos(String bucket, String prefijo) {
        List<ObjetoEstado> objetos = new ArrayList<>();
        for (ListObjectsV2Response pagina : s3.listObjectsV2Paginator(b -> b.bucket(bucket).prefix(prefijo))) {
            for (S3Object o : pagina.contents()) {
                if (claveEsDelEstado(o.key())) {
                    objetos.add(aObjeto(o));
                }
            }
        }
        return objetos;
    }

    /** Historial de UN estado (para elegir qué versión recuperar). La restauración la hace una persona o un runbook, no esta herramienta. */
    public List<VersionDeEstado> versiones(String bucket, String clave) {
        List<VersionDeEstado> versiones = new ArrayList<>();
        for (ListObjectVersionsResponse pagina : s3.listObjectVersionsPaginator(b -> b.bucket(bucket).prefix(clave))) {
            for (ObjectVersion v : pagina.versions()) {
                if (v.key().equals(clave)) {
                    versiones.add(new VersionDeEstado(v.versionId(), v.lastModified(), v.size() == null ? 0L : v.size(), Boolean.TRUE.equals(v.isLatest()), false));
                }
            }
            for (DeleteMarkerEntry m : pagina.deleteMarkers()) {
                if (m.key().equals(clave)) {
                    versiones.add(new VersionDeEstado(m.versionId(), m.lastModified(), 0L, Boolean.TRUE.equals(m.isLatest()), true));
                }
            }
        }
        versiones.sort((a, b) -> b.modificado().compareTo(a.modificado()));
        return versiones;
    }

    public List<Hallazgo> auditar(String bucket, String prefijo, Clock reloj, Duration lockMaximo) {
        List<Hallazgo> hallazgos = new ArrayList<>(ReglasDelEstado.auditarBucket(configuracion(bucket)));
        hallazgos.addAll(ReglasDelEstado.auditarObjetos(objetos(bucket, prefijo), reloj.instant(), lockMaximo));
        return hallazgos;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
class EstadoConfig {
    @Bean(destroyMethod = "close")
    S3Client s3() {
        return S3Client.create();
    }

    @Bean
    AuditorDelEstado auditor(S3Client s3) {
        return new AuditorDelEstado(s3);
    }
}

@RestController
@RequestMapping("/estado")
class EstadoController {
    private final AuditorDelEstado auditor;
    private final String bucket;
    private final Duration lockMaximo;

    EstadoController(AuditorDelEstado auditor, @Value("${app.estado.bucket}") String bucket,
                     @Value("${app.estado.lock-maximo-minutos}") long minutos) {
        this.auditor = auditor;
        this.bucket = bucket;
        this.lockMaximo = Duration.ofMinutes(minutos);
    }

    @GetMapping("/auditoria")
    List<Hallazgo> auditoria(@RequestParam(defaultValue = "env/") String prefijo) {
        return auditor.auditar(bucket, prefijo, Clock.systemUTC(), lockMaximo);
    }

    @GetMapping("/versiones")
    List<VersionDeEstado> versiones(@RequestParam String clave) {
        if (!clave.startsWith("env/") || !clave.endsWith(".tfstate")) {
            throw new IllegalArgumentException("clave fuera de la convención");
        }
        return auditor.versiones(bucket, clave);
    }
}
```

## 4. Spring WebFlux (reactivo)
Las cuatro lecturas de configuración y el listado corren en paralelo con `Mono.zip`; «no existe» se convierte en un valor con `onErrorResume`.
```java
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import software.amazon.awssdk.services.s3.S3AsyncClient;

@Configuration
class EstadoReactivoConfig {
    @Bean(destroyMethod = "close")
    S3AsyncClient s3Async() {
        return S3AsyncClient.create();
    }
}

@RestController
@RequestMapping("/r/estado")
class EstadoReactivoController {
    private final S3AsyncClient s3;
    private final String bucket;
    private final Duration lockMaximo;

    EstadoReactivoController(S3AsyncClient s3, @Value("${app.estado.bucket}") String bucket,
                             @Value("${app.estado.lock-maximo-minutos}") long minutos) {
        this.s3 = s3;
        this.bucket = bucket;
        this.lockMaximo = Duration.ofMinutes(minutos);
    }

    @GetMapping("/auditoria")
    Mono<List<Hallazgo>> auditoria(@RequestParam(defaultValue = "env/") String prefijo) {
        Mono<Boolean> versionado = Mono.fromFuture(() -> s3.getBucketVersioning(b -> b.bucket(bucket)))
                .map(AuditorDelEstado::versionado);
        Mono<String> cifrado = Mono.fromFuture(() -> s3.getBucketEncryption(b -> b.bucket(bucket)))
                .map(AuditorDelEstado::cifrado)
                .onErrorResume(AuditorDelEstado::esAusente, e -> Mono.just(ConfiguracionBucket.SIN_CIFRADO));
        Mono<Boolean> bloqueo = Mono.fromFuture(() -> s3.getPublicAccessBlock(b -> b.bucket(bucket)))
                .map(AuditorDelEstado::bloqueoCompleto)
                .onErrorResume(AuditorDelEstado::esAusente, e -> Mono.just(false));
        Mono<String> politica = Mono.fromFuture(() -> s3.getBucketPolicy(b -> b.bucket(bucket)))
                .map(r -> r.policy())
                .onErrorResume(AuditorDelEstado::esAusente, e -> Mono.just(""));
        Mono<List<ObjetoEstado>> objetos = Flux.from(s3.listObjectsV2Paginator(b -> b.bucket(bucket).prefix(prefijo)).contents())
                .filter(o -> AuditorDelEstado.claveEsDelEstado(o.key()))
                .map(AuditorDelEstado::aObjeto)
                .collectList();

        return Mono.zip(versionado, cifrado, bloqueo, politica, objetos).map(t -> {
            ConfiguracionBucket config = new ConfiguracionBucket(bucket, t.getT1(), t.getT2(), t.getT3(),
                    PoliticaDelBucket.exigeTls(t.getT4()), PoliticaDelBucket.protegeBorradoDeVersiones(t.getT4()));
            List<Hallazgo> hallazgos = new ArrayList<>(ReglasDelEstado.auditarBucket(config));
            hallazgos.addAll(ReglasDelEstado.auditarObjetos(t.getT5(), Clock.systemUTC().instant(), lockMaximo));
            return hallazgos;
        });
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import software.amazon.awssdk.services.s3.S3AsyncClient;
import software.amazon.awssdk.services.s3.S3Client;

@ApplicationScoped
class EstadoProductores {
    @Produces
    @Singleton
    S3Client s3() {
        return S3Client.create();
    }

    void cerrar(@Disposes S3Client c) {
        c.close();
    }

    @Produces
    @Singleton
    S3AsyncClient s3Async() {
        return S3AsyncClient.create();
    }

    void cerrarAsync(@Disposes S3AsyncClient c) {
        c.close();
    }

    @Produces
    @Singleton
    AuditorDelEstado auditor(S3Client s3) {
        return new AuditorDelEstado(s3);
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
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@Path("/estado")
@Produces(MediaType.APPLICATION_JSON)
class EstadoRecurso {
    @Inject
    AuditorDelEstado auditor;

    @ConfigProperty(name = "app.estado.bucket")
    String bucket;

    @ConfigProperty(name = "app.estado.lock-maximo-minutos")
    long lockMaximoMinutos;

    @GET
    @Path("/auditoria")
    public List<Hallazgo> auditoria(@QueryParam("prefijo") @DefaultValue("env/") String prefijo) {
        return auditor.auditar(bucket, prefijo, Clock.systemUTC(), Duration.ofMinutes(lockMaximoMinutos));
    }

    @GET
    @Path("/versiones")
    public List<VersionDeEstado> versiones(@QueryParam("clave") String clave) {
        if (clave == null || !clave.startsWith("env/") || !clave.endsWith(".tfstate")) {
            throw new jakarta.ws.rs.BadRequestException("clave fuera de la convención");
        }
        return auditor.versiones(bucket, clave);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.reactivestreams.FlowAdapters;
import software.amazon.awssdk.services.s3.S3AsyncClient;

@Path("/m/estado")
@Produces(MediaType.APPLICATION_JSON)
class EstadoMutinyRecurso {
    @Inject
    S3AsyncClient s3;

    @ConfigProperty(name = "app.estado.bucket")
    String bucket;

    @ConfigProperty(name = "app.estado.lock-maximo-minutos")
    long lockMaximoMinutos;

    @GET
    @Path("/auditoria")
    public Uni<List<Hallazgo>> auditoria(@QueryParam("prefijo") @DefaultValue("env/") String prefijo) {
        Uni<Boolean> versionado = Uni.createFrom().completionStage(() -> s3.getBucketVersioning(b -> b.bucket(bucket)))
                .map(AuditorDelEstado::versionado);
        Uni<String> cifrado = Uni.createFrom().completionStage(() -> s3.getBucketEncryption(b -> b.bucket(bucket)))
                .map(AuditorDelEstado::cifrado)
                .onFailure(AuditorDelEstado::esAusente).recoverWithItem(ConfiguracionBucket.SIN_CIFRADO);
        Uni<Boolean> bloqueo = Uni.createFrom().completionStage(() -> s3.getPublicAccessBlock(b -> b.bucket(bucket)))
                .map(AuditorDelEstado::bloqueoCompleto)
                .onFailure(AuditorDelEstado::esAusente).recoverWithItem(false);
        Uni<String> politica = Uni.createFrom().completionStage(() -> s3.getBucketPolicy(b -> b.bucket(bucket)))
                .map(r -> r.policy())
                .onFailure(AuditorDelEstado::esAusente).recoverWithItem("");
        Uni<List<ObjetoEstado>> objetos = Multi.createFrom()
                .publisher(FlowAdapters.toFlowPublisher(s3.listObjectsV2Paginator(b -> b.bucket(bucket).prefix(prefijo)).contents()))
                .filter(o -> AuditorDelEstado.claveEsDelEstado(o.key()))
                .map(AuditorDelEstado::aObjeto)
                .collect().asList();

        return Uni.combine().all().unis(versionado, cifrado, bloqueo, politica, objetos).with((v, c, b, p, o) -> {
            ConfiguracionBucket config = new ConfiguracionBucket(bucket, v, c, b,
                    PoliticaDelBucket.exigeTls(p), PoliticaDelBucket.protegeBorradoDeVersiones(p));
            List<Hallazgo> hallazgos = new ArrayList<>(ReglasDelEstado.auditarBucket(config));
            hallazgos.addAll(ReglasDelEstado.auditarObjetos(o, Clock.systemUTC().instant(), Duration.ofMinutes(lockMaximoMinutos)));
            return hallazgos;
        });
    }
}
```

## 7. Permisos
El auditor es de **solo lectura**: `s3:GetBucketVersioning`, `s3:GetEncryptionConfiguration`, `s3:GetBucketPublicAccessBlock`, `s3:GetBucketPolicy` sobre el bucket; `s3:ListBucket` y `s3:ListBucketVersions` sobre el bucket (con condición de prefijo `env/*` si quieres limitarlo). **No** necesita `s3:GetObject`: audita metadatos, no lee los estados (que contienen secretos). Tampoco permisos de escritura ni de borrado.

## 8. Qué NO hacer desde Java
- **No** descargues ni registres el contenido de los estados: contienen secretos en texto claro (§7).
- **No** automatices `force-unlock` ni la restauración de versiones: son decisiones humanas con verificación (§2.4 solo lista).
- **No** des permisos de escritura sobre el bucket del estado a una herramienta de consulta.
- **No** trates «sin política» o «sin cifrado explícito» como error de la herramienta: son hallazgos (§2.4).
- **No** permitas que un parámetro de la API recorra claves arbitrarias del bucket: valida convención de la clave (`env/…/terraform.tfstate`).
- **No** audites desde un rol con permisos de administración del estado.
