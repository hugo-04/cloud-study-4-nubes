import genlib
SEL = '''
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Elige el perfil de conexión según la carga y prefiere TLS one-way. Puro. */
public class SelectorDePerfil {

    public enum Carga { TRANSACCIONAL, CRITICA, REPORTE, ANALITICA }

    public record Perfil(String nombre, String grupo, String tls, String connectString) { }

    private static final Map<Carga, String> GRUPO = Map.of(
        Carga.TRANSACCIONAL, "TP", Carga.CRITICA, "TPURGENT", Carga.REPORTE, "LOW", Carga.ANALITICA, "MEDIUM");

    public Optional<String> urlJdbc(Carga carga, List<Perfil> perfiles, boolean mtlsObligatorio) {
        String grupo = GRUPO.get(carga);
        return perfiles.stream()
            .filter(p -> grupo.equalsIgnoreCase(p.grupo()))
            .filter(p -> !mtlsObligatorio || "MUTUAL".equals(p.tls()))
            // SERVER (one-way, sin wallet) primero cuando está permitido
            .min(Comparator.comparing((Perfil p) -> "SERVER".equals(p.tls()) ? 0 : 1))
            .map(p -> "jdbc:oracle:thin:@" + conReintentos(p.connectString()));
    }

    /** Asegura reintentos de conexión en el descriptor (útil durante failover de Data Guard). */
    static String conReintentos(String descriptor) {
        if (descriptor.contains("retry_count")) {
            return descriptor;
        }
        return descriptor.replaceFirst("(?i)\\\\(description=", "(description=(retry_count=20)(retry_delay=3)");
    }
}
'''
SDK = '''
import com.oracle.bmc.database.DatabaseClient;
import com.oracle.bmc.database.requests.GetAutonomousDatabaseRequest;
import java.util.List;

/** Adaptador del SDK: lee estado, si exige mTLS y los perfiles de conexión de la ADB. */
public class AutonomaOci implements AutoCloseable {

    public record Estado(String nombre, String ciclo, boolean mtls, List<SelectorDePerfil.Perfil> perfiles) { }

    private final DatabaseClient cliente;

    public AutonomaOci(DatabaseClient cliente) {
        this.cliente = cliente;
    }

    public Estado estado(String adbId) {
        var a = cliente.getAutonomousDatabase(GetAutonomousDatabaseRequest.builder()
            .autonomousDatabaseId(adbId).build()).getAutonomousDatabase();
        var perfiles = a.getConnectionStrings().getProfiles().stream()
            .map(p -> new SelectorDePerfil.Perfil(p.getDisplayName(), p.getConsumerGroup().getValue(),
                p.getTlsAuthentication().getValue(), p.getValue()))
            .toList();
        return new Estado(a.getDisplayName(), a.getLifecycleState().getValue(),
            Boolean.TRUE.equals(a.getIsMtlsConnectionRequired()), perfiles);
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
public class ServicioDeConexion {

    public record Respuesta(String base, String estado, String url) { }

    private final AutonomaOci adb;
    private final SelectorDePerfil selector = new SelectorDePerfil();

    public ServicioDeConexion(AutonomaOci adb) {
        this.adb = adb;
    }

    /** La URL se usa para configurar el pool al arrancar (no se pide en cada consulta). */
    public Respuesta url(String adbId, SelectorDePerfil.Carga carga) {
        var e = adb.estado(adbId);
        String url = selector.urlJdbc(carga, e.perfiles(), e.mtls())
            .orElseThrow(() -> new IllegalStateException("no hay perfil para " + carga));
        return new Respuesta(e.nombre(), e.ciclo(), url);
    }
}
'''
genlib.oci('oci/08-datos/autonomous-database', 'Datos · Autonomous Database',
  'Un **selector de conexión**: lee con `DatabaseClient` los perfiles reales de la ADB y elige el servicio según la carga (`TP` para transacciones, `TPURGENT` para lo crítico, `LOW`/`MEDIUM` para reportes), prefiriendo TLS one-way si la base no exige mTLS, y añade reintentos al descriptor para sobrevivir a un *failover*. Con esa URL configuras el pool (UCP o Hikari) con el driver `ojdbc11` y la contraseña desde Vault.',
  [],
  [('Selector de perfil (lógica pura)', SEL, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Conexion', '/datos/adb', 'ServicioDeConexion', 'AutonomaOci',
  ['import com.oracle.bmc.database.DatabaseClient;'],
  'return new AutonomaOci(DatabaseClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='url', v='GET', p='/{id}/url', args=[('String', 'id', 'p'), ('SelectorDePerfil.Carga', 'carga', 'q')], ret='ServicioDeConexion.Respuesta', call='s.url(id, carga)')],
  [('Leer la ADB y sus perfiles', '`Allow dynamic-group app-pedidos to read autonomous-databases in compartment datos-prod`'),
   ('Contraseña del usuario de app', "`Allow dynamic-group app-pedidos to read secret-bundles in compartment datos-prod where target.secret.id = '<ocid>'`")],
  ['No expongas la URL ni credenciales en un endpoint público: este ejemplo es para diagnóstico interno.',
   'No pidas el perfil en cada consulta: resuélvelo al arrancar y configura el pool.',
   'No uses `ADMIN` desde la aplicación.',
   'No uses el servicio `high` para OLTP.',
   'No olvides cerrar `ResultSet`/`Statement` (o usa `JdbcTemplate`).'])
