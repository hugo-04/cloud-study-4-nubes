# Oracle OCI · Gobierno · Presupuestos y costos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.

Una **proyección de cierre de mes por servicio**: trae el costo diario agrupado por servicio con `UsageapiClient.requestSummarizedUsages` (fechas a medianoche UTC) y proyecta el cierre con el ritmo de los últimos 7 días, marcando OK/ATENCIÓN/SE_PASA contra el presupuesto. Complementa las alertas de presupuesto mostrando **qué** servicio empuja el gasto.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
oci:
  auth: instance
  region: sa-saopaulo-1
costos:
  tenancy: ocid1.tenancy.oc1..aaaa
```
```properties
# Quarkus (application.properties)
oci.auth=instance
oci.region=sa-saopaulo-1
costos.tenancy=ocid1.tenancy.oc1..aaaa
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

### 2.2 Proyección (lógica pura)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/** Proyección de cierre de mes por servicio con ritmo de los últimos días. Puro. */
public class ProyeccionDeGasto {

    public record Diario(LocalDate dia, String servicio, BigDecimal costo) { }

    public record Linea(String servicio, BigDecimal acumulado, BigDecimal proyectado) { }

    public record Informe(BigDecimal acumulado, BigDecimal proyectado, BigDecimal presupuesto, String nivel, List<Linea> porServicio) { }

    private final int diasDeRitmo;

    public ProyeccionDeGasto(int diasDeRitmo) {
        this.diasDeRitmo = diasDeRitmo;
    }

    /** hoy = último día con datos completos (los costos llegan con retraso). */
    public Informe proyectar(List<Diario> datos, LocalDate hoy, BigDecimal presupuesto) {
        int restantes = YearMonth.from(hoy).lengthOfMonth() - hoy.getDayOfMonth();
        Map<String, BigDecimal> acumulado = new TreeMap<>();
        Map<String, BigDecimal> reciente = new TreeMap<>();
        LocalDate desde = hoy.minusDays(diasDeRitmo - 1L);
        for (Diario d : datos) {
            if (!YearMonth.from(d.dia()).equals(YearMonth.from(hoy)) || d.dia().isAfter(hoy)) {
                continue;
            }
            acumulado.merge(d.servicio(), d.costo(), BigDecimal::add);
            if (!d.dia().isBefore(desde)) {
                reciente.merge(d.servicio(), d.costo(), BigDecimal::add);
            }
        }
        int dias = Math.min(diasDeRitmo, hoy.getDayOfMonth());
        var lineas = acumulado.entrySet().stream().map(e -> {
            BigDecimal ritmo = reciente.getOrDefault(e.getKey(), BigDecimal.ZERO).divide(BigDecimal.valueOf(dias), 6, RoundingMode.HALF_UP);
            BigDecimal proyectado = e.getValue().add(ritmo.multiply(BigDecimal.valueOf(restantes))).setScale(2, RoundingMode.HALF_UP);
            return new Linea(e.getKey(), e.getValue().setScale(2, RoundingMode.HALF_UP), proyectado);
        }).sorted((a, b) -> b.proyectado().compareTo(a.proyectado())).toList();
        BigDecimal total = lineas.stream().map(Linea::acumulado).reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal proyectado = lineas.stream().map(Linea::proyectado).reduce(BigDecimal.ZERO, BigDecimal::add);
        double pct = presupuesto.signum() == 0 ? 0 : proyectado.doubleValue() / presupuesto.doubleValue();
        String nivel = pct >= 1.0 ? "SE_PASA" : pct >= 0.8 ? "ATENCION" : "OK";
        return new Informe(total, proyectado, presupuesto, nivel, lineas);
    }
}
```

### 2.3 Adaptador del SDK
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.usageapi.UsageapiClient;
import com.oracle.bmc.usageapi.model.RequestSummarizedUsagesDetails;
import com.oracle.bmc.usageapi.requests.RequestSummarizedUsagesRequest;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Date;
import java.util.List;

/** Adaptador del SDK: costo diario por servicio del mes en curso (Usage API, fechas en UTC a medianoche). */
public class CostosOci implements AutoCloseable {

    private final UsageapiClient cliente;
    private final String tenancyId;

    public CostosOci(UsageapiClient cliente, String tenancyId) {
        this.cliente = cliente;
        this.tenancyId = tenancyId;
    }

    public List<ProyeccionDeGasto.Diario> delMes(LocalDate hoy) {
        var desde = hoy.withDayOfMonth(1).atStartOfDay().toInstant(ZoneOffset.UTC);
        var hasta = hoy.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC);
        var det = RequestSummarizedUsagesDetails.builder().tenantId(tenancyId)
            .timeUsageStarted(Date.from(desde)).timeUsageEnded(Date.from(hasta))
            .granularity(RequestSummarizedUsagesDetails.Granularity.Daily)
            .queryType(RequestSummarizedUsagesDetails.QueryType.Cost)
            .groupBy(List.of("service")).build();
        return cliente.requestSummarizedUsages(RequestSummarizedUsagesRequest.builder()
                .requestSummarizedUsagesDetails(det).build())
            .getUsageAggregation().getItems().stream()
            .filter(u -> u.getComputedAmount() != null)
            .map(u -> new ProyeccionDeGasto.Diario(u.getTimeUsageStarted().toInstant().atZone(ZoneOffset.UTC).toLocalDate(),
                u.getService(), u.getComputedAmount()))
            .toList();
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
import java.time.LocalDate;
import java.time.ZoneOffset;

public class ServicioDeCostos {

    private final CostosOci costos;
    private final ProyeccionDeGasto proyeccion = new ProyeccionDeGasto(7);

    public ServicioDeCostos(CostosOci costos) {
        this.costos = costos;
    }

    public ProyeccionDeGasto.Informe proyectar(BigDecimal presupuesto) {
        LocalDate ayer = LocalDate.now(ZoneOffset.UTC).minusDays(1); // último día completo
        return proyeccion.proyectar(costos.delMes(ayer), ayer, presupuesto);
    }
}
```

## 3. Spring MVC (imperativo)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.usageapi.UsageapiClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class CostosConfiguracion {

    @Bean(destroyMethod = "close")
    CostosOci adaptador(@Value("${oci.auth}") String auth_, @Value("${oci.region}") String region, @Value("${costos.tenancy}") String tenancy) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CostosOci(UsageapiClient.builder().region(Region.fromRegionId(region)).build(auth), tenancy);
    }

    @Bean
    ServicioDeCostos servicio(CostosOci a) {
        return new ServicioDeCostos(a);
    }
}

@RestController
@RequestMapping("/gobierno/costos")
class CostosControlador {

    private final ServicioDeCostos s;

    CostosControlador(ServicioDeCostos s) {
        this.s = s;
    }

    @GetMapping("/proyeccion")
    ProyeccionDeGasto.Informe proyectar(@RequestParam java.math.BigDecimal presupuesto) {
        return s.proyectar(presupuesto);
    }

}
```

## 4. Spring WebFlux (reactivo)
El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.usageapi.UsageapiClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/gobierno/costos")
class CostosReactivoControlador {

    private final ServicioDeCostos s;

    CostosReactivoControlador(ServicioDeCostos s) {
        this.s = s;
    }

    @GetMapping("/proyeccion")
    Mono<ProyeccionDeGasto.Informe> proyectar(@RequestParam java.math.BigDecimal presupuesto) {
        return Mono.fromCallable(() -> s.proyectar(presupuesto)).subscribeOn(Schedulers.boundedElastic());
    }

}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.usageapi.UsageapiClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class CostosProductores {

    @ConfigProperty(name = "oci.auth")
    String auth_;

    @ConfigProperty(name = "oci.region")
    String region;

    @ConfigProperty(name = "costos.tenancy")
    String tenancy;

    @jakarta.enterprise.inject.Produces
    @Singleton
    CostosOci adaptador() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);
        return new CostosOci(UsageapiClient.builder().region(Region.fromRegionId(region)).build(auth), tenancy);
    }

    void cerrar(@Disposes CostosOci a) {
        a.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCostos servicio(CostosOci a) {
        return new ServicioDeCostos(a);
    }
}

@Path("/gobierno/costos")
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class CostosRecurso {

    @Inject
    ServicioDeCostos s;

    @GET
    @Path("/proyeccion")
    public ProyeccionDeGasto.Informe proyectar(@QueryParam("presupuesto") java.math.BigDecimal presupuesto) {
        return s.proyectar(presupuesto);
    }

}
```

## 6. Quarkus reactivo (Mutiny)
```java
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.usageapi.UsageapiClient;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;

@Path("/reactivo/gobierno/costos")
@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
class CostosRecursoReactivo {

    @Inject
    ServicioDeCostos s;

    @GET
    @Path("/proyeccion")
    public Uni<ProyeccionDeGasto.Informe> proyectar(@QueryParam("presupuesto") java.math.BigDecimal presupuesto) {
        return Uni.createFrom().item(() -> s.proyectar(presupuesto)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

}
```

## 7. Permisos
| Acción en Java | Política |
|---|---|
| Consultar la Usage API | `Allow group finanzas-automatizacion to read usage-reports in tenancy` |

## 8. Qué NO hacer desde Java
- No uses horas que no sean medianoche UTC en consultas diarias.
- No proyectes con el día de hoy (incompleto): usa ayer.
- No confundas costo calculado con factura (créditos, impuestos).
- No expongas el informe a todos: revela la arquitectura.
