# AWS · Terraform · Módulos y entornos · Uso desde Java

Desde Java **no escribes módulos ni aplicas Terraform**. Lo que sí construyes es la **puerta de entrada de autoservicio**: un portal donde un equipo pide «quiero un servicio con cola, DLQ, logs y rol» y el sistema **valida la solicitud con las mismas reglas del módulo** y **genera, de forma determinista, el archivo `servicios.auto.tfvars.json`** que se sube en un pull request. El pipeline (con su propio rol) revisa y aplica; el portal **nunca** aplica. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40. No hay llamadas al SDK de AWS: es lógica pura.

## 1. Configuración
No requiere configuración de AWS. Si el portal abre el pull request con la API de tu repositorio, esa credencial va por variable de entorno, nunca en el código ni en el archivo generado.

## 2. Núcleo común

### 2.1 La solicitud
Los campos opcionales son `Integer`: `null` significa «usa el valor por defecto del módulo» y **no se escribe** en el archivo.
```java
// (clase reutilizada en los bloques siguientes, ambos)
public record SolicitudDeServicio(String nombre, String dueno, String equipo,
                                  Integer retencionLogsDias, Integer maxReceives, Integer retencionMensajesDias) {}
```

### 2.2 Las reglas: espejo del módulo, más las de la plataforma
Las primeras reglas **repiten** las `validation` de `variables.tf` (para dar el error al instante, sin esperar al pipeline); las últimas son reglas de la plataforma que el módulo no impone. El contrato final lo comprueba `terraform test` (§7).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

public final class ReglasDeServicio {
    public record Violacion(String servicio, String campo, String regla, String detalle) {}

    static final Pattern NOMBRE = Pattern.compile("^[a-z][a-z0-9-]{1,28}[a-z0-9]$");
    static final Pattern EQUIPO = Pattern.compile("^[a-z][a-z0-9-]{1,28}$");
    static final Pattern CORREO = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");
    static final Set<String> ENTORNOS = Set.of("dev", "stg", "prod");
    static final Set<Integer> RETENCIONES_LOGS = Set.of(1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
            1096, 1827, 2192, 2557, 2922, 3288, 3653);
    static final Set<String> RESERVADOS = Set.of("admin", "root", "default", "test", "aws");

    private ReglasDeServicio() {}

    public static List<Violacion> validar(String entorno, List<SolicitudDeServicio> solicitudes) {
        List<Violacion> v = new ArrayList<>();
        if (entorno == null || !ENTORNOS.contains(entorno)) {
            v.add(new Violacion("-", "entorno", "ENTORNO_INVALIDO", "Debe ser dev, stg o prod"));
        }
        if (solicitudes == null || solicitudes.isEmpty()) {
            v.add(new Violacion("-", "servicios", "SIN_SERVICIOS", "La solicitud no define ningún servicio"));
            return v;
        }
        Set<String> vistos = new HashSet<>();
        for (SolicitudDeServicio s : solicitudes) {
            String id = s.nombre() == null ? "(sin nombre)" : s.nombre();
            // --- espejo del módulo
            if (s.nombre() == null || !NOMBRE.matcher(s.nombre()).matches()) {
                v.add(new Violacion(id, "nombre", "NOMBRE_INVALIDO", "3 a 30 caracteres: minúsculas, números y guiones; empieza por letra y no termina en guion"));
            } else if (!vistos.add(s.nombre())) {
                v.add(new Violacion(id, "nombre", "NOMBRE_DUPLICADO", "Cada servicio debe tener un nombre único"));
            }
            if (s.dueno() == null || !CORREO.matcher(s.dueno()).matches()) {
                v.add(new Violacion(id, "dueno", "DUENO_INVALIDO", "Debe ser un correo válido"));
            }
            if (s.equipo() == null || !EQUIPO.matcher(s.equipo()).matches()) {
                v.add(new Violacion(id, "equipo", "EQUIPO_INVALIDO", "Minúsculas, números y guiones"));
            }
            if (s.retencionLogsDias() != null && !RETENCIONES_LOGS.contains(s.retencionLogsDias())) {
                v.add(new Violacion(id, "retencion_logs_dias", "RETENCION_NO_ADMITIDA", "CloudWatch Logs no admite " + s.retencionLogsDias() + " días"));
            }
            if (s.maxReceives() != null && (s.maxReceives() < 1 || s.maxReceives() > 1000)) {
                v.add(new Violacion(id, "max_receives", "FUERA_DE_RANGO", "Debe estar entre 1 y 1000"));
            }
            if (s.retencionMensajesDias() != null && (s.retencionMensajesDias() < 1 || s.retencionMensajesDias() > 14)) {
                v.add(new Violacion(id, "retencion_mensajes_dias", "FUERA_DE_RANGO", "Debe estar entre 1 y 14 días"));
            }
            // --- reglas de la plataforma (el módulo no las impone)
            if (s.nombre() != null && RESERVADOS.contains(s.nombre())) {
                v.add(new Violacion(id, "nombre", "NOMBRE_RESERVADO", "Nombre reservado por la plataforma"));
            }
            if ("prod".equals(entorno) && s.retencionLogsDias() != null && s.retencionLogsDias() < 30) {
                v.add(new Violacion(id, "retencion_logs_dias", "PROD_RETENCION_MINIMA", "En prod los logs se conservan al menos 30 días"));
            }
        }
        return v;
    }
}
```

### 2.3 El generador determinista
El mismo conjunto de solicitudes produce **exactamente el mismo texto** (servicios ordenados por nombre, claves ordenadas, sin campos nulos, saltos de línea fijos): los pull requests solo muestran diferencias reales. Se escribe sin librerías para controlar el formato.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class GeneradorDeVariables {
    private GeneradorDeVariables() {}

    /** Asume solicitudes ya validadas. */
    public static String tfvarsJson(List<SolicitudDeServicio> solicitudes) {
        List<SolicitudDeServicio> ordenadas = new ArrayList<>(solicitudes);
        ordenadas.sort(Comparator.comparing(SolicitudDeServicio::nombre));
        StringBuilder sb = new StringBuilder("{\n  \"servicios\": {\n");
        for (int i = 0; i < ordenadas.size(); i++) {
            SolicitudDeServicio s = ordenadas.get(i);
            Map<String, Object> campos = new LinkedHashMap<>();   // orden alfabético fijo
            campos.put("dueno", s.dueno());
            campos.put("equipo", s.equipo());
            campos.put("max_receives", s.maxReceives());
            campos.put("retencion_logs_dias", s.retencionLogsDias());
            campos.put("retencion_mensajes_dias", s.retencionMensajesDias());
            List<String> lineas = new ArrayList<>();
            campos.forEach((clave, valor) -> {
                if (valor != null) {
                    lineas.add("      \"" + clave + "\": " + (valor instanceof String texto ? "\"" + escapar(texto) + "\"" : valor));
                }
            });
            sb.append("    \"").append(escapar(s.nombre())).append("\": {\n");
            sb.append(String.join(",\n", lineas)).append("\n    }");
            sb.append(i < ordenadas.size() - 1 ? ",\n" : "\n");
        }
        return sb.append("  }\n}\n").toString();
    }

    static String escapar(String texto) {
        StringBuilder sb = new StringBuilder();
        for (char c : texto.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        return sb.toString();
    }
}
```

### 2.4 El servicio y la respuesta
Valida primero; solo genera el archivo si no hay violaciones.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public record RespuestaDeSolicitud(boolean valida, List<ReglasDeServicio.Violacion> violaciones, String tfvars) {}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public final class ServicioDeSolicitudes {
    public RespuestaDeSolicitud procesar(String entorno, List<SolicitudDeServicio> solicitudes) {
        List<ReglasDeServicio.Violacion> violaciones = ReglasDeServicio.validar(entorno, solicitudes);
        if (!violaciones.isEmpty()) {
            return new RespuestaDeSolicitud(false, violaciones, null);
        }
        return new RespuestaDeSolicitud(true, List.of(), GeneradorDeVariables.tfvarsJson(solicitudes));
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
class SolicitudesConfig {
    @Bean
    ServicioDeSolicitudes servicioDeSolicitudes() {
        return new ServicioDeSolicitudes();
    }
}

@RestController
@RequestMapping("/entornos/{entorno}/servicios")
class SolicitudesController {
    private final ServicioDeSolicitudes servicio;

    SolicitudesController(ServicioDeSolicitudes servicio) {
        this.servicio = servicio;
    }

    /** Valida y devuelve el servicios.auto.tfvars.json que se adjuntará al pull request. */
    @PostMapping("/tfvars")
    ResponseEntity<RespuestaDeSolicitud> generar(@PathVariable String entorno, @RequestBody List<SolicitudDeServicio> solicitudes) {
        RespuestaDeSolicitud r = servicio.procesar(entorno, solicitudes);
        return ResponseEntity.status(r.valida() ? HttpStatus.OK : HttpStatus.UNPROCESSABLE_ENTITY).body(r);
    }
}
```

## 4. Spring WebFlux (reactivo)
```java
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/r/entornos/{entorno}/servicios")
class SolicitudesReactivoController {
    private final ServicioDeSolicitudes servicio;

    SolicitudesReactivoController(ServicioDeSolicitudes servicio) {
        this.servicio = servicio;
    }

    @PostMapping("/tfvars")
    Mono<ResponseEntity<RespuestaDeSolicitud>> generar(@PathVariable String entorno, @RequestBody Flux<SolicitudDeServicio> solicitudes) {
        return solicitudes.collectList()
                .map(lista -> servicio.procesar(entorno, List.copyOf(lista)))
                .map(r -> ResponseEntity.status(r.valida() ? HttpStatus.OK : HttpStatus.UNPROCESSABLE_ENTITY).body(r));
    }
}
```
> Es CPU liviana: no hace falta salir del hilo de eventos. Si la validación consultara un catálogo externo, ahí sí iría con `Mono` y `boundedElastic`.

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;

@ApplicationScoped
class SolicitudesProductores {
    @Produces
    @Singleton
    ServicioDeSolicitudes servicio() {
        return new ServicioDeSolicitudes();
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;

@Path("/entornos/{entorno}/servicios")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class SolicitudesRecurso {
    @Inject
    ServicioDeSolicitudes servicio;

    @POST
    @Path("/tfvars")
    public Response generar(@PathParam("entorno") String entorno, List<SolicitudDeServicio> solicitudes) {
        RespuestaDeSolicitud r = servicio.procesar(entorno, solicitudes);
        return Response.status(r.valida() ? 200 : 422).entity(r).build();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;

@Path("/m/entornos/{entorno}/servicios")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class SolicitudesMutinyRecurso {
    @Inject
    ServicioDeSolicitudes servicio;

    @POST
    @Path("/tfvars")
    public Uni<Response> generar(@PathParam("entorno") String entorno, List<SolicitudDeServicio> solicitudes) {
        return Uni.createFrom().item(() -> servicio.procesar(entorno, solicitudes))
                .map(r -> Response.status(r.valida() ? 200 : 422).entity(r).build());
    }
}
```

## 7. Prueba de contrato en CI
El archivo que genera Java debe ser aceptado por el módulo **real**. En el pipeline del portal (o del repositorio de infraestructura):
```bash
# 1) El portal genera el archivo y lo coloca en el entorno.
cp generado/servicios.auto.tfvars.json infra/envs/dev/servicios.auto.tfvars.json

# 2) La prueba de contrato (proveedor simulado, no toca AWS).
cd infra/envs/dev
terraform init -backend=false -input=false
terraform test        # ejecuta tests/contrato.tftest.hcl con el archivo generado
```
Si alguien cambia una `validation` del módulo y no la refleja en Java (o al revés), este paso falla **antes** del `plan` real.

## 8. Qué NO hacer desde Java
- **No** apliques desde el portal: genera el archivo y abre un pull request; el pipeline aplica con su rol (§ intro).
- **No** pongas secretos en el archivo generado: se versiona y termina en el estado; usa referencias (ARN).
- **No** generes el archivo con `Map` sin orden ni librerías que cambien el formato entre versiones: la salida debe ser determinista (§2.3).
- **No** dependas de que Java y el módulo coincidan «de memoria»: la prueba de contrato (§7) lo verifica.
- **No** dejes que el portal escriba directamente en `main`: pull request con revisión.
- **No** expongas el listado de otros equipos en las respuestas de error.
