# Azure · Diagnóstico de conectividad · Uso desde Java

## 1. Probar DNS + TCP desde dentro (ConnCheck)
Sin instalar nada más que un JDK:

```bash
# En un pod de AKS con JDK
kubectl run jdk --rm -it --image=eclipse-temurin:21 -- bash
# pega ConnCheck.java y ejecuta:
java ConnCheck.java sql-modalima.database.windows.net 1433
```
Salida típica y cómo leerla:
| Resultado | Qué significa |
|---|---|
| Resuelve a `10.x` y conecta | RPD correctos |
| Resuelve a IP **pública** | DNS privado mal enlazado |
| `UnknownHost` | DNS roto |
| `Timeout` | Ruta o NSG/firewall |
| `Connection refused` | Nadie escucha o PE sin aprobar |

## 2. Mensajes de error que ayudan
Registra **qué destino** y **qué tipo de error**. Un `catch (Exception e)` genérico oculta en qué escalón falló.

```java
import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import javax.net.ssl.SSLException;

try {
    llamar();
} catch (UnknownHostException e) {
    log.error("DNS: no resuelve {} -> revisar zona privada/DNS", host, e);
} catch (SocketTimeoutException e) {
    log.error("TIMEOUT hacia {}:{} -> revisar ruta, NSG/firewall", host, port, e);
} catch (ConnectException e) {
    log.error("RECHAZADA hacia {}:{} -> nadie escucha o PE sin aprobar", host, port, e);
} catch (SSLException e) {
    log.error("TLS hacia {} -> certificado o nombre", host, e);
}
```
> `java.net.http.HttpConnectTimeoutException` es el timeout de conexión del cliente HTTP de Java 11+; `java.net.http.HttpTimeoutException` es el timeout de la petición.

## 3. Health checks que dicen cuál dependencia falla
**Spring Boot** (Actuator):
```properties
management.endpoint.health.show-details=when_authorized
management.endpoints.web.exposure.include=health,info
```
Un `HealthIndicator` por dependencia crítica que haga DNS + TCP (ver el ejemplo en Private Endpoint · Uso en Java) permite ver el escalón exacto.

**Quarkus** (SmallRye Health):
```java
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;

@Readiness
@ApplicationScoped
public class BaseDeDatosCheck implements HealthCheck {
    @Override
    public HealthCheckResponse call() {
        var b = HealthCheckResponse.named("sql-privado");
        try (var s = new java.net.Socket()) {
            s.connect(new java.net.InetSocketAddress("sql-modalima.database.windows.net", 1433), 2000);
            return b.up().build();
        } catch (Exception e) {
            return b.down().withData("error", e.getClass().getSimpleName()).build();
        }
    }
}
```
> Extensión: `quarkus-smallrye-health`. Verifica el nombre del paquete `jakarta.*` según tu versión.

## 4. Logging útil para el equipo de red
Incluye siempre: host, puerto, tipo de error, tiempo transcurrido, y un **identificador de correlación** (`traceId`). Así un ticket para el equipo de red trae lo que necesitan.

## 5. Reintentos y circuit breaker
Un error de DNS o de NSG **no se arregla reintentando**. Reintenta solo fallos transitorios; abre el circuito cuando un destino falla de forma sostenida.
