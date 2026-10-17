# Oracle OCI · Red · Service Gateway, endpoints privados y DNS privado · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Se construyen dos piezas: un **comprobador de resolución** (la aplicación comprueba, desde su propio pod, que cada nombre resuelva a una **IP privada esperada**) y un **lector de la zona privada** con el SDK (qué registros existen). Cruzar ambos revela el error más común: *el registro existe pero el pod resuelve otra cosa*.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
  compartimento-red: ocid1.compartment.oc1..aaaa
dns:
  vista: ocid1.dnsview.oc1..aaaa
  zona: prod.tienda.interno
  rangos-privados: 10.30.0.0/16
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
oci.compartimento-red=ocid1.compartment.oc1..aaaa
dns.vista=ocid1.dnsview.oc1..aaaa
dns.zona=prod.tienda.interno
dns.rangos-privados=10.30.0.0/16
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

### 2.2 Comprobador de resolución (puro; el resolutor se inyecta)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

public enum Resolucion { OK, NO_RESUELVE, IP_PUBLICA, FUERA_DE_RANGO }

public record ResultadoDns(String nombre, Resolucion resultado, List<String> direcciones) { }

public final class ComprobadorDeDns {

    private final Function<String, List<InetAddress>> resolutor;
    private final List<long[]> rangos; // [inicio, fin) de cada rango privado aceptado

    public ComprobadorDeDns(Function<String, List<InetAddress>> resolutor, List<String> cidrs) {
        this.resolutor = resolutor;
        this.rangos = cidrs.stream().map(ComprobadorDeDns::rango).toList();
    }

    public static ComprobadorDeDns delSistema(List<String> cidrs) {
        return new ComprobadorDeDns(nombre -> {
            try {
                return List.of(InetAddress.getAllByName(nombre));
            } catch (UnknownHostException e) {
                return List.of();
            }
        }, cidrs);
    }

    public ResultadoDns comprobar(String nombre) {
        List<InetAddress> ips = resolutor.apply(nombre);
        if (ips.isEmpty()) {
            return new ResultadoDns(nombre, Resolucion.NO_RESUELVE, List.of());
        }
        var textos = ips.stream().map(InetAddress::getHostAddress).toList();
        // Una sola IP pública entre las respuestas basta para sospechar que se usa el nombre público
        if (ips.stream().anyMatch(ip -> !ip.isSiteLocalAddress() && !ip.isLoopbackAddress())) {
            return new ResultadoDns(nombre, Resolucion.IP_PUBLICA, textos);
        }
        boolean todasEnRango = ips.stream().allMatch(ip -> enRango(ip));
        return new ResultadoDns(nombre, todasEnRango ? Resolucion.OK : Resolucion.FUERA_DE_RANGO, textos);
    }

    public List<ResultadoDns> comprobarTodos(List<String> nombres) {
        var l = new ArrayList<ResultadoDns>();
        nombres.forEach(n -> l.add(comprobar(n)));
        return l;
    }

    private boolean enRango(InetAddress ip) {
        byte[] b = ip.getAddress();
        if (b.length != 4) {
            return false;
        }
        long v = ((b[0] & 255L) << 24) | ((b[1] & 255L) << 16) | ((b[2] & 255L) << 8) | (b[3] & 255L);
        return rangos.stream().anyMatch(r -> v >= r[0] && v < r[1]);
    }

    private static long[] rango(String cidr) {
        String[] p = cidr.trim().split("/");
        String[] o = p[0].split("\\.");
        long ip = 0;
        for (String x : o) {
            ip = ip << 8 | Integer.parseInt(x);
        }
        long tam = 1L << (32 - Integer.parseInt(p[1]));
        return new long[]{ip & ~(tam - 1), (ip & ~(tam - 1)) + tam};
    }
}
```

### 2.3 Lector de la zona privada con el SDK
Los registros se leen **con la vista** (el ámbito privado exige indicar `viewId`); sin ella, la API busca en el ámbito global y no encuentra nada.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.dns.DnsClient;
import com.oracle.bmc.dns.model.Scope;
import com.oracle.bmc.dns.requests.GetZoneRecordsRequest;

public record RegistroDns(String dominio, String tipo, String valor, int ttl) { }

public final class DnsPrivadoOci {

    private final DnsClient cliente;
    private final String compartimento;
    private final String vista;
    private final String zona;

    public DnsPrivadoOci(DnsClient cliente, String compartimento, String vista, String zona) {
        this.cliente = cliente;
        this.compartimento = compartimento;
        this.vista = vista;
        this.zona = zona;
    }

    public List<RegistroDns> registros() {
        var peticion = GetZoneRecordsRequest.builder().zoneNameOrId(zona).scope(Scope.Private).viewId(vista).compartmentId(compartimento).build();
        var lista = new ArrayList<RegistroDns>();
        for (var r : cliente.getPaginators().getZoneRecordsRecordIterator(peticion)) {
            lista.add(new RegistroDns(r.getDomain(), r.getRtype(), r.getRdata(), r.getTtl() == null ? 0 : r.getTtl()));
        }
        return lista;
    }

    /** Cruza lo que DICE la zona con lo que RESUELVE este pod: las diferencias son el diagnóstico. */
    public List<String> discrepancias(ComprobadorDeDns comprobador) {
        var problemas = new ArrayList<String>();
        for (RegistroDns r : registros()) {
            if (!r.tipo().equals("A")) {
                continue;
            }
            ResultadoDns real = comprobador.comprobar(r.dominio());
            if (real.resultado() != Resolucion.OK) {
                problemas.add(r.dominio() + ": la zona dice " + r.valor() + " pero este pod obtiene " + real.resultado() + " " + real.direcciones());
            } else if (!real.direcciones().contains(r.valor())) {
                problemas.add(r.dominio() + ": la zona dice " + r.valor() + " pero este pod obtiene " + real.direcciones());
            }
        }
        return problemas;
    }
}

public final class ServicioDns {

    private final DnsPrivadoOci zona;
    private final ComprobadorDeDns comprobador;

    public ServicioDns(DnsPrivadoOci zona, ComprobadorDeDns comprobador) {
        this.zona = zona;
        this.comprobador = comprobador;
    }

    public List<ResultadoDns> comprobar(List<String> nombres) {
        return comprobador.comprobarTodos(nombres);
    }

    public List<RegistroDns> registros() {
        return zona.registros();
    }

    public List<String> discrepancias() {
        return zona.discrepancias(comprobador);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.dns.DnsClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class DnsConfiguracion {

    @Bean(destroyMethod = "close")
    DnsClient dnsCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return DnsClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDns servicioDns(DnsClient cliente, @Value("${oci.compartimento-red}") String compartimento, @Value("${dns.vista}") String vista,
                            @Value("${dns.zona}") String zona, @Value("${dns.rangos-privados}") List<String> rangos) {
        return new ServicioDns(new DnsPrivadoOci(cliente, compartimento, vista, zona), ComprobadorDeDns.delSistema(rangos));
    }
}

@RestController
@RequestMapping("/red/dns")
class DnsControlador {

    private final ServicioDns s;

    DnsControlador(ServicioDns s) {
        this.s = s;
    }

    @PostMapping("/comprobar")
    List<ResultadoDns> comprobar(@RequestBody List<String> nombres) {
        return s.comprobar(nombres);
    }

    @GetMapping("/registros")
    List<RegistroDns> registros() {
        return s.registros();
    }

    @GetMapping("/discrepancias")
    List<String> discrepancias() {
        return s.discrepancias();
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.dns.DnsClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/dns")
class DnsReactivoControlador {

    private final ServicioDns s;

    DnsReactivoControlador(ServicioDns s) {
        this.s = s;
    }

    @PostMapping("/comprobar")
    Mono<List<ResultadoDns>> comprobar(@RequestBody List<String> nombres) {
        return Mono.fromCallable(() -> s.comprobar(nombres)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/registros")
    Mono<List<RegistroDns>> registros() {
        return Mono.fromCallable(() -> s.registros()).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/discrepancias")
    Mono<List<String>> discrepancias() {
        return Mono.fromCallable(() -> s.discrepancias()).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.dns.DnsClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class DnsProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "oci.compartimento-red")
    String compartimento;

    @ConfigProperty(name = "dns.vista")
    String vista;

    @ConfigProperty(name = "dns.zona")
    String zona;

    @ConfigProperty(name = "dns.rangos-privados")
    List<String> rangos;

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDns servicioDns() {
        var cliente = DnsClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDns(new DnsPrivadoOci(cliente, compartimento, vista, zona), ComprobadorDeDns.delSistema(rangos));
    }
}

@Path("/red/dns")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class DnsRecurso {

    @Inject
    ServicioDns s;

    @POST
    @Path("/comprobar")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<ResultadoDns> comprobar(List<String> nombres) {
        return s.comprobar(nombres);
    }

    @GET
    @Path("/registros")
    public List<RegistroDns> registros() {
        return s.registros();
    }

    @GET
    @Path("/discrepancias")
    public List<String> discrepancias() {
        return s.discrepancias();
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.dns.DnsClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.util.List;

@Path("/reactivo/red/dns")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class DnsRecursoReactivo {

    @Inject
    ServicioDns s;

    @POST
    @Path("/comprobar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<ResultadoDns>> comprobar(List<String> nombres) {
        return Uni.createFrom().item(() -> s.comprobar(nombres)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/registros")
    public Uni<List<RegistroDns>> registros() {
        return Uni.createFrom().item(() -> s.registros()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/discrepancias")
    public Uni<List<String>> discrepancias() {
        return Uni.createFrom().item(() -> s.discrepancias()).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| `GetZoneRecords` (zona privada) | `Allow dynamic-group app-tienda to read dns-zones in compartment red` y `read dns-records in compartment red` |
| Crear/actualizar registros | Solo el pipeline: `manage dns-records in compartment red` |

## 8. Qué NO hacer desde Java
- No pruebes la resolución desde tu laptop y la des por buena para el pod: el comprobador corre **en el pod**.
- No cachees indefinidamente: la JVM guarda las respuestas DNS (`networkaddress.cache.ttl`); ajústalo si la IP puede cambiar.
- No uses IP fijas en la configuración.
- No ejecutes el SDK síncrono en el bucle de eventos de WebFlux/Vert.x.
