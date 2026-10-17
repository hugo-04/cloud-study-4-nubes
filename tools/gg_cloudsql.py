import ggen
CON = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

/**
 * Arma la conexión JDBC al conector de Cloud SQL con autenticación IAM y calcula el pool
 * para que (pool × instancias) no supere max_connections. Puro.
 */
public final class ConexionCloudSql {

    public record Pool(int porInstancia, int totalMaximo, List<String> avisos) { }

    private ConexionCloudSql() {
    }

    /** connectionName = proyecto:region:instancia. Sin host: el conector abre el túnel TLS. */
    public static String url(String base) {
        return "jdbc:postgresql:///" + base;
    }

    public static Properties propiedades(String connectionName, String cuentaServicio, boolean ipPrivada) {
        var p = new Properties();
        p.setProperty("socketFactory", "com.google.cloud.sql.postgres.SocketFactory");
        p.setProperty("cloudSqlInstance", connectionName);
        p.setProperty("enableIamAuth", "true");
        p.setProperty("user", usuarioIam(cuentaServicio));
        p.setProperty("password", "no-se-usa");   // el driver exige un valor; el token IAM la reemplaza
        p.setProperty("sslmode", "disable");       // el conector ya cifra
        if (ipPrivada) {
            p.setProperty("ipTypes", "PRIVATE");
        }
        return p;
    }

    /** En PostgreSQL el usuario IAM es el email de la SA sin el sufijo .gserviceaccount.com. */
    public static String usuarioIam(String email) {
        return email.endsWith(".gserviceaccount.com") ? email.substring(0, email.length() - ".gserviceaccount.com".length()) : email;
    }

    public static Pool pool(int maxConnections, int reserva, int instanciasMaximas, int deseadoPorInstancia) {
        int disponible = Math.max(0, maxConnections - reserva);
        int porInstancia = Math.max(1, Math.min(deseadoPorInstancia, disponible / Math.max(1, instanciasMaximas)));
        var avisos = new ArrayList<String>();
        if (porInstancia < deseadoPorInstancia) {
            avisos.add("pool reducido de " + deseadoPorInstancia + " a " + porInstancia);
        }
        if ((long) porInstancia * instanciasMaximas > disponible) {
            avisos.add("aun con pool 1 se supera el límite: baja instancias o usa réplicas");
        }
        return new Pool(porInstancia, porInstancia * instanciasMaximas, avisos);
    }
}
'''
SDK = '''
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * Adaptador: comprueba la conexión con el conector (en la app real usa el pool del framework
 * con las mismas propiedades; aquí DriverManager para no mezclar el ejemplo con el pool).
 */
public class CloudSqlGcp implements AutoCloseable {

    public record Prueba(String usuario, String version, boolean soloLectura) { }

    private final String connectionName;
    private final String base;
    private final String cuenta;

    public CloudSqlGcp(String connectionName, String base, String cuenta) {
        this.connectionName = connectionName;
        this.base = base;
        this.cuenta = cuenta;
    }

    public Prueba probar() {
        var props = ConexionCloudSql.propiedades(connectionName, cuenta, true);
        try (var c = DriverManager.getConnection(ConexionCloudSql.url(base), props);
             var st = c.createStatement();
             var rs = st.executeQuery("select current_user, version(), pg_is_in_recovery()")) {
            rs.next();
            return new Prueba(rs.getString(1), rs.getString(2), rs.getBoolean(3));
        } catch (SQLException e) {
            throw new IllegalStateException("conexión fallida (" + e.getSQLState() + ")", e);
        }
    }

    @Override
    public void close() {
        // sin recursos abiertos entre llamadas
    }
}
'''
SERV = '''
public class ServicioDeBase {

    private final CloudSqlGcp sql;

    public ServicioDeBase(CloudSqlGcp sql) {
        this.sql = sql;
    }

    public ConexionCloudSql.Pool pool(int maxConnections, int instancias, int deseado) {
        return ConexionCloudSql.pool(maxConnections, 20, instancias, deseado);
    }

    public CloudSqlGcp.Prueba probar() {
        return sql.probar();
    }
}
'''
ggen.gcp('gcp/08-datos/cloud-sql', 'Datos · Cloud SQL',
  'Con Cloud SQL el SQL es el de siempre; lo propio de Google es **la conexión**. Aquí: un armador puro de propiedades del **conector Java** (`socketFactory`, `cloudSqlInstance`, `enableIamAuth`, usuario IAM sin sufijo) más el **cálculo del pool** contra `max_connections`, y un adaptador que prueba la conexión. En Spring estas propiedades van en `spring.datasource.hikari.data-source-properties.*` y en Quarkus en `quarkus.datasource.jdbc.additional-jdbc-properties.*`.',
  [('sql.connection', 'modalima-prod:southamerica-west1:pedidos-pg'), ('sql.base', 'pedidos'), ('sql.cuenta', 'app-pedidos@modalima-prod.iam.gserviceaccount.com')],
  [('Conexión y pool (lógica pura)', CON, True), ('Adaptador JDBC', SDK, True), ('Servicio', SERV, True)],
  'Base', '/datos/base', 'ServicioDeBase', 'CloudSqlGcp', [],
  'return new CloudSqlGcp(connection, base, cuenta);',
  [dict(n='pool', v='GET', p='/pool', args=[('int', 'maxConnections', 'q'), ('int', 'instancias', 'q'), ('int', 'deseado', 'q')], ret='ConexionCloudSql.Pool', call='s.pool(maxConnections, instancias, deseado)', cpu=True),
   dict(n='probar', v='GET', p='/prueba', args=[], ret='CloudSqlGcp.Prueba', call='s.probar()')],
  [('Conectar por el conector', '`roles/cloudsql.client`'),
   ('Entrar con IAM', '`roles/cloudsql.instanceUser` + usuario `CLOUD_IAM_SERVICE_ACCOUNT` + `GRANT` en la base')],
  ['No pongas contraseñas en la configuración: usa IAM.',
   'No abras la IP pública «para probar».',
   'No dimensiones el pool sin contar las instancias máximas.',
   'No expongas `/prueba` fuera de la red interna.'])
