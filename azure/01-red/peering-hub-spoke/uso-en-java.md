# Azure · Peering y Hub-and-Spoke · Uso desde Java

Con peering y firewalls en el medio, tu servicio Java cruza redes. Lo que importa en el código:

## 1. Usa nombres DNS, no IP
Entre VNets peereadas, los nombres de servicios privados deben resolverse desde cada spoke. Usa nombres (`inventario.interno.modalima.example`) respaldados por zonas DNS privadas enlazadas, no direcciones IP.

## 2. Timeouts y latencia entre regiones
Un peering global añade latencia (decenas a cientos de ms según la distancia). Los timeouts de un cliente que funcionaba en la misma región pueden quedarse cortos.

```properties
# Spring Boot (propiedades propias de tu cliente)
inventario.client.connect-timeout=3s
inventario.client.read-timeout=8s      # sube con criterio si el servicio está en otra región
```
```java
// Cliente HTTP con Circuit Breaker para no esperar a un spoke caído (Resilience4j)
// resilience4j.circuitbreaker.instances.inventario.failure-rate-threshold=50
// resilience4j.circuitbreaker.instances.inventario.wait-duration-in-open-state=20s
// resilience4j.timelimiter.instances.inventario.timeout-duration=8s
```

## 3. Servicios entre spokes por firewall: espera "bloqueos" legítimos
Si el hub filtra el tráfico, una llamada nueva puede fallar con **timeout** hasta que alguien abra la regla. Haz que tu aplicación **registre host, puerto y tipo de error** para que el equipo de red vea de inmediato qué regla falta.

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

class LlamadaEntreSpokes {
    private static final Logger log = LoggerFactory.getLogger(LlamadaEntreSpokes.class);

    void ejecutar() {
        try {
            llamarServicioDeOtroSpoke();
        } catch (java.net.http.HttpConnectTimeoutException e) {
            log.error("Timeout conectando a inventario.interno:443 (¿regla de firewall del hub?)", e);
        } catch (java.net.UnknownHostException e) {
            log.error("DNS no resuelve inventario.interno (¿zona privada enlazada al spoke?)", e);
        } catch (java.io.IOException e) {
            log.error("Error de E/S hacia inventario.interno", e);
        }
    }

    private void llamarServicioDeOtroSpoke() throws java.io.IOException { /* llamada real */ }
}
```

## 4. Quarkus
```properties
quarkus.rest-client.inventario.url=https://inventario.interno.modalima.example
quarkus.rest-client.inventario.connect-timeout=3000
quarkus.rest-client.inventario.read-timeout=8000
```
```java
import io.smallrye.faulttolerance.api.CircuitBreakerName;
import org.eclipse.microprofile.faulttolerance.CircuitBreaker;
import org.eclipse.microprofile.faulttolerance.Timeout;

@CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 20000)
@Timeout(8000)
public String consultarStock(String sku) { /* ... */ return ""; }
```
> Verifica anotaciones y propiedades en la versión de Quarkus que uses.

## 5. Idempotencia
Con redes que pueden cortarse en un salto intermedio, asegúrate de que reintentos de operaciones de escritura sean seguros (**clave de idempotencia**). Se ve en detalle en `transversal/patrones-microservicios`.
