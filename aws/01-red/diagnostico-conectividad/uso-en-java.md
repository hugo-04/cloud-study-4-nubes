# AWS · Diagnóstico de conectividad · Uso desde Java

Dos herramientas que cualquier servicio Java debería tener a mano: (1) **`ConnCheck`**, un diagnóstico de DNS → TCP → TLS que corres **dentro** del contenedor, y (2) un **cliente de Reachability Analyzer** con el SDK para lanzar un análisis, esperar y traducir las explicaciones en pistas. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56).

## 1. `ConnCheck` dentro del contenedor
Archivo único, sin compilar ni dependencias ([`ejemplos/java/ConnCheck.java`](ejemplos/java/ConnCheck.java)); Java 11+ lo ejecuta directamente.
```bash
# ECS Exec (sin abrir puertos):
aws ecs execute-command --cluster tienda --task <id> --container app --interactive \
  --command "java /tmp/ConnCheck.java aurora-pedidos.cluster-xxxx.us-east-1.rds.amazonaws.com 5432"
```
Interpretación:

| Salida | Significado | Siguiente paso |
|---|---|---|
| `FALLA: el nombre no resuelve` | DNS (zona privada, endpoint, nombre) | Zona privada, DNS privado, caché |
| IP **PÚBLICA** donde esperabas privada | DNS privado apagado | Endpoint con DNS privado |
| `TIMEOUT` | Algo descarta (SG, NACL, ruta) | Reachability + Flow Logs |
| `REFUSED` | Llegó, nadie escucha | Servicio/puerto del destino |
| `TLS FALLA` | Certificado, nombre o SNI | Certificado y nombre usado |
| `OK` | La red está bien | Mira la aplicación (pool, credenciales) |

## 2. Cliente de Reachability Analyzer

### Núcleo común (pistas + ejecución del análisis)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.ec2.model.AnalysisStatus;
import software.amazon.awssdk.services.ec2.model.CreateNetworkInsightsPathRequest;
import software.amazon.awssdk.services.ec2.model.DeleteNetworkInsightsAnalysisRequest;
import software.amazon.awssdk.services.ec2.model.DeleteNetworkInsightsPathRequest;
import software.amazon.awssdk.services.ec2.model.DescribeNetworkInsightsAnalysesRequest;
import software.amazon.awssdk.services.ec2.model.Explanation;
import software.amazon.awssdk.services.ec2.model.NetworkInsightsAnalysis;
import software.amazon.awssdk.services.ec2.model.Protocol;
import software.amazon.awssdk.services.ec2.model.StartNetworkInsightsAnalysisRequest;

record SolicitudAlcance(String origen, String destino, int puerto) {}

record ResultadoAnalisis(String estado, boolean alcanzable, List<String> pistas) {}

final class Pistas {
    private Pistas() {}

    /** Traduce el código de explicación en una pista accionable (heurística: verifica los códigos en la documentación vigente). */
    static String deCodigo(String codigo) {
        String c = codigo == null ? "" : codigo.toUpperCase();
        if (c.contains("SG") || c.contains("SECURITY_GROUP")) return "Un grupo de seguridad no permite el tráfico: revisa la salida del origen y la entrada del destino";
        if (c.contains("ACL")) return "Una NACL lo bloquea: revisa entrada, salida y puertos efímeros de retorno";
        if (c.contains("ROUTE") || c.contains("RTB")) return "Falta ruta o apunta a un salto equivocado: revisa las tablas de rutas de ambos lados";
        if (c.contains("PEERING") || c.contains("TGW") || c.contains("TRANSIT")) return "Problema en el peering o el Transit Gateway: asociación, propagación y rutas";
        if (c.contains("ENDPOINT") || c.contains("VPCE")) return "Revisa el endpoint: política, SG y DNS privado";
        if (c.contains("BLACKHOLE")) return "Ruta 'blackhole': el adjunto o recurso destino ya no existe";
        return "Código " + codigo + ": consulta la documentación de Reachability Analyzer";
    }

    static List<String> deExplicaciones(List<Explanation> explicaciones) {
        List<String> r = new ArrayList<>();
        for (Explanation e : explicaciones) {
            String comp = e.component() != null ? e.component().id() : "?";
            r.add("[" + comp + "] " + deCodigo(e.explanationCode()));
        }
        return r;
    }
}

final class AnalizadorRutas {
    private final Ec2Client ec2;

    AnalizadorRutas(Ec2Client ec2) { this.ec2 = ec2; }

    /** Crea la ruta, lanza el análisis, espera hasta 'espera' y limpia. Bloquea: úsalo en hilos aptos. */
    ResultadoAnalisis analizar(SolicitudAlcance s, Duration espera) throws InterruptedException {
        String pathId = ec2.createNetworkInsightsPath(CreateNetworkInsightsPathRequest.builder()
                .source(s.origen()).destination(s.destino())
                .protocol(Protocol.TCP).destinationPort(s.puerto()).build())
                .networkInsightsPath().networkInsightsPathId();
        String analisisId = null;
        try {
            analisisId = ec2.startNetworkInsightsAnalysis(StartNetworkInsightsAnalysisRequest.builder()
                    .networkInsightsPathId(pathId).build()).networkInsightsAnalysis().networkInsightsAnalysisId();

            long limite = System.nanoTime() + espera.toNanos();
            while (System.nanoTime() < limite) {
                NetworkInsightsAnalysis a = ec2.describeNetworkInsightsAnalyses(DescribeNetworkInsightsAnalysesRequest.builder()
                        .networkInsightsAnalysisIds(analisisId).build()).networkInsightsAnalyses().get(0);
                if (a.status() != AnalysisStatus.RUNNING) {
                    boolean alcanzable = Boolean.TRUE.equals(a.networkPathFound());
                    return new ResultadoAnalisis(a.statusAsString(), alcanzable,
                            alcanzable ? List.of("La configuración permite el camino. Si falla, mira DNS, servicio, TLS o capacidad.")
                                    : Pistas.deExplicaciones(a.explanations()));
                }
                Thread.sleep(2000);
            }
            return new ResultadoAnalisis("timeout", false, List.of("El análisis no terminó a tiempo: reintenta"));
        } finally {
            limpiar(analisisId, pathId);
        }
    }

    private void limpiar(String analisisId, String pathId) {
        try {
            if (analisisId != null) ec2.deleteNetworkInsightsAnalysis(DeleteNetworkInsightsAnalysisRequest.builder().networkInsightsAnalysisId(analisisId).build());
            ec2.deleteNetworkInsightsPath(DeleteNetworkInsightsPathRequest.builder().networkInsightsPathId(pathId).build());
        } catch (RuntimeException ignorado) {
            // la limpieza es opcional: un fallo no debe ocultar el resultado
        }
    }
}
```

### Spring MVC (imperativo)
```java
import java.time.Duration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
public class DiagnosticoController {
    private final AnalizadorRutas analizador;

    DiagnosticoController(Ec2Client ec2) { this.analizador = new AnalizadorRutas(ec2); }

    @PostMapping("/red/diagnostico/alcance")
    ResultadoAnalisis alcance(@RequestBody SolicitudAlcance s) throws InterruptedException {
        return analizador.analizar(s, Duration.ofSeconds(60));
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.time.Duration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;
import software.amazon.awssdk.services.ec2.Ec2Client;

@RestController
public class DiagnosticoReactivoController {
    private final AnalizadorRutas analizador;

    DiagnosticoReactivoController(Ec2Client ec2) { this.analizador = new AnalizadorRutas(ec2); }

    @PostMapping("/red/reactivo/diagnostico/alcance")
    Mono<ResultadoAnalisis> alcance(@RequestBody Mono<SolicitudAlcance> solicitud) {
        return solicitud.flatMap(s -> Mono.fromCallable(() -> analizador.analizar(s, Duration.ofSeconds(60)))
                .subscribeOn(Schedulers.boundedElastic()))        // espera con sleep: nunca en el bucle de eventos
                .timeout(Duration.ofSeconds(75));
    }
}
```

### Quarkus (imperativo)
```java
import io.smallrye.common.annotation.Blocking;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.time.Duration;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Path("/red/diagnostico/alcance")
public class DiagnosticoResource {
    @Inject
    Ec2Client ec2;

    @POST
    @Blocking
    public ResultadoAnalisis alcance(SolicitudAlcance s) throws InterruptedException {
        return new AnalizadorRutas(ec2).analizar(s, Duration.ofSeconds(60));
    }
}
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import java.time.Duration;
import software.amazon.awssdk.services.ec2.Ec2Client;

@Path("/red/reactivo/diagnostico/alcance")
public class DiagnosticoReactivoResource {
    @Inject
    Ec2Client ec2;

    @POST
    public Uni<ResultadoAnalisis> alcance(SolicitudAlcance s) {
        return Uni.createFrom().item(() -> {
                    try {
                        return new AnalizadorRutas(ec2).analizar(s, Duration.ofSeconds(60));
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        throw new IllegalStateException(e);
                    }
                })
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .ifNoItem().after(Duration.ofSeconds(75)).fail();
    }
}
```
> Permisos mínimos para esta identidad (solo en una cuenta de operaciones): `ec2:CreateNetworkInsightsPath`, `ec2:StartNetworkInsightsAnalysis`, `ec2:DescribeNetworkInsightsAnalyses`, `ec2:DeleteNetworkInsights*`. **No** expongas este endpoint a internet: es una herramienta interna de operaciones, con autenticación.

## 3. Buenas prácticas
- Una **herramienta interna** protegida (rol de operaciones), no un endpoint público.
- Cada análisis cuesta: ponle **límite de frecuencia**.
- Registra `origen/destino/puerto` y el resultado (auditoría) sin guardar datos de usuario.
- Mantén `ConnCheck` en la imagen de diagnóstico del equipo (o súbelo con ECS Exec).

## 4. Qué NO hacer desde Java
- No ejecutar análisis en cada petición de usuario.
- No reintentar sin tope (cobra por análisis).
- No concluir «es la red» sin pasar la escalera completa.
