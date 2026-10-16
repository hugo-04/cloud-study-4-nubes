# Azure · Managed Identity · Uso desde Java

Versiones usadas para compilar estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3**. Verifica las vigentes.

## 1. El patrón base: `DefaultAzureCredential`
```java
import com.azure.identity.DefaultAzureCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;

DefaultAzureCredential credencial = new DefaultAzureCredentialBuilder()
        .managedIdentityClientId(System.getenv("AZURE_CLIENT_ID"))   // solo si hay varias user-assigned
        .build();
```
Orden aproximado en el que prueba: variables de entorno → workload identity → **managed identity** → herramientas de desarrollo (IDE, Azure CLI, Azure PowerShell…). Por eso el **mismo código** funciona en Azure y en tu laptop (con `az login`).

> Para forzar el comportamiento en producción y evitar sorpresas, puedes usar `ManagedIdentityCredentialBuilder` directamente.

## 2. Un solo cliente reutilizable (cachea el token)
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;

class AlmacenamientoConfig {
    // Crea UNA vez (bean singleton) y reutiliza
    static BlobServiceClient blobService(String cuenta) {
        return new BlobServiceClientBuilder()
                .endpoint("https://" + cuenta + ".blob.core.windows.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }
}
```

## 3. Spring Boot (imperativo): propiedades de Spring Cloud Azure
```xml
<dependency>
  <groupId>com.azure.spring</groupId>
  <artifactId>spring-cloud-azure-starter-storage-blob</artifactId>
</dependency>
```
```properties
spring.cloud.azure.storage.blob.account-name=stmodalima
spring.cloud.azure.credential.managed-identity-enabled=true
spring.cloud.azure.credential.client-id=${AZURE_CLIENT_ID}
```
> Verifica que la versión de **Spring Cloud Azure** soporte tu versión de Spring Boot (la matriz de compatibilidad está en su documentación).

## 4. Spring Boot (reactivo)
El SDK de Azure tiene clientes asíncronos (`BlobServiceAsyncClient`) basados en Reactor. La credencial es la misma.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import reactor.core.publisher.Flux;

class ListadoReactivo {
    private final BlobServiceAsyncClient cliente = new BlobServiceClientBuilder()
            .endpoint("https://stmodalima.blob.core.windows.net")
            .credential(new DefaultAzureCredentialBuilder().build())
            .buildAsyncClient();

    Flux<String> nombres(String contenedor) {
        return Flux.from(cliente.getBlobContainerAsyncClient(contenedor).listBlobs())
                .map(b -> b.getName());
    }
}
```

## 5. Quarkus
```properties
quarkus.azure.storage.blob.endpoint=https://stmodalima.blob.core.windows.net
# La autenticación por defecto usa DefaultAzureCredential
```
Ejemplo de uso con inyección:
```java
import com.azure.storage.blob.BlobServiceClient;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/blobs")
public class BlobsResource {

    @Inject
    BlobServiceClient cliente;

    @GET
    public long contarContenedores() {
        return cliente.listBlobContainers().stream().count();
    }
}
```
> Extensión de Quarkiverse: `io.quarkiverse.azureservices:quarkus-azure-storage-blob`. Comprueba el nombre y la versión compatible con tu Quarkus.

## 6. Base de datos sin contraseña

### Azure SQL (driver mssql-jdbc)
```properties
spring.datasource.url=jdbc:sqlserver://sql-modalima.database.windows.net:1433;database=pedidos;encrypt=true;authentication=ActiveDirectoryMSI;msiClientId=${AZURE_CLIENT_ID}
```
En la base: `CREATE USER [id-api-pedidos] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [id-api-pedidos];`
> Según la versión del driver, el valor puede ser `ActiveDirectoryMSI` o `ActiveDirectoryManagedIdentity`. Verifica en la doc del driver.

### PostgreSQL Flexible Server
```xml
<dependency>
  <groupId>com.azure</groupId>
  <artifactId>azure-identity-extensions</artifactId>
</dependency>
```
```properties
spring.datasource.url=jdbc:postgresql://pg-modalima.postgres.database.azure.com:5432/pedidos?sslmode=require&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin
spring.datasource.username=id-api-pedidos
# sin password: el plugin obtiene el token de Entra ID
```

## 7. Manejo de errores típicos
```java
import com.azure.identity.CredentialUnavailableException;

try {
    // llamada que usa DefaultAzureCredential
} catch (CredentialUnavailableException e) {
    // No hay ninguna credencial disponible: en local falta `az login`; en Azure falta asignar la identidad al recurso
}
```
| Excepción / mensaje | Qué revisar |
|---|---|
| `CredentialUnavailableException` | Identidad no asignada al recurso o sin `az login` en local |
| `ManagedIdentityCredential authentication failed ... 400` | `client_id` equivocado o identidad no asignada |
| 403 del servicio | Falta rol de datos o aún no se propagó |
| `ClientAuthenticationException` | Audiencia/recurso equivocado |

## 8. Qué NO hacer
- No crear un cliente (y pedir token) por cada petición.
- No registrar el token en logs.
- No dejar `AZURE_CLIENT_SECRET` en variables "por si acaso": cambia el orden de credenciales sin que lo notes.
