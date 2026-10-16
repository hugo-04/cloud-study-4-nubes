# Azure · SAS tokens · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-storage-blob`, `azure-identity`). Verifica las vigentes.

Tu backend hace **tres cosas** con las SAS: (1) **emitirlas** tras autorizar al usuario, (2) **confirmar** lo que el cliente subió (tamaño, tipo, contenido), y (3) **no filtrarlas** (logs, errores). El cliente (navegador/móvil) solo las **usa**.

Roles de la identidad del backend: **Storage Blob Delegator** (en la cuenta) + **Storage Blob Data Contributor** (en el contenedor). Sin claves de cuenta.

## 1. Emisor de SAS con la clave de delegación en caché

Pedir la clave de delegación en **cada** petición es lento. Se pide una vez, se reutiliza y se renueva con margen.

```java
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.models.UserDelegationKey;
import com.azure.storage.blob.sas.BlobSasPermission;
import com.azure.storage.blob.sas.BlobServiceSasSignatureValues;
import com.azure.storage.common.sas.SasProtocol;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

@Component
class SasEmisor {

    private static final Duration VIDA_CLAVE = Duration.ofHours(6);
    private static final Duration MARGEN = Duration.ofMinutes(30);

    private final BlobServiceClient servicio;
    private UserDelegationKey clave;           // protegida por synchronized

    SasEmisor(BlobServiceClient servicio) {
        this.servicio = servicio;
    }

    private synchronized UserDelegationKey claveVigente() {
        OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
        if (clave == null || clave.getSignedExpiry().isBefore(ahora.plus(MARGEN))) {
            // inicio 5 min atrás: tolera el desfase de relojes
            clave = servicio.getUserDelegationKey(ahora.minusMinutes(5), ahora.plus(VIDA_CLAVE));
        }
        return clave;
    }

    /** URL de LECTURA (permiso r) de un solo blob; opcionalmente fuerza el nombre de descarga. */
    String urlLectura(String contenedor, String nombreBlob, Duration validez, String nombreDescarga) {
        BlobClient blob = servicio.getBlobContainerClient(contenedor).getBlobClient(nombreBlob);
        BlobServiceSasSignatureValues valores = new BlobServiceSasSignatureValues(
                OffsetDateTime.now(ZoneOffset.UTC).plus(validez),
                new BlobSasPermission().setReadPermission(true))
                .setProtocol(SasProtocol.HTTPS_ONLY);
        if (nombreDescarga != null) {
            String seguro = nombreDescarga.replaceAll("[^A-Za-z0-9._-]", "_");     // nada de comillas ni saltos de línea
            valores.setContentDisposition("attachment; filename=\"" + seguro + "\"");
        }
        return blob.getBlobUrl() + "?" + blob.generateUserDelegationSas(valores, claveVigente());
    }

    /** URL de ESCRITURA (permisos c + w) de un blob NUEVO; vale también para subir por bloques. */
    String urlEscritura(String contenedor, String nombreBlob, Duration validez) {
        BlobClient blob = servicio.getBlobContainerClient(contenedor).getBlobClient(nombreBlob);
        OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
        BlobServiceSasSignatureValues valores = new BlobServiceSasSignatureValues(
                ahora.plus(validez),
                new BlobSasPermission().setCreatePermission(true).setWritePermission(true))
                .setStartTime(ahora.minusMinutes(5))
                .setProtocol(SasProtocol.HTTPS_ONLY);
        return blob.getBlobUrl() + "?" + blob.generateUserDelegationSas(valores, claveVigente());
    }
}
```
> La SAS no puede vivir más que la clave de delegación: con clave de 6 h y SAS de 10–60 min, y renovación 30 min antes, siempre es válida.

## 2. API de subida directa: solicitar y confirmar

El endpoint **autoriza**, **valida lo declarado** (tipo y tamaño), **decide el nombre** y responde con la URL y las cabeceras que el cliente debe enviar.

```java
// nocheck: usa SasEmisor de la sección 1 (verificado en conjunto)
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.models.BlobProperties;
import com.azure.storage.blob.models.BlobStorageException;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

record SolicitudSubida(String contentType, long tamanoDeclarado) {
}

record RespuestaSubida(String id, String url, Map<String, String> cabeceras, OffsetDateTime vence) {
}

@RestController
@RequestMapping("/archivos")
class SubidasController {

    private static final String CONTENEDOR = "subidas";
    private static final long MAXIMO = 200L * 1024 * 1024;
    private static final Set<String> TIPOS = Set.of("application/pdf", "image/jpeg", "image/png", "text/csv");

    private final SasEmisor sas;
    private final BlobServiceClient servicio;

    SubidasController(SasEmisor sas, BlobServiceClient servicio) {
        this.sas = sas;
        this.servicio = servicio;
    }

    @PostMapping("/solicitud-subida")
    RespuestaSubida solicitar(@RequestBody SolicitudSubida peticion, @AuthenticationPrincipal Jwt jwt) {
        if (!TIPOS.contains(peticion.contentType())) {
            throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "Tipo no permitido");
        }
        if (peticion.tamanoDeclarado() <= 0 || peticion.tamanoDeclarado() > MAXIMO) {
            throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "Tamaño fuera de rango");
        }
        String id = UUID.randomUUID().toString();
        String nombreBlob = "usuarios/" + jwt.getSubject() + "/" + id;      // prefijo por usuario, nombre del servidor
        Duration validez = Duration.ofMinutes(15);
        String url = sas.urlEscritura(CONTENEDOR, nombreBlob, validez);
        return new RespuestaSubida(id, url,
                Map.of("x-ms-blob-type", "BlockBlob", "Content-Type", peticion.contentType()),
                OffsetDateTime.now(ZoneOffset.UTC).plus(validez));
    }

    /** El cliente avisa "terminé". Aquí se valida LO REAL, porque la SAS no limita el tamaño. */
    @PostMapping("/{id}/confirmar")
    Map<String, Object> confirmar(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
        BlobClient blob = servicio.getBlobContainerClient(CONTENEDOR)
                .getBlobClient("usuarios/" + jwt.getSubject() + "/" + id);        // solo SUS archivos
        BlobProperties propiedades;
        try {
            propiedades = blob.getProperties();
        } catch (BlobStorageException e) {
            if (e.getStatusCode() == 404) {
                throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No se subió el archivo");
            }
            throw e;
        }
        if (propiedades.getBlobSize() > MAXIMO || !TIPOS.contains(propiedades.getContentType())) {
            blob.delete();                                  // lo que excede o no es lo declarado, fuera
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Archivo rechazado");
        }
        blob.setTags(Map.of("estado", "pendiente-analisis"));        // el antivirus / procesador toma estos
        return Map.of("id", id, "tamano", propiedades.getBlobSize(), "estado", "pendiente-analisis");
    }
}
```
En la vida real, `confirmar` también **encola el "ticket"** del Claim Check ([Claim Check](../claim-check/README.md)) y el análisis (antivirus, tipo real por *magic bytes*) ocurre en el consumidor.

### Comprobar el tipo real (magic bytes)
```java
import java.util.Arrays;

final class TipoReal {

    private TipoReal() {
    }

    /** Lee los primeros bytes (con una lectura por rango) y los compara con la firma del formato. */
    static boolean esPdf(byte[] primeros) {
        return primeros.length >= 5 && Arrays.equals(Arrays.copyOf(primeros, 5), new byte[]{'%', 'P', 'D', 'F', '-'});
    }

    static boolean esJpeg(byte[] primeros) {
        return primeros.length >= 3 && (primeros[0] & 0xFF) == 0xFF && (primeros[1] & 0xFF) == 0xD8 && (primeros[2] & 0xFF) == 0xFF;
    }
}
```

## 3. SAS de servicio con política almacenada (acceso a terceros, revocable)

Requiere la **clave de la cuenta** (no está disponible si `allowSharedKeyAccess=false`). Úsala solo cuando un tercero necesite un enlace **revocable de forma central**.

```java
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobContainerClientBuilder;
import com.azure.storage.blob.models.BlobAccessPolicy;
import com.azure.storage.blob.models.BlobSignedIdentifier;
import com.azure.storage.blob.sas.BlobServiceSasSignatureValues;
import com.azure.storage.common.StorageSharedKeyCredential;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;

class SasConPolitica {

    private final BlobContainerClient contenedor;

    SasConPolitica(String cuenta, String clave) {
        this.contenedor = new BlobContainerClientBuilder()
                .endpoint("https://" + cuenta + ".blob.core.windows.net")
                .containerName("socios")
                .credential(new StorageSharedKeyCredential(cuenta, clave))   // la clave viene de Key Vault, nunca del código
                .buildClient();
    }

    /** Crea (o reemplaza) la política "proveedor-x": permisos cw durante 7 días. */
    void crearPolitica() {
        OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
        BlobSignedIdentifier identificador = new BlobSignedIdentifier()
                .setId("proveedor-x")
                .setAccessPolicy(new BlobAccessPolicy()
                        .setPermissions("cw")
                        .setStartsOn(ahora.minusMinutes(5))
                        .setExpiresOn(ahora.plusDays(7)));
        contenedor.setAccessPolicy(null, List.of(identificador));
    }

    /** SAS del contenedor que hereda permisos y vencimiento de la política. Revocar = borrar la política. */
    String sasDelProveedor() {
        return contenedor.getBlobContainerUrl() + "?" + contenedor.generateSas(new BlobServiceSasSignatureValues("proveedor-x"));
    }

    void revocar() {
        contenedor.setAccessPolicy(null, List.of());          // sin políticas → todas las SAS ligadas mueren
    }
}
```

## 4. Reactivo (WebFlux): clave cacheada con `Mono.cache`

```java
import com.azure.storage.blob.BlobAsyncClient;
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.models.UserDelegationKey;
import com.azure.storage.blob.sas.BlobSasPermission;
import com.azure.storage.blob.sas.BlobServiceSasSignatureValues;
import com.azure.storage.common.sas.SasProtocol;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

@Component
class SasEmisorReactivo {

    private final BlobServiceAsyncClient servicio;
    private final Mono<UserDelegationKey> clave;

    SasEmisorReactivo(BlobServiceAsyncClient servicio) {
        this.servicio = servicio;
        // defer: recalcula las fechas cada vez que expira el caché (5 h < 6 h de vida de la clave)
        this.clave = Mono.defer(() -> {
            OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
            return servicio.getUserDelegationKey(ahora.minusMinutes(5), ahora.plusHours(6));
        }).cache(Duration.ofHours(5));
    }

    Mono<String> urlEscritura(String contenedor, String nombreBlob, Duration validez) {
        BlobAsyncClient blob = servicio.getBlobContainerAsyncClient(contenedor).getBlobAsyncClient(nombreBlob);
        return clave.map(k -> {
            OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
            BlobServiceSasSignatureValues valores = new BlobServiceSasSignatureValues(
                    ahora.plus(validez),
                    new BlobSasPermission().setCreatePermission(true).setWritePermission(true))
                    .setStartTime(ahora.minusMinutes(5))
                    .setProtocol(SasProtocol.HTTPS_ONLY);
            return blob.getBlobUrl() + "?" + blob.generateUserDelegationSas(valores, k);
        });
    }
}
```

## 5. Quarkus (imperativo y reactivo con Mutiny)

```java
import com.azure.storage.blob.BlobAsyncClient;
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.models.UserDelegationKey;
import com.azure.storage.blob.sas.BlobSasPermission;
import com.azure.storage.blob.sas.BlobServiceSasSignatureValues;
import com.azure.storage.common.sas.SasProtocol;
import io.smallrye.mutiny.Uni;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.UUID;

@Path("/archivos")
@Produces(MediaType.APPLICATION_JSON)
@ApplicationScoped
public class SasResource {

    @Inject
    BlobServiceAsyncClient servicio;

    private Uni<UserDelegationKey> clave;

    @PostConstruct
    void iniciar() {
        // memoize().atLeast: reutiliza el resultado 5 h y luego vuelve a pedirlo
        this.clave = Uni.createFrom().deferred(() -> {
            OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
            return Uni.createFrom().completionStage(
                    servicio.getUserDelegationKey(ahora.minusMinutes(5), ahora.plusHours(6)).toFuture());
        }).memoize().atLeast(Duration.ofHours(5));
    }

    @POST
    @Path("/solicitud-subida")
    public Uni<Map<String, String>> solicitar() {
        String id = UUID.randomUUID().toString();
        BlobAsyncClient blob = servicio.getBlobContainerAsyncClient("subidas").getBlobAsyncClient("usuarios/demo/" + id);
        return clave.map(k -> {
            OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
            BlobServiceSasSignatureValues valores = new BlobServiceSasSignatureValues(
                    ahora.plusMinutes(15),
                    new BlobSasPermission().setCreatePermission(true).setWritePermission(true))
                    .setStartTime(ahora.minusMinutes(5))
                    .setProtocol(SasProtocol.HTTPS_ONLY);
            return Map.of("id", id, "url", blob.getBlobUrl() + "?" + blob.generateUserDelegationSas(valores, k));
        });
    }
}
```

## 6. El cliente: subir en bloques desde el navegador

Archivo completo: [ejemplos/web/subida.js](ejemplos/web/subida.js). Idea:

```javascript
// 1) Pide la SAS a tu API  2) divide en bloques  3) PUT de cada bloque  4) Put Block List  5) confirma
const bloque = 8 * 1024 * 1024;
for (let i = 0; i * bloque < archivo.size; i++) {
  const id = btoa(String(i).padStart(6, "0"));
  await fetch(`${url}&comp=block&blockid=${encodeURIComponent(id)}`, { method: "PUT", body: archivo.slice(i * bloque, (i + 1) * bloque) });
}
```
Requiere **CORS** en el servicio Blob (origen, `PUT`, `x-ms-*`).

## 7. Cliente Java que sube con una SAS (otro backend o prueba)

```java
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobClientBuilder;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.ParallelTransferOptions;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import com.azure.core.util.BinaryData;
import com.azure.core.util.Context;

import java.io.InputStream;
import java.time.Duration;

class SubidaConSas {

    /** La SAS ya trae la autorización: el cliente se construye con la URL completa. */
    void subir(String urlConSas, InputStream datos, long tamano, String contentType) {
        BlobClient blob = new BlobClientBuilder().endpoint(urlConSas).buildClient();
        BlobParallelUploadOptions opciones = new BlobParallelUploadOptions(BinaryData.fromStream(datos, tamano))
                .setHeaders(new BlobHttpHeaders().setContentType(contentType))
                .setParallelTransferOptions(new ParallelTransferOptions().setBlockSizeLong(8L * 1024 * 1024).setMaxConcurrency(4));
        blob.uploadWithResponse(opciones, Duration.ofMinutes(10), Context.NONE);
    }
}
```

## 8. Imperativo vs reactivo

| | Imperativo | Reactivo |
|---|---|---|
| Emisión de SAS | CPU puro (firma HMAC): casi instantáneo | Igual; lo lento es **pedir la clave**, que va con `Mono.cache` |
| Llamada a `getUserDelegationKey` | Bloquea un hilo (poco) | Sin bloquear |
| Cuándo | MVC o Quarkus clásico | WebFlux / Quarkus reactivo |

## 9. Qué NO hacer en el código
- Pedir una clave de delegación por petición.
- Devolver la SAS en un mensaje de log o en una excepción.
- Aceptar el nombre del blob desde el cliente.
- Usar `StorageSharedKeyCredential` en servicios nuevos si puedes usar Entra ID.
- Emitir SAS de **contenedor** con `l` para un cliente que solo necesita su archivo.
- Confiar en `Content-Type` declarado: comprueba contenido real.
