import genlib
REP = '''
import java.util.LinkedHashMap;
import java.util.Map;

/** Reparte max_connections entre servicios según réplicas y peso. Puro. */
public class RepartidorDeConexiones {

    public record Servicio(int replicas, int peso) { }

    private final int maxConexiones;
    private final int reserva;

    public RepartidorDeConexiones(int maxConexiones, int reserva) {
        this.maxConexiones = maxConexiones;
        this.reserva = reserva;
    }

    /** Devuelve el tamaño máximo del pool POR RÉPLICA de cada servicio (mínimo 2). */
    public Map<String, Integer> poolPorReplica(Map<String, Servicio> servicios) {
        int disponibles = (int) Math.floor((maxConexiones - reserva) * 0.9); // 10 % de margen para picos y reconexiones
        int pesoTotal = servicios.values().stream().mapToInt(s -> s.peso() * s.replicas()).sum();
        if (pesoTotal == 0) {
            throw new IllegalArgumentException("sin servicios");
        }
        var out = new LinkedHashMap<String, Integer>();
        int usadas = 0;
        for (var e : servicios.entrySet()) {
            var s = e.getValue();
            int porReplica = Math.max(2, disponibles * s.peso() / pesoTotal);
            out.put(e.getKey(), porReplica);
            usadas += porReplica * s.replicas();
        }
        if (usadas > maxConexiones - reserva) {
            throw new IllegalStateException("no alcanzan las conexiones: " + usadas + " > " + (maxConexiones - reserva));
        }
        return out;
    }

    public static String urlJdbc(String host, int puerto, String base) {
        return "jdbc:mysql://" + host + ":" + puerto + "/" + base + "?sslMode=REQUIRED&connectTimeout=5000&tcpKeepAlive=true";
    }
}
'''
SDK = '''
import com.oracle.bmc.mysql.DbSystemClient;
import com.oracle.bmc.mysql.model.DbSystemEndpoint;
import com.oracle.bmc.mysql.requests.GetDbSystemRequest;
import java.util.List;

/** Adaptador del SDK: descubre endpoints (escritura/lectura) y si HeatWave está activo. */
public class MysqlOci implements AutoCloseable {

    public record Endpoint(String ip, int puerto, boolean escritura) { }

    public record Estado(String nombre, String ciclo, boolean ha, boolean heatwave, List<Endpoint> endpoints) { }

    private final DbSystemClient cliente;

    public MysqlOci(DbSystemClient cliente) {
        this.cliente = cliente;
    }

    public Estado estado(String dbSystemId) {
        var d = cliente.getDbSystem(GetDbSystemRequest.builder().dbSystemId(dbSystemId).build()).getDbSystem();
        var eps = d.getEndpoints().stream()
            .map(e -> new Endpoint(e.getIpAddress(), e.getPort(), e.getModes().contains(DbSystemEndpoint.Modes.Write)))
            .toList();
        boolean hw = Boolean.TRUE.equals(d.getIsHeatWaveClusterAttached()) && d.getHeatWaveCluster() != null
            && "ACTIVE".equals(d.getHeatWaveCluster().getLifecycleState().getValue());
        return new Estado(d.getDisplayName(), d.getLifecycleState().getValue(), Boolean.TRUE.equals(d.getIsHighlyAvailable()), hw, eps);
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.Map;

public class ServicioDePools {

    public record Plan(String urlEscritura, boolean heatwave, Map<String, Integer> poolPorReplica) { }

    private final MysqlOci mysql;

    public ServicioDePools(MysqlOci mysql) {
        this.mysql = mysql;
    }

    public Plan planificar(String dbSystemId, int maxConexiones, Map<String, RepartidorDeConexiones.Servicio> servicios) {
        var e = mysql.estado(dbSystemId);
        var escritura = e.endpoints().stream().filter(MysqlOci.Endpoint::escritura).findFirst()
            .orElseThrow(() -> new IllegalStateException("sin endpoint de escritura"));
        var pools = new RepartidorDeConexiones(maxConexiones, 20).poolPorReplica(servicios);
        return new Plan(RepartidorDeConexiones.urlJdbc(escritura.ip(), escritura.puerto(), "catalogo"), e.heatwave(), pools);
    }
}
'''
genlib.oci('oci/08-datos/mysql-heatwave', 'Datos · MySQL HeatWave',
  'Un **planificador de pools**: reparte `max_connections` entre servicios según réplicas y peso (con reserva y margen) para que escalar réplicas no tumbe la base, y lee con `DbSystemClient` el endpoint real de escritura y si HeatWave está activo. El resultado alimenta `spring.datasource.hikari.maximum-pool-size` o `quarkus.datasource.jdbc.max-size`.',
  [],
  [('Repartidor de conexiones (lógica pura)', REP, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Pools', '/datos/mysql', 'ServicioDePools', 'MysqlOci',
  ['import com.oracle.bmc.mysql.DbSystemClient;'],
  'return new MysqlOci(DbSystemClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='planificar', v='POST', p='/{id}/plan', args=[('String', 'id', 'p'), ('int', 'max', 'q'), ('java.util.Map<String, RepartidorDeConexiones.Servicio>', 'servicios', 'b')], ret='ServicioDePools.Plan', call='s.planificar(id, max, servicios)', cpu=False)],
  [('Leer el DB system', '`Allow dynamic-group plataforma to read mysql-db-systems in compartment datos-prod`')],
  ['No dimensiones el pool por réplica sin mirar el total global.',
   'No uses el usuario administrador desde la app.',
   'No leas de réplicas lo que el usuario acaba de escribir.',
   'No desactives TLS (`sslMode=DISABLED`).',
   'No ejecutes reportes pesados sin HeatWave sobre el primario en horas punta.'])
