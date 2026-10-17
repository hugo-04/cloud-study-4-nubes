# Oracle OCI · Red · Diagnóstico de conectividad · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Dos herramientas: la **escalera** (DNS → TCP → TLS, desde el propio pod, deteniéndose en el primer fallo) y el **analizador de rutas** (dada una subred y una IP destino, ¿por qué puerta saldría el paquete?, usando la ruta más específica de la tabla de rutas leída con el SDK).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
  compartimento-red: ocid1.compartment.oc1..aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
oci.compartimento-red=ocid1.compartment.oc1..aaaa
```

## 2. Núcleo común

### 2.1 Autenticación según dónde corre el código
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
        }
    }
}
```

### 2.2 La escalera (DNS, puerto, TLS)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.net.ConnectException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NoRouteToHostException;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.time.Duration;
import javax.net.ssl.SSLException;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

public enum Escalon { DNS, RUTA_O_SEGURIDAD, SERVICIO, TLS, TODO_BIEN }

public record Diagnostico(Escalon escalon, String detalle, long ms) { }

public interface Sondeos {
    InetAddress resolver(String host) throws IOException;

    void conectar(InetAddress ip, int puerto, Duration limite) throws IOException;

    void tls(String host, int puerto, Duration limite) throws IOException;
}

public final class SondeosReales implements Sondeos {

    @Override
    public InetAddress resolver(String host) throws IOException {
        return InetAddress.getByName(host);
    }

    @Override
    public void conectar(InetAddress ip, int puerto, Duration limite) throws IOException {
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress(ip, puerto), (int) limite.toMillis());
        }
    }

    @Override
    public void tls(String host, int puerto, Duration limite) throws IOException {
        try (Socket base = new Socket()) {
            base.connect(new InetSocketAddress(host, puerto), (int) limite.toMillis());
            base.setSoTimeout((int) limite.toMillis());
            try (SSLSocket t = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(base, host, puerto, true)) {
                SSLParameters p = t.getSSLParameters();
                p.setEndpointIdentificationAlgorithm("HTTPS"); // verifica el NOMBRE del certificado
                t.setSSLParameters(p);
                t.startHandshake();
            }
        }
    }
}

public final class EscaleraDeConectividad {

    private final Sondeos sondeos;
    private final Duration limite;

    public EscaleraDeConectividad(Sondeos sondeos, Duration limite) {
        this.sondeos = sondeos;
        this.limite = limite;
    }

    public Diagnostico diagnosticar(String host, int puerto, boolean usaTls) {
        long t0 = System.nanoTime();
        try {
            InetAddress ip = sondeos.resolver(host);
            sondeos.conectar(ip, puerto, limite);
            if (usaTls) {
                sondeos.tls(host, puerto, limite);
            }
            return d(Escalon.TODO_BIEN, "alcanzable (" + ip.getHostAddress() + ")", t0);
        } catch (UnknownHostException e) {
            return d(Escalon.DNS, "el nombre no resuelve: revisa la vista privada y el resolutor de esta VCN", t0);
        } catch (SocketTimeoutException | NoRouteToHostException e) {
            return d(Escalon.RUTA_O_SEGURIDAD, "sin respuesta: tabla de rutas, lista de seguridad o NSG (en ambos extremos)", t0);
        } catch (ConnectException e) {
            return d(Escalon.SERVICIO, "conexión rechazada: la red llega pero nadie escucha en ese puerto", t0);
        } catch (SSLException e) {
            return d(Escalon.TLS, "falló TLS: " + e.getClass().getSimpleName() + " (certificado, nombre o fecha)", t0);
        } catch (IOException e) {
            return d(Escalon.RUTA_O_SEGURIDAD, "error de red: " + e.getClass().getSimpleName(), t0);
        }
    }

    private static Diagnostico d(Escalon e, String detalle, long t0) {
        return new Diagnostico(e, detalle, (System.nanoTime() - t0) / 1_000_000);
    }
}
```

### 2.3 Analizador de rutas (ruta más específica) con el SDK
En OCI el tipo de siguiente salto se deduce del **OCID** de la entidad de red: `ocid1.internetgateway…`, `ocid1.natgateway…`, `ocid1.servicegateway…`, `ocid1.drg…`, `ocid1.privateip…`. Las rutas a servicios de Oracle usan un nombre de servicio, no un CIDR: se muestran aparte.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.core.VirtualNetworkClient;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

public record RutaOci(String destino, String tipoDestino, String siguiente) {

    public String tipoDeSalto() {
        String id = siguiente == null ? "" : siguiente;
        if (id.startsWith("ocid1.internetgateway")) return "INTERNET_GATEWAY";
        if (id.startsWith("ocid1.natgateway")) return "NAT_GATEWAY";
        if (id.startsWith("ocid1.servicegateway")) return "SERVICE_GATEWAY";
        if (id.startsWith("ocid1.drg")) return "DRG";
        if (id.startsWith("ocid1.localpeeringgateway")) return "LPG";
        if (id.startsWith("ocid1.privateip")) return "IP_PRIVADA";
        return "DESCONOCIDO";
    }
}

public record SaltoElegido(String destino, String tipoDeSalto, String explicacion) { }

public final class AnalizadorDeRutas {

    private AnalizadorDeRutas() { }

    /** Gana el prefijo más largo entre las rutas CIDR; las rutas a servicios de Oracle no se comparan por IP. */
    public static Optional<SaltoElegido> siguienteSalto(String ip, List<RutaOci> rutas) {
        long destino = aEntero(ip);
        return rutas.stream()
                .filter(r -> r.tipoDestino().equals("CIDR_BLOCK") && contiene(r.destino(), destino))
                .max(Comparator.comparingInt(r -> Integer.parseInt(r.destino().split("/")[1])))
                .map(r -> new SaltoElegido(r.destino(), r.tipoDeSalto(), "la ruta " + r.destino() + " es la más específica para " + ip));
    }

    static boolean contiene(String cidr, long ip) {
        String[] p = cidr.split("/");
        int prefijo = Integer.parseInt(p[1]);
        long mascara = prefijo == 0 ? 0 : (0xFFFFFFFFL << (32 - prefijo)) & 0xFFFFFFFFL;
        return (aEntero(p[0]) & mascara) == (ip & mascara);
    }

    static long aEntero(String ip) {
        long v = 0;
        for (String o : ip.split("\\.")) {
            v = v << 8 | Integer.parseInt(o);
        }
        return v;
    }
}

public final class RutasOci {

    private final VirtualNetworkClient cliente;

    public RutasOci(VirtualNetworkClient cliente) {
        this.cliente = cliente;
    }

    public List<RutaOci> rutasDeSubred(String subredId) {
        var subred = cliente.getSubnet(com.oracle.bmc.core.requests.GetSubnetRequest.builder().subnetId(subredId).build()).getSubnet();
        var tabla = cliente.getRouteTable(com.oracle.bmc.core.requests.GetRouteTableRequest.builder().rtId(subred.getRouteTableId()).build()).getRouteTable();
        var rutas = new ArrayList<RutaOci>();
        for (var r : tabla.getRouteRules()) {
            String tipo = r.getDestinationType() == null ? "CIDR_BLOCK" : r.getDestinationType().getValue();
            rutas.add(new RutaOci(r.getDestination(), tipo, r.getNetworkEntityId()));
        }
        return rutas;
    }
}

public final class ServicioDiagnostico {

    private final EscaleraDeConectividad escalera;
    private final RutasOci rutas;

    public ServicioDiagnostico(EscaleraDeConectividad escalera, RutasOci rutas) {
        this.escalera = escalera;
        this.rutas = rutas;
    }

    public Diagnostico escalera(String host, int puerto, boolean tls) {
        return escalera.diagnosticar(host, puerto, tls);
    }

    public Optional<SaltoElegido> ruta(String subredId, String ip) {
        return AnalizadorDeRutas.siguienteSalto(ip, rutas.rutasDeSubred(subredId));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import java.time.Duration;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class DiagnosticoConfiguracion {

    @Bean(destroyMethod = "close")
    VirtualNetworkClient redCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDiagnostico servicioDiagnostico(VirtualNetworkClient cliente) {
        return new ServicioDiagnostico(new EscaleraDeConectividad(new SondeosReales(), Duration.ofSeconds(3)), new RutasOci(cliente));
    }
}

@RestController
@RequestMapping("/red/diagnostico")
class DiagnosticoControlador {

    private final ServicioDiagnostico s;

    DiagnosticoControlador(ServicioDiagnostico s) {
        this.s = s;
    }

    @GetMapping("/escalera")
    Diagnostico escalera(@RequestParam String host, @RequestParam int puerto, @RequestParam boolean tls) {
        return s.escalera(host, puerto, tls);
    }

    @GetMapping("/ruta")
    Optional<SaltoElegido> ruta(@RequestParam String subred, @RequestParam String ip) {
        return s.ruta(subred, ip);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import java.util.Optional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/diagnostico")
class DiagnosticoReactivoControlador {

    private final ServicioDiagnostico s;

    DiagnosticoReactivoControlador(ServicioDiagnostico s) {
        this.s = s;
    }

    @GetMapping("/escalera")
    Mono<Diagnostico> escalera(@RequestParam String host, @RequestParam int puerto, @RequestParam boolean tls) {
        return Mono.fromCallable(() -> s.escalera(host, puerto, tls)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/ruta")
    Mono<Optional<SaltoElegido>> ruta(@RequestParam String subred, @RequestParam String ip) {
        return Mono.fromCallable(() -> s.ruta(subred, ip)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.time.Duration;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class DiagnosticoProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDiagnostico servicioDiagnostico() {
        var cliente = VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDiagnostico(new EscaleraDeConectividad(new SondeosReales(), Duration.ofSeconds(3)), new RutasOci(cliente));
    }
}

@Path("/red/diagnostico")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class DiagnosticoRecurso {

    @Inject
    ServicioDiagnostico s;

    @GET
    @Path("/escalera")
    public Diagnostico escalera(@QueryParam("host") String host, @QueryParam("puerto") int puerto, @QueryParam("tls") boolean tls) {
        return s.escalera(host, puerto, tls);
    }

    @GET
    @Path("/ruta")
    public Optional<SaltoElegido> ruta(@QueryParam("subred") String subred, @QueryParam("ip") String ip) {
        return s.ruta(subred, ip);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.Optional;

@Path("/reactivo/red/diagnostico")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class DiagnosticoRecursoReactivo {

    @Inject
    ServicioDiagnostico s;

    @GET
    @Path("/escalera")
    public Uni<Diagnostico> escalera(@QueryParam("host") String host, @QueryParam("puerto") int puerto, @QueryParam("tls") boolean tls) {
        return Uni.createFrom().item(() -> s.escalera(host, puerto, tls)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/ruta")
    public Uni<Optional<SaltoElegido>> ruta(@QueryParam("subred") String subred, @QueryParam("ip") String ip) {
        return Uni.createFrom().item(() -> s.ruta(subred, ip)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `GetSubnet`, `GetRouteTable` | `Allow dynamic-group diagnostico to read virtual-network-family in compartment red` |
| La escalera | Ninguna: son sondeos de red desde el propio pod |

## 8. Qué NO hacer desde Java
- No expongas este endpoint a Internet: sondear hosts arbitrarios es un SSRF. Solo operaciones y red interna, y **lista blanca de destinos**.
- No te quedes con «alcanzable» si la prueba no verificó el nombre del certificado.
- No uses el analizador de rutas como prueba de que hay conectividad: no considera reglas de seguridad ni la ruta de vuelta.
- No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).
