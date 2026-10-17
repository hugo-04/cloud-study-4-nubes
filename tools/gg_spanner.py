import ggen
CLA = '''
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Revisa diseños de clave primaria (riesgo de hotspot) y genera claves seguras. Puro.
 */
public final class ClavesSpanner {

    public record Revision(String tabla, boolean riesgo, List<String> motivos) { }

    private static final Pattern CRECIENTE = Pattern.compile("(?i).*(fecha|timestamp|creado|time|_at|seq|secuencia|contador|autoinc).*");

    private ClavesSpanner() {
    }

    /** columnasPk en orden; la primera es la que decide la división. */
    public static Revision revisar(String tabla, List<String> columnasPk, boolean interleavedEnPadre) {
        var motivos = new ArrayList<String>();
        if (!columnasPk.isEmpty() && !interleavedEnPadre && CRECIENTE.matcher(columnasPk.get(0)).matches()) {
            motivos.add("la primera columna de la PK (" + columnasPk.get(0) + ") parece creciente: hotspot");
        }
        if (columnasPk.isEmpty()) {
            motivos.add("tabla sin clave primaria");
        }
        return new Revision(tabla, !motivos.isEmpty(), motivos);
    }

    public static String nuevaClave() {
        return UUID.randomUUID().toString();
    }

    /** Alternativa cuando necesitas ordenar por tiempo dentro de un cliente: prefijo de hash. */
    public static String conPrefijo(String natural, int fragmentos) {
        int f = Math.floorMod(natural.hashCode(), fragmentos);
        return String.format("%02d#%s", f, natural);
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.spanner.DatabaseClient;
import com.google.cloud.spanner.DatabaseId;
import com.google.cloud.spanner.Key;
import com.google.cloud.spanner.Mutation;
import com.google.cloud.spanner.Spanner;
import com.google.cloud.spanner.SpannerOptions;
import java.util.List;

/** Adaptador: reserva de stock en una transacción de lectura-escritura (reintentos automáticos ante ABORTED). */
public class SpannerGcp implements AutoCloseable {

    public record Reserva(String sku, boolean reservada, long stockRestante) { }

    private final Spanner spanner;
    private final DatabaseClient db;

    public SpannerGcp(GoogleCredentials cred, String proyecto, String instancia, String base) {
        this.spanner = SpannerOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.db = spanner.getDatabaseClient(DatabaseId.of(proyecto, instancia, base));
    }

    public Reserva reservar(String sku, long cantidad) {
        return db.readWriteTransaction().run(tx -> {
            var fila = tx.readRow("Inventario", Key.of(sku), List.of("Stock"));
            long stock = fila == null ? 0 : fila.getLong("Stock");
            if (stock < cantidad) {
                return new Reserva(sku, false, stock);   // sin escritura: la transacción termina sin cambios
            }
            tx.buffer(Mutation.newUpdateBuilder("Inventario")
                .set("Sku").to(sku)
                .set("Stock").to(stock - cantidad)
                .set("Actualizado").to(com.google.cloud.spanner.Value.COMMIT_TIMESTAMP)
                .build());
            return new Reserva(sku, true, stock - cantidad);
        });
    }

    @Override
    public void close() {
        spanner.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeInventario {

    private final SpannerGcp spanner;

    public ServicioDeInventario(SpannerGcp spanner) {
        this.spanner = spanner;
    }

    public ClavesSpanner.Revision revisar(String tabla, List<String> pk) {
        return ClavesSpanner.revisar(tabla, pk, false);
    }

    public SpannerGcp.Reserva reservar(String sku, long cantidad) {
        if (cantidad <= 0) {
            throw new IllegalArgumentException("cantidad inválida");
        }
        return spanner.reservar(sku, cantidad);
    }
}
'''
ggen.gcp('gcp/08-datos/spanner', 'Datos · Spanner',
  'Dos piezas: un **revisor puro de claves primarias** que detecta columnas crecientes al inicio de la PK (hotspot) y genera claves UUID o con prefijo de hash, y un adaptador que **reserva stock** en una transacción de lectura-escritura con `readWriteTransaction().run(...)`: si otra transacción choca, Spanner aborta y la biblioteca **reintenta el bloque completo**, por eso el bloque no debe tener efectos externos.',
  [('spanner.instancia', 'modalima-tienda'), ('spanner.base', 'tienda')],
  [('Claves (lógica pura)', CLA, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Inventario', '/datos/inventario', 'ServicioDeInventario', 'SpannerGcp', [],
  'return new SpannerGcp(cred, proyecto, instancia, base);',
  [dict(n='revisar', v='POST', p='/claves/{tabla}', args=[('String', 'tabla', 'p'), ('java.util.List<String>', 'pk', 'b')], ret='ClavesSpanner.Revision', call='s.revisar(tabla, pk)', cpu=True),
   dict(n='reservar', v='POST', p='/{sku}/reserva', args=[('String', 'sku', 'p'), ('long', 'cantidad', 'q')], ret='SpannerGcp.Reserva', call='s.reservar(sku, cantidad)')],
  [('Leer y escribir', '`roles/spanner.databaseUser` en la base'),
   ('Solo lectura', '`roles/spanner.databaseReader`')],
  ['No llames a servicios externos dentro de la transacción: se puede repetir.',
   'No uses PK crecientes.',
   'No abras un `Spanner` por petición: es caro; uno por aplicación.',
   'No hagas lecturas fuertes donde una obsoleta basta.'])
