# Azure · Cost Management · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3, `azure-core` 1.60, `azure-resourcemanager-costmanagement` 1.0.0, `azure-resourcemanager-consumption` 1.0.0, `azure-resourcemanager-resourcegraph` 1.1.0, `azure-resourcemanager-compute` 2.55**. Verifica las vigentes.

## Qué paquetes usar (y por qué son dos)

Cost Management tiene **dos familias de operaciones** y cada una vive en su propio paquete estable:

| Necesidad | Paquete | Clase de entrada |
|---|---|---|
| **Consultar** costos (por etiqueta, por día, por grupo de recursos), **pronóstico**, alertas, exportaciones, vistas | `azure-resourcemanager-costmanagement` | `CostManagementManager` → `queries()`, `forecasts()`, `exports()`, `alerts()` |
| **Presupuestos** (crear, leer gasto actual y pronosticado) | `azure-resourcemanager-consumption` | `ConsumptionManager` → `budgets()` |
| **Cobertura de etiquetas** (cuántos recursos no tienen dueño) | `azure-resourcemanager-resourcegraph` | `ResourceGraphManager` |
| **Respuesta automática** (apagar lo etiquetado cuando el presupuesto se agota) | `azure-resourcemanager-compute` | `ComputeManager` → `virtualMachines()` |

Qué hace tu aplicación Java con los costos (casos de **plataforma / FinOps**, no de negocio):

| Caso | Qué haces desde Java |
|---|---|
| **Panel de gasto por equipo** | Costo del mes por etiqueta `owner` o `cost-center`, con caché |
| **Proyección a fin de mes** | Gasto acumulado + pronóstico de los días restantes, comparado con el presupuesto |
| **Presupuestos como código** | Crear el presupuesto estándar (50/80/100 % reales + 110 % pronosticado) al dar de alta una suscripción |
| **Auditoría de presupuestos** | Detectar presupuestos que no avisan (sin notificaciones, sin pronóstico, ya superados) |
| **Cobertura de etiquetas** | Porcentaje de recursos con `owner`; métrica para alertar |
| **Freno de laboratorios** | Recibir el aviso del 100 % y apagar (desasignar) las VM marcadas `auto-apagar=si` |

> Son SDK **de administración** (plano de control): cientos de milisegundos por llamada, cuotas de limitación y **datos con 8–24 horas de retraso**. **No van en el camino caliente** de una API de clientes: se consultan en segundo plano, se **cachean** y se exponen como métricas.

```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-costmanagement</artifactId><version>1.0.0</version></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-consumption</artifactId><version>1.0.0</version></dependency>
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-resourcegraph</artifactId><version>1.1.0</version></dependency>
<!-- solo si vas a implementar el freno automático -->
<dependency><groupId>com.azure.resourcemanager</groupId><artifactId>azure-resourcemanager-compute</artifactId><version>2.55.0</version></dependency>
```

**Permisos de las identidades** (identidades administradas, sin claves; **una por función**):

| Operación | Rol mínimo | Alcance |
|---|---|---|
| Consultar costos y pronóstico | *Cost Management Reader* (o *Reader*) | El alcance consultado |
| Leer presupuestos | *Cost Management Reader* (o *Reader*) | El alcance del presupuesto |
| Crear o actualizar presupuestos | *Cost Management Contributor* (o *Contributor*) | El alcance del presupuesto |
| Resource Graph (cobertura de etiquetas) | *Reader* | Las suscripciones a revisar |
| Freno de laboratorios | Rol **personalizado** con `Microsoft.Compute/virtualMachines/read` y `Microsoft.Compute/virtualMachines/deallocate/action` | **Solo** el grupo de recursos de Sandbox |

> La identidad que **apaga máquinas** nunca debe ser la que consulta costos ni la que crea presupuestos. Y no le des *Contributor*: si el webhook se compromete, el daño queda limitado a apagar VM de un solo grupo de recursos.

## 1. Leer resultados por nombre de columna (nunca por posición)

La API de consultas devuelve una **tabla**: una lista de columnas y una lista de filas (cada fila, una lista de valores sueltos). Si lees por posición, el día que Azure añada o reordene una columna tu panel mostrará basura sin avisar. Estas clases (sin ninguna dependencia de marcos) leen **por nombre** y toleran los nombres alternativos de la columna de costo (`Cost`, `PreTaxCost`, `CostUSD`, `PreTaxCostUSD`, según el tipo de contrato).

Además: la fecha de uso (`UsageDate`) llega como **número `AAAAMMDD`** (por ejemplo `20261016`) y los números pueden llegar como entero o decimal según el valor; `TablaDeCostos` normaliza ambos casos, y `CacheConTiempo` evita llamar a la API en cada solicitud.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.costmanagement.models.ForecastResult;
import com.azure.resourcemanager.costmanagement.models.QueryResult;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;
import java.util.regex.Pattern;

/** Costo del mes para un valor de etiqueta (por ejemplo owner = "ana"). */
record CostoPorValor(String valor, BigDecimal monto, String moneda) { }

/** Costo de un día para un grupo de recursos. */
record CostoDiario(LocalDate dia, String grupo, BigDecimal monto, String moneda) { }

/** Gasto acumulado del mes más lo que se espera gastar en los días que faltan. */
record Proyeccion(BigDecimal acumulado, BigDecimal restante, String moneda) {

    BigDecimal totalDelMes() {
        return acumulado.add(restante);
    }
}

/** Una tabla de resultados de la API de costos, leída por nombre de columna. */
final class TablaDeCostos {

    private static final DateTimeFormatter AAAAMMDD = DateTimeFormatter.BASIC_ISO_DATE;

    private final List<String> columnas;
    private final List<List<Object>> filas;

    TablaDeCostos(List<String> columnas, List<List<Object>> filas) {
        this.columnas = columnas;
        this.filas = filas;
    }

    static TablaDeCostos de(QueryResult resultado) {
        return new TablaDeCostos(
                resultado.columns() == null ? List.of() : resultado.columns().stream().map(c -> c.name()).toList(),
                resultado.rows() == null ? List.of() : resultado.rows());
    }

    static TablaDeCostos de(ForecastResult resultado) {
        return new TablaDeCostos(
                resultado.columns() == null ? List.of() : resultado.columns().stream().map(c -> c.name()).toList(),
                resultado.rows() == null ? List.of() : resultado.rows());
    }

    int filas() {
        return filas.size();
    }

    /** Valor de la primera columna que exista con alguno de esos nombres (sin distinguir mayúsculas). */
    Object valor(int fila, String... nombres) {
        for (String nombre : nombres) {
            for (int i = 0; i < columnas.size(); i++) {
                if (columnas.get(i).equalsIgnoreCase(nombre)) {
                    List<Object> f = filas.get(fila);
                    return i < f.size() ? f.get(i) : null;
                }
            }
        }
        return null;
    }

    String texto(int fila, String... nombres) {
        Object v = valor(fila, nombres);
        return v == null ? "" : v.toString();
    }

    BigDecimal decimal(int fila, String... nombres) {
        Object v = valor(fila, nombres);
        if (v == null) {
            return BigDecimal.ZERO;
        }
        try {
            return new BigDecimal(v.toString().trim());
        } catch (NumberFormatException e) {
            throw new IllegalStateException("La columna " + String.join("/", nombres) + " no es numérica: " + v, e);
        }
    }

    /** La fecha llega como número AAAAMMDD (20261016) o, a veces, como texto ISO. */
    LocalDate fecha(int fila, String... nombres) {
        Object bruto = valor(fila, nombres);
        try {
            if (bruto instanceof Number n) {
                return LocalDate.parse(Long.toString(new BigDecimal(n.toString()).longValue()), AAAAMMDD);
            }
            String texto = bruto == null ? "" : bruto.toString().trim();
            return texto.matches("\\d{8}") ? LocalDate.parse(texto, AAAAMMDD) : LocalDate.parse(texto.substring(0, 10));
        } catch (DateTimeParseException | StringIndexOutOfBoundsException e) {
            throw new IllegalStateException("Fecha no reconocida en " + String.join("/", nombres) + ": " + bruto, e);
        }
    }
}

/** Caché sencilla con vida limitada. Los datos de costo se actualizan cada 8–24 h: no hace falta más fresco. */
final class CacheConTiempo<K, V> {

    private record Entrada<V>(V valor, Instant hasta) { }

    private final Map<K, Entrada<V>> entradas = new ConcurrentHashMap<>();
    private final Duration vida;
    private final Clock reloj;

    CacheConTiempo(Duration vida, Clock reloj) {
        this.vida = vida;
        this.reloj = reloj;
    }

    V obtener(K clave, Supplier<V> cargador) {
        Instant ahora = reloj.instant();
        Entrada<V> actual = entradas.get(clave);
        if (actual != null && ahora.isBefore(actual.hasta())) {
            return actual.valor();
        }
        V nuevo = cargador.get();           // si falla, la excepción sale y no se guarda nada
        entradas.put(clave, new Entrada<>(nuevo, ahora.plus(vida)));
        return nuevo;
    }
}

/** Valida lo que va dentro de consultas y rutas: nada de texto libre llegando a Azure. */
final class Validaciones {

    private static final Pattern ETIQUETA = Pattern.compile("[A-Za-z0-9_.-]{1,64}");
    private static final Pattern ALCANCE = Pattern.compile(
            "/subscriptions/[0-9a-fA-F-]{36}(/resourceGroups/[\\w.()-]{1,90})?"
                    + "|/providers/Microsoft\\.Management/managementGroups/[\\w.()-]{1,90}");

    private Validaciones() { }

    static String etiqueta(String valor) {
        if (valor == null || !ETIQUETA.matcher(valor).matches()) {
            throw new IllegalArgumentException("Nombre de etiqueta no válido: use letras, números, punto, guion y guion bajo (máx. 64)");
        }
        return valor;
    }

    static String alcance(String valor) {
        if (valor == null || !ALCANCE.matcher(valor).matches()) {
            throw new IllegalArgumentException("Alcance no válido: /subscriptions/{id}[/resourceGroups/{nombre}] o /providers/Microsoft.Management/managementGroups/{id}");
        }
        return valor;
    }

    /** Los SDK de costos y consumo ya anteponen la barra en la ruta: el alcance se les pasa SIN la barra inicial. */
    static String paraElSdk(String alcanceValidado) {
        return alcanceValidado.startsWith("/") ? alcanceValidado.substring(1) : alcanceValidado;
    }
}
```

## 2. Consultas de costo y pronóstico

`ConsultasDeCosto` arma las consultas de las tres preguntas más comunes de FinOps:

- **¿Cuánto lleva cada equipo este mes?** → agrupar por etiqueta (`TagKey`).
- **¿Cómo fue el gasto día a día en cada grupo de recursos?** → granularidad diaria y agrupar por dimensión (`ResourceGroupName`).
- **¿Cómo cerraremos el mes?** → acumulado + pronóstico de los días que faltan.

Detalles que importan:

- El **alcance** (`/subscriptions/{id}`, un grupo de recursos o un grupo de administración) **no viene del cliente HTTP**: se valida con `Validaciones.alcance` y sale de la configuración.
- La API **pagina**. Si `nextLink` viene con valor, el resultado está **incompleto**; el SDK no lo sigue por ti en estas operaciones. Por eso se lanza un error claro: acota la consulta (menos agrupaciones, periodo más corto) o usa una **exportación** para volúmenes grandes.
- La proyección es una **estimación**, no contabilidad: el acumulado sufre el retraso de 8–24 h y el pronóstico necesita historial. Úsala para decidir *a mitad de mes*, no para facturar.
- Con granularidad omitida la API devuelve **totales**; con `DAILY`, una fila por día.
- **El alcance se pasa al SDK sin la barra inicial** (`subscriptions/{id}`, no `/subscriptions/{id}`): estos paquetes ya anteponen la barra al armar la ruta y, si la repites, la solicitud sale con `//subscriptions/…`. Los ejemplos oficiales del SDK lo hacen así; `Validaciones.paraElSdk` lo centraliza.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.costmanagement.CostManagementManager;
import com.azure.resourcemanager.costmanagement.models.ExportType;
import com.azure.resourcemanager.costmanagement.models.ForecastAggregation;
import com.azure.resourcemanager.costmanagement.models.ForecastDataset;
import com.azure.resourcemanager.costmanagement.models.ForecastDefinition;
import com.azure.resourcemanager.costmanagement.models.ForecastTimePeriod;
import com.azure.resourcemanager.costmanagement.models.ForecastTimeframe;
import com.azure.resourcemanager.costmanagement.models.ForecastType;
import com.azure.resourcemanager.costmanagement.models.FunctionName;
import com.azure.resourcemanager.costmanagement.models.FunctionType;
import com.azure.resourcemanager.costmanagement.models.GranularityType;
import com.azure.resourcemanager.costmanagement.models.QueryAggregation;
import com.azure.resourcemanager.costmanagement.models.QueryColumnType;
import com.azure.resourcemanager.costmanagement.models.QueryDataset;
import com.azure.resourcemanager.costmanagement.models.QueryDefinition;
import com.azure.resourcemanager.costmanagement.models.QueryGrouping;
import com.azure.resourcemanager.costmanagement.models.QueryTimePeriod;
import com.azure.resourcemanager.costmanagement.models.TimeframeType;

import java.time.ZoneOffset;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.Comparator;

final class ConsultasDeCosto {

    private static final String[] COSTO = {"Cost", "PreTaxCost", "CostUSD", "PreTaxCostUSD"};

    private final CostManagementManager costos;
    private final Clock reloj;
    private final CacheConTiempo<String, Object> cache;

    ConsultasDeCosto(CostManagementManager costos, Clock reloj, Duration vidaDeLaCache) {
        this.costos = costos;
        this.reloj = reloj;
        this.cache = new CacheConTiempo<>(vidaDeLaCache, reloj);
    }

    /** Costo real del mes en curso agrupado por el valor de una etiqueta, de mayor a menor. */
    List<CostoPorValor> mesPorEtiqueta(String alcance, String etiqueta) {
        String ambito = Validaciones.alcance(alcance);
        String clave = Validaciones.etiqueta(etiqueta);
        return cacheado("etiqueta|" + ambito + "|" + clave, () -> {
            QueryResult resultado = costos.queries().usage(Validaciones.paraElSdk(ambito), new QueryDefinition()
                    .withType(ExportType.ACTUAL_COST)
                    .withTimeframe(TimeframeType.MONTH_TO_DATE)
                    .withDataset(new QueryDataset()
                            .withAggregation(sumaDelCosto())
                            .withGrouping(List.of(new QueryGrouping().withType(QueryColumnType.TAG_KEY).withName(clave)))));
            exigirCompleto(resultado.nextLink());
            TablaDeCostos tabla = TablaDeCostos.de(resultado);
            List<CostoPorValor> salida = new ArrayList<>();
            for (int i = 0; i < tabla.filas(); i++) {
                String valor = tabla.texto(i, "TagValue", clave).trim();
                salida.add(new CostoPorValor(valor.isEmpty() ? "(sin etiqueta)" : valor,
                        tabla.decimal(i, COSTO), tabla.texto(i, "Currency")));
            }
            salida.sort(Comparator.comparing(CostoPorValor::monto).reversed());
            return List.copyOf(salida);
        });
    }

    /** Costo real día a día por grupo de recursos en un rango de fechas (acótalo: rangos enormes se cortan). */
    List<CostoDiario> diarioPorGrupoDeRecursos(String alcance, LocalDate desde, LocalDate hasta) {
        String ambito = Validaciones.alcance(alcance);
        if (hasta.isBefore(desde)) {
            throw new IllegalArgumentException("El rango está al revés: hasta es anterior a desde");
        }
        return cacheado("diario|" + ambito + "|" + desde + "|" + hasta, () -> {
            QueryResult resultado = costos.queries().usage(Validaciones.paraElSdk(ambito), new QueryDefinition()
                    .withType(ExportType.ACTUAL_COST)
                    .withTimeframe(TimeframeType.CUSTOM)
                    .withTimePeriod(new QueryTimePeriod()
                            .withFrom(desde.atStartOfDay().atOffset(ZoneOffset.UTC))
                            .withTo(hasta.atTime(23, 59, 59).atOffset(ZoneOffset.UTC)))
                    .withDataset(new QueryDataset()
                            .withGranularity(GranularityType.DAILY)
                            .withAggregation(sumaDelCosto())
                            .withGrouping(List.of(new QueryGrouping().withType(QueryColumnType.DIMENSION).withName("ResourceGroupName")))));
            exigirCompleto(resultado.nextLink());
            TablaDeCostos tabla = TablaDeCostos.de(resultado);
            List<CostoDiario> salida = new ArrayList<>();
            for (int i = 0; i < tabla.filas(); i++) {
                salida.add(new CostoDiario(tabla.fecha(i, "UsageDate"), tabla.texto(i, "ResourceGroupName", "ResourceGroup"),
                        tabla.decimal(i, COSTO), tabla.texto(i, "Currency")));
            }
            salida.sort(Comparator.comparing(CostoDiario::dia).thenComparing(CostoDiario::grupo));
            return List.copyOf(salida);
        });
    }

    /** Acumulado del mes + pronóstico de lo que falta (desde hoy hasta el último día del mes). */
    Proyeccion proyeccionDeFinDeMes(String alcance) {
        String ambito = Validaciones.alcance(alcance);
        return cacheado("proyeccion|" + ambito, () -> {
            QueryResult acumulado = costos.queries().usage(Validaciones.paraElSdk(ambito), new QueryDefinition()
                    .withType(ExportType.ACTUAL_COST)
                    .withTimeframe(TimeframeType.MONTH_TO_DATE)
                    .withDataset(new QueryDataset().withAggregation(sumaDelCosto())));
            exigirCompleto(acumulado.nextLink());
            TablaDeCostos hasta = TablaDeCostos.de(acumulado);
            BigDecimal gastado = BigDecimal.ZERO;
            String moneda = "";
            for (int i = 0; i < hasta.filas(); i++) {
                gastado = gastado.add(hasta.decimal(i, COSTO));
                moneda = moneda.isEmpty() ? hasta.texto(i, "Currency") : moneda;
            }

            LocalDate hoy = LocalDate.now(reloj);
            LocalDate ultimo = hoy.with(TemporalAdjusters.lastDayOfMonth());
            ForecastResult pronostico = costos.forecasts().usage(Validaciones.paraElSdk(ambito), new ForecastDefinition()
                    .withType(ForecastType.ACTUAL_COST)
                    .withTimeframe(ForecastTimeframe.CUSTOM)
                    .withTimePeriod(new ForecastTimePeriod()
                            .withFrom(hoy.atStartOfDay().atOffset(ZoneOffset.UTC))
                            .withTo(ultimo.atTime(23, 59, 59).atOffset(ZoneOffset.UTC)))
                    .withDataset(new ForecastDataset()
                            .withGranularity(GranularityType.DAILY)
                            .withAggregation(Map.of("totalCost",
                                    new ForecastAggregation().withName(FunctionName.COST).withFunction(FunctionType.SUM))))
                    .withIncludeActualCost(false)
                    .withIncludeFreshPartialCost(false));
            exigirCompleto(pronostico.nextLink());
            TablaDeCostos futuro = TablaDeCostos.de(pronostico);
            BigDecimal restante = BigDecimal.ZERO;
            for (int i = 0; i < futuro.filas(); i++) {
                restante = restante.add(futuro.decimal(i, COSTO));
                moneda = moneda.isEmpty() ? futuro.texto(i, "Currency") : moneda;
            }
            return new Proyeccion(gastado, restante, moneda);
        });
    }

    private static Map<String, QueryAggregation> sumaDelCosto() {
        return Map.of("totalCost", new QueryAggregation().withName("Cost").withFunction(FunctionType.SUM));
    }

    private static void exigirCompleto(String siguiente) {
        if (siguiente != null && !siguiente.isBlank()) {
            throw new IllegalStateException("La API devolvió una página parcial (nextLink): acota la consulta o usa una exportación");
        }
    }

    @SuppressWarnings("unchecked")
    private <T> T cacheado(String clave, Supplier<T> cargador) {
        return (T) cache.obtener(clave, (Supplier<Object>) cargador::get);
    }
}
```

## 3. Presupuestos como código (y auditoría de los que ya existen)

Recordatorio del [README](README.md#5-cómo-se-usa): un presupuesto **sin notificaciones es decorativo** y `az consumption budget create` no permite definirlas. Desde Java sí (`withNotifications`). Crear es un `PUT`: **repetirlo actualiza** el mismo presupuesto, así que el alta es idempotente.

`ReglasDePresupuesto` es una **función pura**: valida la solicitud (límites documentados de 5 umbrales y 5 correos, grupos de acciones solo en suscripción y grupo de recursos) y audita presupuestos existentes. Es lo más fácil de probar y lo que evita la mayoría de los errores de ARM.

La fecha de inicio es el **primer día de un mes (UTC)**. No se envía fecha de fin: según la especificación de la API, sin fecha de fin el servicio asume una larga (10 años desde el inicio; verifícalo en la versión que uses). Si pones una fecha de fin cercana, el presupuesto **deja de existir** ese día y nadie se entera.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.core.management.exception.ManagementException;
import com.azure.resourcemanager.consumption.ConsumptionManager;
import com.azure.resourcemanager.consumption.models.Budget;
import com.azure.resourcemanager.consumption.models.BudgetTimePeriod;
import com.azure.resourcemanager.consumption.models.CategoryType;
import com.azure.resourcemanager.consumption.models.Notification;
import com.azure.resourcemanager.consumption.models.OperatorType;
import com.azure.resourcemanager.consumption.models.ThresholdType;
import com.azure.resourcemanager.consumption.models.TimeGrainType;

import java.time.YearMonth;
import java.util.LinkedHashMap;
import java.util.Optional;

/** Un umbral: porcentaje del presupuesto y si se mide sobre el gasto real o el pronosticado. */
record Aviso(int porcentaje, boolean pronosticado) {

    String clave() {
        return (pronosticado ? "Forecasted" : "Actual") + "_GreaterThan_" + porcentaje + "_Percent";
    }
}

/** Lo que pide el equipo de plataforma al dar de alta una suscripción. */
record SolicitudDePresupuesto(String alcance, String nombre, BigDecimal monto, YearMonth desde,
                              List<String> correos, List<String> gruposDeAcciones) { }

/** Una notificación tal como quedó configurada en Azure. */
record AvisoConfigurado(String clave, boolean activo, boolean pronosticado, BigDecimal umbral,
                        int correos, int gruposDeAcciones) { }

record EstadoDePresupuesto(String nombre, BigDecimal monto, BigDecimal gastoActual, BigDecimal pronostico,
                           List<AvisoConfigurado> avisos) { }

record HallazgoDePresupuesto(String presupuesto, String regla, String detalle) { }

final class ReglasDePresupuesto {

    static final int MAX_AVISOS = 5;
    static final int MAX_CORREOS = 5;
    static final int ACCION_DESDE_EL_PORCENTAJE = 100;

    private ReglasDePresupuesto() { }

    /** El estándar de ModaLima: 50 % y 80 % reales, 100 % real (con acción) y 110 % pronosticado. */
    static List<Aviso> avisosEstandar() {
        return List.of(new Aviso(50, false), new Aviso(80, false), new Aviso(100, false), new Aviso(110, true));
    }

    static void validar(SolicitudDePresupuesto s, List<Aviso> avisos) {
        Validaciones.alcance(s.alcance());
        if (s.nombre() == null || s.nombre().isBlank()) {
            throw new IllegalArgumentException("El presupuesto necesita un nombre");
        }
        if (s.monto() == null || s.monto().signum() <= 0) {
            throw new IllegalArgumentException("El monto debe ser mayor que cero");
        }
        if (s.correos() == null || s.correos().isEmpty() || s.correos().size() > MAX_CORREOS
                || s.correos().stream().anyMatch(c -> c == null || !c.contains("@"))) {
            throw new IllegalArgumentException("Indique entre 1 y " + MAX_CORREOS + " correos válidos");
        }
        if (avisos.isEmpty() || avisos.size() > MAX_AVISOS) {
            throw new IllegalArgumentException("Un presupuesto admite entre 1 y " + MAX_AVISOS + " umbrales");
        }
        if (avisos.stream().anyMatch(a -> a.porcentaje() < 1 || a.porcentaje() > 1000)) {
            throw new IllegalArgumentException("Los umbrales deben estar entre 1 % y 1000 %");
        }
        boolean esGrupoDeAdministracion = s.alcance().contains("/managementGroups/");
        if (esGrupoDeAdministracion && s.gruposDeAcciones() != null && !s.gruposDeAcciones().isEmpty()) {
            throw new IllegalArgumentException(
                    "Los grupos de acciones solo funcionan en suscripción y grupo de recursos: en un grupo de administración solo hay correo");
        }
    }

    /** Presupuestos que existen pero que no cumplen su misión. */
    static List<HallazgoDePresupuesto> auditar(List<EstadoDePresupuesto> presupuestos) {
        List<HallazgoDePresupuesto> hallazgos = new ArrayList<>();
        for (EstadoDePresupuesto p : presupuestos) {
            List<AvisoConfigurado> activos = p.avisos().stream().filter(AvisoConfigurado::activo).toList();
            if (activos.isEmpty()) {
                hallazgos.add(new HallazgoDePresupuesto(p.nombre(), "SIN_AVISOS",
                        "No tiene ninguna notificación activa: no avisará nunca"));
                continue;
            }
            if (activos.stream().noneMatch(AvisoConfigurado::pronosticado)) {
                hallazgos.add(new HallazgoDePresupuesto(p.nombre(), "SIN_PRONOSTICO",
                        "Solo avisa con gasto real: te enteras cuando ya pasó"));
            }
            if (activos.stream().anyMatch(a -> a.correos() == 0 && a.gruposDeAcciones() == 0)) {
                hallazgos.add(new HallazgoDePresupuesto(p.nombre(), "SIN_DESTINATARIOS",
                        "Hay umbrales sin correo ni grupo de acciones"));
            }
            if (p.monto().signum() > 0 && p.gastoActual().compareTo(p.monto()) >= 0) {
                hallazgos.add(new HallazgoDePresupuesto(p.nombre(), "SUPERADO",
                        "El gasto actual ya alcanzó o superó el monto del presupuesto"));
            }
        }
        return hallazgos;
    }
}

final class PresupuestosServicio {

    private final ConsumptionManager consumo;

    PresupuestosServicio(ConsumptionManager consumo) {
        this.consumo = consumo;
    }

    /** Crea (o actualiza) el presupuesto mensual estándar con sus notificaciones. */
    EstadoDePresupuesto crearMensual(SolicitudDePresupuesto solicitud) {
        List<Aviso> avisos = ReglasDePresupuesto.avisosEstandar();
        ReglasDePresupuesto.validar(solicitud, avisos);

        Map<String, Notification> notificaciones = new LinkedHashMap<>();
        for (Aviso aviso : avisos) {
            Notification notificacion = new Notification()
                    .withEnabled(true)
                    .withOperator(OperatorType.GREATER_THAN)
                    .withThreshold(BigDecimal.valueOf(aviso.porcentaje()))
                    .withThresholdType(aviso.pronosticado() ? ThresholdType.FORECASTED : ThresholdType.ACTUAL)
                    .withContactEmails(solicitud.correos());
            boolean llevaAccion = !aviso.pronosticado() && aviso.porcentaje() >= ReglasDePresupuesto.ACCION_DESDE_EL_PORCENTAJE
                    && solicitud.gruposDeAcciones() != null && !solicitud.gruposDeAcciones().isEmpty();
            if (llevaAccion) {
                notificacion = notificacion.withContactGroups(solicitud.gruposDeAcciones());
            }
            notificaciones.put(aviso.clave(), notificacion);
        }

        Budget creado = consumo.budgets().define(solicitud.nombre())
                .withExistingScope(Validaciones.paraElSdk(solicitud.alcance()))
                .withCategory(CategoryType.COST)
                .withAmount(solicitud.monto())
                .withTimeGrain(TimeGrainType.MONTHLY)
                .withTimePeriod(new BudgetTimePeriod()
                        .withStartDate(solicitud.desde().atDay(1).atStartOfDay().atOffset(ZoneOffset.UTC)))
                .withNotifications(notificaciones)
                .create();
        return aEstado(creado);
    }

    List<EstadoDePresupuesto> listar(String alcance) {
        List<EstadoDePresupuesto> estados = new ArrayList<>();
        consumo.budgets().list(Validaciones.paraElSdk(Validaciones.alcance(alcance))).forEach(b -> estados.add(aEstado(b)));
        return estados;
    }

    Optional<EstadoDePresupuesto> porNombre(String alcance, String nombre) {
        try {
            return Optional.of(aEstado(consumo.budgets().get(Validaciones.paraElSdk(Validaciones.alcance(alcance)), nombre)));
        } catch (ManagementException e) {
            if (e.getResponse() != null && e.getResponse().getStatusCode() == 404) {
                return Optional.empty();
            }
            throw e;
        }
    }

    private static EstadoDePresupuesto aEstado(Budget b) {
        List<AvisoConfigurado> avisos = new ArrayList<>();
        if (b.notifications() != null) {
            b.notifications().forEach((clave, n) -> avisos.add(new AvisoConfigurado(
                    clave, n.enabled(), ThresholdType.FORECASTED.equals(n.thresholdType()), n.threshold(),
                    n.contactEmails() == null ? 0 : n.contactEmails().size(),
                    n.contactGroups() == null ? 0 : n.contactGroups().size())));
        }
        return new EstadoDePresupuesto(b.name(),
                b.amount() == null ? BigDecimal.ZERO : b.amount(),
                b.currentSpend() == null || b.currentSpend().amount() == null ? BigDecimal.ZERO : b.currentSpend().amount(),
                b.forecastSpend() == null || b.forecastSpend().amount() == null ? BigDecimal.ZERO : b.forecastSpend().amount(),
                List.copyOf(avisos));
    }
}
```

## 4. Evaluar el estado del gasto (función pura)

La misma regla que usan los umbrales del presupuesto, pero como código que tu aplicación puede consultar: ¿vamos **bien**, hay que **prestar atención** o es **crítico**? Es una función pura, sin Azure: se prueba en milisegundos.

| Nivel | Condición (sobre el presupuesto mensual) |
|---|---|
| `NORMAL` | Acumulado < 80 % **y** proyección < 100 % |
| `ATENCION` | Acumulado ≥ 80 % **o** proyección ≥ 100 % |
| `CRITICO` | Acumulado ≥ 100 % **o** proyección ≥ 110 % |

```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.math.RoundingMode;

enum Nivel { NORMAL, ATENCION, CRITICO }

record EstadoDeGasto(BigDecimal acumulado, BigDecimal proyeccion, BigDecimal presupuesto, String moneda, Nivel nivel) {

    BigDecimal porcentajeAcumulado() {
        return acumulado.multiply(BigDecimal.valueOf(100)).divide(presupuesto, 1, RoundingMode.HALF_UP);
    }

    BigDecimal porcentajeProyectado() {
        return proyeccion.multiply(BigDecimal.valueOf(100)).divide(presupuesto, 1, RoundingMode.HALF_UP);
    }
}

final class EvaluadorDeGasto {

    private static final BigDecimal OCHENTA = new BigDecimal("0.80");
    private static final BigDecimal CIENTO_DIEZ = new BigDecimal("1.10");

    private EvaluadorDeGasto() { }

    static EstadoDeGasto evaluar(BigDecimal acumulado, BigDecimal proyeccion, BigDecimal presupuesto, String moneda) {
        if (presupuesto == null || presupuesto.signum() <= 0) {
            throw new IllegalArgumentException("El presupuesto debe ser mayor que cero");
        }
        Nivel nivel = Nivel.NORMAL;
        if (acumulado.compareTo(presupuesto.multiply(OCHENTA)) >= 0 || proyeccion.compareTo(presupuesto) >= 0) {
            nivel = Nivel.ATENCION;
        }
        if (acumulado.compareTo(presupuesto) >= 0 || proyeccion.compareTo(presupuesto.multiply(CIENTO_DIEZ)) >= 0) {
            nivel = Nivel.CRITICO;
        }
        return new EstadoDeGasto(acumulado, proyeccion, presupuesto, moneda, nivel);
    }
}
```

## 5. Cobertura de etiquetas con Resource Graph

Sin etiqueta `owner` no hay reparto de costos. Esta clase cuenta cuántos recursos **no** la tienen (misma idea que las consultas de [`ejemplos/kql/kql-costos.md`](ejemplos/kql/kql-costos.md)). El nombre de la etiqueta se **valida** antes de entrar en el texto de la consulta.

Límite honesto: Resource Graph (`resources`) solo ve **recursos**, no grupos de recursos ni suscripciones, y algunos tipos de recurso no admiten etiquetas. Un 100 % real puede ser inalcanzable; fija una meta realista (por ejemplo, 95 %).

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.resourcemanager.resourcegraph.ResourceGraphManager;
import com.azure.resourcemanager.resourcegraph.models.QueryRequest;
import com.azure.resourcemanager.resourcegraph.models.QueryRequestOptions;
import com.azure.resourcemanager.resourcegraph.models.QueryResponse;
import com.azure.resourcemanager.resourcegraph.models.ResultFormat;

record Cobertura(String etiqueta, long total, long sinEtiqueta) {

    double porcentajeCubierto() {
        return total == 0 ? 100.0 : 100.0 * (total - sinEtiqueta) / total;
    }
}

final class CoberturaDeEtiquetas {

    private final ResourceGraphManager grafo;

    CoberturaDeEtiquetas(ResourceGraphManager grafo) {
        this.grafo = grafo;
    }

    Cobertura calcular(List<String> suscripciones, String etiqueta) {
        String nombre = Validaciones.etiqueta(etiqueta);
        QueryResponse respuesta = grafo.resourceProviders().resources(new QueryRequest()
                .withQuery("resources | summarize total = count(), sinEtiqueta = countif(isempty(tostring(tags['" + nombre + "'])))")
                .withSubscriptions(suscripciones)
                .withOptions(new QueryRequestOptions().withResultFormat(ResultFormat.OBJECT_ARRAY)));
        if (respuesta.data() instanceof List<?> filas && !filas.isEmpty() && filas.get(0) instanceof Map<?, ?> fila) {
            return new Cobertura(nombre, numero(fila.get("total")), numero(fila.get("sinEtiqueta")));
        }
        return new Cobertura(nombre, 0, 0);
    }

    private static long numero(Object valor) {
        return valor instanceof Number n ? n.longValue() : 0L;
    }
}
```

## 6. El freno de los laboratorios: del aviso del 100 % a apagar VM

Es el [caso real 3](casos-reales.md): al llegar al 100 % real, el grupo de acciones `ag-finops` llama a un webhook de tu servicio, que **desasigna** (no solo apaga: `deallocate` es lo que deja de cobrar el cómputo) las máquinas del grupo de recursos de Sandbox marcadas `auto-apagar=si`.

Principios de diseño, en este orden:

1. **Acotado:** una lista fija en la configuración (`presupuesto → suscripción + grupo de recursos`). Un aviso de un presupuesto que no esté en la lista se **ignora**; el aviso nunca dice *qué* apagar.
2. **Reversible:** desasignar, nunca borrar.
3. **Idempotente:** el grupo de acciones **reintenta** si no responde a tiempo, y Azure puede enviar el mismo aviso más de una vez. Se recuerda "presupuesto + mes" ya procesado.
4. **Simulacro primero:** el modo `simulacro` solo registra qué haría. Actívalo en producción solo cuando el registro te convenza.
5. **Identidad mínima:** el rol personalizado de la tabla de permisos, solo sobre ese grupo de recursos.

> **El contenido del aviso (sus campos) debe verificarse en tu entorno.** Los avisos de presupuesto hacia un grupo de acciones no usan el esquema común de alertas de Azure Monitor; `LectorDeAvisos` lee, de forma tolerante, los campos `data.BudgetName`, `data.SpendingAmount`, `data.Budget` y `data.Unit` tal como aparecen en los ejemplos de la documentación. **Captura un aviso real (por ejemplo, con un presupuesto de prueba muy bajo) y ajusta los nombres antes de activar el apagado.** Si algo falta, el lector devuelve vacío y no se apaga nada.

```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.azure.json.JsonProviders;
import com.azure.json.JsonReader;
import com.azure.resourcemanager.compute.ComputeManager;
import com.azure.resourcemanager.compute.models.VirtualMachine;

import java.io.IOException;
import java.util.Set;
import java.util.function.Function;

/** Lo mínimo que necesitamos del aviso de un presupuesto. */
record AvisoDePresupuesto(String presupuesto, BigDecimal gastado, BigDecimal monto, String moneda) { }

record Objetivo(String suscripcion, String grupoDeRecursos) { }

enum Accion { APAGAR, SOLO_REGISTRAR, IGNORAR }

record Decision(Accion accion, String motivo) { }

final class LectorDeAvisos {

    private LectorDeAvisos() { }

    /** Devuelve vacío si el cuerpo no es JSON o le faltan los campos esperados: ante la duda, no actuar. */
    static Optional<AvisoDePresupuesto> leer(String json) {
        try (JsonReader lector = JsonProviders.createReader(json)) {
            if (lector.readUntyped() instanceof Map<?, ?> raiz && raiz.get("data") instanceof Map<?, ?> datos) {
                String nombre = texto(datos.get("BudgetName"));
                BigDecimal gastado = decimal(datos.get("SpendingAmount"));
                BigDecimal monto = decimal(datos.get("Budget"));
                if (nombre.isEmpty() || gastado == null || monto == null) {
                    return Optional.empty();
                }
                return Optional.of(new AvisoDePresupuesto(nombre, gastado, monto, texto(datos.get("Unit"))));
            }
            return Optional.empty();
        } catch (IOException | RuntimeException e) {
            return Optional.empty();
        }
    }

    private static String texto(Object valor) {
        return valor == null ? "" : valor.toString().trim();
    }

    private static BigDecimal decimal(Object valor) {
        try {
            return valor == null ? null : new BigDecimal(valor.toString().trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }
}

/** Decide si un aviso justifica apagar algo. Función casi pura: solo recuerda lo ya procesado. */
final class PoliticaDeContencion {

    private final Map<String, Objetivo> objetivos;
    private final boolean simulacro;
    private final Set<String> procesados = ConcurrentHashMap.newKeySet();

    PoliticaDeContencion(Map<String, Objetivo> objetivos, boolean simulacro) {
        this.objetivos = Map.copyOf(objetivos);
        this.simulacro = simulacro;
    }

    Optional<Objetivo> objetivo(String presupuesto) {
        return Optional.ofNullable(objetivos.get(presupuesto));
    }

    Decision decidir(AvisoDePresupuesto aviso, YearMonth mes) {
        if (!objetivos.containsKey(aviso.presupuesto())) {
            return new Decision(Accion.IGNORAR, "presupuesto sin objetivo configurado");
        }
        if (aviso.monto().signum() <= 0 || aviso.gastado().compareTo(aviso.monto()) < 0) {
            return new Decision(Accion.IGNORAR, "el gasto aún no alcanza el 100 % del presupuesto");
        }
        if (procesados.contains(clave(aviso, mes))) {
            return new Decision(Accion.IGNORAR, "ya procesado este mes");
        }
        return simulacro
                ? new Decision(Accion.SOLO_REGISTRAR, "simulacro: se apagaría el grupo de recursos configurado")
                : new Decision(Accion.APAGAR, "100 % alcanzado");
    }

    /** Se llama DESPUÉS de apagar con éxito; si falló, el reintento del grupo de acciones vuelve a intentarlo. */
    void confirmar(AvisoDePresupuesto aviso, YearMonth mes) {
        procesados.add(clave(aviso, mes));
    }

    private static String clave(AvisoDePresupuesto aviso, YearMonth mes) {
        return aviso.presupuesto() + "|" + mes;
    }
}

/** Desasigna las VM marcadas con la etiqueta, solo en el grupo de recursos del objetivo. */
final class ApagadorDeMaquinas {

    private final Function<String, ComputeManager> proveedor;
    private final String etiqueta;
    private final String valor;

    ApagadorDeMaquinas(Function<String, ComputeManager> proveedor, String etiqueta, String valor) {
        this.proveedor = proveedor;
        this.etiqueta = etiqueta;
        this.valor = valor;
    }

    /** Devuelve los nombres de las VM desasignadas. Es secuencial y puede tardar minutos: no lo llames en el hilo de la petición. */
    List<String> apagar(Objetivo objetivo) {
        ComputeManager compute = proveedor.apply(objetivo.suscripcion());
        List<String> apagadas = new ArrayList<>();
        for (VirtualMachine vm : compute.virtualMachines().listByResourceGroup(objetivo.grupoDeRecursos())) {
            Map<String, String> etiquetas = vm.tags();
            if (etiquetas != null && valor.equalsIgnoreCase(etiquetas.getOrDefault(etiqueta, ""))) {
                compute.virtualMachines().deallocate(objetivo.grupoDeRecursos(), vm.name());
                apagadas.add(vm.name());
            }
        }
        return apagadas;
    }
}
```

## 7. Métrica: gasto, proyección y cobertura (refresco en segundo plano)

Los datos de costo se renuevan cada 8–24 h: **refrescar cada hora es más que suficiente** (y respeta las cuotas). Los *gauges* alimentan paneles y alertas ("nivel crítico", "cobertura de `owner` por debajo del 95 %").

```java
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicReference;

@Component
@EnableScheduling
class MetricasDeGasto {

    private final ConsultasDeCosto consultas;
    private final PresupuestosServicio presupuestos;
    private final CoberturaDeEtiquetas cobertura;
    private final String alcance;
    private final String presupuesto;
    private final List<String> suscripciones;
    private final String etiqueta;

    private final AtomicReference<Double> acumulado = new AtomicReference<>(0.0);
    private final AtomicReference<Double> proyeccion = new AtomicReference<>(0.0);
    private final AtomicReference<Double> montoDelPresupuesto = new AtomicReference<>(0.0);
    private final AtomicReference<Double> nivel = new AtomicReference<>(0.0);
    private final AtomicReference<Double> coberturaDeEtiqueta = new AtomicReference<>(100.0);

    MetricasDeGasto(MeterRegistry registro, ConsultasDeCosto consultas, PresupuestosServicio presupuestos,
                    CoberturaDeEtiquetas cobertura,
                    @Value("${costos.alcance}") String alcance,
                    @Value("${costos.presupuesto}") String presupuesto,
                    @Value("${costos.suscripciones}") List<String> suscripciones,
                    @Value("${costos.etiqueta-de-dueno:owner}") String etiqueta) {
        this.consultas = consultas;
        this.presupuestos = presupuestos;
        this.cobertura = cobertura;
        this.alcance = alcance;
        this.presupuesto = presupuesto;
        this.suscripciones = suscripciones;
        this.etiqueta = etiqueta;
        Gauge.builder("modalima.costos.acumulado", acumulado, AtomicReference::get).register(registro);
        Gauge.builder("modalima.costos.proyeccion", proyeccion, AtomicReference::get).register(registro);
        Gauge.builder("modalima.costos.presupuesto", montoDelPresupuesto, AtomicReference::get).register(registro);
        Gauge.builder("modalima.costos.nivel", nivel, AtomicReference::get).register(registro);
        Gauge.builder("modalima.etiquetas.cobertura_porcentaje", coberturaDeEtiqueta, AtomicReference::get).register(registro);
    }

    @Scheduled(initialDelayString = "PT1M", fixedDelayString = "PT1H")
    void refrescar() {
        try {
            Proyeccion p = consultas.proyeccionDeFinDeMes(alcance);
            presupuestos.porNombre(alcance, presupuesto).ifPresent(estado -> {
                EstadoDeGasto gasto = EvaluadorDeGasto.evaluar(p.acumulado(), p.totalDelMes(), estado.monto(), p.moneda());
                acumulado.set(gasto.acumulado().doubleValue());
                proyeccion.set(gasto.proyeccion().doubleValue());
                montoDelPresupuesto.set(gasto.presupuesto().doubleValue());
                nivel.set((double) gasto.nivel().ordinal());
            });
        } catch (RuntimeException e) {
            // conserva el último valor: un fallo o una limitación (429) no debe borrar la métrica
        }
        try {
            coberturaDeEtiqueta.set(cobertura.calcular(suscripciones, etiqueta).porcentajeCubierto());
        } catch (RuntimeException e) {
            // idem
        }
    }
}
```

## 8. Clientes de Azure (un solo `TokenCredential`)

```java
// (clase reutilizada en los bloques siguientes)
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class AzureCostosConfig {

    @Bean
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Bean
    Clock reloj() {
        return Clock.systemUTC();
    }

    @Bean
    CostManagementManager costManagement(TokenCredential credencial, @Value("${azure.tenant-id}") String tenant) {
        return CostManagementManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE));
    }

    @Bean
    ConsumptionManager consumption(TokenCredential credencial, @Value("${azure.tenant-id}") String tenant) {
        return ConsumptionManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE));
    }

    @Bean
    ResourceGraphManager grafo(TokenCredential credencial, @Value("${azure.tenant-id}") String tenant) {
        return ResourceGraphManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE));
    }

    @Bean
    ConsultasDeCosto consultas(CostManagementManager costos, Clock reloj,
                               @Value("${costos.cache:PT1H}") Duration cache) {
        return new ConsultasDeCosto(costos, reloj, cache);
    }

    @Bean
    PresupuestosServicio presupuestos(ConsumptionManager consumo) {
        return new PresupuestosServicio(consumo);
    }

    @Bean
    CoberturaDeEtiquetas cobertura(ResourceGraphManager grafo) {
        return new CoberturaDeEtiquetas(grafo);
    }

    @Bean
    PoliticaDeContencion politica(@Value("${costos.contencion.presupuesto}") String presupuesto,
                                  @Value("${costos.contencion.suscripcion}") String suscripcion,
                                  @Value("${costos.contencion.grupo-de-recursos}") String grupoDeRecursos,
                                  @Value("${costos.contencion.simulacro:true}") boolean simulacro) {
        return new PoliticaDeContencion(Map.of(presupuesto, new Objetivo(suscripcion, grupoDeRecursos)), simulacro);
    }

    @Bean
    ApagadorDeMaquinas apagador(TokenCredential credencial, @Value("${azure.tenant-id}") String tenant,
                                @Value("${costos.contencion.etiqueta:auto-apagar}") String etiqueta,
                                @Value("${costos.contencion.valor:si}") String valor) {
        Map<String, ComputeManager> managers = new ConcurrentHashMap<>();
        return new ApagadorDeMaquinas(
                suscripcion -> managers.computeIfAbsent(suscripcion, s ->
                        ComputeManager.authenticate(credencial, new AzureProfile(tenant, s, AzureEnvironment.AZURE))),
                etiqueta, valor);
    }
}
```
```yaml
# application.yml
azure:
  tenant-id: ${AZURE_TENANT_ID}
costos:
  alcance: /subscriptions/${AZURE_SUBSCRIPTION_ID}      # NO viene de la petición HTTP
  presupuesto: presupuesto-suscripcion-mensual
  suscripciones: ${AZURE_SUBSCRIPTION_ID}
  etiqueta-de-dueno: owner
  cache: PT1H
  contencion:
    presupuesto: presupuesto-sandbox-laboratorio
    suscripcion: ${AZURE_SANDBOX_SUBSCRIPTION_ID}
    grupo-de-recursos: rg-sandbox-laboratorio
    etiqueta: auto-apagar
    valor: "si"
    simulacro: true                                      # cámbialo a false solo tras revisar el registro
    token: ${COSTOS_WEBHOOK_TOKEN}                       # secreto largo; viene de Key Vault, no del repositorio
```

## 9. Spring MVC: controlador y traducción de errores

Un controlador interno de FinOps (detrás de autenticación; **no** es una API pública). Fíjate en que ninguna ruta acepta el alcance: sale de la configuración.

```java
import com.azure.core.management.exception.ManagementException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestController
@RequestMapping("/finanzas")
class CostosControlador {

    record PeticionDePresupuesto(String nombre, BigDecimal monto, List<String> correos, List<String> gruposDeAcciones) { }

    private final ConsultasDeCosto consultas;
    private final PresupuestosServicio presupuestos;
    private final CoberturaDeEtiquetas cobertura;
    private final Clock reloj;
    private final String alcance;
    private final List<String> suscripciones;

    CostosControlador(ConsultasDeCosto consultas, PresupuestosServicio presupuestos, CoberturaDeEtiquetas cobertura,
                      Clock reloj,
                      @Value("${costos.alcance}") String alcance,
                      @Value("${costos.suscripciones}") List<String> suscripciones) {
        this.consultas = consultas;
        this.presupuestos = presupuestos;
        this.cobertura = cobertura;
        this.reloj = reloj;
        this.alcance = alcance;
        this.suscripciones = suscripciones;
    }

    @GetMapping("/costos/por-etiqueta")
    List<CostoPorValor> porEtiqueta(@RequestParam(defaultValue = "owner") String etiqueta) {
        return consultas.mesPorEtiqueta(alcance, etiqueta);
    }

    @GetMapping("/costos/proyeccion")
    Proyeccion proyeccion() {
        return consultas.proyeccionDeFinDeMes(alcance);
    }

    @GetMapping("/presupuestos")
    List<EstadoDePresupuesto> presupuestos() {
        return presupuestos.listar(alcance);
    }

    @GetMapping("/presupuestos/hallazgos")
    List<HallazgoDePresupuesto> hallazgos() {
        return ReglasDePresupuesto.auditar(presupuestos.listar(alcance));
    }

    @PostMapping("/presupuestos")
    ResponseEntity<EstadoDePresupuesto> crear(@RequestBody PeticionDePresupuesto peticion) {
        EstadoDePresupuesto creado = presupuestos.crearMensual(new SolicitudDePresupuesto(
                alcance, peticion.nombre(), peticion.monto(), YearMonth.now(reloj),
                peticion.correos(), peticion.gruposDeAcciones() == null ? List.of() : peticion.gruposDeAcciones()));
        return ResponseEntity.status(HttpStatus.CREATED).body(creado);
    }

    @GetMapping("/etiquetas/cobertura")
    Cobertura cobertura(@RequestParam(defaultValue = "owner") String etiqueta) {
        return cobertura.calcular(suscripciones, etiqueta);
    }
}

@RestControllerAdvice
class ErroresDeCostosAdvice {

    @ExceptionHandler(IllegalArgumentException.class)
    ProblemDetail solicitudInvalida(IllegalArgumentException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(ManagementException.class)
    ResponseEntity<ProblemDetail> errorDeAzure(ManagementException e) {
        int estado = e.getResponse() == null ? 502 : e.getResponse().getStatusCode();
        HttpStatus http = switch (estado) {
            case 403 -> HttpStatus.FORBIDDEN;
            case 404 -> HttpStatus.NOT_FOUND;
            case 429 -> HttpStatus.SERVICE_UNAVAILABLE;      // Azure nos limitó: pedimos esperar
            default -> HttpStatus.BAD_GATEWAY;
        };
        ProblemDetail problema = ProblemDetail.forStatusAndDetail(http, "Azure rechazó la operación de costos");
        problema.setProperty("codigoAzure", e.getValue() == null ? null : e.getValue().getCode());
        ResponseEntity.BodyBuilder respuesta = ResponseEntity.status(http);
        if (estado == 429 && e.getResponse() != null && e.getResponse().getHeaderValue("Retry-After") != null) {
            respuesta.header(HttpHeaders.RETRY_AFTER, e.getResponse().getHeaderValue("Retry-After"));
        }
        return respuesta.body(problema);
    }

    @ExceptionHandler(IllegalStateException.class)
    ProblemDetail respuestaIncompleta(IllegalStateException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY, e.getMessage());
    }
}
```

## 10. Spring WebFlux (reactivo): dos consultas en paralelo

El SDK de costos y consumo es **bloqueante**. En WebFlux, cada llamada se envuelve con `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`. La ventaja reactiva aquí es **combinar**: el resumen del gasto necesita la proyección y el presupuesto, que son dos llamadas independientes; con `Mono.zip` corren en paralelo. (Con Java 21 también puedes activar **hilos virtuales** y escribir código imperativo.)

```java
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/finanzas")
class CostosReactivoControlador {

    private final ConsultasDeCosto consultas;
    private final PresupuestosServicio presupuestos;
    private final String alcance;
    private final String presupuesto;

    CostosReactivoControlador(ConsultasDeCosto consultas, PresupuestosServicio presupuestos,
                              @Value("${costos.alcance}") String alcance,
                              @Value("${costos.presupuesto}") String presupuesto) {
        this.consultas = consultas;
        this.presupuestos = presupuestos;
        this.alcance = alcance;
        this.presupuesto = presupuesto;
    }

    @GetMapping("/costos/por-etiqueta")
    Mono<List<CostoPorValor>> porEtiqueta(@RequestParam(defaultValue = "owner") String etiqueta) {
        return Mono.fromCallable(() -> consultas.mesPorEtiqueta(alcance, etiqueta)).subscribeOn(Schedulers.boundedElastic());
    }

    /** Proyección y presupuesto en paralelo; el nivel se calcula con la función pura. */
    @GetMapping("/resumen")
    Mono<EstadoDeGasto> resumen() {
        Mono<Proyeccion> proyeccion = Mono.fromCallable(() -> consultas.proyeccionDeFinDeMes(alcance))
                .subscribeOn(Schedulers.boundedElastic());
        Mono<EstadoDePresupuesto> estado = Mono.fromCallable(() -> presupuestos.porNombre(alcance, presupuesto))
                .subscribeOn(Schedulers.boundedElastic())
                .flatMap(opcional -> opcional.map(Mono::just).orElseGet(Mono::empty));
        return Mono.zip(proyeccion, estado)
                .map(par -> EvaluadorDeGasto.evaluar(par.getT1().acumulado(), par.getT1().totalDelMes(),
                        par.getT2().monto(), par.getT1().moneda()));
    }
}
```

## 11. Webhook del grupo de acciones (Spring)

El grupo de acciones llama a esta URL cuando el presupuesto llega al 100 %. Dos cosas importantes:

- **Autenticación:** un grupo de acciones no puede añadir cabeceras propias. Lo ideal es un **webhook seguro** con Microsoft Entra ID; si no, un **token largo en la URL** (comparado en tiempo constante, rotado, **sin escribir la URL en los registros**).
- **Responder rápido:** apagar VM tarda minutos. Se responde `202 Accepted` y el trabajo corre en un **hilo virtual**. Si el trabajo falla, no se marca como procesado y el reintento del grupo de acciones lo vuelve a intentar.

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@RestController
@RequestMapping("/hooks")
class AvisosDePresupuestoControlador {

    private static final Logger LOG = LoggerFactory.getLogger(AvisosDePresupuestoControlador.class);

    private final PoliticaDeContencion politica;
    private final ApagadorDeMaquinas apagador;
    private final Clock reloj;
    private final String token;
    private final ExecutorService trabajo = Executors.newVirtualThreadPerTaskExecutor();

    AvisosDePresupuestoControlador(PoliticaDeContencion politica, ApagadorDeMaquinas apagador, Clock reloj,
                                   @Value("${costos.contencion.token}") String token) {
        this.politica = politica;
        this.apagador = apagador;
        this.reloj = reloj;
        this.token = token;
    }

    @PostMapping("/presupuesto")
    ResponseEntity<Void> recibir(@RequestParam("token") String recibido, @RequestBody String cuerpo) {
        boolean valido = MessageDigest.isEqual(recibido.getBytes(StandardCharsets.UTF_8), token.getBytes(StandardCharsets.UTF_8));
        if (!valido) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        Optional<AvisoDePresupuesto> leido = LectorDeAvisos.leer(cuerpo);
        if (leido.isEmpty()) {
            LOG.warn("Aviso de presupuesto con formato no reconocido: no se hace nada");
            return ResponseEntity.badRequest().build();
        }
        AvisoDePresupuesto aviso = leido.get();
        YearMonth mes = YearMonth.now(reloj);
        Decision decision = politica.decidir(aviso, mes);
        LOG.info("Presupuesto {}: {} ({})", aviso.presupuesto(), decision.accion(), decision.motivo());

        if (decision.accion() == Accion.APAGAR) {
            trabajo.submit(() -> {
                try {
                    List<String> apagadas = apagador.apagar(politica.objetivo(aviso.presupuesto()).orElseThrow());
                    politica.confirmar(aviso, mes);
                    LOG.info("Presupuesto {}: desasignadas {} máquinas {}", aviso.presupuesto(), apagadas.size(), apagadas);
                } catch (RuntimeException e) {
                    LOG.error("Presupuesto {}: falló el apagado; el reintento lo volverá a intentar", aviso.presupuesto(), e);
                }
            });
        }
        return ResponseEntity.accepted().build();
    }
}
```

## 12. Quarkus · imperativo

Productores CDI y recursos REST con la misma lógica (las secciones 1 a 6 no dependen de ningún marco).

```java
import com.azure.core.credential.TokenCredential;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class AzureCostosProductores {

    @ConfigProperty(name = "azure.tenant-id")
    String tenant;

    @ConfigProperty(name = "costos.cache", defaultValue = "PT1H")
    Duration cache;

    @ConfigProperty(name = "costos.contencion.presupuesto")
    String presupuestoContencion;

    @ConfigProperty(name = "costos.contencion.suscripcion")
    String suscripcionContencion;

    @ConfigProperty(name = "costos.contencion.grupo-de-recursos")
    String grupoContencion;

    @ConfigProperty(name = "costos.contencion.simulacro", defaultValue = "true")
    boolean simulacro;

    @Produces
    @Singleton
    TokenCredential credencial() {
        return new DefaultAzureCredentialBuilder().build();
    }

    @Produces
    @Singleton
    Clock reloj() {
        return Clock.systemUTC();
    }

    @Produces
    @Singleton
    ConsultasDeCosto consultas(TokenCredential credencial, Clock reloj) {
        return new ConsultasDeCosto(
                CostManagementManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE)), reloj, cache);
    }

    @Produces
    @Singleton
    PresupuestosServicio presupuestos(TokenCredential credencial) {
        return new PresupuestosServicio(
                ConsumptionManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE)));
    }

    @Produces
    @Singleton
    CoberturaDeEtiquetas cobertura(TokenCredential credencial) {
        return new CoberturaDeEtiquetas(
                ResourceGraphManager.authenticate(credencial, new AzureProfile(tenant, null, AzureEnvironment.AZURE)));
    }

    @Produces
    @Singleton
    PoliticaDeContencion politica() {
        return new PoliticaDeContencion(
                Map.of(presupuestoContencion, new Objetivo(suscripcionContencion, grupoContencion)), simulacro);
    }

    @Produces
    @Singleton
    ApagadorDeMaquinas apagador(TokenCredential credencial) {
        Map<String, ComputeManager> managers = new ConcurrentHashMap<>();
        return new ApagadorDeMaquinas(
                suscripcion -> managers.computeIfAbsent(suscripcion, s ->
                        ComputeManager.authenticate(credencial, new AzureProfile(tenant, s, AzureEnvironment.AZURE))),
                "auto-apagar", "si");
    }
}
```

```java
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.resteasy.reactive.server.ServerExceptionMapper;

@Path("/finanzas")
@Produces(MediaType.APPLICATION_JSON)
class CostosRecurso {

    @Inject
    ConsultasDeCosto consultas;

    @Inject
    PresupuestosServicio presupuestos;

    @ConfigProperty(name = "costos.alcance")
    String alcance;

    @GET
    @Path("/costos/por-etiqueta")
    List<CostoPorValor> porEtiqueta(@QueryParam("etiqueta") String etiqueta) {
        return consultas.mesPorEtiqueta(alcance, etiqueta == null ? "owner" : etiqueta);
    }

    @GET
    @Path("/costos/proyeccion")
    Proyeccion proyeccion() {
        return consultas.proyeccionDeFinDeMes(alcance);
    }

    @GET
    @Path("/presupuestos/hallazgos")
    List<HallazgoDePresupuesto> hallazgos() {
        return ReglasDePresupuesto.auditar(presupuestos.listar(alcance));
    }

    @ServerExceptionMapper
    Response solicitudInvalida(IllegalArgumentException e) {
        return Response.status(400).entity(Map.of("titulo", e.getMessage())).build();
    }

    @ServerExceptionMapper
    Response errorDeAzure(ManagementException e) {
        int estado = e.getResponse() == null ? 502 : e.getResponse().getStatusCode();
        int http = estado == 403 || estado == 404 ? estado : estado == 429 ? 503 : 502;
        Response.ResponseBuilder respuesta = Response.status(http).entity(Map.of("titulo", "Azure rechazó la operación de costos"));
        if (estado == 429 && e.getResponse() != null && e.getResponse().getHeaderValue("Retry-After") != null) {
            respuesta.header("Retry-After", e.getResponse().getHeaderValue("Retry-After"));
        }
        return respuesta.build();
    }
}

@Path("/hooks")
class AvisosDePresupuestoRecurso {

    @Inject
    PoliticaDeContencion politica;

    @Inject
    ApagadorDeMaquinas apagador;

    @Inject
    Clock reloj;

    @ConfigProperty(name = "costos.contencion.token")
    String token;

    @POST
    @Path("/presupuesto")
    Response recibir(@QueryParam("token") String recibido, String cuerpo) {
        if (recibido == null || !java.security.MessageDigest.isEqual(
                recibido.getBytes(java.nio.charset.StandardCharsets.UTF_8), token.getBytes(java.nio.charset.StandardCharsets.UTF_8))) {
            return Response.status(401).build();
        }
        Optional<AvisoDePresupuesto> leido = LectorDeAvisos.leer(cuerpo);
        if (leido.isEmpty()) {
            return Response.status(400).build();
        }
        AvisoDePresupuesto aviso = leido.get();
        YearMonth mes = YearMonth.now(reloj);
        if (politica.decidir(aviso, mes).accion() == Accion.APAGAR) {
            java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor().submit(() -> {
                apagador.apagar(politica.objetivo(aviso.presupuesto()).orElseThrow());
                politica.confirmar(aviso, mes);
            });
        }
        return Response.accepted().build();
    }
}
```

> En Quarkus, el equivalente de las métricas de la sección 7 es `quarkus-micrometer` + `@Scheduled(every = "1h")` de `quarkus-scheduler`, con la misma lógica de refresco.

## 13. Quarkus · reactivo (Mutiny)

Igual que en WebFlux: lo bloqueante va a un pool de trabajadores y las dos consultas independientes se combinan en paralelo.

```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@Path("/reactivo/finanzas")
@Produces(MediaType.APPLICATION_JSON)
class CostosRecursoReactivo {

    @Inject
    ConsultasDeCosto consultas;

    @Inject
    PresupuestosServicio presupuestos;

    @ConfigProperty(name = "costos.alcance")
    String alcance;

    @ConfigProperty(name = "costos.presupuesto")
    String presupuesto;

    @GET
    @Path("/costos/proyeccion")
    Uni<Proyeccion> proyeccion() {
        return Uni.createFrom().item(() -> consultas.proyeccionDeFinDeMes(alcance))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }

    @GET
    @Path("/resumen")
    Uni<EstadoDeGasto> resumen() {
        Uni<Proyeccion> proyeccion = Uni.createFrom().item(() -> consultas.proyeccionDeFinDeMes(alcance))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
        Uni<EstadoDePresupuesto> estado = Uni.createFrom().item(() -> presupuestos.porNombre(alcance, presupuesto).orElseThrow())
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
        return Uni.combine().all().unis(proyeccion, estado).asTuple()
                .map(par -> EvaluadorDeGasto.evaluar(par.getItem1().acumulado(), par.getItem1().totalDelMes(),
                        par.getItem2().monto(), par.getItem1().moneda()));
    }
}
```

## 14. Pruebas

| Nivel | Cómo | Notas |
|---|---|---|
| **Lector de tablas** | `TablaDeCostos` con columnas y filas escritas a mano | Prueba el orden distinto de columnas, `PreTaxCost` en lugar de `Cost`, fechas `20261016` como entero y como decimal |
| **Reglas de presupuesto** | `ReglasDePresupuesto.validar` y `auditar` | Sin red: 6 correos, grupo de acciones en grupo de administración, sin notificaciones, sin pronóstico |
| **Evaluador de gasto** | `EvaluadorDeGasto.evaluar` en los bordes (79,9 %, 80 %, 100 %, 110 %) | Función pura |
| **Política de contención** | Dobles de `ApagadorDeMaquinas`; reloj fijo | Presupuesto desconocido no actúa; el mismo aviso dos veces solo actúa una; el simulacro nunca apaga |
| **Consultas y presupuestos** | `HttpClient` falso de azure-core con el JSON guardado de una respuesta real, y un `HttpPipeline` propio que entregas a `CostManagementManager.authenticate(pipeline, perfil)` | Comprueba la ruta, la versión de API, el cuerpo enviado (`granularity` omitida, `timePeriod`) y que los números lleguen bien |
| **Integración** | Una suscripción de laboratorio con un presupuesto de 1 USD | Única forma de ver el retraso real, los correos y el contenido real del aviso |

```java
// nocheck — requiere JUnit 5
class CostosTest {

    @Test
    void leePorNombreAunqueCambieElOrden() {
        TablaDeCostos tabla = new TablaDeCostos(
                List.of("Currency", "UsageDate", "PreTaxCost", "ResourceGroupName"),
                List.of(List.of("USD", 20261016, 12.5, "rg-tienda")));

        assertEquals(new BigDecimal("12.5"), tabla.decimal(0, "Cost", "PreTaxCost"));
        assertEquals(LocalDate.of(2026, 10, 16), tabla.fecha(0, "UsageDate"));
        assertEquals("rg-tienda", tabla.texto(0, "ResourceGroupName"));
    }

    @Test
    void elNivelCambiaEnLosBordes() {
        BigDecimal mil = new BigDecimal("1000");
        assertEquals(Nivel.NORMAL, EvaluadorDeGasto.evaluar(new BigDecimal("799"), new BigDecimal("990"), mil, "USD").nivel());
        assertEquals(Nivel.ATENCION, EvaluadorDeGasto.evaluar(new BigDecimal("800"), new BigDecimal("900"), mil, "USD").nivel());
        assertEquals(Nivel.CRITICO, EvaluadorDeGasto.evaluar(new BigDecimal("500"), new BigDecimal("1100"), mil, "USD").nivel());
    }

    @Test
    void unPresupuestoSinNotificacionesSeMarca() {
        var sinAvisos = new EstadoDePresupuesto("p", new BigDecimal("100"), BigDecimal.ZERO, BigDecimal.ZERO, List.of());

        assertEquals("SIN_AVISOS", ReglasDePresupuesto.auditar(List.of(sinAvisos)).get(0).regla());
    }

    @Test
    void elMismoAvisoSoloActuaUnaVez() {
        var politica = new PoliticaDeContencion(Map.of("p-lab", new Objetivo("sub", "rg-lab")), false);
        var aviso = new AvisoDePresupuesto("p-lab", new BigDecimal("100"), new BigDecimal("100"), "USD");
        var mes = YearMonth.of(2026, 10);

        assertEquals(Accion.APAGAR, politica.decidir(aviso, mes).accion());
        politica.confirmar(aviso, mes);
        assertEquals(Accion.IGNORAR, politica.decidir(aviso, mes).accion());
    }
}
```

## 15. Buenas prácticas de código

- **Identidades administradas separadas** por función (consultar, crear presupuestos, apagar). El que apaga solo tiene el rol personalizado sobre un grupo de recursos.
- **El alcance sale de la configuración**, nunca de la petición. Valídalo (`Validaciones.alcance`) igualmente.
- **Lee por nombre de columna**, no por posición; acepta los nombres alternativos de la columna de costo.
- **Cachea** (1 h es de sobra: los datos tienen 8–24 h de retraso) y **refresca en segundo plano**; ante un 429 devuelve `503` con `Retry-After`.
- **Si `nextLink` viene con valor, el resultado está incompleto:** acota la consulta o usa una exportación; no lo ignores.
- **Presupuestos como código con notificaciones**, y una auditoría periódica (`SIN_AVISOS`, `SIN_PRONOSTICO`, `SUPERADO`).
- **Freno acotado, reversible, idempotente y con simulacro primero.** Un aviso nunca decide *qué* apagar.
- **No registres la URL del webhook** (lleva el token) y rota el token; mejor, webhook seguro con Microsoft Entra ID.
- Trata `403`, `404` y `429` de ARM como resultados esperables con su código, no como fallos del servidor.
- En reactivo, **no bloquees** el hilo de eventos: `boundedElastic` / pool de trabajadores / hilos virtuales.
