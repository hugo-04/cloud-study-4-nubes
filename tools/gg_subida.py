import ggen
NUC = '''
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/** Máquina de estados de una subida y validación por firma. Pura. */
public final class Subidas {

    private Subidas() { }

    public enum Estado { PENDIENTE, RECIBIDA, APROBADA, RECHAZADA, EXPIRADA, PROCESADA }

    private static final Map<Estado, Set<Estado>> PERMITIDAS = Map.of(
        Estado.PENDIENTE, Set.of(Estado.RECIBIDA, Estado.EXPIRADA),
        Estado.RECIBIDA, Set.of(Estado.APROBADA, Estado.RECHAZADA),
        Estado.APROBADA, Set.of(Estado.PROCESADA));

    /** Transición condicional: si el estado actual no es el esperado, no se hace nada (evento duplicado). */
    public static Optional<Estado> transicion(Estado actual, Estado esperado, Estado nuevo) {
        if (actual != esperado || !PERMITIDAS.getOrDefault(actual, Set.of()).contains(nuevo)) {
            return Optional.empty();
        }
        return Optional.of(nuevo);
    }

    public record Veredicto(boolean aprobado, String tipo, String motivo) { }

    /** Valida por los primeros bytes (firma), nunca por la extensión. */
    public static Veredicto validar(byte[] cabecera, long bytes, long maxBytes) {
        if (bytes <= 0 || bytes > maxBytes) {
            return new Veredicto(false, null, "tamaño fuera de rango");
        }
        if (empieza(cabecera, 0xFF, 0xD8, 0xFF)) {
            return new Veredicto(true, "image/jpeg", "ok");
        }
        if (empieza(cabecera, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) {
            return new Veredicto(true, "image/png", "ok");
        }
        if (empieza(cabecera, 0x25, 0x50, 0x44, 0x46, 0x2D)) {
            return new Veredicto(true, "application/pdf", "ok");
        }
        return new Veredicto(false, null, "tipo no permitido");
    }

    private static boolean empieza(byte[] b, int... firma) {
        if (b.length < firma.length) {
            return false;
        }
        for (int i = 0; i < firma.length; i++) {
            if ((b[i] & 0xFF) != firma[i]) {
                return false;
            }
        }
        return true;
    }

    public static String destino(String objetoEnCuarentena) {
        if (!objetoEnCuarentena.matches("cuarentena/S-[0-9]{1,20}\\\\.[a-z]{3,4}")) {
            throw new IllegalArgumentException("nombre fuera de la convención");
        }
        return "aprobados/" + objetoEnCuarentena.substring("cuarentena/".length());
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.ByteBuffer;
import java.util.Arrays;

/** Adaptador: lee la cabecera por rango y mueve/borra con precondiciones de generación. */
public class SubidasGcp implements AutoCloseable {

    public record Info(long bytes, long generacion) { }

    private final Storage storage;
    private final String bucket;

    public SubidasGcp(GoogleCredentials cred, String proyecto, String bucket) {
        this.storage = StorageOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.bucket = bucket;
    }

    public Info info(String objeto) {
        var b = storage.get(BlobId.of(bucket, objeto));
        if (b == null) {
            throw new IllegalArgumentException("no existe " + objeto);
        }
        return new Info(b.getSize(), b.getGeneration());
    }

    public byte[] cabecera(String objeto, int n) {
        try (var r = storage.reader(BlobId.of(bucket, objeto))) {
            r.limit(n);                                   // solo los primeros n bytes
            var buf = ByteBuffer.allocate(n);
            int leidos = r.read(buf);
            return Arrays.copyOf(buf.array(), Math.max(leidos, 0));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Copia la generación validada solo si el destino no existe y luego borra esa misma generación. */
    public void mover(String origen, String destino, long generacion) {
        storage.copy(Storage.CopyRequest.newBuilder()
            .setSource(BlobId.of(bucket, origen, generacion))
            .setSourceOptions(Storage.BlobSourceOption.generationMatch(generacion))
            .setTarget(BlobInfo.newBuilder(bucket, destino).build(), Storage.BlobTargetOption.doesNotExist())
            .build()).getResult();
        borrar(origen, generacion);
    }

    public void borrar(String objeto, long generacion) {
        storage.delete(BlobId.of(bucket, objeto), Storage.BlobSourceOption.generationMatch(generacion));
    }

    @Override
    public void close() {
        try {
            storage.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
'''
SERV = '''
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class ServicioDeSubidas {

    public record Resultado(String id, String estado, String detalle) { }

    private final SubidasGcp objetos;
    // Demo: estados en memoria; en la app real, Firestore o la base con actualización condicional.
    private final Map<String, Subidas.Estado> estados = new ConcurrentHashMap<>();

    public ServicioDeSubidas(SubidasGcp objetos) {
        this.objetos = objetos;
    }

    /** Lo invoca el consumidor del evento OBJECT_FINALIZE (función o endpoint). */
    public Resultado alLlegar(String objeto) {
        String id = objeto.substring(objeto.indexOf('/') + 1, objeto.lastIndexOf('.'));
        estados.putIfAbsent(id, Subidas.Estado.PENDIENTE);
        if (Subidas.transicion(estados.get(id), Subidas.Estado.PENDIENTE, Subidas.Estado.RECIBIDA).isEmpty()) {
            return new Resultado(id, estados.get(id).name(), "evento duplicado: ignorado");
        }
        estados.put(id, Subidas.Estado.RECIBIDA);
        var info = objetos.info(objeto);
        var v = Subidas.validar(objetos.cabecera(objeto, 16), info.bytes(), 25L * 1024 * 1024);
        if (!v.aprobado()) {
            objetos.borrar(objeto, info.generacion());
            estados.put(id, Subidas.Estado.RECHAZADA);
            return new Resultado(id, "RECHAZADA", v.motivo());
        }
        objetos.mover(objeto, Subidas.destino(objeto), info.generacion());
        estados.put(id, Subidas.Estado.APROBADA);
        return new Resultado(id, "APROBADA", v.tipo()); // aquí se envía el ticket a la cola
    }
}
'''
ggen.gcp('gcp/11-casos-integrados/subida-claim-check', 'Caso integrado · Subida con claim check',
  'El validador de la cuarentena: una **máquina de estados con transiciones condicionales** (un evento duplicado no hace nada), **validación por firma** de los primeros bytes (JPEG, PNG, PDF) y tamaño, y un adaptador que lee solo 16 bytes con `ReadChannel.limit`, **copia la generación validada** a `aprobados/` con `generationMatch` + `doesNotExist` y borra el original con la misma generación (o borra el rechazado).',
  [('subidas.bucket', 'modalima-subidas')],
  [('Estados y validación (lógica pura)', NUC, True), ('Adaptador de Cloud Storage', SDK, True), ('Servicio', SERV, True)],
  'Subidas', '/tienda/subidas', 'ServicioDeSubidas', 'SubidasGcp', [],
  'return new SubidasGcp(cred, proyecto, bucket);',
  [dict(n='alLlegar', v='POST', p='/llegada', args=[('String', 'objeto', 'q')], ret='ServicioDeSubidas.Resultado', call='s.alLlegar(objeto)')],
  [('Validar y mover', '`roles/storage.objectUser` en el bucket para `run-validador`'),
   ('Publicar el ticket', '`roles/pubsub.publisher` en `subidas-aprobadas`')],
  ['No descargues el archivo completo para validar el tipo.',
   'No muevas sin precondición de generación.',
   'No apruebes por extensión ni por `Content-Type`.',
   'No registres URLs firmadas.'])
