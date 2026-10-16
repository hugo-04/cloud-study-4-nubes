# Azure · Data Lake Gen2 · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-storage-file-datalake`, `azure-identity`). Verifica las vigentes.

Casi todo el código de un lago de datos lo ejecutan **motores de analítica** (Spark, Databricks, Synapse, Fabric) con `abfss://`. Java entra para: **ingestar** datos, **publicar** lotes de forma atómica, **administrar ACL**, **servir** consultas a archivos puntuales y **orquestar** movimientos entre zonas.

```properties
# Spring Boot
app.lago.endpoint=https://stmodalimalake.dfs.core.windows.net
app.lago.sistema=landing
```
```properties
# Quarkus
app.lago.endpoint=https://stmodalimalake.dfs.core.windows.net
app.lago.sistema=landing
```
```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-file-datalake</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
```
Nota: el endpoint es **`dfs`**, no `blob`. Rol de la identidad: *Storage Blob Data Contributor* (o ACL `rwx` en su ruta).

## 1. Escribir un lote y publicarlo de forma atómica

Patrón: escribir en `_tmp/` con `append` + `flush`, y **renombrar** a la partición final. Los lectores (Spark) nunca ven archivos a medias.

```java
import com.azure.core.util.BinaryData;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.file.datalake.DataLakeFileClient;
import com.azure.storage.file.datalake.DataLakeFileSystemClient;
import com.azure.storage.file.datalake.DataLakeServiceClient;
import com.azure.storage.file.datalake.DataLakeServiceClientBuilder;
import com.azure.storage.file.datalake.models.ListPathsOptions;
import com.azure.storage.file.datalake.models.PathItem;
import com.azure.storage.file.datalake.options.DataLakePathDeleteOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Service;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.UUID;

@Configuration
class LagoConfig {

    @Bean
    DataLakeServiceClient servicioLago(@Value("${app.lago.endpoint}") String endpoint) {
        return new DataLakeServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }
}

@Service
class LagoDeDatos {

    private static final int TROZO = 4 * 1024 * 1024;     // 4 MiB por append

    private final DataLakeFileSystemClient sistema;

    LagoDeDatos(DataLakeServiceClient servicio, @Value("${app.lago.sistema}") String nombre) {
        this.sistema = servicio.getFileSystemClient(nombre);
        this.sistema.createIfNotExists();
    }

    /** Ruta con particiones estilo Hive: ventas/anio=2026/mes=10/dia=16 */
    static String particion(String dominio, LocalDate fecha) {
        return "%s/anio=%d/mes=%02d/dia=%02d".formatted(dominio, fecha.getYear(), fecha.getMonthValue(), fecha.getDayOfMonth());
    }

    /**
     * Escribe registros NDJSON (uno por línea) en trozos y publica el archivo con un renombrado atómico.
     * Devuelve la ruta final.
     */
    String publicarLote(String dominio, LocalDate fecha, Iterator<String> lineas) throws IOException {
        String temporal = "_tmp/" + UUID.randomUUID() + ".ndjson";
        DataLakeFileClient archivo = sistema.createFile(temporal, true);

        long desplazamiento = 0;
        ByteArrayOutputStream buffer = new ByteArrayOutputStream(TROZO + 8192);
        while (lineas.hasNext()) {
            buffer.write((lineas.next() + "\n").getBytes(StandardCharsets.UTF_8));
            if (buffer.size() >= TROZO) {
                desplazamiento = anexar(archivo, buffer, desplazamiento);
            }
        }
        if (buffer.size() > 0) {
            desplazamiento = anexar(archivo, buffer, desplazamiento);
        }
        archivo.flush(desplazamiento, true);                  // hasta aquí NO es visible como archivo completo

        String directorioFinal = particion(dominio, fecha);
        sistema.createDirectoryIfNotExists(directorioFinal);
        String rutaFinal = directorioFinal + "/part-" + UUID.randomUUID() + ".ndjson";
        archivo.rename(null, rutaFinal);                      // null = mismo sistema de archivos; atómico
        return rutaFinal;
    }

    private static long anexar(DataLakeFileClient archivo, ByteArrayOutputStream buffer, long desplazamiento) {
        byte[] datos = buffer.toByteArray();
        archivo.append(BinaryData.fromBytes(datos), desplazamiento);
        buffer.reset();
        return desplazamiento + datos.length;
    }

    /** Sube un archivo local grande (el SDK lo trocea). */
    void subirArchivo(String rutaDestino, java.nio.file.Path origen) {
        sistema.getFileClient(rutaDestino).uploadFromFile(origen.toString(), true);
    }

    InputStream abrir(String ruta) {
        return sistema.getFileClient(ruta).openInputStream().getInputStream();
    }

    /** Lista recursivamente una partición. */
    List<String> listar(String directorio) {
        List<String> rutas = new ArrayList<>();
        ListPathsOptions opciones = new ListPathsOptions().setPath(directorio).setRecursive(true);
        for (PathItem item : sistema.listPaths(opciones, null)) {
            if (!item.isDirectory()) {
                rutas.add(item.getName() + " (" + item.getContentLength() + " bytes)");
            }
        }
        return rutas;
    }

    /** Mueve una carpeta entera de zona: una sola operación de metadatos, sin copiar datos. */
    void promover(String directorioOrigen, String sistemaDestino, String directorioDestino) {
        sistema.getDirectoryClient(directorioOrigen).rename(sistemaDestino, directorioDestino);
    }

    /** Borra una partición completa (recursivo). */
    void borrarParticion(String directorio) {
        sistema.getDirectoryClient(directorio)
                .deleteIfExistsWithResponse(new DataLakePathDeleteOptions().setIsRecursive(true), null, null);
    }
}
```
Notas:
- Los nombres de **partición** son parte del contrato con Spark: `anio=2026/mes=10/dia=16`.
- Si el proceso cae antes del `rename`, queda basura en `_tmp/`: una regla de ciclo de vida la limpia.
- Para ingestas de un solo archivo pequeño, `upload(InputStream, length, true)` basta.

## 2. Administrar ACL por grupos (con herencia para lo nuevo)

Aplica a un directorio **y a todo lo que contiene** (ACL de acceso) y deja **por defecto** la misma regla para lo que se cree después.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.file.datalake.DataLakeDirectoryClient;
import com.azure.storage.file.datalake.DataLakeFileSystemClient;
import com.azure.storage.file.datalake.DataLakeServiceClientBuilder;
import com.azure.storage.file.datalake.models.AccessControlChangeResult;
import com.azure.storage.file.datalake.models.AccessControlType;
import com.azure.storage.file.datalake.models.PathAccessControl;
import com.azure.storage.file.datalake.models.PathAccessControlEntry;
import com.azure.storage.file.datalake.models.RolePermissions;

import java.util.ArrayList;
import java.util.List;

class AdministradorDeAcl {

    private final DataLakeFileSystemClient sistema;

    AdministradorDeAcl(String endpoint, String nombreSistema) {
        this.sistema = new DataLakeServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient()
                .getFileSystemClient(nombreSistema);
    }

    private static PathAccessControlEntry entradaGrupo(String grupoObjectId, String permisos, boolean porDefecto) {
        return new PathAccessControlEntry()
                .setAccessControlType(AccessControlType.GROUP)
                .setEntityId(grupoObjectId)
                .setPermissions(RolePermissions.parseSymbolic(permisos, false))
                .setDefaultScope(porDefecto);
    }

    /**
     * Da a un grupo permisos sobre un directorio: ACL de acceso (para lo existente) y por defecto (para lo nuevo).
     * Recorre el árbol: puede tardar y genera transacciones, hazlo fuera de horas pico.
     */
    AccessControlChangeResult concederAGrupo(String directorio, String grupoObjectId, String permisos) {
        DataLakeDirectoryClient dir = sistema.getDirectoryClient(directorio);
        List<PathAccessControlEntry> entradas = new ArrayList<>();
        entradas.add(entradaGrupo(grupoObjectId, permisos, false));
        entradas.add(entradaGrupo(grupoObjectId, permisos, true));
        return dir.updateAccessControlRecursive(entradas);   // "update" = agrega o modifica solo esas entradas
    }

    /** El grupo necesita 'x' en cada directorio padre para llegar al dato: concédeselo (sin recursión). */
    void permitirAtravesar(String directorioPadre, String grupoObjectId) {
        DataLakeDirectoryClient dir = sistema.getDirectoryClient(directorioPadre);
        PathAccessControl actual = dir.getAccessControl();
        List<PathAccessControlEntry> lista = new ArrayList<>(actual.getAccessControlList());
        lista.removeIf(e -> e.getAccessControlType() == AccessControlType.GROUP
                && grupoObjectId.equals(e.getEntityId()) && !e.isInDefaultScope());
        lista.add(entradaGrupo(grupoObjectId, "--x", false));
        dir.setAccessControlList(lista, null, null);
    }

    /** Resumen legible de las ACL de una ruta (para auditar). */
    String mostrar(String ruta) {
        return PathAccessControlEntry.serializeList(sistema.getDirectoryClient(ruta).getAccessControl().getAccessControlList());
    }

    /** Resultado de una operación recursiva: ¿cuántos directorios/archivos cambiaron y cuántos fallaron? */
    static String resumen(AccessControlChangeResult resultado) {
        var c = resultado.getCounters();
        return "directorios=%d archivos=%d fallos=%d".formatted(
                c.getChangedDirectoriesCount(), c.getChangedFilesCount(), c.getFailedChangesCount());
    }
}
```
Notas:
- `updateAccessControlRecursive` **agrega o actualiza** esas entradas sin tocar las demás; `setAccessControlRecursive` **reemplaza** todas (peligroso); `removeAccessControlRecursive` quita entradas.
- Si hay fallos, el resultado trae un *token de continuación* para reanudar sin repetir lo hecho.
- Usa **object id de grupos de Entra ID**, nunca de personas.

## 3. Lectura y escritura reactivas (Reactor)

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.file.datalake.DataLakeFileAsyncClient;
import com.azure.storage.file.datalake.DataLakeFileSystemAsyncClient;
import com.azure.storage.file.datalake.DataLakeServiceClientBuilder;
import com.azure.storage.file.datalake.models.PathItem;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.HexFormat;

class LagoReactivo {

    private final DataLakeFileSystemAsyncClient sistema;

    LagoReactivo(String endpoint, String nombreSistema) {
        this.sistema = new DataLakeServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildAsyncClient()
                .getFileSystemAsyncClient(nombreSistema);
    }

    /** Contenido como flujo de bloques (para devolverlo por WebFlux sin cargarlo en memoria). */
    Flux<ByteBuffer> leer(String ruta) {
        return sistema.getFileAsyncClient(ruta).read();
    }

    /** Lista de archivos de una partición, paginada y sin bloquear. */
    Flux<String> archivos(String directorio) {
        return sistema.listPaths(new com.azure.storage.file.datalake.models.ListPathsOptions().setPath(directorio).setRecursive(true))
                .filter(item -> !item.isDirectory())
                .map(PathItem::getName);
    }

    /** SHA-256 en streaming de un archivo del lago. */
    Mono<String> hash(String ruta) {
        return Mono.fromCallable(() -> MessageDigest.getInstance("SHA-256"))
                .flatMap(sha -> leer(ruta)
                        .doOnNext(bloque -> sha.update(bloque.asReadOnlyBuffer()))
                        .then(Mono.fromSupplier(() -> HexFormat.of().formatHex(sha.digest()))));
    }

    /** Escribe un contenido (una sola pasada) y lo confirma. Para cargas grandes, usa trozos de varios MiB. */
    Mono<Void> escribir(String ruta, Flux<ByteBuffer> datos, long longitud) {
        DataLakeFileAsyncClient archivo = sistema.getFileAsyncClient(ruta);
        return archivo.create(true)
                .then(archivo.append(datos, 0, longitud))
                .then(archivo.flush(longitud, true))
                .then();
    }
}
```

## 4. Quarkus (Mutiny)

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.file.datalake.DataLakeFileSystemAsyncClient;
import com.azure.storage.file.datalake.DataLakeServiceClientBuilder;
import com.azure.storage.file.datalake.models.ListPathsOptions;
import com.azure.storage.file.datalake.models.PathItem;
import io.smallrye.mutiny.Multi;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import reactor.adapter.JdkFlowAdapter;

@ApplicationScoped
class LagoProductor {

    @ConfigProperty(name = "app.lago.endpoint")
    String endpoint;

    @ConfigProperty(name = "app.lago.sistema")
    String sistema;

    @Produces
    @ApplicationScoped
    DataLakeFileSystemAsyncClient sistemaDeArchivos() {
        return new DataLakeServiceClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildAsyncClient()
                .getFileSystemAsyncClient(sistema);
    }
}

@Path("/lago")
@ApplicationScoped
public class LagoResource {

    @Inject
    DataLakeFileSystemAsyncClient sistema;

    @GET
    @Path("/archivos")
    public Multi<String> archivos(@QueryParam("directorio") String directorio) {
        var opciones = new ListPathsOptions().setPath(directorio).setRecursive(true);
        return Multi.createFrom().publisher(JdkFlowAdapter.publisherToFlowPublisher(sistema.listPaths(opciones)))
                .filter(item -> !item.isDirectory())
                .map(PathItem::getName);
    }
}
```

## 5. Spark/Hadoop (ABFS): la configuración, no el código
Los motores de analítica leen y escriben con `abfss://` y autentican con identidad (sin claves). El archivo [ejemplos/spark/abfs-config.properties](ejemplos/spark/abfs-config.properties) trae la configuración para identidad administrada y para principal de servicio. En tu código Spark en Java solo usas rutas:

```
abfss://silver@stmodalimalake.dfs.core.windows.net/ventas/anio=2026/mes=10/
```

## 6. Imperativo vs reactivo en este caso

| | Imperativo | Reactivo |
|---|---|---|
| Ingesta por lotes (trabajos programados) | Natural: bucle + `append` + `flush` + `rename` | Útil si ya hay un `Flux` de origen |
| APIs que sirven archivos puntuales | `InputStream` hacia la respuesta | `Flux<ByteBuffer>` en WebFlux |
| ACL y administración | Imperativo (pocas llamadas, resultados con contadores) | No aporta |
| Hilos virtuales (Java 21) | Excelente para E/S bloqueante en trabajos | No hacen falta |

## 7. Qué NO hacer en el código
- Escribir directamente en la ruta final y dejar que los lectores vean archivos a medias.
- Hacer `append` de bloques diminutos (cada llamada es una transacción): acumula varios MiB.
- Olvidar el `flush` final (los datos no quedan confirmados).
- Aplicar `setAccessControlRecursive` cuando quieres *añadir* (borra las demás entradas): usa `update`.
- Asignar ACL a usuarios sueltos en vez de grupos.
- Dar roles amplios a la app y esperar que las ACL la limiten.
- Cargar el archivo completo en memoria para leerlo.
- Usar el endpoint `blob` esperando semántica de directorios.
