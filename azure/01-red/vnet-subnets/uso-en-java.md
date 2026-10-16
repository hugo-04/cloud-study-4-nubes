# Azure · VNet y Subnets · Uso desde Java

La red no se "programa" desde Java, pero **cómo está hecha la red afecta directamente cómo debes configurar tu aplicación**. Estos son los cuatro puntos que más fallan en producción.

## 1. Timeouts explícitos
Sin timeouts, una conexión a un destino bloqueado por un NSG se queda esperando mucho tiempo. Siempre configura **connect timeout** y **read timeout**.

### Spring Boot (imperativo) con `RestClient`
```java
import java.net.http.HttpClient;
import java.time.Duration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(3))
        .build();

JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(http);
factory.setReadTimeout(Duration.ofSeconds(5));

RestClient client = RestClient.builder()
        .baseUrl("https://api.interna.modalima.example")
        .requestFactory(factory)
        .build();
```

### Spring Boot (reactivo) con `WebClient`
```java
import io.netty.channel.ChannelOption;
import java.time.Duration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;

HttpClient httpClient = HttpClient.create()
        .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 3000)
        .responseTimeout(Duration.ofSeconds(5));

WebClient client = WebClient.builder()
        .baseUrl("https://api.interna.modalima.example")
        .clientConnector(new ReactorClientHttpConnector(httpClient))
        .build();
```

### Quarkus (REST Client)
```properties
# application.properties
quarkus.rest-client.pagos.url=https://api.interna.modalima.example
quarkus.rest-client.pagos.connect-timeout=3000
quarkus.rest-client.pagos.read-timeout=5000
```
> Los nombres de propiedades de Quarkus pueden variar entre versiones: verifica en la guía de tu versión.

## 2. Caché de DNS de la JVM
Si un nombre cambia de IP (por ejemplo, al hacer un failover o mover un Private Endpoint), la JVM puede seguir usando la IP vieja.

- Por defecto la JVM cachea resultados positivos unos 30 segundos (si no hay Security Manager). Con un Security Manager el valor por defecto es **infinito**.
- Se controla con la propiedad de seguridad `networkaddress.cache.ttl`:

```java
// Al inicio de la aplicación (antes de cualquier resolución)
java.security.Security.setProperty("networkaddress.cache.ttl", "30");
java.security.Security.setProperty("networkaddress.cache.negative.ttl", "5");
```

## 3. Timeout de inactividad (idle) de la red de Azure
El balanceador y el NAT de Azure **cierran conexiones TCP inactivas** (el valor por defecto ronda los 4 minutos; verifica el vigente). Si tu pool de conexiones mantiene conexiones "dormidas" más tiempo que eso, la próxima petición fallará con `Connection reset`.

Regla: **el tiempo máximo de vida/inactividad del pool debe ser menor que el idle timeout de la red.**

```properties
# Spring Boot + HikariCP
spring.datasource.hikari.max-lifetime=1500000      # 25 min, menor que el límite del servidor de BD
spring.datasource.hikari.idle-timeout=180000       # 3 min, menor que el idle de la red
spring.datasource.hikari.keepalive-time=120000     # envía un ping cada 2 min
```
```properties
# Quarkus + Agroal
quarkus.datasource.jdbc.idle-removal-interval=PT3M
quarkus.datasource.jdbc.max-lifetime=PT25M
```

## 4. Verificar la red desde dentro de la aplicación
Cuando algo "no conecta", no adivines: comprueba **DNS y puerto** desde el mismo lugar donde corre la app. Hay una herramienta lista en este repo:

```bash
javac -d . ../diagnostico-conectividad/ejemplos/java/ConnCheck.java
java ConnCheck mi-servidor.database.windows.net 1433
```
Interpretación: si el nombre resuelve a una IP **privada** (10.x), el DNS privado funciona; si resuelve a una **pública**, falta el enlace de la zona DNS privada.

## 5. Qué NO hacer desde Java
- No dejar timeouts en `0` (infinito).
- No fijar IP en el código: usa nombres DNS.
- No desactivar la validación TLS "porque en la red privada da error": arréglalo con el nombre correcto o el certificado correcto.
