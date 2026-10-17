# Azure · Casos integrados · Subida con Claim Check · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3** (`azure-storage-blob`, `azure-storage-queue`, `azure-identity`, `azure-json`). Verifica las vigentes.

Este caso **no repite** el código de los capítulos de almacenamiento: reutiliza el emisor de SAS ([SAS tokens](../../06-storage/sas-tokens/uso-en-java.md)), el ticket de Claim Check ([Claim Check](../../06-storage/claim-check/uso-en-java.md)) y la lectura de eventos de blob ([eventos de blob](../../06-storage/eventos-blob/uso-en-java.md)). Aquí está lo que los une: **la máquina de estados de cada subida**, la validación y el conciliador.

## El diseño en una página

```
 App ──1 POST /api/subidas──► API ──► fila PENDIENTE + SAS (10 min, solo escritura en UN blob de cuarentena)
  │                                                    │
  └──2 PUT directo a Blob ─────────────────────────────┘         (los bytes NO pasan por la API)
                     │ BlobCreated
                     ▼ Event Grid ──► cola eventos-cuarentena
                                         │  3 Validador: PENDIENTE→SUBIDA, revisa tamaño, tipo real (bytes mágicos), hash
                                         ├─ mal ─► RECHAZADA + borra de cuarentena
                                         └─ bien ─► copia a «validados», SUBIDA→VALIDADA + evento en la bandeja de salida
                                                          │
                              Service Bus (ticket con la referencia) ──► procesadores ──► PROCESADA
 Conciliador (cada 5 min): PENDIENTE vieja → EXPIRADA · SUBIDA atascada → revalidar
```

**Estados y transiciones permitidas** (cualquier otra se ignora; así los eventos duplicados no hacen daño):

| Desde | Hacia | Quién | Cuándo |
|---|---|---|---|
| `PENDIENTE` | `SUBIDA` | Validador | Llega el evento de blob creado |
| `PENDIENTE` | `EXPIRADA` | Conciliador | Pasó el plazo y nunca se subió nada |
| `SUBIDA` | `VALIDADA` | Validador | Tamaño, tipo real y hash correctos |
| `SUBIDA` | `RECHAZADA` | Validador | Alguna regla falló (se guarda el motivo) |
| `VALIDADA` | `PROCESADA` | Procesador de negocio | Terminó de usarse el archivo |

Permisos (plano de datos): la **API** necesita *Storage Blob Delegator* (pedir la clave de delegación) y datos sobre el contenedor de cuarentena; el **validador** lee/borra en cuarentena, escribe en `validados` y procesa la cola; los **procesadores** solo leen `validados`. El Terraform exacto está en [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-blob</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-queue</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-json</artifactId></dependency>
```

## 1. Estados, reglas de archivo y repositorio (comunes a ambos stacks)

```java
// (clase reutilizada en los bloques siguientes, ambos)
import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

public enum EstadoSubida {
    PENDIENTE, SUBIDA, VALIDADA, RECHAZADA, PROCESADA, EXPIRADA;

    private static final Map<EstadoSubida, Set<EstadoSubida>> PERMITIDAS = new EnumMap<>(EstadoSubida.class);

    static {
        PERMITIDAS.put(PENDIENTE, EnumSet.of(SUBIDA, EXPIRADA));
        PERMITIDAS.put(SUBIDA, EnumSet.of(VALIDADA, RECHAZADA));
        PERMITIDAS.put(VALIDADA, EnumSet.of(PROCESADA));
        PERMITIDAS.put(RECHAZADA, EnumSet.noneOf(EstadoSubida.class));
        PERMITIDAS.put(PROCESADA, EnumSet.noneOf(EstadoSubida.class));
        PERMITIDAS.put(EXPIRADA, EnumSet.noneOf(EstadoSubida.class));
    }

    public boolean puedePasarA(EstadoSubida destino) {
        return PERMITIDAS.get(this).contains(destino);
    }

    public boolean esFinal() {
        return PERMITIDAS.get(this).isEmpty();
    }
}

public record Subida(UUID id, String propietario, String tipoDeclarado, long tamanoMax, EstadoSubida estado, String rutaCuarentena) { }

public record PoliticaDeArchivos(Set<String> tiposPermitidos, long tamanoMaximo) {

    public static PoliticaDeArchivos comprobantes() {
        return new PoliticaDeArchivos(Set.of("application/pdf", "image/png", "image/jpeg"), 50L * 1024 * 1024);
    }
}

/** Reglas puras: no tocan la red, se prueban con arreglos de bytes. */
public final class ReglasDeArchivo {

    private ReglasDeArchivo() { }

    /** El tipo se deduce de los primeros bytes, NO de lo que dice el cliente. */
    public static Optional<String> tipoReal(byte[] cabecera) {
        if (cabecera.length >= 5 && cabecera[0] == '%' && cabecera[1] == 'P' && cabecera[2] == 'D' && cabecera[3] == 'F' && cabecera[4] == '-') {
            return Optional.of("application/pdf");
        }
        if (cabecera.length >= 4 && (cabecera[0] & 0xFF) == 0x89 && cabecera[1] == 'P' && cabecera[2] == 'N' && cabecera[3] == 'G') {
            return Optional.of("image/png");
        }
        if (cabecera.length >= 3 && (cabecera[0] & 0xFF) == 0xFF && (cabecera[1] & 0xFF) == 0xD8 && (cabecera[2] & 0xFF) == 0xFF) {
            return Optional.of("image/jpeg");
        }
        return Optional.empty();
    }

    /** Devuelve el motivo del rechazo, o vacío si el archivo es aceptable. */
    public static Optional<String> motivoDeRechazo(String tipoDeclarado, long tamano, byte[] cabecera, PoliticaDeArchivos politica) {
        if (tamano <= 0) {
            return Optional.of("vacio");
        }
        if (tamano > politica.tamanoMaximo()) {
            return Optional.of("demasiado_grande");
        }
        Optional<String> real = tipoReal(cabecera);
        if (real.isEmpty() || !politica.tiposPermitidos().contains(real.get())) {
            return Optional.of("tipo_no_permitido");
        }
        if (!real.get().equals(tipoDeclarado)) {
            return Optional.of("tipo_no_coincide");
        }
        return Optional.empty();
    }
}

public final class Transaccion {

    @FunctionalInterface
    public interface Trabajo<T> {
        T ejecutar(Connection cx) throws SQLException;
    }

    private final DataSource origen;

    public Transaccion(DataSource origen) {
        this.origen = origen;
    }

    public <T> T ejecutar(Trabajo<T> trabajo) {
        try (Connection cx = origen.getConnection()) {
            boolean autoCommit = cx.getAutoCommit();
            cx.setAutoCommit(false);
            try {
                T resultado = trabajo.ejecutar(cx);
                cx.commit();
                return resultado;
            } catch (SQLException | RuntimeException e) {
                cx.rollback();
                throw e;
            } finally {
                cx.setAutoCommit(autoCommit);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Error de base de datos", e);
        }
    }
}

public final class RepositorioDeSubidas {

    public void crear(Connection cx, Subida s) throws SQLException {
        try (PreparedStatement ps = cx.prepareStatement(
                "insert into subidas (id, propietario, tipo_declarado, tamano_max, ruta_cuarentena) values (?, ?, ?, ?, ?)")) {
            ps.setObject(1, s.id());
            ps.setString(2, s.propietario());
            ps.setString(3, s.tipoDeclarado());
            ps.setLong(4, s.tamanoMax());
            ps.setString(5, s.rutaCuarentena());
            ps.executeUpdate();
        }
    }

    public Optional<Subida> buscar(Connection cx, UUID id) throws SQLException {
        try (PreparedStatement ps = cx.prepareStatement(
                "select id, propietario, tipo_declarado, tamano_max, estado, ruta_cuarentena from subidas where id = ?")) {
            ps.setObject(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return Optional.empty();
                }
                return Optional.of(new Subida(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), rs.getLong(4),
                        EstadoSubida.valueOf(rs.getString(5)), rs.getString(6)));
            }
        }
    }

    /**
     * Cambia el estado SOLO si sigue siendo el esperado (control optimista). Devuelve false si otro proceso
     * ya la movió: así dos eventos duplicados no avanzan el estado dos veces.
     */
    public boolean transicionar(Connection cx, UUID id, EstadoSubida desde, EstadoSubida hacia, String motivo) throws SQLException {
        if (!desde.puedePasarA(hacia)) {
            throw new IllegalArgumentException("Transición no permitida: " + desde + " -> " + hacia);
        }
        try (PreparedStatement ps = cx.prepareStatement(
                "update subidas set estado = ?, motivo = ?, actualizada_en = now() where id = ? and estado = ?")) {
            ps.setString(1, hacia.name());
            ps.setString(2, motivo);
            ps.setObject(3, id);
            ps.setString(4, desde.name());
            return ps.executeUpdate() == 1;
        }
    }

    public boolean marcarValidada(Connection cx, UUID id, String rutaFinal, String sha256) throws SQLException {
        try (PreparedStatement ps = cx.prepareStatement(
                "update subidas set estado = 'VALIDADA', ruta_final = ?, sha256 = ?, actualizada_en = now() where id = ? and estado = 'SUBIDA'")) {
            ps.setString(1, rutaFinal);
            ps.setString(2, sha256);
            ps.setObject(3, id);
            return ps.executeUpdate() == 1;
        }
    }

    public int expirarPendientes(Connection cx, Duration antiguedad) throws SQLException {
        try (PreparedStatement ps = cx.prepareStatement(
                "update subidas set estado = 'EXPIRADA', actualizada_en = now() where estado = 'PENDIENTE' and actualizada_en < ?")) {
            ps.setTimestamp(1, Timestamp.from(Instant.now().minus(antiguedad)));
            return ps.executeUpdate();
        }
    }

    public List<UUID> atascadas(Connection cx, EstadoSubida estado, Duration antiguedad, int maximo) throws SQLException {
        List<UUID> ids = new ArrayList<>();
        try (PreparedStatement ps = cx.prepareStatement(
                "select id from subidas where estado = ? and actualizada_en < ? order by actualizada_en limit ?")) {
            ps.setString(1, estado.name());
            ps.setTimestamp(2, Timestamp.from(Instant.now().minus(antiguedad)));
            ps.setInt(3, maximo);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    ids.add(rs.getObject(1, UUID.class));
                }
            }
        }
        return ids;
    }
}
```

## 2. Los casos de uso: iniciar, validar, conciliar

`AlmacenDeArchivos`, `EmisorDeSas` y `Avisador` son **puertas** (interfaces): la lógica no sabe si detrás hay Azure, una carpeta local o un simulado en las pruebas.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;

public interface AlmacenDeArchivos {
    long tamano(String rutaCuarentena);

    byte[] cabecera(String rutaCuarentena, int bytes);

    String sha256(String rutaCuarentena);

    /** Copia a «validados» y devuelve la ruta final. */
    String copiarAValidados(String rutaCuarentena, String nombreFinal);

    void borrarDeCuarentena(String rutaCuarentena);
}

public interface EmisorDeSas {
    record Firmada(String url, OffsetDateTime vence) { }

    /** SAS de delegación de usuario: un solo blob, solo crear/escribir, vigencia corta. */
    Firmada paraSubir(String rutaCuarentena, Duration vigencia);
}

/** Escribe el aviso en la bandeja de salida, en la MISMA transacción (ver el caso «tienda online»). */
public interface Avisador {
    void guardar(Connection cx, String tipo, String clave, String carga) throws SQLException;
}

public record Autorizacion(UUID id, String url, Map<String, String> cabeceras, OffsetDateTime vence) { }

public final class IniciarSubida {

    private final Transaccion tx;
    private final RepositorioDeSubidas repositorio;
    private final EmisorDeSas emisor;
    private final PoliticaDeArchivos politica;

    public IniciarSubida(Transaccion tx, RepositorioDeSubidas repositorio, EmisorDeSas emisor, PoliticaDeArchivos politica) {
        this.tx = tx;
        this.repositorio = repositorio;
        this.emisor = emisor;
        this.politica = politica;
    }

    public Autorizacion iniciar(String propietario, String tipo, long tamano) {
        if (propietario == null || propietario.isBlank()) {
            throw new IllegalArgumentException("Propietario requerido");
        }
        if (!politica.tiposPermitidos().contains(tipo)) {
            throw new IllegalArgumentException("Tipo de archivo no permitido");
        }
        if (tamano <= 0 || tamano > politica.tamanoMaximo()) {
            throw new IllegalArgumentException("Tamaño fuera de rango");
        }
        UUID id = UUID.randomUUID();
        OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
        String ruta = "%d/%02d/%s".formatted(ahora.getYear(), ahora.getMonthValue(), id);
        // Primero se registra, después se firma: no puede existir una subida que el sistema no conozca.
        tx.ejecutar(cx -> {
            repositorio.crear(cx, new Subida(id, propietario, tipo, politica.tamanoMaximo(), EstadoSubida.PENDIENTE, ruta));
            return null;
        });
        EmisorDeSas.Firmada firmada = emisor.paraSubir(ruta, Duration.ofMinutes(10));
        Map<String, String> cabeceras = new LinkedHashMap<>();
        cabeceras.put("x-ms-blob-type", "BlockBlob");
        cabeceras.put("Content-Type", tipo);
        return new Autorizacion(id, firmada.url(), cabeceras, firmada.vence());
    }
}

public final class ValidadorDeSubida {

    private static final System.Logger LOG = System.getLogger("subidas.validador");

    private final Transaccion tx;
    private final RepositorioDeSubidas repositorio;
    private final AlmacenDeArchivos almacen;
    private final Avisador avisador;
    private final PoliticaDeArchivos politica;

    public ValidadorDeSubida(Transaccion tx, RepositorioDeSubidas repositorio, AlmacenDeArchivos almacen,
                             Avisador avisador, PoliticaDeArchivos politica) {
        this.tx = tx;
        this.repositorio = repositorio;
        this.almacen = almacen;
        this.avisador = avisador;
        this.politica = politica;
    }

    /** true = el mensaje de la cola se puede borrar (procesado o duplicado). Cualquier excepción = se reintenta. */
    public boolean alLlegarElArchivo(UUID id) {
        Subida subida = tx.ejecutar(cx -> repositorio.buscar(cx, id)).orElse(null);
        if (subida == null) {
            LOG.log(System.Logger.Level.WARNING, "subida.desconocida id={0}", id); // blob huérfano: la limpieza lo borrará
            return true;
        }
        if (subida.estado() == EstadoSubida.PENDIENTE) {
            boolean movida = tx.ejecutar(cx -> repositorio.transicionar(cx, id, EstadoSubida.PENDIENTE, EstadoSubida.SUBIDA, null));
            LOG.log(System.Logger.Level.INFO, "subida.transicion subidaId={0} hacia=SUBIDA ok={1}", id, movida);
        } else if (subida.estado() != EstadoSubida.SUBIDA) {
            return true; // evento duplicado o tardío: ya se atendió
        }
        validar(subida);
        return true;
    }

    /** Se puede llamar varias veces: cada paso comprueba el estado actual. */
    public void validar(Subida subida) {
        long tamano = almacen.tamano(subida.rutaCuarentena());
        byte[] cabecera = tamano > 0 ? almacen.cabecera(subida.rutaCuarentena(), 16) : new byte[0];
        var motivo = ReglasDeArchivo.motivoDeRechazo(subida.tipoDeclarado(), tamano, cabecera, politica);
        if (motivo.isPresent()) {
            tx.ejecutar(cx -> repositorio.transicionar(cx, subida.id(), EstadoSubida.SUBIDA, EstadoSubida.RECHAZADA, motivo.get()));
            almacen.borrarDeCuarentena(subida.rutaCuarentena());
            LOG.log(System.Logger.Level.INFO, "subida.rechazada subidaId={0} motivo={1}", subida.id(), motivo.get());
            return;
        }
        String hash = almacen.sha256(subida.rutaCuarentena());
        String rutaFinal = almacen.copiarAValidados(subida.rutaCuarentena(), subida.id().toString());
        tx.ejecutar(cx -> {
            if (repositorio.marcarValidada(cx, subida.id(), rutaFinal, hash)) {
                avisador.guardar(cx, "archivo.validado", subida.id().toString(),
                        "{\"tipo\":\"archivo.validado\",\"version\":1,\"subidaId\":\"" + subida.id() + "\",\"ruta\":\"" + rutaFinal
                                + "\",\"tamano\":" + tamano + ",\"sha256\":\"" + hash + "\",\"contentType\":\"" + subida.tipoDeclarado() + "\"}");
            }
            return null;
        });
        almacen.borrarDeCuarentena(subida.rutaCuarentena());
        LOG.log(System.Logger.Level.INFO, "subida.transicion subidaId={0} hacia=VALIDADA", subida.id());
    }
}

public final class ConciliadorDeSubidas {

    private final Transaccion tx;
    private final RepositorioDeSubidas repositorio;
    private final ValidadorDeSubida validador;

    public ConciliadorDeSubidas(Transaccion tx, RepositorioDeSubidas repositorio, ValidadorDeSubida validador) {
        this.tx = tx;
        this.repositorio = repositorio;
        this.validador = validador;
    }

    /** Pendientes que nunca se subieron -> EXPIRADA. Atascadas en SUBIDA (el validador murió a medias) -> se revalidan. */
    public int conciliar(Duration plazoPendiente, Duration plazoAtascada) {
        int expiradas = tx.ejecutar(cx -> repositorio.expirarPendientes(cx, plazoPendiente));
        List<UUID> atascadas = tx.ejecutar(cx -> repositorio.atascadas(cx, EstadoSubida.SUBIDA, plazoAtascada, 50));
        for (UUID id : atascadas) {
            tx.ejecutar(cx -> repositorio.buscar(cx, id)).ifPresent(validador::validar);
        }
        return expiradas + atascadas.size();
    }
}
```

## 3. El adaptador real de Azure (Blob y cola)

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.util.Context;
import com.azure.json.JsonProviders;
import com.azure.json.JsonReader;
import com.azure.json.JsonToken;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobRange;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

public final class AlmacenBlob implements AlmacenDeArchivos {

    private final BlobContainerClient cuarentena;
    private final BlobContainerClient validados;

    public AlmacenBlob(BlobContainerClient cuarentena, BlobContainerClient validados) {
        this.cuarentena = cuarentena;
        this.validados = validados;
    }

    @Override
    public long tamano(String ruta) {
        return cuarentena.getBlobClient(ruta).getProperties().getBlobSize();
    }

    @Override
    public byte[] cabecera(String ruta, int bytes) {
        ByteArrayOutputStream salida = new ByteArrayOutputStream();
        cuarentena.getBlobClient(ruta).downloadStreamWithResponse(salida, new BlobRange(0, (long) bytes), null, null, false, null, Context.NONE);
        return salida.toByteArray();
    }

    @Override
    public String sha256(String ruta) {
        try (InputStream entrada = cuarentena.getBlobClient(ruta).openInputStream()) {
            MessageDigest resumen = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[64 * 1024];
            int leidos;
            while ((leidos = entrada.read(buffer)) != -1) {
                resumen.update(buffer, 0, leidos);
            }
            return HexFormat.of().formatHex(resumen.digest());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    @Override
    public String copiarAValidados(String ruta, String nombreFinal) {
        // Copia dentro de la misma cuenta, autorizada con la identidad del validador (verifica los requisitos en la doc oficial)
        validados.getBlobClient(nombreFinal)
                .beginCopy(cuarentena.getBlobClient(ruta).getBlobUrl(), Duration.ofSeconds(1))
                .waitForCompletion();
        return nombreFinal;
    }

    @Override
    public void borrarDeCuarentena(String ruta) {
        cuarentena.getBlobClient(ruta).deleteIfExists();
    }
}

/** Saca el id de la subida del evento de Event Grid (el nombre del blob termina en el UUID). */
public final class EventoDeBlob {

    private EventoDeBlob() { }

    public static Optional<UUID> subidaDe(String cuerpo) {
        try (JsonReader lector = JsonProviders.createReader(cuerpo)) {
            String subject = lector.readObject(r -> {
                String valor = null;
                while (r.nextToken() != JsonToken.END_OBJECT) {
                    String campo = r.getFieldName();
                    r.nextToken();
                    if ("subject".equals(campo)) {
                        valor = r.getString();
                    } else {
                        r.skipChildren();
                    }
                }
                return valor;
            });
            if (subject == null) {
                return Optional.empty();
            }
            String ultimo = subject.substring(subject.lastIndexOf('/') + 1);
            return Optional.of(UUID.fromString(ultimo));
        } catch (IOException | IllegalArgumentException e) {
            return Optional.empty();
        }
    }
}
```

## 4. Spring Boot (MVC): configuración, API, consumidor de la cola y conciliador

La firma de la SAS de delegación la hace `EmisorDeSas`; su implementación completa (clave de delegación en caché, permisos `create`+`write`, un solo blob) está en el capítulo de [SAS tokens](../../06-storage/sas-tokens/uso-en-java.md).

```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.azure.storage.queue.models.QueueMessageItem;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.time.Duration;

@Configuration
@EnableScheduling
class SubidasConfiguracion {

    @Bean
    Transaccion transaccion(DataSource origen) {
        return new Transaccion(origen);
    }

    @Bean
    PoliticaDeArchivos politica() {
        return PoliticaDeArchivos.comprobantes();
    }

    @Bean
    AlmacenDeArchivos almacen(@Value("${subidas.cuenta}") String cuenta) {
        var servicio = new BlobServiceClientBuilder()
                .endpoint("https://" + cuenta + ".blob.core.windows.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
        BlobContainerClient cuarentena = servicio.getBlobContainerClient("cuarentena");
        BlobContainerClient validados = servicio.getBlobContainerClient("validados");
        return new AlmacenBlob(cuarentena, validados);
    }

    @Bean
    QueueClient cola(@Value("${subidas.cuenta}") String cuenta) {
        return new QueueClientBuilder()
                .endpoint("https://" + cuenta + ".queue.core.windows.net")
                .queueName("eventos-cuarentena")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }

    @Bean
    ValidadorDeSubida validador(Transaccion tx, AlmacenDeArchivos almacen, Avisador avisador, PoliticaDeArchivos politica) {
        return new ValidadorDeSubida(tx, new RepositorioDeSubidas(), almacen, avisador, politica);
    }

    @Bean
    ConciliadorDeSubidas conciliador(Transaccion tx, ValidadorDeSubida validador) {
        return new ConciliadorDeSubidas(tx, new RepositorioDeSubidas(), validador);
    }

    @Bean
    IniciarSubida iniciarSubida(Transaccion tx, EmisorDeSas emisor, PoliticaDeArchivos politica) {
        return new IniciarSubida(tx, new RepositorioDeSubidas(), emisor, politica);
    }
}

@Component
class ConsumidorDeEventos {

    private static final System.Logger LOG = System.getLogger("subidas.cola");

    private final QueueClient cola;
    private final ValidadorDeSubida validador;
    private final ConciliadorDeSubidas conciliador;

    ConsumidorDeEventos(QueueClient cola, ValidadorDeSubida validador, ConciliadorDeSubidas conciliador) {
        this.cola = cola;
        this.validador = validador;
        this.conciliador = conciliador;
    }

    @Scheduled(fixedDelayString = "${subidas.intervalo-ms:2000}")
    void leerCola() {
        // El mensaje queda invisible 5 minutos mientras se valida; si el proceso muere, reaparece solo
        for (QueueMessageItem mensaje : cola.receiveMessages(10, Duration.ofMinutes(5), Duration.ofSeconds(5), null)) {
            try {
                boolean listo = EventoDeBlob.subidaDe(mensaje.getBody().toString())
                        .map(validador::alLlegarElArchivo)
                        .orElse(true); // evento que no es de una subida nuestra: se descarta
                if (listo) {
                    cola.deleteMessage(mensaje.getMessageId(), mensaje.getPopReceipt());
                }
            } catch (RuntimeException e) {
                LOG.log(System.Logger.Level.WARNING, "No se pudo validar (se reintentará): {0}", e.getClass().getSimpleName());
            }
        }
    }

    @Scheduled(fixedDelay = 300_000)
    void conciliar() {
        int tocadas = conciliador.conciliar(Duration.ofMinutes(30), Duration.ofMinutes(10));
        if (tocadas > 0) {
            LOG.log(System.Logger.Level.INFO, "subidas.conciliadas cantidad={0}", tocadas);
        }
    }
}
```
```java
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/subidas")
class SubidasControlador {

    record Solicitud(String contentType, long tamano) { }

    private final IniciarSubida iniciar;

    SubidasControlador(IniciarSubida iniciar) {
        this.iniciar = iniciar;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    Autorizacion crear(@AuthenticationPrincipal Jwt token, @RequestBody Solicitud solicitud) {
        return iniciar.iniciar(token.getSubject(), solicitud.contentType(), solicitud.tamano());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ProblemDetail invalido(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }
}
```

## 5. Spring WebFlux (reactivo)
La parte reactiva es solo el borde HTTP; la base JDBC y el SDK de firma son bloqueantes y van en `boundedElastic`.

```java
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/api/subidas")
class SubidasReactivoControlador {

    record Solicitud(String contentType, long tamano) { }

    private final IniciarSubida iniciar;

    SubidasReactivoControlador(IniciarSubida iniciar) {
        this.iniciar = iniciar;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    Mono<Autorizacion> crear(@AuthenticationPrincipal Jwt token, @RequestBody Mono<Solicitud> solicitud) {
        return solicitud
                .flatMap(s -> Mono.fromCallable(() -> iniciar.iniciar(token.getSubject(), s.contentType(), s.tamano()))
                        .subscribeOn(Schedulers.boundedElastic()))
                .onErrorMap(IllegalArgumentException.class, e -> new ResponseStatusException(HttpStatus.BAD_REQUEST, e.getMessage()));
    }
}
```

## 6. Quarkus · imperativo
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.azure.storage.queue.models.QueueMessageItem;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import javax.sql.DataSource;
import java.time.Duration;

@ApplicationScoped
class SubidasProductores {

    @ConfigProperty(name = "subidas.cuenta")
    String cuenta;

    @Produces
    @Singleton
    Transaccion transaccion(DataSource origen) {
        return new Transaccion(origen);
    }

    @Produces
    @Singleton
    PoliticaDeArchivos politica() {
        return PoliticaDeArchivos.comprobantes();
    }

    @Produces
    @Singleton
    AlmacenDeArchivos almacen() {
        var servicio = new BlobServiceClientBuilder()
                .endpoint("https://" + cuenta + ".blob.core.windows.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
        return new AlmacenBlob(servicio.getBlobContainerClient("cuarentena"), servicio.getBlobContainerClient("validados"));
    }

    @Produces
    @Singleton
    QueueClient cola() {
        return new QueueClientBuilder()
                .endpoint("https://" + cuenta + ".queue.core.windows.net")
                .queueName("eventos-cuarentena")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }

    @Produces
    @Singleton
    ValidadorDeSubida validador(Transaccion tx, AlmacenDeArchivos almacen, Avisador avisador, PoliticaDeArchivos politica) {
        return new ValidadorDeSubida(tx, new RepositorioDeSubidas(), almacen, avisador, politica);
    }

    @Produces
    @Singleton
    ConciliadorDeSubidas conciliador(Transaccion tx, ValidadorDeSubida validador) {
        return new ConciliadorDeSubidas(tx, new RepositorioDeSubidas(), validador);
    }

    @Produces
    @Singleton
    IniciarSubida iniciarSubida(Transaccion tx, EmisorDeSas emisor, PoliticaDeArchivos politica) {
        return new IniciarSubida(tx, new RepositorioDeSubidas(), emisor, politica);
    }
}

@ApplicationScoped
class ConsumidorDeEventosQuarkus {

    private static final System.Logger LOG = System.getLogger("subidas.cola");

    @Inject
    QueueClient cola;

    @Inject
    ValidadorDeSubida validador;

    @Inject
    ConciliadorDeSubidas conciliador;

    @Scheduled(every = "2s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void leerCola() {
        for (QueueMessageItem mensaje : cola.receiveMessages(10, Duration.ofMinutes(5), Duration.ofSeconds(5), null)) {
            try {
                boolean listo = EventoDeBlob.subidaDe(mensaje.getBody().toString())
                        .map(validador::alLlegarElArchivo)
                        .orElse(true);
                if (listo) {
                    cola.deleteMessage(mensaje.getMessageId(), mensaje.getPopReceipt());
                }
            } catch (RuntimeException e) {
                LOG.log(System.Logger.Level.WARNING, "No se pudo validar (se reintentará): {0}", e.getClass().getSimpleName());
            }
        }
    }

    @Scheduled(every = "5m", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void conciliar() {
        conciliador.conciliar(Duration.ofMinutes(30), Duration.ofMinutes(10));
    }
}
```
```java
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/api/subidas")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class SubidasRecurso {

    public record Solicitud(String contentType, long tamano) { }

    @Inject
    IniciarSubida iniciar;

    @Inject
    SecurityIdentity identidad;

    @POST
    public Response crear(Solicitud solicitud) {
        try {
            Autorizacion autorizacion = iniciar.iniciar(identidad.getPrincipal().getName(), solicitud.contentType(), solicitud.tamano());
            return Response.status(Response.Status.CREATED).entity(autorizacion).build();
        } catch (IllegalArgumentException e) {
            throw new BadRequestException(e.getMessage());
        }
    }
}
```

## 7. Quarkus · reactivo (Mutiny)
```java
import io.quarkus.security.identity.SecurityIdentity;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/reactivo/api/subidas")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
class SubidasRecursoReactivo {

    public record Solicitud(String contentType, long tamano) { }

    @Inject
    IniciarSubida iniciar;

    @Inject
    SecurityIdentity identidad;

    @POST
    public Uni<Response> crear(Solicitud solicitud) {
        String propietario = identidad.getPrincipal().getName();
        return Uni.createFrom().item(() -> iniciar.iniciar(propietario, solicitud.contentType(), solicitud.tamano()))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(a -> Response.status(Response.Status.CREATED).entity(a).build())
                .onFailure(IllegalArgumentException.class).transform(e -> new BadRequestException(e.getMessage()));
    }
}
```

## 8. Pruebas

| Nivel | Qué se comprueba | Cómo |
|---|---|---|
| **Reglas de archivo** | PDF renombrado a `.png`, archivo vacío, tamaño excedido, tipo no permitido | Arreglos de bytes; sin red |
| **Máquina de estados** | Solo se permiten las transiciones de la tabla; un evento duplicado no avanza | Base en memoria + `AlmacenDeArchivos` falso |
| **Validador** | Rechazado: borra de cuarentena y guarda el motivo. Aceptado: copia, VALIDADA y aviso en la misma transacción | Falsos que registran las llamadas |
| **Conciliador** | Pendiente vieja → EXPIRADA; SUBIDA atascada → se revalida | Reloj controlado (fechas en la base de prueba) |
| **Integración** | Subida real con SAS contra una cuenta de laboratorio; CORS del navegador | Script con `curl` + cuenta de pruebas |

## 9. Buenas prácticas de código
- **Registrar antes de firmar:** la fila `PENDIENTE` existe antes de entregar la SAS.
- **El tipo se decide por los bytes**, no por el nombre ni por el `Content-Type` que declara el cliente.
- **Transiciones con control optimista** (`where estado = ?`): los eventos duplicados no hacen daño.
- **Todo paso es repetible:** el validador puede ejecutarse dos veces sobre la misma subida.
- **Cuarentena sin consumidores:** nadie lee de `cuarentena` salvo el validador; los demás leen de `validados`.
- **El aviso a otros servicios va por la bandeja de salida**, igual que en la tienda online.
- **Un registro nunca contiene la URL con SAS**; solo rutas.
- **Archivos grandes (cientos de MB):** sube por bloques con el SDK desde el cliente o con varias solicitudes de bloque; el límite de un `PUT` único depende de la versión de la API (verifica en la doc oficial).
