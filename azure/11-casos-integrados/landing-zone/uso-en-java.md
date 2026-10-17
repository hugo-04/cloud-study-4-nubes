# Azure · Casos integrados · Landing zone · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (solo `azure-json` en la lógica). Verifica las vigentes.

La landing zone se construye con Terraform; Java entra en dos lugares donde un equipo de plataforma lo necesita de verdad:

1. **El portal de solicitud de suscripciones** (*subscription vending*): un equipo pide su espacio y el servicio **valida**, **asigna un bloque de red sin solapamientos** (el problema clásico) y genera el `terraform.tfvars.json` que irá a una solicitud de cambio.
2. **El verificador de la zona** (*checklist*): reglas puras que comparan lo que debería haber con lo que hay y devuelven hallazgos.

Para leer la jerarquía de grupos de administración, mover suscripciones o inventariar con Resource Graph, usa el código ya explicado en [Grupos de administración](../../09-gobierno/grupos-de-administracion/uso-en-java.md).

```
 Equipo ──solicitud──► Portal (Spring/Quarkus) ── valida ── asigna CIDR libre ── escribe en la base (clave primaria = sin duplicados)
                                         │
                                         └─► terraform.tfvars.json ──► repositorio ──► revisión ──► pipeline (Terraform)
 Programado: Resource Graph ──► EstadoDeSuscripcion ──► ChecklistDeAterrizaje ──► hallazgos ──► alerta/ticket
```

Permisos (plano de datos/control): el **portal** no necesita ningún permiso de Azure para asignar direcciones (solo su base de datos); el **verificador** necesita *Reader* y lectura de Resource Graph sobre la jerarquía; **nadie** del portal tiene permisos para crear suscripciones o cambiar políticas: eso lo hace el pipeline de Terraform ([capítulo 10](../../10-terraform/autenticacion-y-pipelines/README.md)).

## 1. Direcciones, solicitud y generador de variables (puro)

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.json.JsonProviders;
import com.azure.json.JsonWriter;

import java.io.IOException;
import java.io.StringWriter;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;

/** Bloque IPv4 en notación CIDR. Se guarda como número para comparar sin trucos de texto. */
public record Cidr(long inicio, int prefijo) {

    public Cidr {
        if (prefijo < 8 || prefijo > 30) {
            throw new IllegalArgumentException("Prefijo fuera de rango: /" + prefijo);
        }
        long tamano = 1L << (32 - prefijo);
        if (inicio % tamano != 0 || inicio < 0 || inicio > 0xFFFFFFFFL) {
            throw new IllegalArgumentException("Dirección no alineada con /" + prefijo);
        }
    }

    public static Cidr parse(String texto) {
        String[] partes = texto.trim().split("/");
        if (partes.length != 2) {
            throw new IllegalArgumentException("CIDR inválido: " + texto);
        }
        String[] octetos = partes[0].split("\\.");
        if (octetos.length != 4) {
            throw new IllegalArgumentException("CIDR inválido: " + texto);
        }
        long valor = 0;
        for (String o : octetos) {
            int n = Integer.parseInt(o);
            if (n < 0 || n > 255) {
                throw new IllegalArgumentException("Octeto fuera de rango: " + o);
            }
            valor = (valor << 8) | n;
        }
        return new Cidr(valor, Integer.parseInt(partes[1]));
    }

    public long tamano() {
        return 1L << (32 - prefijo);
    }

    public long fin() {
        return inicio + tamano() - 1;
    }

    public boolean solapa(Cidr otro) {
        return inicio <= otro.fin() && otro.inicio <= fin();
    }

    public boolean contiene(Cidr otro) {
        return inicio <= otro.inicio && otro.fin() <= fin();
    }

    @Override
    public String toString() {
        return ((inicio >> 24) & 255) + "." + ((inicio >> 16) & 255) + "." + ((inicio >> 8) & 255) + "." + (inicio & 255) + "/" + prefijo;
    }
}

public final class AsignadorDeRedes {

    private static final int RESERVADAS_POR_SUBRED = 5; // Azure reserva 5 direcciones en cada subred

    private AsignadorDeRedes() { }

    /** Prefijo más largo (bloque más pequeño) que alcanza para los equipos y las subredes pedidas. */
    public static int prefijoPara(int hostsNecesarios, int subredes) {
        if (hostsNecesarios < 1 || subredes < 1) {
            throw new IllegalArgumentException("hosts y subredes deben ser positivos");
        }
        long total = (long) hostsNecesarios + (long) RESERVADAS_POR_SUBRED * subredes;
        int bits = 64 - Long.numberOfLeadingZeros(total - 1); // ceil(log2(total))
        int prefijo = 32 - Math.max(bits, 4);
        if (prefijo < 16) {
            throw new IllegalArgumentException("Más de 65 000 direcciones: divide la carga en varias redes");
        }
        return Math.min(prefijo, 28);
    }

    /** Primer bloque alineado del tamaño pedido, dentro de la reserva, que no choca con ninguno ocupado. */
    public static Optional<Cidr> siguienteLibre(Cidr reserva, int prefijo, Collection<Cidr> ocupadas) {
        if (prefijo < reserva.prefijo()) {
            return Optional.empty();
        }
        long paso = 1L << (32 - prefijo);
        for (long inicio = reserva.inicio(); inicio + paso - 1 <= reserva.fin(); inicio += paso) {
            Cidr candidato = new Cidr(inicio, prefijo);
            if (ocupadas.stream().noneMatch(candidato::solapa)) {
                return Optional.of(candidato);
            }
        }
        return Optional.empty();
    }
}

public record SolicitudDeAterrizaje(String equipo, String entorno, String propietario, String centroDeCosto,
                                    int presupuestoMensual, List<String> correosDeAlerta, int hostsNecesarios) {

    private static final Pattern EQUIPO = Pattern.compile("^[a-z][a-z0-9]{2,11}$");
    private static final Pattern CORREO = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");
    private static final Pattern CENTRO = Pattern.compile("^CC-\\d{4}$");

    /** Lista de errores; vacía si la solicitud es aceptable. */
    public List<String> validar() {
        List<String> errores = new ArrayList<>();
        if (equipo == null || !EQUIPO.matcher(equipo).matches()) {
            errores.add("equipo: minúsculas y dígitos, 3-12 caracteres, empieza con letra");
        }
        if (!"dev".equals(entorno) && !"prod".equals(entorno)) {
            errores.add("entorno: dev o prod");
        }
        if (propietario == null || !CORREO.matcher(propietario).matches()) {
            errores.add("propietario: correo válido");
        }
        if (centroDeCosto == null || !CENTRO.matcher(centroDeCosto).matches()) {
            errores.add("centroDeCosto: formato CC-0000");
        }
        if (presupuestoMensual < 100 || presupuestoMensual > 100_000) {
            errores.add("presupuestoMensual: entre 100 y 100000");
        }
        if (correosDeAlerta == null || correosDeAlerta.isEmpty() || correosDeAlerta.stream().anyMatch(c -> c == null || !CORREO.matcher(c).matches())) {
            errores.add("correosDeAlerta: al menos un correo válido");
        }
        if (hostsNecesarios < 1 || hostsNecesarios > 30_000) {
            errores.add("hostsNecesarios: entre 1 y 30000");
        }
        return errores;
    }
}

public final class GeneradorDeTfvars {

    private GeneradorDeTfvars() { }

    /** Salida determinista (mismo orden siempre): los cambios en el repositorio muestran solo diferencias reales. */
    public static String aJson(SolicitudDeAterrizaje s, Cidr red) {
        StringWriter salida = new StringWriter();
        try (JsonWriter json = JsonProviders.createWriter(salida)) {
            json.writeStartObject()
                    .writeStringField("equipo", s.equipo())
                    .writeStringField("entorno", s.entorno())
                    .writeStringField("propietario", s.propietario())
                    .writeStringField("centro_de_costo", s.centroDeCosto())
                    .writeIntField("presupuesto_mensual", s.presupuestoMensual())
                    .writeStartArray("correos_de_alerta");
            for (String correo : s.correosDeAlerta()) {
                json.writeString(correo);
            }
            json.writeEndArray().writeStringField("cidr_red", red.toString()).writeEndObject().flush();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return salida.toString();
    }
}
```

## 2. El servicio de asignación (y la carrera que hay que evitar)

Dos solicitudes simultáneas leen las mismas direcciones ocupadas y **eligen el mismo bloque**. La defensa es la **clave primaria**: el que pierde la inserción vuelve a intentar con la lista actualizada. Además, la solicitud es **idempotente**: si el equipo ya tiene bloque para ese entorno, se le devuelve el mismo.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

public interface RegistroDeRedes {
    List<Cidr> ocupadas();

    Optional<Cidr> deEquipo(String equipo, String entorno);

    /** false si el bloque (o el equipo y entorno) ya estaba registrado. */
    boolean reservar(Cidr red, String equipo, String entorno);
}

public final class RegistroJdbc implements RegistroDeRedes {

    private final DataSource origen;

    public RegistroJdbc(DataSource origen) {
        this.origen = origen;
    }

    @Override
    public List<Cidr> ocupadas() {
        List<Cidr> lista = new ArrayList<>();
        try (Connection cx = origen.getConnection();
             PreparedStatement ps = cx.prepareStatement("select cidr from redes_asignadas");
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                lista.add(Cidr.parse(rs.getString(1)));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("No se pudo leer el registro de redes", e);
        }
        return lista;
    }

    @Override
    public Optional<Cidr> deEquipo(String equipo, String entorno) {
        try (Connection cx = origen.getConnection();
             PreparedStatement ps = cx.prepareStatement("select cidr from redes_asignadas where equipo = ? and entorno = ?")) {
            ps.setString(1, equipo);
            ps.setString(2, entorno);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? Optional.of(Cidr.parse(rs.getString(1))) : Optional.empty();
            }
        } catch (SQLException e) {
            throw new IllegalStateException("No se pudo leer el registro de redes", e);
        }
    }

    @Override
    public boolean reservar(Cidr red, String equipo, String entorno) {
        try (Connection cx = origen.getConnection();
             PreparedStatement ps = cx.prepareStatement(
                     "insert into redes_asignadas (cidr, equipo, entorno) values (?, ?, ?) on conflict do nothing")) {
            ps.setString(1, red.toString());
            ps.setString(2, equipo);
            ps.setString(3, entorno);
            return ps.executeUpdate() == 1;
        } catch (SQLException e) {
            throw new IllegalStateException("No se pudo reservar la red", e);
        }
    }
}

public final class ServicioDeAterrizaje {

    public record Propuesta(String cidr, String tfvarsJson, boolean nueva) { }

    private static final int INTENTOS = 5;
    private static final int SUBREDES_POR_DEFECTO = 2; // aplicación y datos (Private Endpoint)

    private final RegistroDeRedes registro;
    private final Cidr reserva;

    public ServicioDeAterrizaje(RegistroDeRedes registro, Cidr reserva) {
        this.registro = registro;
        this.reserva = reserva;
    }

    public Propuesta solicitar(SolicitudDeAterrizaje solicitud) {
        List<String> errores = solicitud.validar();
        if (!errores.isEmpty()) {
            throw new IllegalArgumentException(String.join("; ", errores));
        }
        Optional<Cidr> existente = registro.deEquipo(solicitud.equipo(), solicitud.entorno());
        if (existente.isPresent()) {
            return new Propuesta(existente.get().toString(), GeneradorDeTfvars.aJson(solicitud, existente.get()), false);
        }
        int prefijo = AsignadorDeRedes.prefijoPara(solicitud.hostsNecesarios(), SUBREDES_POR_DEFECTO);
        for (int intento = 0; intento < INTENTOS; intento++) {
            Cidr candidato = AsignadorDeRedes.siguienteLibre(reserva, prefijo, registro.ocupadas())
                    .orElseThrow(() -> new IllegalStateException("No quedan bloques libres de /" + prefijo + " en " + reserva));
            if (registro.reservar(candidato, solicitud.equipo(), solicitud.entorno())) {
                return new Propuesta(candidato.toString(), GeneradorDeTfvars.aJson(solicitud, candidato), true);
            }
            // Perdimos la carrera (otro tomó el bloque o el equipo ya quedó registrado): se reintenta con datos frescos
            Optional<Cidr> ya = registro.deEquipo(solicitud.equipo(), solicitud.entorno());
            if (ya.isPresent()) {
                return new Propuesta(ya.get().toString(), GeneradorDeTfvars.aJson(solicitud, ya.get()), false);
            }
        }
        throw new IllegalStateException("No se pudo reservar una red tras " + INTENTOS + " intentos");
    }
}
```

## 3. El verificador de la zona (reglas puras)

Cada regla dice **de dónde sale el dato** (ver la tabla); la función solo decide.

| Dato del modelo | De dónde se obtiene |
|---|---|
| `grupoInmediato` | Resource Graph, `resourcecontainers`, cadena de ancestros ([consulta 1](ejemplos/kql/kql-aterrizaje.md)) |
| `etiquetas` | Resource Graph, grupos de recursos ([consulta 2](ejemplos/kql/kql-aterrizaje.md)) |
| `tienePresupuesto` | API de presupuestos de Cost Management ([capítulo 09](../../09-gobierno/cost-management/uso-en-java.md)) |
| `peeringConectado` | Resource Graph, redes virtuales ([consulta 4](ejemplos/kql/kql-aterrizaje.md)) |
| `bloqueoEnRed`, `diagnosticoCentral` | API de ARM (bloqueos y configuración de diagnóstico) |
| `accesoPublicoAbierto` | Resource Graph ([consulta 5](ejemplos/kql/kql-aterrizaje.md)) |

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Map;
import java.util.Set;

public record EstadoDeSuscripcion(String nombre, String entorno, String grupoInmediato, Map<String, String> etiquetas,
                                  boolean tienePresupuesto, boolean diagnosticoCentral, boolean peeringConectado,
                                  boolean bloqueoEnRed, boolean accesoPublicoAbierto, boolean contributorEnSuscripcion) { }

public final class ChecklistDeAterrizaje {

    public enum Severidad { ALTA, MEDIA }

    public record Hallazgo(String regla, Severidad severidad, String suscripcion, String detalle) { }

    private static final Set<String> GRUPOS_DE_CARGA = Set.of("mg-modalima-corp", "mg-modalima-online", "mg-modalima-sandbox");
    private static final List<String> ETIQUETAS_OBLIGATORIAS = List.of("owner", "costcenter", "env", "team");

    private ChecklistDeAterrizaje() { }

    public static List<Hallazgo> revisar(EstadoDeSuscripcion s) {
        List<Hallazgo> h = new ArrayList<>();
        if (!GRUPOS_DE_CARGA.contains(s.grupoInmediato())) {
            h.add(new Hallazgo("FUERA_DE_ZONA_DE_CARGA", Severidad.ALTA, s.nombre(), "Cuelga de " + s.grupoInmediato()));
        }
        for (String etiqueta : ETIQUETAS_OBLIGATORIAS) {
            String valor = s.etiquetas().get(etiqueta);
            if (valor == null || valor.isBlank()) {
                h.add(new Hallazgo("ETIQUETA_FALTANTE", Severidad.MEDIA, s.nombre(), etiqueta));
            }
        }
        if (!s.tienePresupuesto()) {
            h.add(new Hallazgo("SIN_PRESUPUESTO", Severidad.ALTA, s.nombre(), "No hay presupuesto mensual con alertas"));
        }
        if (!s.diagnosticoCentral()) {
            h.add(new Hallazgo("SIN_REGISTRO_CENTRAL", Severidad.MEDIA, s.nombre(), "El registro de actividad no llega al espacio central"));
        }
        if (!s.peeringConectado()) {
            h.add(new Hallazgo("SIN_CONECTIVIDAD", Severidad.ALTA, s.nombre(), "El peering con el hub no está conectado"));
        }
        if ("prod".equals(s.entorno()) && !s.bloqueoEnRed()) {
            h.add(new Hallazgo("PROD_SIN_BLOQUEO", Severidad.ALTA, s.nombre(), "La red de producción no tiene bloqueo CanNotDelete"));
        }
        if (s.accesoPublicoAbierto() && !"mg-modalima-sandbox".equals(s.grupoInmediato())) {
            h.add(new Hallazgo("ACCESO_PUBLICO", Severidad.ALTA, s.nombre(), "Hay recursos de datos con acceso público fuera del sandbox"));
        }
        if (s.contributorEnSuscripcion()) {
            h.add(new Hallazgo("PERMISO_AMPLIO", Severidad.ALTA, s.nombre(), "El equipo tiene Contributor en toda la suscripción"));
        }
        return h;
    }
}
```

## 4. Spring Boot (MVC)

```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import javax.sql.DataSource;

@Configuration
class AterrizajeConfiguracion {

    @Bean
    ServicioDeAterrizaje servicioDeAterrizaje(DataSource origen) {
        return new ServicioDeAterrizaje(new RegistroJdbc(origen), Cidr.parse("10.40.0.0/16"));
    }
}

@RestController
@RequestMapping("/api/aterrizaje/solicitudes")
class AterrizajeControlador {

    private final ServicioDeAterrizaje servicio;

    AterrizajeControlador(ServicioDeAterrizaje servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    ServicioDeAterrizaje.Propuesta solicitar(@RequestBody SolicitudDeAterrizaje solicitud) {
        return servicio.solicitar(solicitud);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ProblemDetail invalida(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(IllegalStateException.class)
    ProblemDetail sinEspacio(IllegalStateException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
    }
}
```

## 5. Spring WebFlux (reactivo)
```java
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/api/aterrizaje/solicitudes")
class AterrizajeReactivoControlador {

    private final ServicioDeAterrizaje servicio;

    AterrizajeReactivoControlador(ServicioDeAterrizaje servicio) {
        this.servicio = servicio;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    Mono<ServicioDeAterrizaje.Propuesta> solicitar(@RequestBody Mono<SolicitudDeAterrizaje> solicitud) {
        return solicitud
                .flatMap(s -> Mono.fromCallable(() -> servicio.solicitar(s)).subscribeOn(Schedulers.boundedElastic()))
                .onErrorMap(IllegalArgumentException.class, e -> new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()))
                .onErrorMap(IllegalStateException.class, e -> new ResponseStatusException(HttpStatus.CONFLICT, e.getMessage()));
    }
}
```

## 6. Quarkus · imperativo
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import javax.sql.DataSource;

@ApplicationScoped
class AterrizajeProductores {

    @Produces
    @Singleton
    ServicioDeAterrizaje servicio(DataSource origen) {
        return new ServicioDeAterrizaje(new RegistroJdbc(origen), Cidr.parse("10.40.0.0/16"));
    }
}

@Path("/api/aterrizaje/solicitudes")
@Consumes(MediaType.APPLICATION_JSON)
@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)
class AterrizajeRecurso {

    @Inject
    ServicioDeAterrizaje servicio;

    @POST
    public Response solicitar(SolicitudDeAterrizaje solicitud) {
        try {
            return Response.status(Response.Status.CREATED).entity(servicio.solicitar(solicitud)).build();
        } catch (IllegalArgumentException e) {
            throw new BadRequestException(e.getMessage());
        } catch (IllegalStateException e) {
            throw new ClientErrorException(e.getMessage(), Response.Status.CONFLICT);
        }
    }
}
```

## 7. Quarkus · reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/reactivo/api/aterrizaje/solicitudes")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class AterrizajeRecursoReactivo {

    @Inject
    ServicioDeAterrizaje servicio;

    @POST
    public Uni<Response> solicitar(SolicitudDeAterrizaje solicitud) {
        return Uni.createFrom().item(() -> servicio.solicitar(solicitud))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(p -> Response.status(Response.Status.CREATED).entity(p).build())
                .onFailure(IllegalArgumentException.class).transform(e -> new BadRequestException(e.getMessage()))
                .onFailure(IllegalStateException.class).transform(e -> new ClientErrorException(e.getMessage(), Response.Status.CONFLICT));
    }
}
```

## 8. Pruebas

| Nivel | Qué se comprueba |
|---|---|
| **Cidr** | `10.40.0.0/22` contiene `10.40.1.0/24`; `10.40.0.0/22` no solapa con `10.40.4.0/22`; una dirección no alineada lanza error |
| **Prefijo** | 900 hosts + 2 subredes → `/22`; 10 hosts → `/27`; 70 000 → error |
| **Siguiente libre** | Con ocupados `[/22 en .0, /24 en .8]`, el siguiente `/22` es `10.40.4.0`; sin espacio → vacío |
| **Idempotencia** | Dos solicitudes iguales devuelven el mismo bloque y `nueva = false` la segunda |
| **Carrera** | Registro falso que pierde la primera reserva: el servicio reintenta y obtiene otro bloque |
| **Checklist** | Un estado completo no da hallazgos; uno de producción sin bloqueo da `PROD_SIN_BLOQUEO` |
| **Generador** | El JSON sale con el mismo orden de campos siempre |

## 9. Buenas prácticas de código
- **El bloque de red lo asigna un servicio, no una persona con una hoja de cálculo.**
- **La base de datos decide la carrera** (clave primaria), no un `synchronized` en una réplica.
- **Operaciones idempotentes:** repetir la solicitud no consume otro bloque.
- **El portal no tiene permisos de Azure** para cambiar nada: genera variables que revisa una persona y aplica el pipeline.
- **Reglas puras y datos aparte:** el verificador se prueba sin Azure.
- **Un hallazgo es una tarea**, no un correo: crea un ticket con responsable y fecha.
