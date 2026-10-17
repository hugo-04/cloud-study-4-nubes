# Azure · Terraform · Módulos y entornos · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, `azure-json` 1.5**. Verifica las vigentes.

## Qué haces (y qué no) con módulos desde Java

Terraform **no tiene SDK para Java** y tu microservicio no declara infraestructura. Lo que sí se construye en Java es **plataforma**: el **portal de autoservicio** donde un equipo pide "una aplicación nueva" y el sistema produce el cambio de infraestructura por la vía normal (Git y pipeline).

| Caso | Qué haces desde Java |
|---|---|
| **Validar la solicitud** | Aplicar las mismas reglas del módulo (nombres, entornos, IP) **antes** de abrir un cambio |
| **Generar `terraform.tfvars.json`** | Añadir la aplicación al archivo del entorno, de forma **determinista** (claves ordenadas, un valor por línea) para que el diff sea legible |
| **Abrir el pull request** | (No cubierto aquí) Subir el archivo a Git y dejar que el pipeline haga `plan`, revisión y `apply` |

> Reglas de oro: el portal **no aplica nada** por su cuenta (el pipeline y sus aprobaciones mandan), **no guarda secretos** (el módulo no los pide) y las reglas de Java **se prueban contra el módulo real** para que no se desincronicen.

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-json</artifactId></dependency>
```

**Permisos:** el portal necesita permiso para **abrir pull requests** en el repositorio de infraestructura (una aplicación de GitHub con alcance mínimo). No necesita ningún rol de Azure.

## 1. La solicitud y las reglas (funciones puras)

Las reglas repiten lo que el módulo exige (`validation` y `precondition`); su ventaja es que el equipo recibe **todos los errores a la vez, en el formulario**, y no uno por vez en un `plan`.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

public record SolicitudDeAplicacion(String aplicacion, String entorno, String sufijo, String dueno,
                                    Set<String> contenedores, List<String> ips, String replicacion) {

    public SolicitudDeAplicacion {
        contenedores = contenedores == null ? Set.of() : Set.copyOf(contenedores);
        ips = ips == null ? List.of() : List.copyOf(ips);
        replicacion = replicacion == null || replicacion.isBlank() ? "ZRS" : replicacion;
    }
}

public final class ReglasDeNombres {

    public record Violacion(String campo, String mensaje) { }

    private static final Pattern APLICACION = Pattern.compile("^[a-z0-9]{3,14}$");
    private static final Pattern SUFIJO = Pattern.compile("^[a-z0-9]{3,6}$");
    // 3 a 63 caracteres; empieza y termina con letra o número; guiones solo entre letras/números y sin repetirse
    private static final Pattern CONTENEDOR = Pattern.compile("^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){1,61}[a-z0-9]$");
    private static final Set<String> ENTORNOS = Set.of("dev", "qa", "prod");
    private static final Set<String> REPLICACIONES = Set.of("LRS", "ZRS", "GRS", "GZRS");
    private static final int MAXIMO_CONTENEDORES = 20;
    private static final int MAXIMO_NOMBRE_CUENTA = 24;

    public List<Violacion> validar(SolicitudDeAplicacion s) {
        List<Violacion> v = new ArrayList<>();
        if (s.aplicacion() == null || !APLICACION.matcher(s.aplicacion()).matches()) {
            v.add(new Violacion("aplicacion", "Debe tener 3 a 14 letras minúsculas o números"));
        }
        if (s.entorno() == null || !ENTORNOS.contains(s.entorno())) {
            v.add(new Violacion("entorno", "Debe ser dev, qa o prod"));
        }
        if (s.sufijo() == null || !SUFIJO.matcher(s.sufijo()).matches()) {
            v.add(new Violacion("sufijo", "Debe tener 3 a 6 letras minúsculas o números"));
        }
        if (s.dueno() == null || s.dueno().isBlank() || s.dueno().length() > 64
                || s.dueno().chars().anyMatch(Character::isISOControl)) {
            v.add(new Violacion("dueno", "Obligatorio, hasta 64 caracteres y sin caracteres de control"));
        }
        if (!REPLICACIONES.contains(s.replicacion())) {
            v.add(new Violacion("replicacion", "Debe ser LRS, ZRS, GRS o GZRS"));
        }
        if (s.contenedores().size() > MAXIMO_CONTENEDORES) {
            v.add(new Violacion("contenedores", "Máximo " + MAXIMO_CONTENEDORES + " contenedores por solicitud"));
        }
        for (String c : s.contenedores()) {
            if (!CONTENEDOR.matcher(c).matches()) {
                v.add(new Violacion("contenedores", "Nombre de contenedor inválido (3 a 63 caracteres, minúsculas, números y guiones)"));
                break;
            }
        }
        for (String ip : s.ips()) {
            String problema = problemaDeIp(ip);
            if (problema != null) {
                v.add(new Violacion("ips", problema));
            }
        }
        // Relación entre campos: el nombre global de la cuenta (st + aplicación + entorno + sufijo)
        if (s.aplicacion() != null && s.entorno() != null && s.sufijo() != null) {
            int largo = 2 + s.aplicacion().length() + s.entorno().length() + s.sufijo().length();
            if (largo > MAXIMO_NOMBRE_CUENTA) {
                v.add(new Violacion("aplicacion", "El nombre de la cuenta tendría " + largo
                        + " caracteres; el máximo es " + MAXIMO_NOMBRE_CUENTA));
            }
        }
        return v;
    }

    /** Reglas de las IP del firewall de la cuenta: públicas, IPv4, sin /31 ni /32 y sin rangos enormes. */
    static String problemaDeIp(String texto) {
        if (texto == null || texto.isBlank()) {
            return "IP vacía";
        }
        String[] partes = texto.split("/", -1);
        if (partes.length > 2) {
            return "Formato de IP inválido: " + texto;
        }
        String[] octetos = partes[0].split("\\.", -1);
        if (octetos.length != 4) {
            return "Solo se admite IPv4 en formato a.b.c.d o a.b.c.d/n: " + texto;
        }
        int[] o = new int[4];
        for (int i = 0; i < 4; i++) {
            try {
                o[i] = Integer.parseInt(octetos[i]);
            } catch (NumberFormatException e) {
                return "Formato de IP inválido: " + texto;
            }
            if (o[i] < 0 || o[i] > 255 || octetos[i].length() > 3) {
                return "Formato de IP inválido: " + texto;
            }
        }
        if (partes.length == 2) {
            int prefijo;
            try {
                prefijo = Integer.parseInt(partes[1]);
            } catch (NumberFormatException e) {
                return "Prefijo inválido: " + texto;
            }
            if (prefijo >= 31) {
                return "Los rangos /31 y /32 no se admiten: indica la IP sola (" + partes[0] + ")";
            }
            if (prefijo < 16) {
                return "Rango demasiado amplio (mínimo /16): " + texto;
            }
        }
        boolean privada = o[0] == 10 || (o[0] == 172 && o[1] >= 16 && o[1] <= 31) || (o[0] == 192 && o[1] == 168)
                || o[0] == 127 || o[0] == 0 || (o[0] == 169 && o[1] == 254);
        if (privada) {
            return "Las IP privadas no se admiten en el firewall de la cuenta (usa subredes o Private Endpoint): " + texto;
        }
        return null;
    }
}
```

> La regla `/16` es **una política tuya**, no de Azure: evita abrir media Internet por error. Las demás (IPv4, públicas, sin /31 y /32) responden a las restricciones de las reglas IP de Azure Storage: **verifica en la documentación vigente**.

## 2. El generador de `terraform.tfvars.json` (determinista)

Añade la aplicación al archivo existente **sin reordenar lo demás**: claves ordenadas, un valor por línea, sin duplicar aplicaciones. Un archivo estable produce *diffs* pequeños en el pull request.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.json.JsonProviders;
import com.azure.json.JsonReader;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;

public final class GeneradorDeVariables {

    public String crear(SolicitudDeAplicacion s) {
        return agregar("{}", s);
    }

    @SuppressWarnings("unchecked")
    public String agregar(String tfvarsExistente, SolicitudDeAplicacion s) {
        Map<String, Object> raiz = new LinkedHashMap<>();
        Map<String, Object> aplicaciones = new TreeMap<>();
        Object leido = leer(tfvarsExistente == null || tfvarsExistente.isBlank() ? "{}" : tfvarsExistente);
        if (!(leido instanceof Map<?, ?> existente)) {
            throw new IllegalArgumentException("El archivo de variables no es un objeto JSON");
        }
        for (Map.Entry<?, ?> e : existente.entrySet()) {
            if ("aplicaciones".equals(e.getKey())) {
                if (e.getValue() instanceof Map<?, ?> apps) {
                    apps.forEach((k, val) -> aplicaciones.put(String.valueOf(k), val));
                }
            } else {
                raiz.put(String.valueOf(e.getKey()), e.getValue());
            }
        }
        if (aplicaciones.containsKey(s.aplicacion())) {
            throw new IllegalStateException("La aplicación " + s.aplicacion() + " ya existe en este entorno");
        }
        Map<String, Object> nueva = new TreeMap<>();
        nueva.put("dueno", s.dueno().strip());
        nueva.put("contenedores", new ArrayList<>(new TreeSet<>(s.contenedores())));
        nueva.put("ips", new ArrayList<>(new TreeSet<>(s.ips())));
        nueva.put("replicacion", s.replicacion());
        aplicaciones.put(s.aplicacion(), nueva);
        raiz.put("aplicaciones", aplicaciones);

        StringBuilder salida = new StringBuilder();
        escribir(raiz, 0, salida);
        return salida.append('\n').toString();
    }

    private static Object leer(String json) {
        try (JsonReader lector = JsonProviders.createReader(json)) {
            return lector.readUntyped();
        } catch (IOException | RuntimeException e) {
            throw new IllegalArgumentException("El archivo de variables no es un JSON válido");
        }
    }

    private static void escribir(Object valor, int nivel, StringBuilder sb) {
        String sangria = "  ".repeat(nivel + 1);
        String cierre = "  ".repeat(nivel);
        if (valor instanceof Map<?, ?> mapa) {
            if (mapa.isEmpty()) {
                sb.append("{}");
                return;
            }
            sb.append("{\n");
            int i = 0;
            for (Map.Entry<?, ?> e : mapa.entrySet()) {
                sb.append(sangria);
                texto(String.valueOf(e.getKey()), sb);
                sb.append(": ");
                escribir(e.getValue(), nivel + 1, sb);
                sb.append(++i < mapa.size() ? ",\n" : "\n");
            }
            sb.append(cierre).append('}');
        } else if (valor instanceof List<?> lista) {
            if (lista.isEmpty()) {
                sb.append("[]");
                return;
            }
            sb.append("[\n");
            for (int i = 0; i < lista.size(); i++) {
                sb.append(sangria);
                escribir(lista.get(i), nivel + 1, sb);
                sb.append(i < lista.size() - 1 ? ",\n" : "\n");
            }
            sb.append(cierre).append(']');
        } else if (valor instanceof String s) {
            texto(s, sb);
        } else {
            sb.append(valor); // número, booleano o null
        }
    }

    private static void texto(String s, StringBuilder sb) {
        sb.append('"');
        for (char c : s.toCharArray()) {
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
        sb.append('"');
    }
}
```

## 3. El servicio y la respuesta
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.List;

public record RespuestaDeSolicitud(boolean valida, List<ReglasDeNombres.Violacion> violaciones, String tfvars) { }

public final class ServicioDeSolicitudes {

    private final ReglasDeNombres reglas = new ReglasDeNombres();
    private final GeneradorDeVariables generador = new GeneradorDeVariables();

    /** tfvarsActual: contenido del archivo del entorno en Git (o null si todavía no existe). */
    public RespuestaDeSolicitud evaluar(SolicitudDeAplicacion solicitud, String tfvarsActual) {
        List<ReglasDeNombres.Violacion> violaciones = reglas.validar(solicitud);
        if (!violaciones.isEmpty()) {
            return new RespuestaDeSolicitud(false, violaciones, null);
        }
        return new RespuestaDeSolicitud(true, List.of(), generador.agregar(tfvarsActual, solicitud));
    }
}
```

## 4. Spring MVC
Para este ejemplo, el archivo actual del entorno llega en el cuerpo; en la vida real lo lees del repositorio con la API de Git.

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/plataforma/terraform/solicitudes")
class SolicitudesControlador {

    private final ServicioDeSolicitudes servicio = new ServicioDeSolicitudes();

    record Pedido(SolicitudDeAplicacion solicitud, String tfvarsActual) { }

    @PostMapping("/validacion")
    ResponseEntity<RespuestaDeSolicitud> validar(@RequestBody Pedido pedido) {
        RespuestaDeSolicitud respuesta = servicio.evaluar(pedido.solicitud(), pedido.tfvarsActual());
        return ResponseEntity.status(respuesta.valida() ? HttpStatus.OK : HttpStatus.UNPROCESSABLE_ENTITY).body(respuesta);
    }
}
```

## 5. Spring WebFlux (reactivo)
El trabajo es **CPU ligera y sin entrada/salida**: no hace falta cambiar de planificador. El reactivo aquí solo evita bloquear el hilo mientras llega el cuerpo.

```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/reactivo/plataforma/terraform/solicitudes")
class SolicitudesReactivoControlador {

    private final ServicioDeSolicitudes servicio = new ServicioDeSolicitudes();

    record Pedido(SolicitudDeAplicacion solicitud, String tfvarsActual) { }

    @PostMapping("/validacion")
    Mono<ResponseEntity<RespuestaDeSolicitud>> validar(@RequestBody Mono<Pedido> pedido) {
        return pedido
                .map(p -> servicio.evaluar(p.solicitud(), p.tfvarsActual()))
                .map(r -> ResponseEntity.status(r.valida() ? HttpStatus.OK : HttpStatus.UNPROCESSABLE_ENTITY).body(r));
    }
}
```

## 6. Quarkus · imperativo
```java
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/plataforma/terraform/solicitudes")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class SolicitudesRecurso {

    private final ServicioDeSolicitudes servicio = new ServicioDeSolicitudes();

    public record Pedido(SolicitudDeAplicacion solicitud, String tfvarsActual) { }

    @POST
    @Path("/validacion")
    public Response validar(Pedido pedido) {
        RespuestaDeSolicitud respuesta = servicio.evaluar(pedido.solicitud(), pedido.tfvarsActual());
        return Response.status(respuesta.valida() ? 200 : 422).entity(respuesta).build();
    }
}
```

## 7. Quarkus · reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/reactivo/plataforma/terraform/solicitudes")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class SolicitudesRecursoReactivo {

    private final ServicioDeSolicitudes servicio = new ServicioDeSolicitudes();

    public record Pedido(SolicitudDeAplicacion solicitud, String tfvarsActual) { }

    @POST
    @Path("/validacion")
    public Uni<Response> validar(Pedido pedido) {
        return Uni.createFrom().item(() -> servicio.evaluar(pedido.solicitud(), pedido.tfvarsActual()))
                .map(r -> Response.status(r.valida() ? 200 : 422).entity(r).build());
    }
}
```

## 8. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Reglas** | Una solicitud mala por campo; todos los errores a la vez | Funciones puras |
| **Generador** | Entrada con aplicaciones existentes → salida con las claves ordenadas y sin tocar lo demás | Compara texto exacto (el diff debe ser mínimo) |
| **Duplicados** | Agregar una aplicación que ya existe | Debe fallar |
| **Contrato con el módulo** | El JSON generado se usa como `-var-file` en `terraform test` de la raíz del entorno ([`contrato.tftest.hcl`](ejemplos/envs/dev/tests/contrato.tftest.hcl)): probado con el archivo que genera este código | La prueba que evita que Java y el módulo se desincronicen |
| **Integración** | Un repositorio de laboratorio: el portal abre el PR y el pipeline planifica | Prueba el flujo completo |

```bash
# Prueba de contrato en CI: el archivo que genera Java debe pasar la validación del módulo
terraform -chdir=envs/dev test -var-file=../../generado/aplicaciones.tfvars.json   # ver envs/dev/tests/contrato.tftest.hcl
```

```java
// nocheck — requiere JUnit 5
class SolicitudesTest {

    private final ServicioDeSolicitudes servicio = new ServicioDeSolicitudes();

    @Test
    void rechazaTodosLosErroresALaVez() {
        var mala = new SolicitudDeAplicacion("Pedidos!", "pruebas", "1", "", Set.of("A_B"), List.of("10.0.0.1", "203.0.113.5/32"), "XYZ");

        var r = servicio.evaluar(mala, null);

        assertFalse(r.valida());
        assertTrue(r.violaciones().size() >= 6);
    }

    @Test
    void generaUnArchivoEstableYOrdenado() {
        var s = new SolicitudDeAplicacion("pedidos", "dev", "001", "equipo-pedidos", Set.of("fotos", "facturas"), List.of(), "ZRS");

        String json = servicio.evaluar(s, null).tfvars();

        assertTrue(json.indexOf("facturas") < json.indexOf("fotos"));
        assertEquals(json, servicio.evaluar(s, null).tfvars());
    }
}
```

## 9. Buenas prácticas de código
- **El portal propone, el pipeline dispone:** el resultado es un pull request, nunca un `apply`.
- **Mismas reglas que el módulo**, y una **prueba de contrato** en CI para que no se desincronicen.
- **Todos los errores a la vez**, con el nombre del campo.
- **Salida determinista** (claves ordenadas, un valor por línea): diffs legibles.
- **Sin secretos** en solicitudes, archivos ni registros.
- **No confíes en el cliente:** valida siempre en el servidor, también longitudes y caracteres de control.
- En reactivo, no hace falta cambiar de hilo para trabajo puro y corto; sí para I/O bloqueante (Git, red).
