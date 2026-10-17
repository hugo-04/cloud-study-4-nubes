# AWS · Budgets y Cost Explorer · Uso desde Java

Desde Java, estos servicios son una **fuente de números que consultas, interpretas y publicas**: un informe de costos por equipo, una proyección de fin de mes, una alerta temprana de pico diario. Los presupuestos y avisos de AWS siguen siendo la red de seguridad; tu código aporta lo que necesita contexto de tu negocio. El núcleo común son siete piezas: **proyección de gasto**, **reparto por etiqueta** (con la cubeta «sin etiqueta»), **detector de picos diarios**, **validador de avisos**, **consulta a Cost Explorer con caché** y **consulta a Budgets**. Todo el dinero va en `BigDecimal`. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56, `costexplorer` + `budgets`).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  costos:
    cuenta: ${CUENTA_AWS}        # 12 dígitos (Budgets la pide)
    etiqueta: equipo             # etiqueta de asignación activada en Facturación
    cache-minutos: 30            # cada solicitud a la API de Cost Explorer tiene costo
```
```properties
# Quarkus (application.properties)
app.costos.cuenta=${CUENTA_AWS}
app.costos.etiqueta=equipo
app.costos.cache-minutos=30
```
Budgets y Cost Explorer son **globales**: los clientes se crean con `Region.US_EAST_1` aunque tu carga viva en otra región.

## 2. Núcleo común

### 2.1 Proyección de fin de mes
Ritmo diario (*run-rate*) proyectado al mes. Los datos de costo llegan con retraso: se cuentan los **días con datos** (normalmente hasta ayer), no el día de hoy.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.YearMonth;

public final class ProyeccionGasto {
    public enum Estado { EN_CAMINO, ATENCION, EXCEDERA, EXCEDIDO }

    /** diaDeAgotamiento: día del mes en que, a este ritmo, se alcanza el límite (null si no ocurre este mes). */
    public record Resultado(BigDecimal gastoActual, BigDecimal proyectado, BigDecimal limite,
                            BigDecimal porcentajeProyectado, Estado estado, Integer diaDeAgotamiento) {}

    private ProyeccionGasto() {}

    /** Días del mes con datos: hasta ayer (mínimo 1). */
    public static int diasConDatos(LocalDate hoy) {
        return Math.max(1, hoy.getDayOfMonth() - 1);
    }

    public static Resultado proyectar(BigDecimal gastoAcumulado, YearMonth mes, int diasConDatos, BigDecimal limite) {
        int diasMes = mes.lengthOfMonth();
        if (diasConDatos < 1 || diasConDatos > diasMes) {
            throw new IllegalArgumentException("diasConDatos fuera de rango: " + diasConDatos);
        }
        if (limite.signum() <= 0) {
            throw new IllegalArgumentException("el límite debe ser positivo");
        }
        if (gastoAcumulado.signum() < 0) {
            throw new IllegalArgumentException("gasto negativo: usa costos sin créditos o revisa el filtro");
        }
        BigDecimal diario = gastoAcumulado.divide(BigDecimal.valueOf(diasConDatos), 10, RoundingMode.HALF_EVEN);
        BigDecimal proyectado = diario.multiply(BigDecimal.valueOf(diasMes)).setScale(2, RoundingMode.HALF_EVEN);
        BigDecimal pct = proyectado.multiply(BigDecimal.valueOf(100)).divide(limite, 1, RoundingMode.HALF_EVEN);

        Estado estado;
        if (gastoAcumulado.compareTo(limite) >= 0) {
            estado = Estado.EXCEDIDO;
        } else if (pct.compareTo(BigDecimal.valueOf(100)) >= 0) {
            estado = Estado.EXCEDERA;
        } else if (pct.compareTo(BigDecimal.valueOf(80)) >= 0) {
            estado = Estado.ATENCION;
        } else {
            estado = Estado.EN_CAMINO;
        }

        Integer dia = null;
        if (estado == Estado.EXCEDERA && diario.signum() > 0) {
            int d = limite.divide(diario, 0, RoundingMode.CEILING).intValueExact();
            dia = d <= diasMes ? d : null;
        }
        return new Resultado(gastoAcumulado.setScale(2, RoundingMode.HALF_EVEN), proyectado, limite, pct, estado, dia);
    }
}
```
> Es una **orientación**: una proyección lineal se equivoca con pagos por adelantado (Reservas, Savings Plans), cobros de soporte proporcionales y picos puntuales.

### 2.2 Reparto por etiqueta
Cost Explorer devuelve las claves como `equipo$pagos`; los recursos sin la etiqueta llegan como `equipo$` (valor vacío). Se **normaliza** (sin mayúsculas ni espacios), se funden valores equivalentes y se muestra una cubeta explícita «sin etiqueta».
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;

/** Un renglón de costo: clave tal como la devuelve Cost Explorer ("equipo$pagos") y su monto. */
public record Cargo(String clave, BigDecimal monto) {}
```
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class AsignacionCostos {
    public static final String SIN_ETIQUETA = "(sin etiqueta)";

    public record Parte(String equipo, BigDecimal monto, BigDecimal porcentaje) {}

    public record Reparto(List<Parte> partes, BigDecimal total, BigDecimal sinEtiqueta, BigDecimal porcentajeSinEtiqueta) {}

    private AsignacionCostos() {}

    /** "equipo$Pagos" → "pagos"; "equipo$" → SIN_ETIQUETA. Acepta también el prefijo "user:". */
    public static String valorDe(String claveEtiqueta, String claveCostExplorer) {
        String s = claveCostExplorer == null ? "" : claveCostExplorer;
        if (s.startsWith("user:")) {
            s = s.substring("user:".length());
        }
        String prefijo = claveEtiqueta + "$";
        if (s.startsWith(prefijo)) {
            s = s.substring(prefijo.length());
        }
        s = s.trim().toLowerCase(Locale.ROOT);
        return s.isEmpty() ? SIN_ETIQUETA : s;
    }

    public static Reparto repartir(String claveEtiqueta, Collection<Cargo> cargos) {
        Map<String, BigDecimal> porValor = new LinkedHashMap<>();
        BigDecimal total = BigDecimal.ZERO;
        for (Cargo c : cargos) {
            porValor.merge(valorDe(claveEtiqueta, c.clave()), c.monto(), BigDecimal::add);
            total = total.add(c.monto());
        }
        final BigDecimal totalFinal = total;
        List<Parte> partes = new ArrayList<>();
        porValor.forEach((valor, monto) -> partes.add(new Parte(valor, monto.setScale(2, RoundingMode.HALF_EVEN), porcentaje(monto, totalFinal))));
        partes.sort(Comparator.comparing(Parte::monto).reversed().thenComparing(Parte::equipo));
        BigDecimal sin = porValor.getOrDefault(SIN_ETIQUETA, BigDecimal.ZERO).setScale(2, RoundingMode.HALF_EVEN);
        return new Reparto(List.copyOf(partes), total.setScale(2, RoundingMode.HALF_EVEN), sin, porcentaje(sin, total));
    }

    private static BigDecimal porcentaje(BigDecimal parte, BigDecimal total) {
        if (total.signum() == 0) {
            return BigDecimal.ZERO.setScale(1);
        }
        return parte.multiply(BigDecimal.valueOf(100)).divide(total, 1, RoundingMode.HALF_EVEN);
    }
}
```

### 2.3 Detector de picos diarios
Una alarma local y barata sobre la serie diaria: un día es pico si supera la **mediana** de los días previos más *k* veces la **desviación absoluta mediana** (robusta ante picos pasados) **y** el exceso supera un mínimo en dinero. Complementa —no reemplaza— a Cost Anomaly Detection.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

public final class DetectorAnomalias {
    public record Dia(LocalDate fecha, BigDecimal monto) {}

    public record Anomalia(LocalDate fecha, BigDecimal monto, BigDecimal esperado, BigDecimal exceso) {}

    private static final int VENTANA = 14;
    private static final double ESCALA_MAD = 1.4826;

    private DetectorAnomalias() {}

    /** La serie debe terminar en el último día COMPLETO (no incluyas hoy: su dato es parcial). */
    public static List<Anomalia> detectar(List<Dia> serie, double k, BigDecimal excesoMinimo, int historialMinimo) {
        if (k <= 0 || historialMinimo < 3) {
            throw new IllegalArgumentException("k debe ser positivo y el historial mínimo, al menos 3");
        }
        List<Dia> orden = new ArrayList<>(serie);
        orden.sort(Comparator.comparing(Dia::fecha));
        List<Anomalia> resultado = new ArrayList<>();
        for (int i = historialMinimo; i < orden.size(); i++) {
            int desde = Math.max(0, i - VENTANA);
            double[] previos = new double[i - desde];
            for (int j = desde; j < i; j++) {
                previos[j - desde] = orden.get(j).monto().doubleValue();
            }
            double mediana = mediana(previos);
            double[] desviaciones = new double[previos.length];
            for (int j = 0; j < previos.length; j++) {
                desviaciones[j] = Math.abs(previos[j] - mediana);
            }
            double mad = mediana(desviaciones) * ESCALA_MAD;
            double actual = orden.get(i).monto().doubleValue();
            double exceso = actual - mediana;
            if (actual > mediana + k * mad && exceso >= excesoMinimo.doubleValue()) {
                resultado.add(new Anomalia(orden.get(i).fecha(), orden.get(i).monto().setScale(2, RoundingMode.HALF_EVEN),
                        BigDecimal.valueOf(mediana).setScale(2, RoundingMode.HALF_EVEN),
                        BigDecimal.valueOf(exceso).setScale(2, RoundingMode.HALF_EVEN)));
            }
        }
        return resultado;
    }

    static double mediana(double[] valores) {
        double[] copia = valores.clone();
        Arrays.sort(copia);
        int n = copia.length;
        return n % 2 == 1 ? copia[n / 2] : (copia[n / 2 - 1] + copia[n / 2]) / 2.0;
    }
}
```

### 2.4 Validador de avisos de presupuesto
Revisa la configuración antes de crearla: errores que impiden que alguien se entere y omisiones frecuentes (sin pronóstico, sin SNS).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

public final class AvisosPresupuesto {
    public enum Tipo { ACTUAL, FORECASTED }

    public enum Nivel { ERROR, AVISO }

    public record Aviso(Tipo tipo, double umbralPorcentaje, List<String> destinos) {}

    public record Hallazgo(Nivel nivel, String mensaje) {}

    private static final Pattern CORREO = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");
    private static final Pattern SNS = Pattern.compile("^arn:aws[a-z-]*:sns:[a-z0-9-]+:\\d{12}:[A-Za-z0-9_-]{1,256}$");

    private AvisosPresupuesto() {}

    public static boolean hayErrores(List<Hallazgo> hallazgos) {
        return hallazgos.stream().anyMatch(h -> h.nivel() == Nivel.ERROR);
    }

    public static List<Hallazgo> validar(List<Aviso> avisos) {
        List<Hallazgo> r = new ArrayList<>();
        if (avisos.isEmpty()) {
            r.add(new Hallazgo(Nivel.ERROR, "El presupuesto no tiene avisos: nadie se enterará"));
            return r;
        }
        Set<String> vistos = new HashSet<>();
        boolean haySns = false;
        boolean hayPronostico = false;
        boolean hayRealCien = false;
        for (Aviso a : avisos) {
            String id = a.tipo() + "@" + a.umbralPorcentaje();
            if (!vistos.add(id)) {
                r.add(new Hallazgo(Nivel.AVISO, "Aviso duplicado: " + id));
            }
            if (a.umbralPorcentaje() <= 0) {
                r.add(new Hallazgo(Nivel.ERROR, "Umbral inválido (" + a.umbralPorcentaje() + "): debe ser mayor que 0"));
            } else if (a.umbralPorcentaje() > 200) {
                r.add(new Hallazgo(Nivel.AVISO, "Umbral muy alto (" + a.umbralPorcentaje() + " %): ¿es intencional?"));
            }
            if (a.destinos().isEmpty()) {
                r.add(new Hallazgo(Nivel.ERROR, "El aviso " + id + " no tiene destinatarios"));
            }
            for (String d : a.destinos()) {
                if (SNS.matcher(d).matches()) {
                    haySns = true;
                } else if (!CORREO.matcher(d).matches()) {
                    r.add(new Hallazgo(Nivel.ERROR, "Destino inválido (ni correo ni tópico SNS): " + d));
                }
            }
            hayPronostico |= a.tipo() == Tipo.FORECASTED;
            hayRealCien |= a.tipo() == Tipo.ACTUAL && a.umbralPorcentaje() >= 100;
        }
        if (!hayPronostico) {
            r.add(new Hallazgo(Nivel.AVISO, "Sin aviso pronosticado: te enterarás cuando ya gastaste"));
        }
        if (!hayRealCien) {
            r.add(new Hallazgo(Nivel.AVISO, "Falta un aviso real al 100 % (o más)"));
        }
        if (!haySns) {
            r.add(new Hallazgo(Nivel.AVISO, "Solo hay correos: añade un tópico SNS para poder automatizar la respuesta"));
        }
        return r;
    }
}
```

### 2.5 Consulta a Cost Explorer (con caché)
Las peticiones se construyen en funciones estáticas **compartidas** con el cliente asíncrono. La caché evita pagar la API por cada petición web.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;
import software.amazon.awssdk.services.costexplorer.CostExplorerClient;
import software.amazon.awssdk.services.costexplorer.model.DateInterval;
import software.amazon.awssdk.services.costexplorer.model.GetCostAndUsageRequest;
import software.amazon.awssdk.services.costexplorer.model.GetCostAndUsageResponse;
import software.amazon.awssdk.services.costexplorer.model.Granularity;
import software.amazon.awssdk.services.costexplorer.model.Group;
import software.amazon.awssdk.services.costexplorer.model.GroupDefinition;
import software.amazon.awssdk.services.costexplorer.model.GroupDefinitionType;
import software.amazon.awssdk.services.costexplorer.model.ResultByTime;

public final class ConsultaCostos {
    static final String METRICA = "UnblendedCost";

    private record Entrada(Instant hasta, Object valor) {}

    private final CostExplorerClient costExplorer;
    private final Clock reloj;
    private final Duration vigencia;
    private final Map<String, Entrada> cache = new ConcurrentHashMap<>();

    public ConsultaCostos(CostExplorerClient costExplorer, Clock reloj, Duration vigencia) {
        this.costExplorer = costExplorer;
        this.reloj = reloj;
        this.vigencia = vigencia;
    }

    // ---- Peticiones y mapeos (también las usa el cliente asíncrono)
    static DateInterval periodo(YearMonth mes) {
        return DateInterval.builder().start(mes.atDay(1).toString()).end(mes.plusMonths(1).atDay(1).toString()).build();
    }

    public static GetCostAndUsageRequest peticionPorEtiqueta(String claveEtiqueta, YearMonth mes, String token) {
        return GetCostAndUsageRequest.builder()
                .timePeriod(periodo(mes))
                .granularity(Granularity.MONTHLY)
                .metrics(METRICA)
                .groupBy(GroupDefinition.builder().type(GroupDefinitionType.TAG).key(claveEtiqueta).build())
                .nextPageToken(token)
                .build();
    }

    public static GetCostAndUsageRequest peticionDiaria(YearMonth mes, String token) {
        return GetCostAndUsageRequest.builder()
                .timePeriod(periodo(mes))
                .granularity(Granularity.DAILY)
                .metrics(METRICA)
                .nextPageToken(token)
                .build();
    }

    public static List<Cargo> cargosDe(GetCostAndUsageResponse r) {
        List<Cargo> cargos = new ArrayList<>();
        for (ResultByTime t : r.resultsByTime()) {
            for (Group g : t.groups()) {
                cargos.add(new Cargo(g.keys().get(0), new BigDecimal(g.metrics().get(METRICA).amount())));
            }
        }
        return cargos;
    }

    public static List<DetectorAnomalias.Dia> diasDe(GetCostAndUsageResponse r) {
        List<DetectorAnomalias.Dia> dias = new ArrayList<>();
        for (ResultByTime t : r.resultsByTime()) {
            dias.add(new DetectorAnomalias.Dia(LocalDate.parse(t.timePeriod().start().substring(0, 10)),
                    new BigDecimal(t.total().get(METRICA).amount())));
        }
        return dias;
    }

    // ---- Consultas con caché
    public List<Cargo> costoPorEtiqueta(String claveEtiqueta, YearMonth mes) {
        return conCache("etiqueta|" + claveEtiqueta + "|" + mes, () -> {
            List<Cargo> cargos = new ArrayList<>();
            String token = null;
            do {
                GetCostAndUsageResponse r = costExplorer.getCostAndUsage(peticionPorEtiqueta(claveEtiqueta, mes, token));
                cargos.addAll(cargosDe(r));
                token = r.nextPageToken();
            } while (token != null);
            return List.copyOf(cargos);
        });
    }

    public List<DetectorAnomalias.Dia> costoDiario(YearMonth mes) {
        return conCache("diario|" + mes, () -> {
            List<DetectorAnomalias.Dia> dias = new ArrayList<>();
            String token = null;
            do {
                GetCostAndUsageResponse r = costExplorer.getCostAndUsage(peticionDiaria(mes, token));
                dias.addAll(diasDe(r));
                token = r.nextPageToken();
            } while (token != null);
            return List.copyOf(dias);
        });
    }

    @SuppressWarnings("unchecked")
    private <T> T conCache(String clave, Supplier<T> carga) {
        Instant ahora = reloj.instant();
        Entrada e = cache.get(clave);
        if (e != null && ahora.isBefore(e.hasta())) {
            return (T) e.valor();
        }
        T valor = carga.get();
        cache.put(clave, new Entrada(ahora.plus(vigencia), valor));
        return valor;
    }
}
```

### 2.6 Consulta a Budgets
`calculatedSpend`, el pronóstico y el límite pueden ser `null` (presupuestos nuevos o con ajuste automático): se tratan como «sin dato», nunca como cero.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;
import software.amazon.awssdk.services.budgets.BudgetsClient;
import software.amazon.awssdk.services.budgets.model.Budget;
import software.amazon.awssdk.services.budgets.model.CalculatedSpend;
import software.amazon.awssdk.services.budgets.model.DescribeBudgetsResponse;
import software.amazon.awssdk.services.budgets.model.Spend;

public final class ConsultaPresupuestos {
    public record Estado(String nombre, String unidad, BigDecimal limite, BigDecimal actual, BigDecimal pronosticado) {
        public BigDecimal porcentajeActual() {
            if (limite == null || limite.signum() <= 0 || actual == null) {
                return null;
            }
            return actual.multiply(BigDecimal.valueOf(100)).divide(limite, 1, RoundingMode.HALF_EVEN);
        }
    }

    private final BudgetsClient budgets;

    public ConsultaPresupuestos(BudgetsClient budgets) {
        this.budgets = budgets;
    }

    public List<Estado> listar(String cuenta) {
        List<Estado> estados = new ArrayList<>();
        for (DescribeBudgetsResponse pagina : budgets.describeBudgetsPaginator(req -> req.accountId(cuenta))) {
            for (Budget presupuesto : pagina.budgets()) {
                estados.add(aEstado(presupuesto));
            }
        }
        return estados;
    }

    public static Estado aEstado(Budget b) {
        Spend limite = b.budgetLimit();
        CalculatedSpend calculado = b.calculatedSpend();
        return new Estado(b.budgetName(), limite == null ? null : limite.unit(), monto(limite),
                calculado == null ? null : monto(calculado.actualSpend()),
                calculado == null ? null : monto(calculado.forecastedSpend()));
    }

    private static BigDecimal monto(Spend s) {
        return s == null ? null : s.amount();   // en Budgets, amount() ya es BigDecimal
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.budgets.BudgetsClient;
import software.amazon.awssdk.services.costexplorer.CostExplorerClient;

@Configuration
class CostosConfig {
    @Bean(destroyMethod = "close")
    CostExplorerClient costExplorer() {
        return CostExplorerClient.builder().region(Region.US_EAST_1).build();   // servicio global
    }

    @Bean(destroyMethod = "close")
    BudgetsClient budgets() {
        return BudgetsClient.builder().region(Region.US_EAST_1).build();        // servicio global
    }

    @Bean
    ConsultaCostos consultaCostos(CostExplorerClient ce, @Value("${app.costos.cache-minutos}") long minutos) {
        return new ConsultaCostos(ce, Clock.systemUTC(), Duration.ofMinutes(minutos));
    }

    @Bean
    ConsultaPresupuestos consultaPresupuestos(BudgetsClient budgets) {
        return new ConsultaPresupuestos(budgets);
    }
}

@RestController
@RequestMapping("/costos")
class CostosController {
    private final ConsultaCostos costos;
    private final ConsultaPresupuestos presupuestos;
    private final String cuenta;
    private final String etiqueta;

    CostosController(ConsultaCostos costos, ConsultaPresupuestos presupuestos,
                     @Value("${app.costos.cuenta}") String cuenta, @Value("${app.costos.etiqueta}") String etiqueta) {
        this.costos = costos;
        this.presupuestos = presupuestos;
        this.cuenta = cuenta;
        this.etiqueta = etiqueta;
    }

    @GetMapping("/por-equipo")
    AsignacionCostos.Reparto porEquipo(@RequestParam String mes) {
        return AsignacionCostos.repartir(etiqueta, costos.costoPorEtiqueta(etiqueta, YearMonth.parse(mes)));
    }

    @GetMapping("/proyeccion")
    ProyeccionGasto.Resultado proyeccion(@RequestParam BigDecimal limite) {
        LocalDate hoy = LocalDate.now(ZoneOffset.UTC);
        YearMonth mes = YearMonth.from(hoy);
        BigDecimal gasto = costos.costoPorEtiqueta(etiqueta, mes).stream().map(Cargo::monto).reduce(BigDecimal.ZERO, BigDecimal::add);
        return ProyeccionGasto.proyectar(gasto, mes, ProyeccionGasto.diasConDatos(hoy), limite);
    }

    @GetMapping("/anomalias")
    List<DetectorAnomalias.Anomalia> anomalias(@RequestParam(defaultValue = "4") double k) {
        LocalDate hoy = LocalDate.now(ZoneOffset.UTC);
        YearMonth mes = YearMonth.from(hoy);
        List<DetectorAnomalias.Dia> serie = new ArrayList<>(costos.costoDiario(mes.minusMonths(1)));
        serie.addAll(costos.costoDiario(mes));
        serie.removeIf(d -> !d.fecha().isBefore(hoy));   // hoy es parcial: no se evalúa
        return DetectorAnomalias.detectar(serie, k, new BigDecimal("20"), 7);
    }

    @GetMapping("/presupuestos")
    List<ConsultaPresupuestos.Estado> presupuestos() {
        return presupuestos.listar(cuenta);
    }

    @ResponseStatus(HttpStatus.BAD_REQUEST)
    @ExceptionHandler({DateTimeParseException.class, IllegalArgumentException.class})
    String peticionInvalida(RuntimeException e) {
        return e.getMessage();
    }
}
```

## 4. Spring WebFlux (reactivo)
Cost Explorer pagina con `nextPageToken`: `expand` encadena páginas hasta que no haya más, sin bloquear. Budgets sí trae paginador reactivo.
```java
import java.time.YearMonth;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.budgets.BudgetsAsyncClient;
import software.amazon.awssdk.services.budgets.model.DescribeBudgetsResponse;
import software.amazon.awssdk.services.costexplorer.CostExplorerAsyncClient;
import software.amazon.awssdk.services.costexplorer.model.GetCostAndUsageResponse;

@Configuration
class CostosReactivoConfig {
    @Bean(destroyMethod = "close")
    CostExplorerAsyncClient costExplorerAsync() {
        return CostExplorerAsyncClient.builder().region(Region.US_EAST_1).build();
    }

    @Bean(destroyMethod = "close")
    BudgetsAsyncClient budgetsAsync() {
        return BudgetsAsyncClient.builder().region(Region.US_EAST_1).build();
    }
}

@RestController
@RequestMapping("/r/costos")
class CostosReactivoController {
    private final CostExplorerAsyncClient costExplorer;
    private final BudgetsAsyncClient budgets;
    private final String cuenta;
    private final String etiqueta;

    CostosReactivoController(CostExplorerAsyncClient costExplorer, BudgetsAsyncClient budgets,
                             @Value("${app.costos.cuenta}") String cuenta, @Value("${app.costos.etiqueta}") String etiqueta) {
        this.costExplorer = costExplorer;
        this.budgets = budgets;
        this.cuenta = cuenta;
        this.etiqueta = etiqueta;
    }

    @GetMapping("/por-equipo")
    Mono<AsignacionCostos.Reparto> porEquipo(@RequestParam String mes) {
        YearMonth periodo = YearMonth.parse(mes);
        return pagina(periodo, null)
                .expand(r -> r.nextPageToken() == null ? Mono.<GetCostAndUsageResponse>empty() : pagina(periodo, r.nextPageToken()))
                .concatMapIterable(ConsultaCostos::cargosDe)
                .collectList()
                .map(cargos -> AsignacionCostos.repartir(etiqueta, cargos));
    }

    private Mono<GetCostAndUsageResponse> pagina(YearMonth periodo, String token) {
        return Mono.fromFuture(() -> costExplorer.getCostAndUsage(ConsultaCostos.peticionPorEtiqueta(etiqueta, periodo, token)));
    }

    @GetMapping("/presupuestos")
    Flux<ConsultaPresupuestos.Estado> presupuestos() {
        return Flux.from(budgets.describeBudgetsPaginator(req -> req.accountId(cuenta)))
                .concatMapIterable(DescribeBudgetsResponse::budgets)
                .map(ConsultaPresupuestos::aEstado);
    }
}
```
> Aquí no hay caché: en un servicio real, pon una caché reactiva (por ejemplo `Mono.cache(Duration)` por mes) o reutiliza la del servicio imperativo.

## 5. Quarkus (imperativo)
```java
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Disposes;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.time.Clock;
import java.time.Duration;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.budgets.BudgetsAsyncClient;
import software.amazon.awssdk.services.budgets.BudgetsClient;
import software.amazon.awssdk.services.costexplorer.CostExplorerAsyncClient;
import software.amazon.awssdk.services.costexplorer.CostExplorerClient;

@ApplicationScoped
class CostosProductores {
    @Produces
    @Singleton
    CostExplorerClient costExplorer() {
        return CostExplorerClient.builder().region(Region.US_EAST_1).build();
    }

    void cerrar(@Disposes CostExplorerClient c) {
        c.close();
    }

    @Produces
    @Singleton
    CostExplorerAsyncClient costExplorerAsync() {
        return CostExplorerAsyncClient.builder().region(Region.US_EAST_1).build();
    }

    void cerrarAsync(@Disposes CostExplorerAsyncClient c) {
        c.close();
    }

    @Produces
    @Singleton
    BudgetsClient budgets() {
        return BudgetsClient.builder().region(Region.US_EAST_1).build();
    }

    void cerrarBudgets(@Disposes BudgetsClient c) {
        c.close();
    }

    @Produces
    @Singleton
    BudgetsAsyncClient budgetsAsync() {
        return BudgetsAsyncClient.builder().region(Region.US_EAST_1).build();
    }

    void cerrarBudgetsAsync(@Disposes BudgetsAsyncClient c) {
        c.close();
    }

    @Produces
    @Singleton
    ConsultaCostos consultaCostos(CostExplorerClient ce, @ConfigProperty(name = "app.costos.cache-minutos") long minutos) {
        return new ConsultaCostos(ce, Clock.systemUTC(), Duration.ofMinutes(minutos));
    }

    @Produces
    @Singleton
    ConsultaPresupuestos consultaPresupuestos(BudgetsClient budgets) {
        return new ConsultaPresupuestos(budgets);
    }
}
```
```java
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneOffset;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@Path("/costos")
@Produces(MediaType.APPLICATION_JSON)
class CostosRecurso {
    @Inject
    ConsultaCostos costos;

    @Inject
    ConsultaPresupuestos presupuestos;

    @ConfigProperty(name = "app.costos.cuenta")
    String cuenta;

    @ConfigProperty(name = "app.costos.etiqueta")
    String etiqueta;

    @GET
    @Path("/por-equipo")
    public AsignacionCostos.Reparto porEquipo(@QueryParam("mes") String mes) {
        return AsignacionCostos.repartir(etiqueta, costos.costoPorEtiqueta(etiqueta, YearMonth.parse(mes)));
    }

    @GET
    @Path("/proyeccion")
    public ProyeccionGasto.Resultado proyeccion(@QueryParam("limite") BigDecimal limite) {
        LocalDate hoy = LocalDate.now(ZoneOffset.UTC);
        YearMonth mes = YearMonth.from(hoy);
        BigDecimal gasto = costos.costoPorEtiqueta(etiqueta, mes).stream().map(Cargo::monto).reduce(BigDecimal.ZERO, BigDecimal::add);
        return ProyeccionGasto.proyectar(gasto, mes, ProyeccionGasto.diasConDatos(hoy), limite);
    }

    @GET
    @Path("/presupuestos")
    public List<ConsultaPresupuestos.Estado> presupuestos() {
        return presupuestos.listar(cuenta);
    }
}
```

## 6. Quarkus reactivo (Mutiny)
Las páginas de Cost Explorer se encadenan con `Uni` recursivo; Budgets se expone como `Multi`.
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.reactivestreams.FlowAdapters;
import software.amazon.awssdk.services.budgets.BudgetsAsyncClient;
import software.amazon.awssdk.services.budgets.model.DescribeBudgetsResponse;
import software.amazon.awssdk.services.costexplorer.CostExplorerAsyncClient;

@Path("/m/costos")
@Produces(MediaType.APPLICATION_JSON)
class CostosMutinyRecurso {
    @Inject
    CostExplorerAsyncClient costExplorer;

    @Inject
    BudgetsAsyncClient budgets;

    @ConfigProperty(name = "app.costos.cuenta")
    String cuenta;

    @ConfigProperty(name = "app.costos.etiqueta")
    String etiqueta;

    @GET
    @Path("/por-equipo")
    public Uni<AsignacionCostos.Reparto> porEquipo(@QueryParam("mes") String mes) {
        return todas(YearMonth.parse(mes), null, new ArrayList<>())
                .map(cargos -> AsignacionCostos.repartir(etiqueta, cargos));
    }

    private Uni<List<Cargo>> todas(YearMonth periodo, String token, List<Cargo> acumulado) {
        return Uni.createFrom().completionStage(() -> costExplorer.getCostAndUsage(ConsultaCostos.peticionPorEtiqueta(etiqueta, periodo, token)))
                .onItem().transformToUni(r -> {
                    acumulado.addAll(ConsultaCostos.cargosDe(r));
                    return r.nextPageToken() == null
                            ? Uni.createFrom().item(acumulado)
                            : todas(periodo, r.nextPageToken(), acumulado);
                });
    }

    @GET
    @Path("/presupuestos")
    public Multi<ConsultaPresupuestos.Estado> presupuestos() {
        return Multi.createFrom().publisher(FlowAdapters.toFlowPublisher(budgets.describeBudgetsPaginator(req -> req.accountId(cuenta))))
                .onItem().transformToIterable(DescribeBudgetsResponse::budgets)
                .map(ConsultaPresupuestos::aEstado);
    }
}
```

## 7. Permisos
Aplicación de informes: [`ejemplos/json/politica-costos-lectura.json`](ejemplos/json/politica-costos-lectura.json) — `ce:GetCostAndUsage`, `ce:GetCostForecast`, `ce:GetDimensionValues`, `ce:GetTags`, `ce:GetAnomalies` (sobre `*`: estas acciones no admiten recurso) y `budgets:ViewBudget` sobre `arn:aws:budgets::<cuenta>:budget/*`. **Solo lectura**: la aplicación no crea ni modifica presupuestos (eso es infraestructura como código). Si la consumes desde una cuenta miembro, la cuenta de administración debe permitir el acceso a Cost Explorer.

## 8. Qué NO hacer desde Java
- **No** llames a `GetCostAndUsage` por cada petición web: cada solicitud tiene costo; usa caché de minutos (§2.5).
- **No** uses `double` para dinero: `BigDecimal` (§2.1 a §2.6).
- **No** ocultes el «sin etiqueta»: es el indicador de higiene del etiquetado (§2.2).
- **No** evalúes el día de hoy en la detección de picos: su dato es parcial (§2.3).
- **No** trates un `null` de pronóstico como cero (§2.6).
- **No** tomes la proyección lineal como promesa: sirve de orientación (§2.1).
- **No** des permisos de escritura sobre presupuestos o acciones a una aplicación de consulta.
- **No** pongas la cuenta o claves en el código: configuración y credenciales por la cadena por defecto.
