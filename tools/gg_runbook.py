import ggen
TRI = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/** Triage por capas: evalúa en orden y señala la primera que falla; «no se pudo comprobar» también cuenta. Puro. */
public class TriageDeCapas {

    public enum Resultado { OK, FALLA, DESCONOCIDO }

    public record Chequeo(String capa, Supplier<Boolean> prueba) { }

    public record Paso(String capa, Resultado resultado, String detalle) { }

    public record Informe(List<Paso> pasos, String primeraCapaConProblema, String runbook) { }

    private static final Map<String, String> RUNBOOK = Map.of(
        "load-balancer", "502/504: salud de backends → readiness → último despliegue",
        "computo", "revisión activa/instancias al tope/reinicios → revertir tráfico → escalar",
        "dependencias", "conexiones de Cloud SQL, latencia de Memorystore, backlog/DLQ de Pub/Sub → pools → consultas top",
        "cambios", "revertir el último cambio de infraestructura o aplicación");

    public Informe evaluar(List<Chequeo> chequeos) {
        var pasos = new ArrayList<Paso>();
        String primera = null;
        for (Chequeo c : chequeos) {
            Resultado r;
            String detalle;
            try {
                r = c.prueba().get() ? Resultado.OK : Resultado.FALLA;
                detalle = r == Resultado.OK ? "ok" : "falla";
            } catch (RuntimeException e) {
                r = Resultado.DESCONOCIDO;
                detalle = "no se pudo comprobar: " + e.getClass().getSimpleName();
            }
            pasos.add(new Paso(c.capa(), r, detalle));
            if (primera == null && r != Resultado.OK) {
                primera = c.capa();
            }
        }
        return new Informe(pasos, primera, primera == null ? "sin hallazgos en las capas" : RUNBOOK.getOrDefault(primera, "revisar la capa"));
    }

    /** Tasa de error a partir de conteos (protege la división). */
    public static double tasaDeError(double errores, double total) {
        return total <= 0 ? 0 : errores / total;
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.monitoring.v3.MetricServiceClient;
import com.google.cloud.monitoring.v3.MetricServiceSettings;
import com.google.monitoring.v3.Aggregation;
import com.google.monitoring.v3.ListTimeSeriesRequest;
import com.google.monitoring.v3.ProjectName;
import com.google.monitoring.v3.TimeInterval;
import com.google.protobuf.util.Durations;
import com.google.protobuf.util.Timestamps;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Duration;

/** Adaptador: suma de solicitudes del LB en una ventana (total o por clase de respuesta). */
public class SenalesGcp implements AutoCloseable {

    private final MetricServiceClient cliente;
    private final String proyecto;

    public SenalesGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = MetricServiceClient.create(MetricServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    /** claseRespuesta null = total; "500" = 5xx. urlMap identifica el LB. */
    public double solicitudesLb(String urlMap, String claseRespuesta, Duration ventana) {
        String filtro = "metric.type=\\"loadbalancing.googleapis.com/https/request_count\\""
            + " AND resource.labels.url_map_name=\\"" + urlMap.replace("\\"", "") + "\\""
            + (claseRespuesta == null ? "" : " AND metric.labels.response_code_class=" + Integer.parseInt(claseRespuesta));
        long ahora = System.currentTimeMillis();
        var req = ListTimeSeriesRequest.newBuilder()
            .setName(ProjectName.of(proyecto).toString())
            .setFilter(filtro)
            .setInterval(TimeInterval.newBuilder()
                .setStartTime(Timestamps.fromMillis(ahora - ventana.toMillis()))
                .setEndTime(Timestamps.fromMillis(ahora)))
            .setAggregation(Aggregation.newBuilder()
                .setAlignmentPeriod(Durations.fromSeconds(ventana.toSeconds()))
                .setPerSeriesAligner(Aggregation.Aligner.ALIGN_SUM)
                .setCrossSeriesReducer(Aggregation.Reducer.REDUCE_SUM))
            .setView(ListTimeSeriesRequest.TimeSeriesView.FULL)
            .build();
        double suma = 0;
        for (var serie : cliente.listTimeSeries(req).iterateAll()) {
            for (var punto : serie.getPointsList()) {
                suma += punto.getValue().getInt64Value();
            }
        }
        return suma;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Duration;
import java.util.List;

public class ServicioDeTriage {

    private final SenalesGcp senales;
    private final TriageDeCapas triage = new TriageDeCapas();

    public ServicioDeTriage(SenalesGcp senales) {
        this.senales = senales;
    }

    public TriageDeCapas.Informe evaluar(String urlMap, double umbralError) {
        var ventana = Duration.ofMinutes(5);
        return triage.evaluar(List.of(
            new TriageDeCapas.Chequeo("load-balancer", () -> senales.solicitudesLb(urlMap, null, ventana) > 0),
            new TriageDeCapas.Chequeo("errores-5xx", () -> TriageDeCapas.tasaDeError(
                senales.solicitudesLb(urlMap, "500", ventana), senales.solicitudesLb(urlMap, null, ventana)) < umbralError)
            // + cómputo, dependencias y cambios recientes con sus propios adaptadores
        ));
    }
}
'''
ggen.gcp('gcp/11-casos-integrados/runbook-diagnostico', 'Caso integrado · Runbook de diagnóstico',
  'Un **triage automático por capas**: recorre chequeos en orden (¿llega tráfico al LB?, tasa de 5xx de los últimos 5 minutos con `MetricServiceClient.listTimeSeries` alineando con `ALIGN_SUM` y `REDUCE_SUM`), marca la **primera capa con problema** y sugiere el runbook; si un chequeo no puede ejecutarse (permisos, red), lo reporta como DESCONOCIDO, que también es un hallazgo.',
  [],
  [('Triage (lógica pura)', TRI, True), ('Adaptador de Cloud Monitoring', SDK, True), ('Servicio', SERV, True)],
  'Triage', '/operacion/triage', 'ServicioDeTriage', 'SenalesGcp', [],
  'return new SenalesGcp(cred, proyecto);',
  [dict(n='evaluar', v='GET', p='', args=[('String', 'urlMap', 'q'), ('double', 'umbral', 'q')], ret='TriageDeCapas.Informe', call='s.evaluar(urlMap, umbral)')],
  [('Leer métricas', '`roles/monitoring.viewer` para `triage-capas`')],
  ['No tomes un error del chequeo como OK.',
   'No automatices la reversión sin aprobación humana.',
   'No olvides el retraso de las métricas (1–3 min).',
   'No expongas el triage fuera de la red interna.'])
