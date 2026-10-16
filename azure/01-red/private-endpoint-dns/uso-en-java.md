# Azure · Private Endpoint y DNS · Uso desde Java

Para tu código, un Private Endpoint es **transparente**: usas el mismo nombre (`mistorage.blob.core.windows.net`) y la red decide si va por IP pública o privada. Lo que debes cuidar es **no romper esa transparencia**.

## 1. Conecta siempre por nombre, nunca por IP
El certificado TLS del servicio es válido para el nombre. Si pones la IP, falla el handshake (o te tientas a desactivar la validación, que es peor).

## 2. Azure SDK para Java con identidad administrada (sin claves)
Dependencias (Maven):
```xml
<dependency>
  <groupId>com.azure</groupId>
  <artifactId>azure-storage-blob</artifactId>
</dependency>
<dependency>
  <groupId>com.azure</groupId>
  <artifactId>azure-identity</artifactId>
</dependency>
```
> Usa el BOM `com.azure:azure-sdk-bom` para alinear versiones. Verifica la versión vigente.

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;

public class StorageEjemplo {
    public static void main(String[] args) {
        BlobServiceClient cliente = new BlobServiceClientBuilder()
                .endpoint("https://mistorage.blob.core.windows.net")   // el MISMO nombre público; el DNS privado lo desvía
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();

        cliente.listBlobContainers().forEach(c -> System.out.println(c.getName()));
    }
}
```
Si el DNS privado funciona, esta llamada va por `10.x.x.x`. Si el acceso público está cerrado y el DNS no está bien, verás un error de **conexión** o `403 ... not authorized to perform this operation` por red.

## 3. Spring Boot
```xml
<dependency>
  <groupId>com.azure.spring</groupId>
  <artifactId>spring-cloud-azure-starter-storage-blob</artifactId>
</dependency>
```
```properties
spring.cloud.azure.storage.blob.account-name=mistorage
spring.cloud.azure.storage.blob.container-name=entrada
# Credencial: la identidad administrada del entorno (DefaultAzureCredential)
```

## 4. Quarkus
```properties
quarkus.azure.storage.blob.endpoint=https://mistorage.blob.core.windows.net
# Autenticación con DefaultAzureCredential (identidad administrada)
```
> Extensión: `io.quarkiverse.azureservices:quarkus-azure-storage-blob`. Verifica el nombre y la versión en Quarkiverse.

## 5. JDBC hacia Azure SQL o PostgreSQL por Private Endpoint
```properties
# Spring Boot
spring.datasource.url=jdbc:sqlserver://sql-modalima.database.windows.net:1433;database=pedidos;encrypt=true;trustServerCertificate=false;loginTimeout=10
```
- `trustServerCertificate=false`: mantén la validación del certificado.
- `loginTimeout=10`: si el DNS o el NSG fallan, no esperes minutos.
- El nombre de host es el **público**; la zona privada lo resuelve a la IP del PE.

## 6. Verifica DNS desde la aplicación
```java
import java.net.InetAddress;

InetAddress[] ips = InetAddress.getAllByName("mistorage.blob.core.windows.net");
for (InetAddress ip : ips) {
    System.out.println(ip.getHostAddress() + (ip.isSiteLocalAddress() ? "  (privada)" : "  (PÚBLICA)"));
}
```
Si imprime pública, tienes un problema de DNS privado. Para una prueba completa de DNS + TCP usa [`ConnCheck.java`](../diagnostico-conectividad/ejemplos/java/ConnCheck.java).

## 7. Un healthcheck de dependencias
Haz que el endpoint `/health` de tu microservicio compruebe DNS y conexión a sus dependencias críticas, y que **diga cuál falla**. Así un incidente de DNS se ve en segundos.

```java
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

// Spring Boot 4: las clases de health viven en org.springframework.boot.health.contributor
// (en Spring Boot 3.x estaban en org.springframework.boot.actuate.health)
@Component
class StorageHealth implements HealthIndicator {
    public Health health() {
        try {
            var ip = java.net.InetAddress.getByName("mistorage.blob.core.windows.net");
            try (var s = new java.net.Socket()) {
                s.connect(new java.net.InetSocketAddress(ip, 443), 2000);
            }
            return Health.up().withDetail("ip", ip.getHostAddress()).build();
        } catch (Exception e) {
            return Health.down(e).build();
        }
    }
}
```
