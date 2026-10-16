# Azure · Blob Storage · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-storage-blob`, `azure-identity`). Verifica las vigentes.

Regla de oro: **identidad administrada + RBAC** (sin claves), **streaming** (nunca el archivo completo en memoria), **reintentos con espera** y **nombres generados por el servidor**.

Dependencias (Maven):
```xml
<dependencyManagement><dependencies>
  <dependency><groupId>com.azure</groupId><artifactId>azure-sdk-bom</artifactId><version>1.3.9</version><type>pom</type><scope>import</scope></dependency>
</dependencies></dependencyManagement>
<dependencies>
  <dependency><groupId>com.azure</groupId><artifactId>azure-storage-blob</artifactId></dependency>
  <dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
</dependencies>
```
Alternativas: `spring-cloud-azure-starter-storage-blob` (autoconfiguración y soporte de `azure-blob://` como `Resource`) y la extensión Quarkiverse `quarkus-azure-storage-blob` (`quarkus.azure.storage.blob.endpoint`). *Verifica versiones y compatibilidad con tu Spring Boot/Quarkus.*

## 1. Configuración

```properties
# Spring Boot
app.storage.endpoint=https://stmodalima01.blob.core.windows.net
app.storage.container=fotos
```
```properties
# Quarkus
app.storage.endpoint=https://stmodalima01.blob.core.windows.net
app.storage.container=fotos
```
Local: `az login` (DefaultAzureCredential usa tu usuario). En AKS/Container Apps/App Service: identidad administrada o Workload Identity con el rol de datos asignado.

### Clientes como *beans* (Spring)
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.common.policy.RequestRetryOptions;
import com.azure.storage.common.policy.RetryPolicyType;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class AlmacenConfig {

    @Bean
    BlobServiceClientBuilder blobBuilder(@Value("${app.storage.endpoint}") String endpoint) {
        return new BlobServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                // 5 intentos, 30 s por intento, espera exponencial de 0,5 s a 8 s
                .retryOptions(new RequestRetryOptions(RetryPolicyType.EXPONENTIAL, 5, 30, 500L, 8000L, null));
    }

    @Bean
    BlobServiceClient blobServiceClient(BlobServiceClientBuilder builder) {
        return builder.buildClient();
    }

    @Bean
    BlobServiceAsyncClient blobServiceAsyncClient(BlobServiceClientBuilder builder) {
        return builder.buildAsyncClient();
    }
}
```
Los clientes son **seguros entre hilos y baratos de reutilizar**: crea uno por cuenta, no por petición.

## 2. Subir un blob nuevo (en bloques, sin sobrescribir)

```java
import com.azure.core.util.BinaryData;
import com.azure.core.util.Context;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.BlobRequestConditions;
import com.azure.storage.blob.models.ParallelTransferOptions;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.InputStream;
import java.time.Duration;
import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;

@Service
class ArchivoService {

    private final BlobContainerClient contenedor;

    ArchivoService(BlobServiceClient servicio, @Value("${app.storage.container}") String contenedor) {
        this.contenedor = servicio.getBlobContainerClient(contenedor);
    }

    /** El NOMBRE lo decide el servidor (fecha + UUID): evita colisiones y ataques de ruta. */
    String subir(InputStream datos, long tamano, String contentType) {
        String nombre = LocalDate.now() + "/" + UUID.randomUUID();
        BlobClient blob = contenedor.getBlobClient(nombre);

        ParallelTransferOptions transferencia = new ParallelTransferOptions()
                .setBlockSizeLong(8L * 1024 * 1024)               // bloques de 8 MiB
                .setMaxConcurrency(8)                              // 8 bloques en paralelo
                .setMaxSingleUploadSizeLong(32L * 1024 * 1024);    // hasta 32 MiB, una sola operación

        BlobParallelUploadOptions opciones = new BlobParallelUploadOptions(BinaryData.fromStream(datos, tamano))
                .setParallelTransferOptions(transferencia)
                .setHeaders(new BlobHttpHeaders().setContentType(contentType).setCacheControl("private, max-age=0"))
                .setTags(Map.of("estado", "pendiente"))                          // etiqueta de índice
                .setMetadata(Map.of("origen", "api-pedidos"))
                .setRequestConditions(new BlobRequestConditions().setIfNoneMatch("*")); // solo si NO existe

        blob.uploadWithResponse(opciones, Duration.ofMinutes(10), Context.NONE);
        return nombre;
    }
}
```
Si el archivo viene de un formulario web, valida **tipo y tamaño** antes de subir y analiza el contenido después. Para archivos grandes, **no pases por tu API**: entrega una SAS ([SAS tokens](../sas-tokens/README.md)).

## 3. Descargar sin llenar la memoria

```java
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.models.BlobRange;
import com.azure.storage.blob.models.BlobStorageException;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;

class DescargaService {

    private final BlobServiceClient servicio;

    DescargaService(BlobServiceClient servicio) {
        this.servicio = servicio;
    }

    /** Copia el blob a un OutputStream por trozos (p. ej. la respuesta HTTP). */
    void aStream(String contenedor, String nombre, OutputStream salida) throws IOException {
        BlobClient blob = servicio.getBlobContainerClient(contenedor).getBlobClient(nombre);
        try (InputStream in = blob.openInputStream()) {
            in.transferTo(salida);
        }
    }

    /** Descarga a un archivo temporal (para procesos que necesitan disco). */
    Path aArchivo(String contenedor, String nombre) throws IOException {
        Path destino = Files.createTempFile("blob-", ".tmp");
        servicio.getBlobContainerClient(contenedor).getBlobClient(nombre)
                .downloadToFile(destino.toString(), true);
        return destino;
    }

    /** Solo los primeros 1 KiB (cabecera/mágicos del archivo) con una lectura por rango. */
    byte[] primerosBytes(String contenedor, String nombre) throws IOException {
        BlobClient blob = servicio.getBlobContainerClient(contenedor).getBlobClient(nombre);
        try (var salida = new java.io.ByteArrayOutputStream()) {
            blob.downloadStreamWithResponse(salida, new BlobRange(0, 1024L), null, null, false, null,
                    com.azure.core.util.Context.NONE);
            return salida.toByteArray();
        }
    }

    Optional<Long> tamano(String contenedor, String nombre) {
        try {
            return Optional.of(servicio.getBlobContainerClient(contenedor).getBlobClient(nombre)
                    .getProperties().getBlobSize());
        } catch (BlobStorageException e) {
            if (e.getStatusCode() == 404) {
                return Optional.empty();
            }
            throw e;
        }
    }
}
```

## 4. Listar por prefijo y buscar por etiquetas

```java
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.AccessTier;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.ListBlobsOptions;
import com.azure.storage.blob.models.RehydratePriority;
import com.azure.storage.blob.models.TaggedBlobItem;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

class CatalogoBlobs {

    private final BlobContainerClient contenedor;

    CatalogoBlobs(BlobContainerClient contenedor) {
        this.contenedor = contenedor;
    }

    List<String> listar(String prefijo) {
        List<String> nombres = new ArrayList<>();
        ListBlobsOptions opciones = new ListBlobsOptions().setPrefix(prefijo).setMaxResultsPerPage(500);
        for (BlobItem item : contenedor.listBlobs(opciones, Duration.ofSeconds(30))) {   // paginado automático
            nombres.add(item.getName());
        }
        return nombres;
    }

    /** Busca por ETIQUETAS indexadas (no por metadatos). */
    List<String> pendientes() {
        List<String> nombres = new ArrayList<>();
        for (TaggedBlobItem item : contenedor.findBlobsByTags("\"estado\" = 'pendiente'")) {
            nombres.add(item.getName());
        }
        return nombres;
    }

    void marcarProcesado(String nombre) {
        contenedor.getBlobClient(nombre).setTags(Map.of("estado", "procesado"));
    }

    void enfriar(String nombre) {
        contenedor.getBlobClient(nombre).setAccessTier(AccessTier.COOL);
    }

    /** Rehidratar desde Archive con prioridad alta (cuesta más). */
    void rehidratar(String nombre) {
        contenedor.getBlobClient(nombre).setAccessTierWithResponse(AccessTier.HOT, RehydratePriority.HIGH, null, null, null);
    }
}
```
Evita listar **millones** de blobs para "buscar": usa etiquetas de índice o el inventario de blobs.

## 5. Concurrencia: ETag y lease

```java
import com.azure.core.util.BinaryData;
import com.azure.core.util.Context;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.models.BlobRequestConditions;
import com.azure.storage.blob.models.BlobStorageException;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import com.azure.storage.blob.specialized.BlobLeaseClient;
import com.azure.storage.blob.specialized.BlobLeaseClientBuilder;

import java.util.function.UnaryOperator;

class ActualizacionSegura {

    /** Lee, transforma y escribe SOLO si nadie lo cambió; si cambió (412), reintenta. */
    void actualizarJson(BlobClient blob, UnaryOperator<String> transformar) {
        for (int intento = 1; intento <= 5; intento++) {
            String etag = blob.getProperties().getETag();
            String actual = blob.downloadContent().toString();
            BlobParallelUploadOptions opciones = new BlobParallelUploadOptions(BinaryData.fromString(transformar.apply(actual)))
                    .setRequestConditions(new BlobRequestConditions().setIfMatch(etag));
            try {
                blob.uploadWithResponse(opciones, null, Context.NONE);
                return;
            } catch (BlobStorageException e) {
                if (e.getStatusCode() != 412) {
                    throw e;                          // otro error: no es una carrera
                }                                      // 412: otro escritor ganó → releer y reintentar
            }
        }
        throw new IllegalStateException("Demasiados conflictos de escritura sobre " + blob.getBlobName());
    }

    /** Exclusión mutua de 30 s sobre un blob (p. ej. un "lock" de proceso único). */
    void conLease(BlobClient blob, Runnable trabajo) {
        BlobLeaseClient lease = new BlobLeaseClientBuilder().blobClient(blob).buildClient();
        lease.acquireLease(30);
        try {
            trabajo.run();                            // si dura > 30 s, renueva con lease.renewLease()
        } finally {
            lease.releaseLease();
        }
    }
}
```
`downloadContent()` carga el contenido en memoria: úsalo **solo** para blobs pequeños (JSON de configuración).

## 6. Reactivo (WebFlux): streaming de punta a punta

```java
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.models.ParallelTransferOptions;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.nio.ByteBuffer;
import java.util.UUID;

@RestController
class ArchivosReactivos {

    private final BlobServiceAsyncClient servicio;

    ArchivosReactivos(BlobServiceAsyncClient servicio) {
        this.servicio = servicio;
    }

    @GetMapping(value = "/descargas", produces = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    Flux<ByteBuffer> descargar(@RequestParam String nombre) {
        return servicio.getBlobContainerAsyncClient("fotos").getBlobAsyncClient(nombre).downloadStream();   // sin cargar todo
    }

    @PostMapping(value = "/subidas", consumes = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    Mono<String> subir(@RequestBody Flux<ByteBuffer> cuerpo) {
        String nombre = "subidas/" + UUID.randomUUID();
        BlobParallelUploadOptions opciones = new BlobParallelUploadOptions(cuerpo)
                .setParallelTransferOptions(new ParallelTransferOptions().setBlockSizeLong(8L * 1024 * 1024).setMaxConcurrency(4));
        return servicio.getBlobContainerAsyncClient("fotos").getBlobAsyncClient(nombre)
                .uploadWithResponse(opciones)
                .thenReturn(nombre);
    }
}
```

## 7. Quarkus (imperativo y reactivo con Mutiny)

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class AlmacenProductor {

    @ConfigProperty(name = "app.storage.endpoint")
    String endpoint;

    private BlobServiceClientBuilder builder() {
        return new BlobServiceClientBuilder().endpoint(endpoint).credential(new DefaultAzureCredentialBuilder().build());
    }

    @Produces
    @ApplicationScoped
    BlobServiceClient cliente() {
        return builder().buildClient();
    }

    @Produces
    @ApplicationScoped
    BlobServiceAsyncClient clienteAsync() {
        return builder().buildAsyncClient();
    }
}
```
```java
import com.azure.storage.blob.BlobServiceAsyncClient;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.util.Map;

@Path("/archivos")
@Produces(MediaType.APPLICATION_JSON)
public class ArchivosResource {

    @Inject
    BlobServiceAsyncClient servicio;

    @GET
    @Path("/{nombre}/propiedades")
    public Uni<Map<String, Object>> propiedades(@PathParam("nombre") String nombre) {
        return Uni.createFrom().completionStage(() -> servicio
                .getBlobContainerAsyncClient("fotos").getBlobAsyncClient(nombre)
                .getProperties()
                .map(p -> Map.<String, Object>of("tamano", p.getBlobSize(), "tier", String.valueOf(p.getAccessTier())))
                .toFuture());
    }
}
```
El SDK usa Reactor internamente; en Quarkus conviértelo a `Uni` con `completionStage(mono.toFuture())` (no uses `Uni.createFrom().publisher(Mono)`: espera `Flow.Publisher`).

## 8. Imperativo vs reactivo para Blob

| | Imperativo (`BlobClient`) | Reactivo (`BlobAsyncClient`) |
|---|---|---|
| Modelo | Bloquea el hilo mientras transfiere | No bloquea; `Flux<ByteBuffer>` |
| Cuándo | Procesos por lotes, MVC, hilos virtuales | WebFlux/Quarkus reactivo, muchos clientes lentos |
| Streaming | `openInputStream`, `downloadToFile` | `downloadStream()` |
| Hilos virtuales (Java 21) | Excelentes con el cliente síncrono | No necesarios |

## 9. Qué NO hacer en el código
- Crear un `BlobServiceClient` por petición.
- `downloadContent()` sobre blobs grandes.
- Aceptar el nombre del blob que envía el usuario sin sanearlo.
- Usar la clave de cuenta o cadenas de conexión con `AccountKey=` en la configuración.
- Capturar `BlobStorageException` y ocultar el `x-ms-error-code` (guárdalo en el log).
- Reintentar a ciegas errores 4xx (salvo 408/429/412 con lógica).
