# Azure · Casos integrados · Runbook de diagnóstico · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-identity`). Verifica las vigentes.

El runbook se ejecuta con consultas y comandos ([`triage.sh`](ejemplos/cli/triage.sh), [KQL](ejemplos/kql/kql-incidente.md)). Java aporta lo que ninguna consulta ve: **lo que la aplicación ve desde su propio pod**, con su propia red e identidad. La idea es una **sonda sintética** que recorre la escalera de [diagnóstico de conectividad](../../01-red/diagnostico-conectividad/README.md) para cada dependencia, **se detiene en el primer escalón que falla** y propone una hipótesis:

```
 DNS ──► RUTA Y PUERTO ──► TLS ──► IDENTIDAD       (cada escalón depende del anterior: si DNS falla, no tiene sentido probar el puerto)
  │          │               │         │
 ¿resuelve? ¿conecta?     ¿certificado ¿se obtiene
 ¿a IP      ¿timeout o      y nombre    el token?
 privada?    rechazo?       válidos?
```

La clase [`ConnCheck`](../../01-red/diagnostico-conectividad/ejemplos/java/ConnCheck.java) del capítulo de red hace esto para **un** destino desde la línea de comandos. Aquí se convierte en un componente que prueba **todas** las dependencias en paralelo, se expone en un endpoint interno y se ejecuta de forma programada (para que las alertas lo usen).

Permisos: la sonda usa **la identidad de la aplicación** (no una más poderosa) y solo pide un token, no usa los servicios. Su endpoint **solo** lo ven operaciones y desde la red interna: revela la topología.

## 1. La escalera y las hipótesis (sin dependencias de Spring ni de Quarkus)

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.net.ConnectException;
import java.net.InetAddress;
import java.net.NoRouteToHostException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import javax.net.ssl.SSLException;

public enum Causa {
    OK("OK"), DNS_NO_RESUELVE("DNS"), DNS_PUBLICA("DNS"), TIMEOUT("RUTA_Y_PUERTO"), RECHAZADA("RUTA_Y_PUERTO"),
    ERROR_DE_RED("RUTA_Y_PUERTO"), TLS_INVALIDO("TLS"), TOKEN_FALLIDO("IDENTIDAD");

    private final String escalon;

    Causa(String escalon) {
        this.escalon = escalon;
    }

    public String escalon() {
        return escalon;
    }
}

public record Dependencia(String nombre, String host, int puerto, boolean tls, boolean esperaPrivada, String alcanceDeToken) { }

public record ResultadoDeDependencia(String dependencia, Causa causa, long ms, String detalle) {

    public boolean ok() {
        return causa == Causa.OK;
    }
}

public record Hipotesis(String dependencia, String causaProbable, String siguientePaso) { }

public record InformeDeSonda(Instant inicio, long duracionMs, List<ResultadoDeDependencia> dependencias, List<Hipotesis> hipotesis) {

    public boolean todoBien() {
        return dependencias.stream().allMatch(ResultadoDeDependencia::ok);
    }
}

/** Las cuatro pruebas posibles, detrás de una interfaz para poder simularlas en las pruebas. */
public interface Pruebas {
    List<InetAddress> resolver(String host) throws IOException;

    void conectar(InetAddress direccion, int puerto, Duration limite) throws IOException;

    void handshakeTls(String host, int puerto, Duration limite) throws IOException;

    /** Lanza una excepción si no se puede obtener el token. */
    void obtenerToken(String alcance);
}

public final class EscaleraDeDiagnostico {

    private final Pruebas pruebas;
    private final Duration limite;

    public EscaleraDeDiagnostico(Pruebas pruebas, Duration limite) {
        this.pruebas = pruebas;
        this.limite = limite;
    }

    public ResultadoDeDependencia diagnosticar(Dependencia d) {
        long inicio = System.nanoTime();
        try {
            List<InetAddress> direcciones = pruebas.resolver(d.host());
            if (direcciones.isEmpty()) {
                return resultado(d, Causa.DNS_NO_RESUELVE, inicio, "no devuelve direcciones");
            }
            InetAddress direccion = direcciones.get(0);
            if (d.esperaPrivada() && !direccion.isSiteLocalAddress()) {
                return resultado(d, Causa.DNS_PUBLICA, inicio, "resuelve a IP pública " + enmascarar(direccion) + ": se esperaba una privada");
            }
            pruebas.conectar(direccion, d.puerto(), limite);
            if (d.tls()) {
                pruebas.handshakeTls(d.host(), d.puerto(), limite);
            }
        } catch (UnknownHostException e) {
            return resultado(d, Causa.DNS_NO_RESUELVE, inicio, "el nombre no resuelve");
        } catch (SocketTimeoutException | NoRouteToHostException e) {
            return resultado(d, Causa.TIMEOUT, inicio, "sin respuesta hacia el puerto " + d.puerto() + " (ruta o firewall)");
        } catch (ConnectException e) {
            return resultado(d, Causa.RECHAZADA, inicio, "conexión rechazada: nadie escucha o el Private Endpoint no está aprobado");
        } catch (SSLException e) {
            return resultado(d, Causa.TLS_INVALIDO, inicio, "falló el protocolo seguro: " + e.getClass().getSimpleName());
        } catch (IOException e) {
            return resultado(d, Causa.ERROR_DE_RED, inicio, e.getClass().getSimpleName());
        }
        if (d.alcanceDeToken() != null) {
            try {
                pruebas.obtenerToken(d.alcanceDeToken());
            } catch (RuntimeException e) {
                return resultado(d, Causa.TOKEN_FALLIDO, inicio, "no se obtuvo el token: " + e.getClass().getSimpleName());
            }
        }
        return resultado(d, Causa.OK, inicio, "alcanzable");
    }

    private static ResultadoDeDependencia resultado(Dependencia d, Causa causa, long inicioNanos, String detalle) {
        return new ResultadoDeDependencia(d.nombre(), causa, (System.nanoTime() - inicioNanos) / 1_000_000, detalle);
    }

    /** Las IP públicas se muestran parcialmente: el informe no debe servir de mapa a un atacante. */
    static String enmascarar(InetAddress direccion) {
        String[] octetos = direccion.getHostAddress().split("\\.");
        return octetos.length == 4 ? octetos[0] + "." + octetos[1] + ".x.x" : "(IPv6)";
    }
}

public final class ClasificadorDeSintomas {

    private ClasificadorDeSintomas() { }

    public static Hipotesis para(ResultadoDeDependencia r) {
        return switch (r.causa()) {
            case DNS_NO_RESUELVE -> new Hipotesis(r.dependencia(), "El nombre no resuelve desde este pod",
                    "Revisar la zona privatelink, el enlace a la red virtual del clúster y los reenviadores de DNS");
            case DNS_PUBLICA -> new Hipotesis(r.dependencia(), "Resuelve a la IP pública: la zona DNS privada no está enlazada o falta el registro",
                    "Comprobar el enlace de la zona a la VNet de AKS y el registro A del Private Endpoint");
            case TIMEOUT -> new Hipotesis(r.dependencia(), "Los paquetes se descartan: NSG, firewall o ruta",
                    "Revisar reglas efectivas del NSG y la verificación de flujo IP de Network Watcher");
            case RECHAZADA -> new Hipotesis(r.dependencia(), "Llega al destino pero nadie atiende: servicio detenido o Private Endpoint sin aprobar",
                    "Revisar el estado de la conexión del Private Endpoint y el puerto del servicio");
            case ERROR_DE_RED -> new Hipotesis(r.dependencia(), "Error de red no clasificado",
                    "Ver el detalle y los registros del nodo; repetir la prueba desde otro pod");
            case TLS_INVALIDO -> new Hipotesis(r.dependencia(), "Certificado vencido, nombre que no coincide o CA no confiable",
                    "Comprobar el certificado del destino y los almacenes de confianza de la imagen");
            case TOKEN_FALLIDO -> new Hipotesis(r.dependencia(), "La identidad no consigue el token (federación, audiencia o emisor)",
                    "Revisar la credencial federada, la cuenta de servicio y la etiqueta de identidad del pod");
            case OK -> new Hipotesis(r.dependencia(), "Sin problema en esta capa", "Pasar a la capa de aplicación (logs y trazas)");
        };
    }
}

public final class SondaSintetica {

    private static final System.Logger LOG = System.getLogger("sonda");

    private final EscaleraDeDiagnostico escalera;
    private final Duration limiteTotal;

    public SondaSintetica(EscaleraDeDiagnostico escalera, Duration limiteTotal) {
        this.escalera = escalera;
        this.limiteTotal = limiteTotal;
    }

    /** Prueba todas las dependencias en paralelo (hilos virtuales). Una dependencia colgada no frena a las demás. */
    public InformeDeSonda ejecutar(List<Dependencia> dependencias) {
        Instant inicio = Instant.now();
        long t0 = System.nanoTime();
        List<ResultadoDeDependencia> resultados = new ArrayList<>();
        try (var ejecutor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<ResultadoDeDependencia>> futuros = dependencias.stream()
                    .map(d -> ejecutor.submit(() -> escalera.diagnosticar(d)))
                    .toList();
            for (int i = 0; i < futuros.size(); i++) {
                try {
                    resultados.add(futuros.get(i).get(limiteTotal.toMillis(), TimeUnit.MILLISECONDS));
                } catch (TimeoutException | ExecutionException e) {
                    futuros.get(i).cancel(true);
                    resultados.add(new ResultadoDeDependencia(dependencias.get(i).nombre(), Causa.TIMEOUT, limiteTotal.toMillis(),
                            "la prueba superó el límite total"));
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        List<Hipotesis> hipotesis = resultados.stream().filter(r -> !r.ok()).map(ClasificadorDeSintomas::para).toList();
        for (ResultadoDeDependencia r : resultados) {
            // Una línea estructurada por dependencia: es lo que leen la alerta y el panel
            LOG.log(System.Logger.Level.INFO, "sonda.dependencia dependencia={0} escalon={1} ok={2} ms={3}",
                    r.dependencia(), r.causa().escalon(), r.ok(), r.ms());
        }
        return new InformeDeSonda(inicio, (System.nanoTime() - t0) / 1_000_000, resultados, hipotesis);
    }
}
```

## 2. Las pruebas reales (JDK y Azure Identity)

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;

import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import java.net.InetSocketAddress;
import java.net.Socket;

public final class PruebasReales implements Pruebas {

    private final TokenCredential credencial;

    public PruebasReales(TokenCredential credencial) {
        this.credencial = credencial;
    }

    @Override
    public List<InetAddress> resolver(String host) throws IOException {
        return List.of(InetAddress.getAllByName(host));
    }

    @Override
    public void conectar(InetAddress direccion, int puerto, Duration limite) throws IOException {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(direccion, puerto), (int) limite.toMillis());
        }
    }

    @Override
    public void handshakeTls(String host, int puerto, Duration limite) throws IOException {
        // Se verifica el NOMBRE del certificado contra el host (algoritmo HTTPS), no solo que el certificado sea válido
        try (Socket base = new Socket()) {
            base.connect(new InetSocketAddress(host, puerto), (int) limite.toMillis());
            base.setSoTimeout((int) limite.toMillis());
            try (SSLSocket tls = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(base, host, puerto, true)) {
                SSLParameters parametros = tls.getSSLParameters();
                parametros.setEndpointIdentificationAlgorithm("HTTPS");
                tls.setSSLParameters(parametros);
                tls.startHandshake();
            }
        }
    }

    @Override
    public void obtenerToken(String alcance) {
        // El token se obtiene y se descarta: nunca se registra ni se devuelve
        credencial.getTokenSync(new TokenRequestContext().addScopes(alcance));
    }
}
```

## 3. Spring Boot (MVC): endpoint interno y ejecución programada

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.List;

@Configuration
@EnableScheduling
class SondaConfiguracion {

    @Bean
    SondaSintetica sonda() {
        var pruebas = new PruebasReales(new DefaultAzureCredentialBuilder().build());
        return new SondaSintetica(new EscaleraDeDiagnostico(pruebas, Duration.ofSeconds(3)), Duration.ofSeconds(8));
    }

    @Bean
    List<Dependencia> dependencias(@Value("${sonda.sql}") String sql, @Value("${sonda.bovedas}") String bovedas,
                                   @Value("${sonda.mensajeria}") String mensajeria, @Value("${sonda.comprobantes}") String comprobantes) {
        return List.of(
                new Dependencia("azure-sql", sql, 1433, true, true, null),
                new Dependencia("key-vault", bovedas, 443, true, true, "https://vault.azure.net/.default"),
                new Dependencia("service-bus", mensajeria, 5671, false, true, "https://servicebus.azure.net/.default"),
                new Dependencia("blob-comprobantes", comprobantes, 443, true, true, "https://storage.azure.com/.default"));
    }
}

@RestController
@RequestMapping("/diagnostico")
class DiagnosticoControlador {

    private final SondaSintetica sonda;
    private final List<Dependencia> dependencias;

    DiagnosticoControlador(SondaSintetica sonda, List<Dependencia> dependencias) {
        this.sonda = sonda;
        this.dependencias = dependencias;
    }

    @GetMapping("/dependencias")
    @PreAuthorize("hasAuthority('SCOPE_operaciones')") // revela la topología: solo operaciones, y solo por la red interna
    InformeDeSonda dependencias() {
        return sonda.ejecutar(dependencias);
    }
}

@Component
class SondaProgramada {

    private final SondaSintetica sonda;
    private final List<Dependencia> dependencias;

    SondaProgramada(SondaSintetica sonda, List<Dependencia> dependencias) {
        this.sonda = sonda;
        this.dependencias = dependencias;
    }

    @Scheduled(fixedDelayString = "${sonda.intervalo-ms:60000}")
    void ejecutar() {
        sonda.ejecutar(dependencias); // el registro estructurado alimenta la alerta de la sonda
    }
}
```

## 4. Spring WebFlux (reactivo)
Las pruebas de red del JDK son bloqueantes: se aíslan en `boundedElastic`.

```java
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

import java.util.List;

@RestController
@RequestMapping("/reactivo/diagnostico")
class DiagnosticoReactivoControlador {

    private final SondaSintetica sonda;
    private final List<Dependencia> dependencias;

    DiagnosticoReactivoControlador(SondaSintetica sonda, List<Dependencia> dependencias) {
        this.sonda = sonda;
        this.dependencias = dependencias;
    }

    @GetMapping("/dependencias")
    @PreAuthorize("hasAuthority('SCOPE_operaciones')")
    Mono<InformeDeSonda> dependencias() {
        return Mono.fromCallable(() -> sonda.ejecutar(dependencias)).subscribeOn(Schedulers.boundedElastic());
    }
}
```

## 5. Quarkus · imperativo
```java
// (clase reutilizada en los bloques siguientes)
import com.azure.identity.DefaultAzureCredentialBuilder;
import io.quarkus.scheduler.Scheduled;
import jakarta.annotation.security.RolesAllowed;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.time.Duration;
import java.util.List;

@ApplicationScoped
class SondaProductores {

    @ConfigProperty(name = "sonda.sql")
    String sql;

    @ConfigProperty(name = "sonda.bovedas")
    String bovedas;

    @ConfigProperty(name = "sonda.mensajeria")
    String mensajeria;

    @ConfigProperty(name = "sonda.comprobantes")
    String comprobantes;

    @Produces
    @Singleton
    SondaSintetica sonda() {
        var pruebas = new PruebasReales(new DefaultAzureCredentialBuilder().build());
        return new SondaSintetica(new EscaleraDeDiagnostico(pruebas, Duration.ofSeconds(3)), Duration.ofSeconds(8));
    }

    List<Dependencia> dependencias() {
        return List.of(
                new Dependencia("azure-sql", sql, 1433, true, true, null),
                new Dependencia("key-vault", bovedas, 443, true, true, "https://vault.azure.net/.default"),
                new Dependencia("service-bus", mensajeria, 5671, false, true, "https://servicebus.azure.net/.default"),
                new Dependencia("blob-comprobantes", comprobantes, 443, true, true, "https://storage.azure.com/.default"));
    }
}

@ApplicationScoped
class SondaProgramadaQuarkus {

    @Inject
    SondaSintetica sonda;

    @Inject
    SondaProductores productores;

    @Scheduled(every = "1m", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void ejecutar() {
        sonda.ejecutar(productores.dependencias());
    }
}

@Path("/diagnostico")
class DiagnosticoRecurso {

    @Inject
    SondaSintetica sonda;

    @Inject
    SondaProductores productores;

    @GET
    @Path("/dependencias")
    @RolesAllowed("operaciones")
    @jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public InformeDeSonda dependencias() {
        return sonda.ejecutar(productores.dependencias());
    }
}
```

## 6. Quarkus · reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/reactivo/diagnostico")
class DiagnosticoRecursoReactivo {

    @Inject
    SondaSintetica sonda;

    @Inject
    SondaProductores productores;

    @GET
    @Path("/dependencias")
    @RolesAllowed("operaciones")
    @jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<InformeDeSonda> dependencias() {
        return Uni.createFrom().item(() -> sonda.ejecutar(productores.dependencias()))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 7. Ejecutarla en el pod que falla (sin tocar la aplicación)
El manifiesto [`pod-diagnostico.yaml`](ejemplos/k8s/pod-diagnostico.yaml) levanta un pod efímero **con la misma cuenta de servicio (y, por tanto, identidad y red) que la aplicación**. Copia en él `ConnCheck.java` o el JAR de la sonda y ejecútalo; al terminar, bórralo. Es la forma de saber qué ve la aplicación sin reiniciarla.

## 8. Pruebas

| Nivel | Qué se comprueba | Cómo |
|---|---|---|
| **Escalera** | Cada falla simulada cae en su escalón: nombre inexistente → `DNS_NO_RESUELVE`; IP pública cuando se esperaba privada → `DNS_PUBLICA`; timeout → `TIMEOUT`; rechazo → `RECHAZADA`; error SSL → `TLS_INVALIDO`; token → `TOKEN_FALLIDO` | `Pruebas` falso |
| **Orden** | Si DNS falla, **no** se intenta conectar | El falso cuenta las llamadas |
| **Paralelismo** | Una dependencia colgada no impide que las demás reporten | Falso que duerme más que el límite total |
| **Clasificador** | Cada causa tiene hipótesis y siguiente paso | Tabla de casos |
| **Real local** | Conexión a un puerto abierto en `localhost` → `OK`; puerto cerrado → `RECHAZADA` | `ServerSocket` en la prueba |
| **Seguridad** | El informe nunca contiene tokens ni IP públicas completas | Revisar el JSON |

## 9. Buenas prácticas de código
- **Probar en el orden de la escalera** y detenerse en el primer fallo: es lo que da una respuesta clara.
- **La sonda corre con la identidad de la aplicación**, no con una más poderosa: si no puede, la aplicación tampoco.
- **Tiempos límite siempre** (por escalón y total): una sonda colgada es otro incidente.
- **Una línea estructurada por dependencia** (`sonda.dependencia …`): es la fuente de la alerta y del panel.
- **El informe no revela secretos ni IP públicas completas.**
- **El endpoint es interno y con rol**: es un mapa de tu arquitectura.
- **Verificar el nombre del certificado**, no solo que sea válido.
