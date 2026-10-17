import ggen
CLA = '''
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Diseño de clave de fila para series de tiempo: entidad#timestampInvertido (lo último primero). Puro.
 */
public final class ClaveDeFila {

    public record Revision(boolean riesgo, List<String> motivos) { }

    private ClaveDeFila() {
    }

    public static String de(String entidad, Instant momento) {
        long invertido = Long.MAX_VALUE - momento.toEpochMilli();
        return entidad + "#" + String.format("%019d", invertido);
    }

    public static Instant momento(String clave) {
        long invertido = Long.parseLong(clave.substring(clave.lastIndexOf('#') + 1));
        return Instant.ofEpochMilli(Long.MAX_VALUE - invertido);
    }

    public static String prefijo(String entidad) {
        return entidad + "#";
    }

    public static Revision revisar(String clave) {
        var motivos = new ArrayList<String>();
        if (clave.matches("^\\\\d{8}.*") || clave.matches("^\\\\d{4}-\\\\d{2}-\\\\d{2}.*")) {
            motivos.add("empieza por fecha: todas las escrituras recientes caen en el mismo rango");
        }
        if (clave.length() > 4096) {
            motivos.add("clave demasiado larga");
        }
        return new Revision(!motivos.isEmpty(), motivos);
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.bigtable.data.v2.BigtableDataClient;
import com.google.cloud.bigtable.data.v2.BigtableDataSettings;
import com.google.cloud.bigtable.data.v2.models.Query;
import com.google.cloud.bigtable.data.v2.models.RowMutation;
import com.google.cloud.bigtable.data.v2.models.TableId;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: escribe lecturas por máquina y lee las últimas N por prefijo. */
public class BigtableGcp implements AutoCloseable {

    public record Lectura(Instant momento, double temperatura) { }

    private static final TableId TABLA = TableId.of("lecturas");
    private final BigtableDataClient cliente;

    public BigtableGcp(GoogleCredentials cred, String proyecto, String instancia) {
        try {
            this.cliente = BigtableDataClient.create(BigtableDataSettings.newBuilder()
                .setProjectId(proyecto).setInstanceId(instancia)
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public void escribir(String maquina, Lectura l) {
        cliente.mutateRow(RowMutation.create(TABLA, ClaveDeFila.de(maquina, l.momento()))
            .setCell("m", "temp", Double.toString(l.temperatura())));
    }

    public List<Lectura> ultimas(String maquina, int n) {
        var out = new ArrayList<Lectura>();
        for (var fila : cliente.readRows(Query.create(TABLA).prefix(ClaveDeFila.prefijo(maquina)).limit(n))) {
            var celdas = fila.getCells("m", "temp");
            if (!celdas.isEmpty()) {
                out.add(new Lectura(ClaveDeFila.momento(fila.getKey().toStringUtf8()),
                    Double.parseDouble(celdas.get(0).getValue().toStringUtf8())));
            }
        }
        return out;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Instant;
import java.util.List;

public class ServicioDeTelemetria {

    private final BigtableGcp bt;

    public ServicioDeTelemetria(BigtableGcp bt) {
        this.bt = bt;
    }

    public ClaveDeFila.Revision revisar(String clave) {
        return ClaveDeFila.revisar(clave);
    }

    public List<BigtableGcp.Lectura> registrar(String maquina, double temperatura) {
        bt.escribir(maquina, new BigtableGcp.Lectura(Instant.now(), temperatura));
        return bt.ultimas(maquina, 10);
    }
}
'''
ggen.gcp('gcp/08-datos/bigtable', 'Datos · Bigtable',
  'En Bigtable todo depende de la **clave de fila**. La lógica pura arma `maquina#timestampInvertido` (19 dígitos con ceros para que el orden lexicográfico funcione), recupera el instante y detecta claves que empiezan por fecha; el adaptador escribe con `mutateRow` y lee las últimas N con `Query.prefix(...).limit(n)`, que gracias a la inversión son las más recientes.',
  [('bigtable.instancia', 'telemetria-cafe')],
  [('Clave de fila (lógica pura)', CLA, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Telemetria', '/datos/telemetria', 'ServicioDeTelemetria', 'BigtableGcp', [],
  'return new BigtableGcp(cred, proyecto, instancia);',
  [dict(n='revisar', v='GET', p='/clave', args=[('String', 'clave', 'q')], ret='ClaveDeFila.Revision', call='s.revisar(clave)', cpu=True),
   dict(n='registrar', v='POST', p='/{maquina}', args=[('String', 'maquina', 'p'), ('double', 'temperatura', 'q')], ret='java.util.List<BigtableGcp.Lectura>', call='s.registrar(maquina, temperatura)')],
  [('Leer y escribir', '`roles/bigtable.user` en la instancia'),
   ('Solo lectura', '`roles/bigtable.reader`')],
  ['No empieces la clave con una fecha.',
   'No hagas escaneos completos desde la API: exporta para analítica.',
   'No guardes celdas grandes (> 10 MB).',
   'No crees un cliente por petición.'])
