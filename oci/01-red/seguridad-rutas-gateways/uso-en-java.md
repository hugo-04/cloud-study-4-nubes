# Oracle OCI · Red · Listas de seguridad, NSG, rutas y gateways · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Se construye un **auditor de reglas de red**: lee las listas de seguridad y los NSG de una VCN con el SDK y señala lo peligroso (administración o bases de datos abiertas a Internet, todo abierto, reglas sin estado, reglas sin descripción). El análisis es **puro** (se prueba sin red); el SDK solo trae las reglas. **Una regla que no se pudo leer es un hallazgo**, no «sin problemas».

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

### 2.2 Auditor de reglas (puro)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Set;

public record Regla(String propietario, String direccion, String protocolo, String origen, int desde, int hasta, boolean sinEstado, String descripcion) { }

public enum Gravedad { ALTA, MEDIA, BAJA }

public record Hallazgo(String propietario, Gravedad gravedad, String codigo, String detalle) { }

public final class AuditorDeReglas {

    static final Set<Integer> ADMINISTRACION = Set.of(22, 3389);
    static final Set<Integer> DATOS = Set.of(1521, 1522, 3306, 5432, 6379, 9092, 27017);
    static final Set<String> ABIERTO = Set.of("0.0.0.0/0", "::/0");

    private AuditorDeReglas() { }

    static boolean cubre(Regla r, int puerto) {
        if (r.protocolo().equals("all")) {
            return true;
        }
        return (r.protocolo().equals("6") || r.protocolo().equals("17")) && r.desde() <= puerto && puerto <= r.hasta();
    }

    public static List<Hallazgo> auditar(List<Regla> reglas) {
        var h = new ArrayList<Hallazgo>();
        for (Regla r : reglas) {
            boolean entradaAbierta = r.direccion().equals("INGRESS") && ABIERTO.contains(r.origen());
            if (entradaAbierta) {
                boolean todo = r.protocolo().equals("all") || (r.desde() <= 1 && r.hasta() >= 65535);
                if (todo) {
                    h.add(new Hallazgo(r.propietario(), Gravedad.ALTA, "TODO_ABIERTO", "entrada desde Internet a todos los puertos"));
                } else {
                    ADMINISTRACION.stream().filter(p -> cubre(r, p)).findFirst().ifPresent(p ->
                            h.add(new Hallazgo(r.propietario(), Gravedad.ALTA, "ADMIN_ABIERTO", "administración (puerto " + p + ") abierta a Internet")));
                    DATOS.stream().filter(p -> cubre(r, p)).findFirst().ifPresent(p ->
                            h.add(new Hallazgo(r.propietario(), Gravedad.ALTA, "DATOS_ABIERTO", "puerto de datos " + p + " abierto a Internet")));
                    boolean web = r.desde() >= 80 && r.hasta() <= 443 && (r.desde() == r.hasta() || (r.desde() == 80 && r.hasta() == 443));
                    if (!web && r.hasta() - r.desde() > 100 && h.stream().noneMatch(x -> x.propietario().equals(r.propietario()) && x.gravedad() == Gravedad.ALTA)) {
                        h.add(new Hallazgo(r.propietario(), Gravedad.MEDIA, "RANGO_AMPLIO", "rango de " + (r.hasta() - r.desde() + 1) + " puertos abierto a Internet"));
                    }
                }
            }
            if (r.sinEstado()) {
                h.add(new Hallazgo(r.propietario(), Gravedad.MEDIA, "SIN_ESTADO", "regla sin estado: comprueba que exista la regla de retorno"));
            }
            if (r.descripcion() == null || r.descripcion().isBlank()) {
                h.add(new Hallazgo(r.propietario(), Gravedad.BAJA, "SIN_DESCRIPCION", "regla sin descripción"));
            }
        }
        h.sort(Comparator.comparing(Hallazgo::gravedad).thenComparing(Hallazgo::propietario));
        return h;
    }
}
```

### 2.3 Lectura con el SDK y servicio
Los rangos de puertos son opcionales en OCI: **sin rango de destino significa todos los puertos**, y el lector debe respetarlo (si no, se subestima el riesgo).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.core.VirtualNetworkClient;
import com.oracle.bmc.core.model.PortRange;
import com.oracle.bmc.core.model.TcpOptions;
import com.oracle.bmc.core.model.UdpOptions;
import com.oracle.bmc.core.requests.ListNetworkSecurityGroupSecurityRulesRequest;
import com.oracle.bmc.core.requests.ListNetworkSecurityGroupsRequest;
import com.oracle.bmc.core.requests.ListSecurityListsRequest;

public final class AuditoriaDeRed {

    private final VirtualNetworkClient cliente;
    private final String compartimento;

    public AuditoriaDeRed(VirtualNetworkClient cliente, String compartimento) {
        this.cliente = cliente;
        this.compartimento = compartimento;
    }

    /** Auditoría pura de reglas ya leídas (por ejemplo, enviadas por un pipeline). */
    public List<Hallazgo> evaluar(List<Regla> reglas) {
        return AuditorDeReglas.auditar(reglas);
    }

    public List<Hallazgo> auditar(String vcnId) {
        var reglas = new ArrayList<Regla>();
        var fallos = new ArrayList<Hallazgo>();
        try {
            var peticion = ListSecurityListsRequest.builder().compartmentId(compartimento).vcnId(vcnId).build();
            for (var lista : cliente.getPaginators().listSecurityListsRecordIterator(peticion)) {
                String nombre = "lista:" + lista.getDisplayName();
                for (var e : lista.getIngressSecurityRules()) {
                    int[] p = puertos(e.getProtocol(), e.getTcpOptions(), e.getUdpOptions());
                    reglas.add(new Regla(nombre, "INGRESS", e.getProtocol(), e.getSource(), p[0], p[1], Boolean.TRUE.equals(e.getIsStateless()), e.getDescription()));
                }
            }
        } catch (RuntimeException e) {
            fallos.add(new Hallazgo("listas de seguridad", Gravedad.ALTA, "NO_SE_PUDO_VERIFICAR", e.getClass().getSimpleName()));
        }
        try {
            var peticion = ListNetworkSecurityGroupsRequest.builder().compartmentId(compartimento).vcnId(vcnId).build();
            for (var nsg : cliente.getPaginators().listNetworkSecurityGroupsRecordIterator(peticion)) {
                String nombre = "nsg:" + nsg.getDisplayName();
                var rp = ListNetworkSecurityGroupSecurityRulesRequest.builder().networkSecurityGroupId(nsg.getId()).build();
                for (var r : cliente.getPaginators().listNetworkSecurityGroupSecurityRulesRecordIterator(rp)) {
                    int[] p = puertos(r.getProtocol(), r.getTcpOptions(), r.getUdpOptions());
                    String direccion = r.getDirection().getValue().toUpperCase();
                    String origen = direccion.equals("INGRESS") ? r.getSource() : r.getDestination();
                    reglas.add(new Regla(nombre, direccion, r.getProtocol(), origen, p[0], p[1], Boolean.TRUE.equals(r.getIsStateless()), r.getDescription()));
                }
            }
        } catch (RuntimeException e) {
            fallos.add(new Hallazgo("NSG", Gravedad.ALTA, "NO_SE_PUDO_VERIFICAR", e.getClass().getSimpleName()));
        }
        var todos = new ArrayList<Hallazgo>(fallos);
        todos.addAll(AuditorDeReglas.auditar(reglas));
        return todos;
    }

    /** Sin rango de destino = todos los puertos (1-65535). */
    static int[] puertos(String protocolo, TcpOptions tcp, UdpOptions udp) {
        PortRange rango = protocolo.equals("6") && tcp != null ? tcp.getDestinationPortRange()
                : protocolo.equals("17") && udp != null ? udp.getDestinationPortRange() : null;
        return rango == null ? new int[]{1, 65535} : new int[]{rango.getMin(), rango.getMax()};
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class AuditoriaConfiguracion {

    @Bean(destroyMethod = "close")
    VirtualNetworkClient redCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    AuditoriaDeRed auditoria(VirtualNetworkClient cliente, @Value("${oci.compartimento-red}") String compartimento) {
        return new AuditoriaDeRed(cliente, compartimento);
    }
}

@RestController
@RequestMapping("/red/auditoria")
class AuditoriaControlador {

    private final AuditoriaDeRed s;

    AuditoriaControlador(AuditoriaDeRed s) {
        this.s = s;
    }

    @PostMapping("/evaluar")
    List<Hallazgo> evaluar(@RequestBody List<Regla> reglas) {
        return s.evaluar(reglas);
    }

    @GetMapping("/vcn")
    List<Hallazgo> vcn(@RequestParam String vcn) {
        return s.auditar(vcn);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.core.VirtualNetworkClient;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/red/auditoria")
class AuditoriaReactivoControlador {

    private final AuditoriaDeRed s;

    AuditoriaReactivoControlador(AuditoriaDeRed s) {
        this.s = s;
    }

    @PostMapping("/evaluar")
    Mono<List<Hallazgo>> evaluar(@RequestBody List<Regla> reglas) {
        return Mono.fromCallable(() -> s.evaluar(reglas));
    }

    @GetMapping("/vcn")
    Mono<List<Hallazgo>> vcn(@RequestParam String vcn) {
        return Mono.fromCallable(() -> s.auditar(vcn)).subscribeOn(Schedulers.boundedElastic());
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
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AuditoriaProductores {

    @ConfigProperty(name = "oci.auth")
    String modo;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "oci.compartimento-red")
    String compartimento;

    @jakarta.enterprise.inject.Produces
    @Singleton
    AuditoriaDeRed auditoria() {
        var cliente = VirtualNetworkClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new AuditoriaDeRed(cliente, compartimento);
    }
}

@Path("/red/auditoria")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class AuditoriaRecurso {

    @Inject
    AuditoriaDeRed s;

    @POST
    @Path("/evaluar")
    @Consumes(MediaType.APPLICATION_JSON)
    public List<Hallazgo> evaluar(List<Regla> reglas) {
        return s.evaluar(reglas);
    }

    @GET
    @Path("/vcn")
    public List<Hallazgo> vcn(@QueryParam("vcn") String vcn) {
        return s.auditar(vcn);
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
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.util.List;

@Path("/reactivo/red/auditoria")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class AuditoriaRecursoReactivo {

    @Inject
    AuditoriaDeRed s;

    @POST
    @Path("/evaluar")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<List<Hallazgo>> evaluar(List<Regla> reglas) {
        return Uni.createFrom().item(() -> s.evaluar(reglas));
    }

    @GET
    @Path("/vcn")
    public Uni<List<Hallazgo>> vcn(@QueryParam("vcn") String vcn) {
        return Uni.createFrom().item(() -> s.auditar(vcn)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política (en el compartimento de red) |
|---|---|
| `ListSecurityLists`, `ListNetworkSecurityGroups`, `ListNetworkSecurityGroupSecurityRules` | `Allow dynamic-group auditor-red to inspect security-lists in compartment red` y `inspect network-security-groups in compartment red` |
| Cambiar reglas | **Ninguna** desde el auditor: solo lectura |

## 8. Qué NO hacer desde Java
- No marques «sin hallazgos» cuando una lectura falló: se reporta `NO_SE_PUDO_VERIFICAR`.
- No des permisos de escritura al auditor; que sugiera, y que el cambio pase por Terraform y revisión.
- No asumas que «sin rango» es «ningún puerto»: es **todos**.
- No audites en cada petición HTTP: ejecútalo programado y guarda el último informe.
- No ejecutes el SDK síncrono en el bucle de eventos de WebFlux/Vert.x.
