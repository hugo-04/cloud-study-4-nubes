import ggen
REA = '''
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

/**
 * Reacción a las notificaciones del presupuesto (llegan varias veces al día):
 * solo actúa cuando se cruza un umbral nuevo en el periodo. Más una proyección lineal de fin de mes. Puro.
 */
public final class ReaccionAPresupuesto {

    public record Aviso(String presupuesto, String periodo, double costo, double monto, Double umbralCruzado) { }

    public record Decision(String accion, double porcentaje, String motivo) { }

    private static final Pattern TABLA = Pattern.compile("[a-z][a-z0-9-]{4,28}[a-z0-9]\\\\.[A-Za-z0-9_]+\\\\.[A-Za-z0-9_]+");
    private final Map<String, Double> ultimoUmbral = new ConcurrentHashMap<>();

    /** Campos del JSON del mensaje: budgetDisplayName, costIntervalStart, costAmount, budgetAmount, alertThresholdExceeded. */
    public static Aviso desde(Map<String, Object> m) {
        Object u = m.get("alertThresholdExceeded");
        return new Aviso((String) m.get("budgetDisplayName"), String.valueOf(m.get("costIntervalStart")),
            ((Number) m.get("costAmount")).doubleValue(), ((Number) m.get("budgetAmount")).doubleValue(),
            u == null ? null : ((Number) u).doubleValue());
    }

    public Decision evaluar(Aviso a, boolean esSandbox) {
        double pct = a.monto() == 0 ? 0 : a.costo() / a.monto();
        if (a.umbralCruzado() == null) {
            return new Decision("nada", pct, "sin umbral cruzado");
        }
        String clave = a.presupuesto() + "|" + a.periodo();
        Double previo = ultimoUmbral.get(clave);
        if (previo != null && previo >= a.umbralCruzado()) {
            return new Decision("nada", pct, "umbral ya procesado");
        }
        ultimoUmbral.put(clave, a.umbralCruzado());
        if (a.umbralCruzado() >= 1.0 && esSandbox) {
            return new Decision("detener-sandbox", pct, "100 % alcanzado en sandbox");
        }
        return new Decision("avisar", pct, "umbral " + Math.round(a.umbralCruzado() * 100) + " %");
    }

    /** Gasto proyectado a fin de mes con ritmo constante. */
    public static double proyectar(double gastoAlDia, int diaDelMes, int diasDelMes) {
        return diaDelMes <= 0 ? 0 : gastoAlDia / diaDelMes * diasDelMes;
    }

    public static String tablaValida(String tabla) {
        if (!TABLA.matcher(tabla).matches()) {
            throw new IllegalArgumentException("tabla de exportación inválida");
        }
        return tabla;
    }
}
'''
SDK = '''
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.bigquery.BigQuery;
import com.google.cloud.bigquery.BigQueryOptions;
import com.google.cloud.bigquery.QueryJobConfiguration;
import com.google.cloud.bigquery.QueryParameterValue;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: costo neto por equipo desde la exportación de facturación en BigQuery. */
public class CostosGcp implements AutoCloseable {

    public record CostoEquipo(String equipo, double costoNeto, String moneda) { }

    private final BigQuery bq;
    private final String tabla;

    public CostosGcp(GoogleCredentials cred, String proyecto, String tabla) {
        this.bq = BigQueryOptions.newBuilder().setProjectId(proyecto).setCredentials(cred).build().getService();
        this.tabla = ReaccionAPresupuesto.tablaValida(tabla);   // el nombre de tabla no admite parámetros
    }

    public List<CostoEquipo> porEquipo(String mes) {
        String sql = "SELECT IFNULL((SELECT value FROM UNNEST(labels) WHERE key = 'equipo'), 'sin-equipo') AS equipo, "
            + "SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS neto, currency "
            + "FROM `" + tabla + "` WHERE invoice.month = @mes GROUP BY equipo, currency ORDER BY neto DESC";
        var cfg = QueryJobConfiguration.newBuilder(sql).addNamedParameter("mes", QueryParameterValue.string(mes)).build();
        try {
            var out = new ArrayList<CostoEquipo>();
            for (var fila : bq.query(cfg).iterateAll()) {
                out.add(new CostoEquipo(fila.get("equipo").getStringValue(), fila.get("neto").getDoubleValue(),
                    fila.get("currency").getStringValue()));
            }
            return out;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }

    @Override
    public void close() {
        // el cliente de BigQuery no mantiene conexiones que cerrar
    }
}
'''
SERV = '''
import java.util.List;
import java.util.Map;

public class ServicioDeCostos {

    private final CostosGcp gcp;
    private final ReaccionAPresupuesto reaccion = new ReaccionAPresupuesto();

    public ServicioDeCostos(CostosGcp gcp) {
        this.gcp = gcp;
    }

    /** Recibe el JSON ya decodificado del mensaje de Pub/Sub del presupuesto. */
    public ReaccionAPresupuesto.Decision aviso(Map<String, Object> mensaje) {
        var a = ReaccionAPresupuesto.desde(mensaje);
        return reaccion.evaluar(a, a.presupuesto() != null && a.presupuesto().startsWith("sandbox-"));
    }

    public List<CostosGcp.CostoEquipo> porEquipo(String mes) {
        return gcp.porEquipo(mes);
    }
}
'''
ggen.gcp('gcp/09-gobierno/presupuestos-costos', 'Gobierno · Presupuestos y costos',
  'Dos piezas: una **reacción pura** al mensaje del presupuesto en Pub/Sub (llega varias veces al día: solo actúa cuando se cruza un **umbral nuevo** en el periodo, y detiene solo lo que es sandbox) más una proyección lineal; y un adaptador que consulta el **costo neto por equipo** (costo + créditos) en la exportación de facturación de BigQuery con parámetro de mes. El nombre de la tabla se valida porque no puede ir como parámetro.',
  [('costos.tabla', 'modalima-finanzas.facturacion.gcp_billing_export_resource_v1_ABC123')],
  [('Reacción (lógica pura)', REA, True), ('Adaptador de BigQuery', SDK, True), ('Servicio', SERV, True)],
  'Costos', '/gobierno/costos', 'ServicioDeCostos', 'CostosGcp', [],
  'return new CostosGcp(cred, proyecto, tabla);',
  [dict(n='aviso', v='POST', p='/aviso', args=[('java.util.Map<String, Object>', 'mensaje', 'b')], ret='ReaccionAPresupuesto.Decision', call='s.aviso(mensaje)', cpu=True),
   dict(n='porEquipo', v='GET', p='/equipos', args=[('String', 'mes', 'q')], ret='java.util.List<CostosGcp.CostoEquipo>', call='s.porEquipo(mes)')],
  [('Consultar la exportación', '`roles/bigquery.dataViewer` en el dataset + `roles/bigquery.jobUser` en el proyecto'),
   ('Detener sandbox (si lo implementas)', 'Permisos mínimos solo en proyectos con tag `entorno=sandbox`')],
  ['No concatenes el mes en el SQL: usa parámetros.',
   'No reacciones a cada mensaje: se repiten.',
   'No desvincules la facturación de producción.',
   'No des acceso a todo el dataset de facturación a los equipos.'])
