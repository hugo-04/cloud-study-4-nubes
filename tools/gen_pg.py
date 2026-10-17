import genlib
ENR = '''
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Decide primario o réplica con consistencia «leer lo que escribí» por usuario. Puro: reloj inyectado. */
public class EnrutadorLecturaEscritura {

    public enum Destino { PRIMARIO, LECTURA }

    private final Clock reloj;
    private final Duration ventana;
    private final Map<String, Instant> ultimaEscritura = new ConcurrentHashMap<>();

    public EnrutadorLecturaEscritura(Clock reloj, Duration ventana) {
        this.reloj = reloj;
        this.ventana = ventana;
    }

    public Destino paraEscritura(String usuario) {
        ultimaEscritura.put(usuario, reloj.instant());
        return Destino.PRIMARIO;
    }

    /** toleraRetraso=false fuerza el primario (saldos, stock en checkout). */
    public Destino paraLectura(String usuario, boolean toleraRetraso) {
        if (!toleraRetraso) {
            return Destino.PRIMARIO;
        }
        Instant ultima = ultimaEscritura.get(usuario);
        if (ultima != null && reloj.instant().isBefore(ultima.plus(ventana))) {
            return Destino.PRIMARIO;
        }
        if (ultima != null) {
            ultimaEscritura.remove(usuario, ultima); // limpieza perezosa
        }
        return Destino.LECTURA;
    }

    public static String urlJdbc(String host, String base) {
        return "jdbc:postgresql://" + host + ":5432/" + base + "?sslmode=verify-full&connectTimeout=5&tcpKeepAlive=true";
    }
}
'''
SDK = '''
import com.oracle.bmc.psql.PostgresqlClient;
import com.oracle.bmc.psql.requests.GetDbSystemRequest;

/** Adaptador del SDK: descubre la IP del primario y si el endpoint de lectura está activo. */
public class PostgresOci implements AutoCloseable {

    public record Estado(String nombre, String ciclo, String version, int nodos, String ipPrimario, boolean lectorActivo) { }

    private final PostgresqlClient cliente;
    private final String hostLectura;

    public PostgresOci(PostgresqlClient cliente, String hostLectura) {
        this.cliente = cliente;
        this.hostLectura = hostLectura;
    }

    /** El endpoint de lectura se usa por su nombre DNS privado (configurado). */
    public String hostLectura() {
        return hostLectura;
    }

    public Estado estado(String dbSystemId) {
        var d = cliente.getDbSystem(GetDbSystemRequest.builder().dbSystemId(dbSystemId).build()).getDbSystem();
        var red = d.getNetworkDetails();
        return new Estado(d.getDisplayName(), d.getLifecycleState().getValue(), d.getDbVersion(), d.getInstanceCount(),
            red.getPrimaryDbEndpointPrivateIp(), Boolean.TRUE.equals(red.getIsReaderEndpointEnabled()));
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Clock;
import java.time.Duration;

public class ServicioDeRutas {

    public record Ruta(String destino, String url) { }

    private final PostgresOci pg;
    private final EnrutadorLecturaEscritura enrutador = new EnrutadorLecturaEscritura(Clock.systemUTC(), Duration.ofSeconds(5));

    public ServicioDeRutas(PostgresOci pg) {
        this.pg = pg;
    }

    public PostgresOci.Estado estado(String id) {
        return pg.estado(id);
    }

    /** En una app real esto elige entre dos DataSource (primario y lectura) ya creados al arrancar. */
    public Ruta ruta(String id, String usuario, boolean escritura, boolean toleraRetraso) {
        var e = pg.estado(id);
        var d = escritura ? enrutador.paraEscritura(usuario) : enrutador.paraLectura(usuario, toleraRetraso);
        boolean usarLector = d == EnrutadorLecturaEscritura.Destino.LECTURA && e.lectorActivo();
        String host = usarLector ? pg.hostLectura() : e.ipPrimario();
        return new Ruta(usarLector ? "LECTURA" : "PRIMARIO", EnrutadorLecturaEscritura.urlJdbc(host, "pedidos"));
    }
}
'''
genlib.oci('oci/08-datos/postgresql', 'Datos · PostgreSQL',
  'Un **enrutador de lectura/escritura** con consistencia «leer lo que escribí»: tras una escritura, ese usuario lee del primario durante una ventana; las lecturas que no toleran retraso (stock, saldo) van siempre al primario. El adaptador descubre con `PostgresqlClient` la IP del primario y si el endpoint de lectura está activo. En la app real esto elige entre dos `DataSource` creados al arrancar (JDBC o R2DBC en reactivo).',
  [('pg.hostLectura', 'lectura.pg-pedidos.subred.vcn.oraclevcn.com')],
  [('Enrutador (lógica pura)', ENR, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Rutas', '/datos/pg', 'ServicioDeRutas', 'PostgresOci',
  ['import com.oracle.bmc.psql.PostgresqlClient;'],
  'return new PostgresOci(PostgresqlClient.builder().region(Region.fromRegionId(region)).build(auth), hostLectura);',
  [dict(n='estado', v='GET', p='/{id}', args=[('String', 'id', 'p')], ret='PostgresOci.Estado', call='s.estado(id)'),
   dict(n='ruta', v='GET', p='/{id}/ruta', args=[('String', 'id', 'p'), ('String', 'usuario', 'q'), ('boolean', 'escritura', 'q'), ('boolean', 'tolera', 'q')], ret='ServicioDeRutas.Ruta', call='s.ruta(id, usuario, escritura, tolera)')],
  [('Leer el DB system', '`Allow dynamic-group plataforma to read postgres-db-systems in compartment datos-prod`')],
  ['No mezcles JDBC bloqueante en el hilo de eventos de WebFlux: usa R2DBC o aísla en `boundedElastic`.',
   'No abras pools grandes: PostgreSQL paga cada conexión con memoria.',
   'No leas de réplica justo después de escribir.',
   'No ejecutes migraciones con el rol de la aplicación.',
   'No uses `sslmode=disable` ni `require` sin verificar el servidor en producción.'])
