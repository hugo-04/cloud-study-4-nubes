# Oracle OCI · Datos · NoSQL · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Un **carrito con concurrencia optimista**: el carrito es un valor inmutable con reglas (límites de ítems y cantidades) y conversión a fila; el adaptador lee por clave completa (`id_cliente`, `id_carrito`) con `NosqlClient.getRow` y escribe de forma **condicional** (`IfAbsent` si es nuevo, `ifMatch` con la versión si existe), y el servicio reintenta si otra pestaña escribió antes. El TTL de la tabla limpia los carritos abandonados.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
nosql:
  compartimento: ocid1.compartment.oc1..aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
nosql.compartimento=ocid1.compartment.oc1..aaaa
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

### 2.2 El carrito (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** El carrito como valor inmutable y su conversión a fila. Puro. */
public record Carrito(String idCliente, Map<String, Integer> items, BigDecimal total) {

    public static final int MAX_ITEMS = 50;

    public static Carrito vacio(String idCliente) {
        if (idCliente == null || !idCliente.matches("C-[0-9]{1,12}")) {
            throw new IllegalArgumentException("idCliente inválido");
        }
        return new Carrito(idCliente, Map.of(), BigDecimal.ZERO);
    }

    public Carrito agregar(String sku, int cantidad, BigDecimal precio) {
        if (cantidad < 1 || cantidad > 10 || precio.signum() <= 0) {
            throw new IllegalArgumentException("cantidad 1..10 y precio positivo");
        }
        var nuevos = new LinkedHashMap<>(items);
        nuevos.merge(sku, cantidad, Integer::sum);
        if (nuevos.size() > MAX_ITEMS || nuevos.get(sku) > 10) {
            throw new IllegalStateException("límite del carrito alcanzado");
        }
        return new Carrito(idCliente, Map.copyOf(nuevos), total.add(precio.multiply(BigDecimal.valueOf(cantidad))));
    }

    public Map<String, Object> aFila() {
        var lineas = items.entrySet().stream().map(e -> Map.<String, Object>of("sku", e.getKey(), "cantidad", e.getValue())).toList();
        return Map.of("id_cliente", idCliente, "id_carrito", "actual", "items", lineas, "total", total);
    }

    @SuppressWarnings("unchecked")
    public static Carrito deFila(Map<String, Object> fila) {
        var items = new LinkedHashMap<String, Integer>();
        for (Object o : (List<Object>) fila.getOrDefault("items", List.of())) {
            var m = (Map<String, Object>) o;
            items.put((String) m.get("sku"), ((Number) m.get("cantidad")).intValue());
        }
        return new Carrito((String) fila.get("id_cliente"), Map.copyOf(items), new BigDecimal(fila.get("total").toString()));
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.nosql.NosqlClient;
import com.oracle.bmc.nosql.model.UpdateRowDetails;
import com.oracle.bmc.nosql.requests.GetRowRequest;
import com.oracle.bmc.nosql.requests.UpdateRowRequest;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Adaptador del SDK: lectura por clave y escritura condicional por versión. */
public class CarritosOci implements AutoCloseable {

    public record Leido(Map<String, Object> fila, String version) { }

    private final NosqlClient cliente;
    private final String compartimentoId;

    public CarritosOci(NosqlClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public Optional<Leido> leer(String idCliente) {
        var r = cliente.getRow(GetRowRequest.builder().tableNameOrId("carritos").compartmentId(compartimentoId)
            .key(List.of("id_cliente:" + idCliente, "id_carrito:actual")).build());
        var fila = r.getRow().getValue();
        // el etag de la respuesta es la versión de la fila: se usa en ifMatch al escribir
        return fila == null || fila.isEmpty() ? Optional.empty() : Optional.of(new Leido(fila, r.getEtag()));
    }

    /** versionEsperada == null ⇒ solo si no existe. Devuelve false si otro escribió antes. */
    public boolean guardar(Map<String, Object> fila, String versionEsperada) {
        var det = UpdateRowDetails.builder().compartmentId(compartimentoId).value(fila).isTtlUseTableDefault(true);
        var req = UpdateRowRequest.builder().tableNameOrId("carritos");
        if (versionEsperada == null) {
            det.option(UpdateRowDetails.Option.IfAbsent);
        } else {
            req.ifMatch(versionEsperada);
        }
        return cliente.updateRow(req.updateRowDetails(det.build()).build()).getUpdateRowResult().getVersion() != null;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
```

### 2.4 Servicio
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;

public class ServicioDeCarritos {

    public record Linea(String sku, int cantidad, BigDecimal precio) { }

    private final CarritosOci carritos;

    public ServicioDeCarritos(CarritosOci carritos) {
        this.carritos = carritos;
    }

    /** Concurrencia optimista: leer, modificar, escribir si nadie cambió la fila; si no, reintentar. */
    public Carrito agregar(String idCliente, Linea l) {
        for (int intento = 0; intento < 5; intento++) {
            var leido = carritos.leer(idCliente);
            var actual = leido.map(x -> Carrito.deFila(x.fila())).orElse(Carrito.vacio(idCliente));
            var nuevo = actual.agregar(l.sku(), l.cantidad(), l.precio());
            if (carritos.guardar(nuevo.aFila(), leido.map(CarritosOci.Leido::version).orElse(null))) {
                return nuevo;
            }
        }
        throw new IllegalStateException("conflicto persistente en el carrito " + idCliente);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.nosql.NosqlClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class CarritosConfiguracion {

    @Bean(destroyMethod = "close")
    CarritosOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${nosql.compartimento}") String compartimento) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CarritosOci(NosqlClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    @Bean
    ServicioDeCarritos servicio(CarritosOci a) {
        return new ServicioDeCarritos(a);
    }
}

@RestController
@RequestMapping("/datos/carritos")
class CarritosControlador {

    private final ServicioDeCarritos s;

    CarritosControlador(ServicioDeCarritos s) {
        this.s = s;
    }

    @PostMapping("/{cliente}")
    Carrito agregar(@PathVariable String cliente, @RequestBody ServicioDeCarritos.Linea l) {
        return s.agregar(cliente, l);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.nosql.NosqlClient;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/datos/carritos")
class CarritosReactivoControlador {

    private final ServicioDeCarritos s;

    CarritosReactivoControlador(ServicioDeCarritos s) {
        this.s = s;
    }

    @PostMapping("/{cliente}")
    Mono<Carrito> agregar(@PathVariable String cliente, @RequestBody ServicioDeCarritos.Linea l) {
        return Mono.fromCallable(() -> s.agregar(cliente, l)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.nosql.NosqlClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class CarritosProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "nosql.compartimento")
    String compartimento;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CarritosOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CarritosOci(NosqlClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);
    }

    void cerrar(@Disposes CarritosOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCarritos servicio(CarritosOci a) {
        return new ServicioDeCarritos(a);
    }
}

@Path("/datos/carritos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class CarritosRecurso {

    @Inject
    ServicioDeCarritos s;

    @POST
    @Path("/{cliente}")
    @Consumes(MediaType.APPLICATION_JSON)
    public Carrito agregar(@PathParam("cliente") String cliente, ServicioDeCarritos.Linea l) {
        return s.agregar(cliente, l);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.nosql.NosqlClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/reactivo/datos/carritos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class CarritosRecursoReactivo {

    @Inject
    ServicioDeCarritos s;

    @POST
    @Path("/{cliente}")
    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<Carrito> agregar(@PathParam("cliente") String cliente, ServicioDeCarritos.Linea l) {
        return Uni.createFrom().item(() -> s.agregar(cliente, l)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Leer y escribir filas del carrito | `Allow dynamic-group app-tienda to use nosql-rows in compartment tienda-prod where target.nosql-table.name = 'carritos'` |

## 8. Qué NO hacer desde Java
- No hagas leer-modificar-escribir sin condición de versión.
- No uses `query` sin clave en el camino de cada petición.
- No guardes el carrito sin TTL.
- No pidas consistencia absoluta donde no hace falta.
