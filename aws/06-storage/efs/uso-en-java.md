# AWS · EFS · Uso desde Java

Para Java, EFS es **una carpeta**: usas `java.nio.file`. Lo que cambia respecto a un disco local es que está en red: hay que **validar rutas**, **escribir de forma atómica**, **coordinarse con bloqueos** y **no dejar que una comprobación de salud se cuelgue** si el montaje no responde. La administración (auditar configuración) se hace con el SDK. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  efs:
    ruta: /mnt/datos            # punto de montaje (ver ECS / EKS / Lambda)
    timeout-sonda: 2s
management:
  endpoint:
    health:
      probes:
        enabled: true
```
```properties
# Quarkus (application.properties)
app.efs.ruta=/mnt/datos
app.efs.timeout-sonda=2S
quarkus.efs.aws.region=us-east-1
```
Montaje: ECS (`ejemplos/json/ecs-volumen.json`), EKS (`ejemplos/k8s/efs.yaml`), Lambda (`/mnt/...` por configuración de la función).

## 2. Núcleo común

### 2.1 Rutas seguras dentro del montaje
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;

public final class RutaSegura {
    private final java.nio.file.Path base;

    public RutaSegura(java.nio.file.Path base) throws IOException {
        this.base = base.toRealPath();                  // resuelve enlaces simbólicos de la propia base
    }

    /** Resuelve una ruta relativa que viene del usuario. Rechaza "..", rutas absolutas y enlaces que escapan. */
    public java.nio.file.Path resolver(String relativa) {
        if (relativa == null || relativa.isBlank() || relativa.indexOf('\0') >= 0 || relativa.indexOf('\\') >= 0) {
            throw new IllegalArgumentException("ruta inválida");
        }
        java.nio.file.Path rel = java.nio.file.Path.of(relativa);
        if (rel.isAbsolute()) {
            throw new IllegalArgumentException("la ruta debe ser relativa");
        }
        java.nio.file.Path destino = base.resolve(rel).normalize();
        if (!destino.startsWith(base)) {
            throw new SecurityException("la ruta sale del directorio permitido");
        }
        // Un enlace simbólico dentro del montaje puede apuntar fuera: se comprueba el ancestro existente más cercano.
        java.nio.file.Path existente = destino;
        while (existente != null && !Files.exists(existente, LinkOption.NOFOLLOW_LINKS)) {
            existente = existente.getParent();
        }
        try {
            if (existente != null && !existente.toRealPath().startsWith(base)) {
                throw new SecurityException("un enlace simbólico apunta fuera del directorio permitido");
            }
        } catch (IOException e) {
            throw new SecurityException("enlace roto o ilegible: " + existente);
        }
        return destino;
    }

    public java.nio.file.Path base() {
        return base;
    }
}
```

### 2.2 Escritura atómica y «crear solo si no existe»
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.io.InputStream;
import java.nio.channels.FileChannel;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.UUID;

public final class EscrituraAtomica {
    private EscrituraAtomica() {}

    /** Escribe en un temporal del MISMO directorio, fuerza a disco y renombra: nadie ve un archivo a medias. */
    public static void escribir(java.nio.file.Path destino, InputStream datos) throws IOException {
        java.nio.file.Path dir = destino.getParent();
        Files.createDirectories(dir);
        java.nio.file.Path tmp = dir.resolve(".tmp-" + UUID.randomUUID());
        try {
            try (FileChannel canal = FileChannel.open(tmp, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = datos.read(buf)) > 0) {
                    canal.write(java.nio.ByteBuffer.wrap(buf, 0, n));
                }
                canal.force(true);
            }
            Files.move(tmp, destino, StandardCopyOption.ATOMIC_MOVE);
        } finally {
            Files.deleteIfExists(tmp);
        }
    }

    /** true si lo creó; false si ya existía. Usa un enlace duro: la operación es atómica incluso sobre NFS. */
    public static boolean crearSiNoExiste(java.nio.file.Path destino, byte[] contenido) throws IOException {
        java.nio.file.Path dir = destino.getParent();
        Files.createDirectories(dir);
        java.nio.file.Path tmp = dir.resolve(".tmp-" + UUID.randomUUID());
        try {
            Files.write(tmp, contenido, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
            Files.createLink(destino, tmp);
            return true;
        } catch (FileAlreadyExistsException e) {
            return false;
        } finally {
            Files.deleteIfExists(tmp);
        }
    }
}
```

### 2.3 Bloqueo de archivo con espera máxima
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.channels.OverlappingFileLockException;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.util.concurrent.Callable;
import java.util.concurrent.TimeoutException;

public final class Candado {
    private Candado() {}

    /**
     * Ejecuta la tarea con un bloqueo consultivo (NFS) sobre un archivo ".lock".
     * Solo coordina a quienes también usan el bloqueo; no protege contra escritores que lo ignoren.
     */
    public static <T> T conBloqueo(java.nio.file.Path archivoLock, Duration espera, Callable<T> tarea) throws Exception {
        long limite = System.nanoTime() + espera.toNanos();
        try (FileChannel canal = FileChannel.open(archivoLock, StandardOpenOption.CREATE, StandardOpenOption.WRITE)) {
            while (true) {
                FileLock lock = null;
                try {
                    lock = canal.tryLock();
                } catch (OverlappingFileLockException ocupadoEnEstaJvm) {
                    // otro hilo de esta JVM lo tiene: reintentar
                }
                if (lock != null) {
                    try {
                        return tarea.call();
                    } finally {
                        lock.release();
                    }
                }
                if (System.nanoTime() > limite) {
                    throw new TimeoutException("no se obtuvo el bloqueo en " + espera);
                }
                Thread.sleep(100);
            }
        }
    }
}
```

### 2.4 Sonda del montaje (con timeout)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

public final class SondaMontaje implements AutoCloseable {
    public record Resultado(boolean ok, long milisegundos, String detalle) {}

    private final java.nio.file.Path directorio;
    private final Duration timeout;
    private final ExecutorService hilo = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "sonda-montaje");
        t.setDaemon(true);                             // una sonda colgada no impide apagar la aplicación
        return t;
    });
    private Future<Long> anterior;

    public SondaMontaje(java.nio.file.Path directorio, Duration timeout) {
        this.directorio = directorio;
        this.timeout = timeout;
    }

    /** Escribe, lee y borra un archivo diminuto. Si la sonda anterior sigue colgada, falla al instante. */
    public synchronized Resultado verificar() {
        if (anterior != null && !anterior.isDone()) {
            return new Resultado(false, 0, "la sonda anterior sigue sin terminar: el montaje no responde");
        }
        long ini = System.nanoTime();
        anterior = hilo.submit(() -> {
            java.nio.file.Path p = directorio.resolve(".sonda-" + UUID.randomUUID());
            Files.writeString(p, "ok", StandardCharsets.UTF_8);
            String leido = Files.readString(p, StandardCharsets.UTF_8);
            Files.delete(p);
            if (!"ok".equals(leido)) {
                throw new IOException("lectura distinta a la escritura");
            }
            return 0L;
        });
        try {
            anterior.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
            return new Resultado(true, (System.nanoTime() - ini) / 1_000_000, "escritura y lectura correctas");
        } catch (TimeoutException e) {
            return new Resultado(false, timeout.toMillis(), "sin respuesta en " + timeout);
        } catch (ExecutionException e) {
            return new Resultado(false, (System.nanoTime() - ini) / 1_000_000, String.valueOf(e.getCause()));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return new Resultado(false, 0, "interrumpida");
        }
    }

    @Override
    public void close() {
        hilo.shutdownNow();
    }
}
```

### 2.5 Auditoría de la configuración con el SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import software.amazon.awssdk.services.efs.EfsClient;
import software.amazon.awssdk.services.efs.model.DescribeAccessPointsRequest;
import software.amazon.awssdk.services.efs.model.DescribeBackupPolicyRequest;
import software.amazon.awssdk.services.efs.model.DescribeFileSystemsRequest;
import software.amazon.awssdk.services.efs.model.DescribeLifecycleConfigurationRequest;
import software.amazon.awssdk.services.efs.model.DescribeMountTargetsRequest;
import software.amazon.awssdk.services.efs.model.FileSystemDescription;

public final class AuditoriaEfs {
    public record Resumen(String id, boolean cifrado, String throughput, int mountTargets, int zonasEsperadas,
                          int puntosAcceso, boolean cicloDeVida, boolean backup) {}

    private final EfsClient efs;

    public AuditoriaEfs(EfsClient efs) {
        this.efs = efs;
    }

    public Resumen resumen(String fileSystemId, int zonasEsperadas) {
        FileSystemDescription fs = efs.describeFileSystems(
                DescribeFileSystemsRequest.builder().fileSystemId(fileSystemId).build()).fileSystems().get(0);
        int mt = efs.describeMountTargets(DescribeMountTargetsRequest.builder().fileSystemId(fileSystemId).build())
                .mountTargets().size();
        int ap = efs.describeAccessPoints(DescribeAccessPointsRequest.builder().fileSystemId(fileSystemId).build())
                .accessPoints().size();
        boolean ciclo = !efs.describeLifecycleConfiguration(
                DescribeLifecycleConfigurationRequest.builder().fileSystemId(fileSystemId).build())
                .lifecyclePolicies().isEmpty();
        boolean backup = efs.describeBackupPolicy(DescribeBackupPolicyRequest.builder().fileSystemId(fileSystemId).build())
                .backupPolicy().statusAsString().equals("ENABLED");
        return new Resumen(fs.fileSystemId(), Boolean.TRUE.equals(fs.encrypted()), fs.throughputModeAsString(),
                mt, zonasEsperadas, ap, ciclo, backup);
    }

    /** Reglas de buena práctica. Es una función pura: se prueba sin red. */
    public static List<String> evaluar(Resumen r) {
        List<String> h = new ArrayList<>();
        if (!r.cifrado()) {
            h.add("CRÍTICO: sin cifrado en reposo (no se puede activar después: crear uno nuevo y migrar)");
        }
        if (r.mountTargets() < r.zonasEsperadas()) {
            h.add("ALTO: faltan mount targets (" + r.mountTargets() + " de " + r.zonasEsperadas() + " zonas)");
        }
        if (r.puntosAcceso() == 0) {
            h.add("MEDIO: sin puntos de acceso: las aplicaciones montarán la raíz");
        }
        if (!r.cicloDeVida()) {
            h.add("BAJO: sin ciclo de vida hacia IA/Archive");
        }
        if (!r.backup()) {
            h.add("ALTO: sin respaldo automático (AWS Backup)");
        }
        if (!"elastic".equalsIgnoreCase(r.throughput())) {
            h.add("INFO: throughput " + r.throughput() + " (revisa si Elastic te conviene)");
        }
        return h;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.nio.file.Files;
import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.efs.EfsClient;

@Configuration
class EfsConfig {
    @Bean
    RutaSegura rutaSegura(@Value("${app.efs.ruta}") String ruta) throws IOException {
        return new RutaSegura(java.nio.file.Path.of(ruta));
    }

    @Bean(destroyMethod = "close")
    SondaMontaje sonda(@Value("${app.efs.ruta}") String ruta, @Value("${app.efs.timeout-sonda:2s}") Duration timeout) {
        return new SondaMontaje(java.nio.file.Path.of(ruta), timeout);
    }

    @Bean(destroyMethod = "close")
    EfsClient efs() {
        return EfsClient.create();
    }

    @Bean
    AuditoriaEfs auditoria(EfsClient efs) {
        return new AuditoriaEfs(efs);
    }
}

/** Salud de READINESS (no de liveness): si el montaje falla, el pod deja de recibir tráfico pero no se reinicia en bucle. */
@Component("montajeEfs")
class MontajeEfsHealth implements HealthIndicator {
    private final SondaMontaje sonda;

    MontajeEfsHealth(SondaMontaje sonda) {
        this.sonda = sonda;
    }

    @Override
    public Health health() {
        SondaMontaje.Resultado r = sonda.verificar();
        Health.Builder b = r.ok() ? Health.up() : Health.down();
        return b.withDetail("ms", r.milisegundos()).withDetail("detalle", r.detalle()).build();
    }
}

@RestController
class ArchivosEfsController {
    private final RutaSegura rutas;
    private final AuditoriaEfs auditoria;

    ArchivosEfsController(RutaSegura rutas, AuditoriaEfs auditoria) {
        this.rutas = rutas;
        this.auditoria = auditoria;
    }

    @PutMapping("/archivos-efs")
    Map<String, Object> guardar(@RequestParam String ruta, HttpServletRequest req) throws IOException {
        java.nio.file.Path destino = rutas.resolver(ruta);
        EscrituraAtomica.escribir(destino, req.getInputStream());
        return Map.of("ruta", ruta, "bytes", Files.size(destino));
    }

    @GetMapping("/archivos-efs")
    ResponseEntity<Resource> leer(@RequestParam String ruta) {
        java.nio.file.Path origen = rutas.resolver(ruta);
        if (!Files.isRegularFile(origen)) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(new FileSystemResource(origen));
    }

    @GetMapping("/interno/efs/auditoria")
    Map<String, Object> auditar(@RequestParam String fileSystemId, @RequestParam(defaultValue = "3") int zonas) {
        var resumen = auditoria.resumen(fileSystemId, zonas);
        return Map.of("resumen", resumen, "hallazgos", AuditoriaEfs.evaluar(resumen));
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.nio.file.Files;
import java.util.Map;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.ReactiveHealthIndicator;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@Component("montajeEfsReactivo")
class MontajeEfsReactiveHealth implements ReactiveHealthIndicator {
    private final SondaMontaje sonda;

    MontajeEfsReactiveHealth(SondaMontaje sonda) {
        this.sonda = sonda;
    }

    /** La sonda bloquea (con timeout propio): se aísla en boundedElastic. */
    @Override
    public Mono<Health> health() {
        return Mono.fromCallable(sonda::verificar)
                .subscribeOn(Schedulers.boundedElastic())
                .map(r -> (r.ok() ? Health.up() : Health.down())
                        .withDetail("ms", r.milisegundos()).withDetail("detalle", r.detalle()).build());
    }
}

@RestController
class ArchivosEfsReactivoController {
    private final RutaSegura rutas;

    ArchivosEfsReactivoController(RutaSegura rutas) {
        this.rutas = rutas;
    }

    /** El archivo llega por partes; se escribe con transferTo y luego se mueve de forma atómica. */
    @PostMapping("/archivos-efs-r")
    Mono<Map<String, Object>> subir(@RequestParam String ruta, @RequestPart("archivo") FilePart parte) {
        return Mono.fromCallable(() -> rutas.resolver(ruta))
                .subscribeOn(Schedulers.boundedElastic())
                .flatMap(destino -> Mono.fromCallable(() -> {
                            Files.createDirectories(destino.getParent());
                            return destino.resolveSibling(".tmp-" + java.util.UUID.randomUUID());
                        })
                        .subscribeOn(Schedulers.boundedElastic())
                        .flatMap(tmp -> parte.transferTo(tmp)
                                .then(Mono.fromCallable(() -> {
                                    Files.move(tmp, destino, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
                                    return Map.<String, Object>of("ruta", ruta, "bytes", Files.size(destino));
                                }).subscribeOn(Schedulers.boundedElastic()))
                                .doOnError(e -> tmp.toFile().delete())));
    }
}
```

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.io.IOException;
import java.time.Duration;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;

@ApplicationScoped
class EfsProductores {
    @Produces
    @Singleton
    RutaSegura rutaSegura(@ConfigProperty(name = "app.efs.ruta") String ruta) throws IOException {
        return new RutaSegura(java.nio.file.Path.of(ruta));
    }

    @Produces
    @Singleton
    SondaMontaje sonda(@ConfigProperty(name = "app.efs.ruta") String ruta,
                       @ConfigProperty(name = "app.efs.timeout-sonda") Duration timeout) {
        return new SondaMontaje(java.nio.file.Path.of(ruta), timeout);
    }
}

@Readiness
@ApplicationScoped
class MontajeEfsCheck implements HealthCheck {
    private final SondaMontaje sonda;

    MontajeEfsCheck(SondaMontaje sonda) {
        this.sonda = sonda;
    }

    @Override
    public HealthCheckResponse call() {
        SondaMontaje.Resultado r = sonda.verificar();
        var b = HealthCheckResponse.named("montaje-efs").withData("ms", r.milisegundos()).withData("detalle", r.detalle());
        return r.ok() ? b.up().build() : b.down().build();
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.util.Map;

@Path("/archivos-efs")
class ArchivosEfsRecurso {
    @Inject
    RutaSegura rutas;

    @PUT
    @Consumes(MediaType.APPLICATION_OCTET_STREAM)
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, Object> guardar(@QueryParam("ruta") String ruta, InputStream cuerpo) throws IOException {
        java.nio.file.Path destino = rutas.resolver(ruta);
        EscrituraAtomica.escribir(destino, cuerpo);
        return Map.of("ruta", ruta, "bytes", Files.size(destino));
    }

    @GET
    @Produces(MediaType.APPLICATION_OCTET_STREAM)
    public java.io.File leer(@QueryParam("ruta") String ruta) {
        java.nio.file.Path origen = rutas.resolver(ruta);
        if (!Files.isRegularFile(origen)) {
            throw new NotFoundException();
        }
        return origen.toFile();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;

@Path("/interno/efs")
class EfsMutinyRecurso {
    @Inject
    SondaMontaje sonda;

    /** Comprobar el montaje es E/S bloqueante: fuera del hilo de eventos. */
    @GET
    @Path("/sonda")
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Map<String, Object>> sonda() {
        return Uni.createFrom().item(sonda::verificar)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(r -> Map.<String, Object>of("ok", r.ok(), "ms", r.milisegundos(), "detalle", r.detalle()));
    }
}
```

## 7. Permisos
Rol de la aplicación: `elasticfilesystem:ClientMount` y `ClientWrite` condicionados al punto de acceso (ver [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)). Para `AuditoriaEfs` (herramienta de operación): `elasticfilesystem:Describe*` de solo lectura.

## 8. Qué NO hacer desde Java
- **No** concatenes rutas del usuario con `Path.of(base, entrada)`: usa `RutaSegura` (`..` y enlaces simbólicos).
- **No** escribas directo en el destino: usa `EscrituraAtomica`.
- **No** hagas E/S del montaje en un hilo de eventos (WebFlux/Vert.x): `boundedElastic` / pool de trabajadores.
- **No** pongas el EFS en la sonda de *liveness*: un fallo del montaje reiniciaría todos los pods a la vez; úsalo en *readiness*.
- **No** tomes `FileLock` como candado distribuido infalible: es consultivo y depende del cliente NFS.
- **No** guardes millones de archivos diminutos en un solo directorio: reparte en subdirectorios.
- **No** uses EFS como base de datos ni para logs de alto volumen.
