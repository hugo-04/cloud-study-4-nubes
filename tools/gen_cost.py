import genlib
PRO = '''
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/** Proyección de cierre de mes por servicio con ritmo de los últimos días. Puro. */
public class ProyeccionDeGasto {

    public record Diario(LocalDate dia, String servicio, BigDecimal costo) { }

    public record Linea(String servicio, BigDecimal acumulado, BigDecimal proyectado) { }

    public record Informe(BigDecimal acumulado, BigDecimal proyectado, BigDecimal presupuesto, String nivel, List<Linea> porServicio) { }

    private final int diasDeRitmo;

    public ProyeccionDeGasto(int diasDeRitmo) {
        this.diasDeRitmo = diasDeRitmo;
    }

    /** hoy = último día con datos completos (los costos llegan con retraso). */
    public Informe proyectar(List<Diario> datos, LocalDate hoy, BigDecimal presupuesto) {
        int restantes = YearMonth.from(hoy).lengthOfMonth() - hoy.getDayOfMonth();
        Map<String, BigDecimal> acumulado = new TreeMap<>();
        Map<String, BigDecimal> reciente = new TreeMap<>();
        LocalDate desde = hoy.minusDays(diasDeRitmo - 1L);
        for (Diario d : datos) {
            if (!YearMonth.from(d.dia()).equals(YearMonth.from(hoy)) || d.dia().isAfter(hoy)) {
                continue;
            }
            acumulado.merge(d.servicio(), d.costo(), BigDecimal::add);
            if (!d.dia().isBefore(desde)) {
                reciente.merge(d.servicio(), d.costo(), BigDecimal::add);
            }
        }
        int dias = Math.min(diasDeRitmo, hoy.getDayOfMonth());
        var lineas = acumulado.entrySet().stream().map(e -> {
            BigDecimal ritmo = reciente.getOrDefault(e.getKey(), BigDecimal.ZERO).divide(BigDecimal.valueOf(dias), 6, RoundingMode.HALF_UP);
            BigDecimal proyectado = e.getValue().add(ritmo.multiply(BigDecimal.valueOf(restantes))).setScale(2, RoundingMode.HALF_UP);
            return new Linea(e.getKey(), e.getValue().setScale(2, RoundingMode.HALF_UP), proyectado);
        }).sorted((a, b) -> b.proyectado().compareTo(a.proyectado())).toList();
        BigDecimal total = lineas.stream().map(Linea::acumulado).reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal proyectado = lineas.stream().map(Linea::proyectado).reduce(BigDecimal.ZERO, BigDecimal::add);
        double pct = presupuesto.signum() == 0 ? 0 : proyectado.doubleValue() / presupuesto.doubleValue();
        String nivel = pct >= 1.0 ? "SE_PASA" : pct >= 0.8 ? "ATENCION" : "OK";
        return new Informe(total, proyectado, presupuesto, nivel, lineas);
    }
}
'''
SDK = '''
import com.oracle.bmc.usageapi.UsageapiClient;
import com.oracle.bmc.usageapi.model.RequestSummarizedUsagesDetails;
import com.oracle.bmc.usageapi.requests.RequestSummarizedUsagesRequest;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Date;
import java.util.List;

/** Adaptador del SDK: costo diario por servicio del mes en curso (Usage API, fechas en UTC a medianoche). */
public class CostosOci implements AutoCloseable {

    private final UsageapiClient cliente;
    private final String tenancyId;

    public CostosOci(UsageapiClient cliente, String tenancyId) {
        this.cliente = cliente;
        this.tenancyId = tenancyId;
    }

    public List<ProyeccionDeGasto.Diario> delMes(LocalDate hoy) {
        var desde = hoy.withDayOfMonth(1).atStartOfDay().toInstant(ZoneOffset.UTC);
        var hasta = hoy.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC);
        var det = RequestSummarizedUsagesDetails.builder().tenantId(tenancyId)
            .timeUsageStarted(Date.from(desde)).timeUsageEnded(Date.from(hasta))
            .granularity(RequestSummarizedUsagesDetails.Granularity.Daily)
            .queryType(RequestSummarizedUsagesDetails.QueryType.Cost)
            .groupBy(List.of("service")).build();
        return cliente.requestSummarizedUsages(RequestSummarizedUsagesRequest.builder()
                .requestSummarizedUsagesDetails(det).build())
            .getUsageAggregation().getItems().stream()
            .filter(u -> u.getComputedAmount() != null)
            .map(u -> new ProyeccionDeGasto.Diario(u.getTimeUsageStarted().toInstant().atZone(ZoneOffset.UTC).toLocalDate(),
                u.getService(), u.getComputedAmount()))
            .toList();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneOffset;

public class ServicioDeCostos {

    private final CostosOci costos;
    private final ProyeccionDeGasto proyeccion = new ProyeccionDeGasto(7);

    public ServicioDeCostos(CostosOci costos) {
        this.costos = costos;
    }

    public ProyeccionDeGasto.Informe proyectar(BigDecimal presupuesto) {
        LocalDate ayer = LocalDate.now(ZoneOffset.UTC).minusDays(1); // último día completo
        return proyeccion.proyectar(costos.delMes(ayer), ayer, presupuesto);
    }
}
'''
genlib.oci('oci/09-gobierno/budgets-costos', 'Gobierno · Presupuestos y costos',
  'Una **proyección de cierre de mes por servicio**: trae el costo diario agrupado por servicio con `UsageapiClient.requestSummarizedUsages` (fechas a medianoche UTC) y proyecta el cierre con el ritmo de los últimos 7 días, marcando OK/ATENCIÓN/SE_PASA contra el presupuesto. Complementa las alertas de presupuesto mostrando **qué** servicio empuja el gasto.',
  [('costos.tenancy', 'ocid1.tenancy.oc1..aaaa')],
  [('Proyección (lógica pura)', PRO, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Costos', '/gobierno/costos', 'ServicioDeCostos', 'CostosOci',
  ['import com.oracle.bmc.usageapi.UsageapiClient;'],
  'return new CostosOci(UsageapiClient.builder().region(Region.fromRegionId(region)).build(auth), tenancy);',
  [dict(n='proyectar', v='GET', p='/proyeccion', args=[('java.math.BigDecimal', 'presupuesto', 'q')], ret='ProyeccionDeGasto.Informe', call='s.proyectar(presupuesto)')],
  [('Consultar la Usage API', '`Allow group finanzas-automatizacion to read usage-reports in tenancy`')],
  ['No uses horas que no sean medianoche UTC en consultas diarias.',
   'No proyectes con el día de hoy (incompleto): usa ayer.',
   'No confundas costo calculado con factura (créditos, impuestos).',
   'No expongas el informe a todos: revela la arquitectura.'])
