import ggen
CON = '''
import java.util.List;
import java.util.random.RandomGenerator;

/**
 * Contador distribuido: cuántos fragmentos hacen falta, a cuál escribir y cómo leer. Puro.
 */
public final class ContadorDistribuido {

    public record Plan(int fragmentos, double escriturasPorFragmento) { }

    private ContadorDistribuido() {
    }

    /** Un documento sostiene ~1 escritura/s (verifica): fragmentos = techo(tasa / capacidad) con margen. */
    public static Plan planificar(double escriturasPorSegundo, double capacidadPorDocumento, double margen) {
        int f = Math.max(1, (int) Math.ceil(escriturasPorSegundo * (1 + margen) / capacidadPorDocumento));
        return new Plan(f, escriturasPorSegundo / f);
    }

    public static String rutaFragmento(String contador, int fragmentos, RandomGenerator azar) {
        return "contadores/" + contador + "/fragmentos/" + azar.nextInt(fragmentos);
    }

    public static long sumar(List<Long> valores) {
        return valores.stream().mapToLong(Long::longValue).sum();
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.FieldValue;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.FirestoreOptions;
import com.google.cloud.firestore.SetOptions;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.random.RandomGenerator;

/** Adaptador: incrementa un fragmento aleatorio y suma todos al leer. */
public class FirestoreGcp implements AutoCloseable {

    private final Firestore db;
    private final int fragmentos;
    private final RandomGenerator azar = RandomGenerator.getDefault();

    public FirestoreGcp(GoogleCredentials cred, String proyecto, String base, int fragmentos) {
        this.db = FirestoreOptions.newBuilder().setProjectId(proyecto).setDatabaseId(base).setCredentials(cred).build().getService();
        this.fragmentos = fragmentos;
    }

    public void incrementar(String contador) {
        var ruta = ContadorDistribuido.rutaFragmento(contador, fragmentos, azar);
        esperar(db.document(ruta).set(Map.of("n", FieldValue.increment(1)), SetOptions.merge()));
    }

    public long leer(String contador) {
        var docs = esperar(db.collection("contadores/" + contador + "/fragmentos").get()).getDocuments();
        return ContadorDistribuido.sumar(docs.stream().map(d -> d.getLong("n") == null ? 0L : d.getLong("n")).toList());
    }

    private static <T> T esperar(com.google.api.core.ApiFuture<T> f) {
        try {
            return f.get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (ExecutionException e) {
            throw new IllegalStateException(e.getCause());
        }
    }

    @Override
    public void close() {
        try {
            db.close();
        } catch (Exception e) {
            // cierre best effort
        }
    }
}
'''
SERV = '''
public class ServicioDeContadores {

    private final FirestoreGcp fs;

    public ServicioDeContadores(FirestoreGcp fs) {
        this.fs = fs;
    }

    public ContadorDistribuido.Plan planificar(double escrituras) {
        return ContadorDistribuido.planificar(escrituras, 1.0, 0.5);
    }

    public long visitar(String producto) {
        fs.incrementar("visitas-" + producto);
        return fs.leer("visitas-" + producto);
    }
}
'''
ggen.gcp('gcp/08-datos/firestore', 'Datos · Firestore',
  'Un patrón propio de Firestore: el **contador distribuido**. La lógica pura calcula cuántos fragmentos hacen falta para una tasa de escritura (un documento sostiene poco), elige uno al azar y suma; el adaptador escribe con `FieldValue.increment` y `SetOptions.merge()` sobre el fragmento y lee la subcolección completa. Las llamadas devuelven `ApiFuture`: aquí se esperan, en WebFlux/Mutiny se aíslan del hilo de eventos.',
  [('firestore.base', 'tienda'), ('firestore.fragmentos', '20')],
  [('Contador (lógica pura)', CON, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Contadores', '/datos/contadores', 'ServicioDeContadores', 'FirestoreGcp', [],
  'return new FirestoreGcp(cred, proyecto, base, Integer.parseInt(fragmentos));',
  [dict(n='planificar', v='GET', p='/plan', args=[('double', 'escrituras', 'q')], ret='ContadorDistribuido.Plan', call='s.planificar(escrituras)', cpu=True),
   dict(n='visitar', v='POST', p='/{producto}', args=[('String', 'producto', 'p')], ret='Long', call='s.visitar(producto)')],
  [('Leer y escribir', '`roles/datastore.user`'),
   ('Solo lectura', '`roles/datastore.viewer`')],
  ['No escribas cientos de veces por segundo al mismo documento.',
   'No uses IDs secuenciales.',
   'No confíes en reglas de seguridad desde el backend: aplica IAM.',
   'No abras un cliente por petición.'])
