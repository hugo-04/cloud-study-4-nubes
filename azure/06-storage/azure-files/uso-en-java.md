# Azure · Azure Files · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-storage-file-share`, `azure-identity`). Verifica las vigentes.

Hay **dos formas** de usar Azure Files desde Java y se eligen por el caso:

| Forma | Cómo | Cuándo |
|---|---|---|
| **A. Ruta montada** | El share está montado en el sistema operativo (VM, pod de AKS, Container Apps) y usas `java.nio.file` | Aplicaciones que ya trabajan con carpetas; lotes; varios procesos compartiendo archivos |
| **B. SDK por REST** | `azure-storage-file-share` con identidad administrada, sin montar nada | Servicios fuera de Azure o sin montaje; control fino; instantáneas; no depender del puerto 445 |

```properties
# Spring Boot
app.files.endpoint=https://stmodalimafiles.file.core.windows.net
app.files.share=contabilidad
app.carpeta.base=/mnt/contabilidad
app.carpeta.intervalo=PT10S
```
```properties
# Quarkus
app.files.endpoint=https://stmodalimafiles.file.core.windows.net
app.files.share=contabilidad
```
```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-file-share</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
```
Rol del SDK: *Storage File Data Privileged Contributor* (o *Privileged Reader* para solo lectura). Con identidad por REST hay que declarar la **intención del token** (`BACKUP`).

## 1. Forma A · Ruta montada: producir archivos sin que el lector vea "a medias"

SMB y NFS no avisan a otros clientes de lo que escribes, y un archivo grande tarda en copiarse. Regla de oro: **escribe con extensión temporal y renombra al terminar** (el renombrado dentro del mismo share es atómico).

```java
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.UUID;

class EscritorDeCarpeta {

    private final Path base;

    EscritorDeCarpeta(Path base) {
        this.base = base;
    }

    /** Escribe en un archivo .part y lo publica con un renombrado atómico. */
    Path publicar(String nombreFinal, InputStream contenido) throws IOException {
        Files.createDirectories(base.resolve("entrada"));
        Path temporal = base.resolve("entrada").resolve(nombreFinal + "." + UUID.randomUUID() + ".part");
        Path destino = base.resolve("entrada").resolve(nombreFinal);
        try (var salida = Files.newOutputStream(temporal, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            contenido.transferTo(salida);
        }
        return Files.move(temporal, destino, StandardCopyOption.ATOMIC_MOVE);
    }
}
```

## 2. Forma A · Consumir: sondeo, "reclamar" por renombrado y mover a procesados

`WatchService` de Java **no detecta** cambios hechos por otros clientes sobre SMB/NFS: usa **sondeo**. Para que varias réplicas no procesen el mismo archivo, cada una intenta **reclamarlo moviéndolo** a `procesando/`: el renombrado atómico lo gana solo una.

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.stream.Stream;

@Component
class ProcesadorDeCarpeta {

    private static final Logger LOG = LoggerFactory.getLogger(ProcesadorDeCarpeta.class);
    private static final Duration ESTABILIDAD = Duration.ofSeconds(30);   // el archivo no debe haberse tocado en 30 s

    private final Path entrada;
    private final Path procesando;
    private final Path procesados;
    private final Path errores;

    ProcesadorDeCarpeta(@Value("${app.carpeta.base}") Path base) throws IOException {
        this.entrada = Files.createDirectories(base.resolve("entrada"));
        this.procesando = Files.createDirectories(base.resolve("procesando"));
        this.procesados = Files.createDirectories(base.resolve("procesados"));
        this.errores = Files.createDirectories(base.resolve("errores"));
    }

    @Scheduled(fixedDelayString = "${app.carpeta.intervalo:PT10S}")
    void revisar() throws IOException {
        List<Path> candidatos;
        try (Stream<Path> lista = Files.list(entrada)) {
            candidatos = lista.filter(Files::isRegularFile)
                    .filter(p -> !p.getFileName().toString().endsWith(".part"))     // nunca los temporales
                    .filter(this::estable)
                    .toList();
        }
        for (Path archivo : candidatos) {
            Path reclamado = reclamar(archivo);
            if (reclamado != null) {
                procesar(reclamado);
            }
        }
    }

    private boolean estable(Path archivo) {
        try {
            return Files.getLastModifiedTime(archivo).toInstant().isBefore(Instant.now().minus(ESTABILIDAD));
        } catch (IOException e) {
            return false;
        }
    }

    /** Solo una réplica gana el renombrado; las demás reciben NoSuchFileException y lo saltan. */
    private Path reclamar(Path archivo) throws IOException {
        Path destino = procesando.resolve(archivo.getFileName());
        try {
            return Files.move(archivo, destino, StandardCopyOption.ATOMIC_MOVE);
        } catch (NoSuchFileException otraReplicaLoTomo) {
            return null;
        } catch (AtomicMoveNotSupportedException e) {
            LOG.error("El sistema de archivos no soporta renombrado atómico: {}", e.getMessage());
            return null;
        }
    }

    private void procesar(Path archivo) {
        try (BufferedReader lector = Files.newBufferedReader(archivo, StandardCharsets.UTF_8)) {
            long filas = 0;
            while (lector.readLine() != null) {
                filas++;                                                           // validar/cargar por lotes
            }
            Files.move(archivo, procesados.resolve(archivo.getFileName()), StandardCopyOption.REPLACE_EXISTING);
            LOG.info("{} procesado ({} filas)", archivo.getFileName(), filas);
        } catch (IOException | RuntimeException e) {
            LOG.warn("Fallo con {}: {}", archivo.getFileName(), e.toString());
            try {
                Files.move(archivo, errores.resolve(archivo.getFileName()), StandardCopyOption.REPLACE_EXISTING);
            } catch (IOException ignorado) {
                LOG.error("No se pudo mover a errores: {}", archivo);
            }
        }
    }
}
```
Recuerda `@EnableScheduling` en la aplicación. Si el proceso se cae con el archivo en `procesando/`, un trabajo de limpieza debe devolver a `entrada/` lo que lleve demasiado tiempo allí.

## 3. Forma B · SDK por REST con identidad administrada (imperativo)

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.file.share.ShareClient;
import com.azure.storage.file.share.ShareDirectoryClient;
import com.azure.storage.file.share.ShareFileClient;
import com.azure.storage.file.share.ShareServiceClient;
import com.azure.storage.file.share.ShareServiceClientBuilder;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareTokenIntent;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

@Configuration
class FilesConfig {

    @Bean
    ShareServiceClient servicioDeShares(@Value("${app.files.endpoint}") String endpoint) {
        return new ShareServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .shareTokenIntent(ShareTokenIntent.BACKUP)       // obligatorio con identidad por REST
                .buildClient();
    }
}

@Service
class RepositorioCompartido {

    private final ShareClient share;

    RepositorioCompartido(ShareServiceClient servicio, @Value("${app.files.share}") String nombre) {
        this.share = servicio.getShareClient(nombre);
    }

    /** Crea la jerarquía de carpetas "a/b/c" si no existe. */
    ShareDirectoryClient asegurarDirectorio(String ruta) {
        ShareDirectoryClient actual = share.getRootDirectoryClient();
        for (String parte : ruta.split("/")) {
            if (parte.isBlank()) {
                continue;
            }
            actual = actual.getSubdirectoryClient(parte);
            if (!actual.exists()) {
                actual.create();
            }
        }
        return actual;
    }

    /** Sube un archivo local de cualquier tamaño (el SDK lo parte en rangos). */
    void subirArchivo(String directorio, String nombre, Path origen) throws IOException {
        ShareFileClient archivo = asegurarDirectorio(directorio).getFileClient(nombre);
        archivo.uploadFromFile(origen.toString());
    }

    /** Sube un contenido pequeño (hasta 4 MiB por llamada) desde un flujo. */
    void subirPequeno(String directorio, String nombre, InputStream datos, long longitud) {
        ShareFileClient archivo = asegurarDirectorio(directorio).getFileClient(nombre);
        archivo.create(longitud);
        archivo.upload(datos, longitud);
    }

    /** Descarga en streaming a cualquier OutputStream (por ejemplo, la respuesta HTTP). */
    void descargar(String ruta, OutputStream destino) {
        share.getFileClient(ruta).download(destino);
    }

    InputStream abrir(String ruta) {
        return share.getFileClient(ruta).openInputStream();
    }

    List<String> listar(String directorio) {
        List<String> nombres = new ArrayList<>();
        for (ShareFileItem item : asegurarDirectorio(directorio).listFilesAndDirectories()) {
            nombres.add((item.isDirectory() ? "[dir] " : "") + item.getName());
        }
        return nombres;
    }

    void borrar(String ruta) {
        share.getFileClient(ruta).deleteIfExists();
    }

    /** Crea una instantánea del share antes de un cambio masivo y devuelve su identificador. */
    String instantanea() {
        return share.createSnapshot().getSnapshot();
    }

    /** Restaura UN archivo desde una instantánea: lo lee de la instantánea y lo reescribe en el share vivo. */
    void restaurarDesdeInstantanea(String snapshotId, String ruta) throws IOException {
        ShareFileClient origen = share.getSnapshotClient(snapshotId).getFileClient(ruta);
        Path temporal = Files.createTempFile("restaurar-", ".dat");
        try {
            origen.downloadToFile(temporal.toString());
            share.getFileClient(ruta).uploadFromFile(temporal.toString());
        } finally {
            Files.deleteIfExists(temporal);
        }
    }
}
```
Notas:
- `exists()` + `create()` tiene una carrera si dos instancias crean la misma carpeta a la vez: captura el error 409 (`ResourceAlreadyExists`) en producción, o usa `createIfNotExists()` si tu versión del SDK lo ofrece.
- La clave de la cuenta **no aparece**: el acceso es por rol de datos de Entra ID.

## 4. Forma B · Reactivo (Reactor)

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.file.share.ShareAsyncClient;
import com.azure.storage.file.share.ShareServiceAsyncClient;
import com.azure.storage.file.share.ShareServiceClientBuilder;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareTokenIntent;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.HexFormat;

class RepositorioCompartidoReactivo {

    private final ShareAsyncClient share;

    RepositorioCompartidoReactivo(String endpoint, String nombreShare) {
        ShareServiceAsyncClient servicio = new ShareServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .shareTokenIntent(ShareTokenIntent.BACKUP)
                .buildAsyncClient();
        this.share = servicio.getShareAsyncClient(nombreShare);
    }

    /** Lista una carpeta como flujo paginado, sin cargarla toda en memoria. */
    Flux<String> listar(String directorio) {
        return share.getDirectoryClient(directorio).listFilesAndDirectories().map(ShareFileItem::getName);
    }

    /** Descarga como flujo de bloques de bytes (por ejemplo, para responder en WebFlux). */
    Flux<ByteBuffer> descargar(String ruta) {
        return share.getFileClient(ruta).download();
    }

    /** SHA-256 del archivo en streaming: memoria constante. */
    Mono<String> hashSha256(String ruta) {
        return Mono.fromCallable(() -> MessageDigest.getInstance("SHA-256"))
                .flatMap(sha -> descargar(ruta)
                        .doOnNext(bloque -> sha.update(bloque.asReadOnlyBuffer()))
                        .then(Mono.fromSupplier(() -> HexFormat.of().formatHex(sha.digest()))));
    }

    /** Sube un contenido pequeño (hasta 4 MiB) desde un flujo reactivo. */
    Mono<Void> subirPequeno(String ruta, Flux<ByteBuffer> datos, long longitud) {
        return share.getFileClient(ruta).create(longitud)
                .then(share.getFileClient(ruta).upload(datos, longitud))
                .then();
    }
}
```

## 5. Quarkus (Mutiny)

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.file.share.ShareAsyncClient;
import com.azure.storage.file.share.ShareServiceClientBuilder;
import com.azure.storage.file.share.models.ShareFileItem;
import com.azure.storage.file.share.models.ShareTokenIntent;
import io.smallrye.mutiny.Multi;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import reactor.adapter.JdkFlowAdapter;

@ApplicationScoped
class FilesProductor {

    @ConfigProperty(name = "app.files.endpoint")
    String endpoint;

    @ConfigProperty(name = "app.files.share")
    String nombre;

    @Produces
    @ApplicationScoped
    ShareAsyncClient share() {
        return new ShareServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .shareTokenIntent(ShareTokenIntent.BACKUP)
                .buildAsyncClient()
                .getShareAsyncClient(nombre);
    }
}

@Path("/archivos")
@ApplicationScoped
public class ArchivosResource {

    @Inject
    ShareAsyncClient share;

    @GET
    @Path("/{directorio}")
    public Multi<String> listar(@PathParam("directorio") String directorio) {
        // Mutiny usa java.util.concurrent.Flow; Reactor ofrece el adaptador
        return Multi.createFrom().publisher(JdkFlowAdapter.publisherToFlowPublisher(
                        share.getDirectoryClient(directorio).listFilesAndDirectories()))
                .map(ShareFileItem::getName);
    }
}
```
Para montajes en Quarkus (forma A) se usa `java.nio.file` igual que en Spring; con Mutiny, ejecuta el trabajo bloqueante en el *worker pool* (`@Blocking` o `Uni.createFrom().item(...).runSubscriptionOn(Infrastructure.getDefaultWorkerPool())`).

## 6. Montar el share en Kubernetes (forma A en AKS)
El YAML completo (StorageClass, PVC `ReadWriteMany`, Deployment y variante NFS) está en [ejemplos/yaml/azure-files-aks.yaml](ejemplos/yaml/azure-files-aks.yaml). La aplicación ve `/mnt/contabilidad` como una carpeta cualquiera y usa el código de las secciones 1 y 2.

## 7. Cuál elegir

| Necesidad | Forma |
|---|---|
| Procesamiento por lotes que ya lee carpetas | A (ruta montada) |
| Muchas réplicas compartiendo configuración o contenido | A |
| Servicio fuera de Azure o sin acceso al puerto 445 | B (SDK) |
| Instantáneas, listados paginados, metadatos | B |
| Alto volumen de archivos pequeños y baja latencia | Premium + A; evalúa Blob si no necesitas semántica de archivos |

## 8. Qué NO hacer en el código
- Usar `WatchService` sobre un share para detectar archivos de otros clientes.
- Leer archivos que aún se están copiando (sin extensión temporal ni espera de estabilidad).
- Procesar el mismo archivo en varias réplicas sin un mecanismo de "reclamar".
- Cargar archivos enteros en memoria.
- Usar la clave de la cuenta para montar o para el SDK en producción.
- Escribir logs o archivos temporales de la aplicación en el share.
- Listar un directorio con millones de entradas sin paginar ni particionar por prefijos.
