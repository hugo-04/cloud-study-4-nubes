# Azure · RBAC · Uso desde Java

Para tu código, RBAC se ve en dos momentos: **qué rol necesita tu aplicación** y **cómo reaccionas cuando falta**.

## 1. Qué rol necesita tu microservicio (tabla de decisión)
| Tu código hace... | Rol mínimo (plano de datos) | Alcance |
|---|---|---|
| Leer blobs | Storage Blob Data Reader | Contenedor |
| Subir blobs | Storage Blob Data Contributor | Contenedor |
| Generar un SAS de usuario delegado | Storage Blob Delegator (a nivel de cuenta) + el permiso del dato | Cuenta |
| Leer un secreto | Key Vault Secrets User | Vault o secreto |
| Enviar mensajes | Azure Service Bus Data Sender | Cola/tópico |
| Recibir mensajes | Azure Service Bus Data Receiver | Cola/suscripción |
| Publicar en Event Hubs | Azure Event Hubs Data Sender | Event Hub |
| Leer de Event Hubs | Azure Event Hubs Data Receiver | Event Hub + consumer group |
| Leer/escribir en Cosmos DB | Cosmos DB Built-in Data Reader / Contributor (RBAC propio de Cosmos) | Cuenta/BD/contenedor |
| Bajar imágenes de ACR | AcrPull | Registro |

## 2. Detectar un 403 de RBAC y explicarlo
Si falta el rol de datos, Storage responde 403 con el código `AuthorizationPermissionMismatch`:

```java
import com.azure.core.exception.HttpResponseException;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

class LectorDeBlobs {
    private static final Logger log = LoggerFactory.getLogger(LectorDeBlobs.class);

    private final BlobContainerClient contenedor = new BlobServiceClientBuilder()
            .endpoint("https://stmodalima.blob.core.windows.net")
            .credential(new DefaultAzureCredentialBuilder().build())
            .buildClient()
            .getBlobContainerClient("fotos");

    byte[] leer(String nombre) {
        try {
            return contenedor.getBlobClient(nombre).downloadContent().toBytes();
        } catch (HttpResponseException e) {
            int estado = e.getResponse().getStatusCode();
            if (estado == 403) {
                log.error("403 al leer {}: falta rol de DATOS (Storage Blob Data Reader) o hay un bloqueo de red. "
                        + "Revisar la asignación de rol de la identidad y el firewall del storage.", nombre, e);
            } else if (estado == 404) {
                log.warn("El blob {} no existe", nombre);
            }
            throw e;
        }
    }
}
```

## 3. No pidas más permisos de los que usas
Una aplicación que solo lee **no** debe tener *Contributor*. Documenta en el README del servicio los roles que necesita (y por qué) para que la revisión de seguridad sea fácil.

## 4. Spring Boot: credencial única para todo el servicio
```properties
# Spring Cloud Azure: usa la identidad administrada del entorno
spring.cloud.azure.credential.managed-identity-enabled=true
spring.cloud.azure.credential.client-id=${AZURE_CLIENT_ID:}
```
Con esto, los clientes de Blob, Service Bus, Key Vault, etc. usan la misma identidad y por tanto los mismos roles.

## 5. Quarkus
```properties
# Las extensiones de Quarkiverse para Azure usan DefaultAzureCredential por defecto
quarkus.azure.storage.blob.endpoint=https://stmodalima.blob.core.windows.net
```
> Verifica los nombres de extensiones/propiedades de Quarkiverse para Azure en tu versión.

## 6. Pruebas locales
Con `az login` tu usuario es la identidad: necesitas **los mismos roles** que tendrá la aplicación (o un grupo de desarrollo con los roles de datos en el entorno de dev). No pruebes con permisos mayores a los de producción.
