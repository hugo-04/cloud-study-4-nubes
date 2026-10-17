# AWS · Caso integrado · Runbook de diagnóstico · Uso desde Java

Versiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK for Java v2 BOM 2.56.0**. Verifica las vigentes.

El runbook se ejecuta con consultas y comandos ([`triage.sh`](ejemplos/cli/triage.sh), [Logs Insights](ejemplos/logs-insights/consultas.md)). Java aporta lo que ninguna consulta ve —**lo que la aplicación ve desde su propio pod, con su propia red e identidad**— y automatiza las tres preguntas de los primeros cinco minutos:

| Pregunta del runbook | Pieza en Java |
|---|---|
| ¿Qué dependencia no alcanzo yo? | `SondaSintetica` + `EscaleraDeDiagnostico` (DNS → ruta y puerto → TLS → identidad) |
| ¿Cuánto y desde cuándo falla? | `MetricasCloudWatch` (`GetMetricData`) + `TriageDeIncidente` |
| ¿Qué cambió justo antes? | `CambiosCloudTrail` (`LookupEvents`, solo eventos que modifican) |
| ¿Qué excepción se repite? | `RegistrosInsights` (`StartQuery` / `GetQueryResults`) |
| Todo junto, sin machacar las APIs | `ServicioDeIncidente` (informe en caché unos segundos) |

```
 DNS ──► RUTA Y PUERTO ──► TLS ──► IDENTIDAD       (cada escalón depende del anterior: si DNS falla, no se prueba el puerto)
  │          │               │         │
 ¿resuelve? ¿conecta?     ¿certificado ¿se obtienen
 ¿a IP      ¿timeout o      y nombre    credenciales
 privada?    rechazo?       válidos?    del pod/rol?
```

La clase [`ConnCheck`](../../01-red/diagnostico-conectividad/ejemplos/java/ConnCheck.java) del capítulo de red hace esto para **un** destino desde la línea de comandos. Aquí se convierte en un componente que prueba **todas** las dependencias en paralelo, se expone en un endpoint interno y corre de forma programada (para que las alarmas la usen).

Permisos: la sonda usa **la identidad de la aplicación** (no una más poderosa) y solo comprueba que obtiene credenciales; el endpoint revela la topología, así que **solo** lo ve operaciones, por la red interna.

## 1. Configuración
```yaml
# Spring Boot (application.yml)
sonda:
  intervalo-ms: 60000
  rds: prod-pedidos.cluster-abc123.us-east-1.rds.amazonaws.com
  redis: prod-sesiones.abc123.use1.cache.amazonaws.com
  sqs: sqs.us-east-1.amazonaws.com
  secretos: secretsmanager.us-east-1.amazonaws.com
incidente:
  alb: app/prod-tienda/50dc6c495c0c9188
  grupo-logs: /tienda/prod/api
  umbral-errores-pct: 2
  cache-segundos: 20
```
```properties
# Quarkus (application.properties)
sonda.rds=prod-pedidos.cluster-abc123.us-east-1.rds.amazonaws.com
sonda.redis=prod-sesiones.abc123.use1.cache.amazonaws.com
sonda.sqs=sqs.us-east-1.amazonaws.com
sonda.secretos=secretsmanager.us-east-1.amazonaws.com
incidente.alb=app/prod-tienda/50dc6c495c0c9188
incidente.grupo-logs=/tienda/prod/api
incidente.umbral-errores-pct=2
incidente.cache-segundos=20
quarkus.scheduler.enabled=true
```

## 2. Núcleo común

### 2.1 La escalera y las hipótesis (sin Spring ni Quarkus, sin SDK)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.io.IOException;
import java.net.ConnectException;
import java.net.InetAddress;
import java.net.NoRouteToHostException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import javax.net.ssl.SSLException;

public enum Causa {
    OK("OK"), DNS_NO_RESUELVE("DNS"), DNS_PUBLICA("DNS"), TIMEOUT("RUTA_Y_PUERTO"), RECHAZADA("RUTA_Y_PUERTO"),
    ERROR_DE_RED("RUTA_Y_PUERTO"), TLS_INVALIDO("TLS"), SIN_CREDENCIALES("IDENTIDAD");

    private final String escalon;

    Causa(String escalon) {
        this.escalon = escalon;
    }

    public String escalon() {
        return escalon;
    }
}

public record Dependencia(String nombre, String host, int puerto, boolean tls, boolean esperaPrivada, boolean verificaIdentidad) { }

public record ResultadoDeDependencia(String dependencia, Causa causa, long ms, String detalle) {

    public boolean ok() {
        return causa == Causa.OK;
    }
}

public record Hipotesis(String dependencia, String causaProbable, String siguientePaso) { }

public record InformeDeSonda(Instant inicio, long duracionMs, List<ResultadoDeDependencia> dependencias, List<Hipotesis> hipotesis) {

    public boolean todoBien() {
        return dependencias.stream().allMatch(ResultadoDeDependencia::ok);
    }
}

/** Las cuatro pruebas posibles, detrás de una interfaz para poder simularlas en las pruebas. */
public interface Pruebas {
    List<InetAddress> resolver(String host) throws IOException;

    void conectar(InetAddress direccion, int puerto, Duration limite) throws IOException;

    void handshakeTls(String host, int puerto, Duration limite) throws IOException;

    /** Lanza una excepción si la aplicación no consigue credenciales (Pod Identity, rol de la tarea, perfil de instancia…). */
    void verificarIdentidad();
}

public final class EscaleraDeDiagnostico {

    private final Pruebas pruebas;
    private final Duration limite;

    public EscaleraDeDiagnostico(Pruebas pruebas, Duration limite) {
        this.pruebas = pruebas;
        this.limite = limite;
    }

    public ResultadoDeDependencia diagnosticar(Dependencia d) {
        long inicio = System.nanoTime();
        try {
            List<InetAddress> direcciones = pruebas.resolver(d.host());
            if (direcciones.isEmpty()) {
                return resultado(d, Causa.DNS_NO_RESUELVE, inicio, "no devuelve direcciones");
            }
            InetAddress direccion = direcciones.get(0);
            if (d.esperaPrivada() && !direccion.isSiteLocalAddress()) {
                return resultado(d, Causa.DNS_PUBLICA, inicio, "resuelve a IP pública " + enmascarar(direccion) + ": se esperaba una privada");
            }
            pruebas.conectar(direccion, d.puerto(), limite);
            if (d.tls()) {
                pruebas.handshakeTls(d.host(), d.puerto(), limite);
            }
        } catch (UnknownHostException e) {
            return resultado(d, Causa.DNS_NO_RESUELVE, inicio, "el nombre no resuelve");
        } catch (SocketTimeoutException | NoRouteToHostException e) {
            return resultado(d, Causa.TIMEOUT, inicio, "sin respuesta hacia el puerto " + d.puerto() + " (ruta, grupo de seguridad o ACL)");
        } catch (ConnectException e) {
            return resultado(d, Causa.RECHAZADA, inicio, "conexión rechazada: nadie escucha en ese puerto");
        } catch (SSLException e) {
            return resultado(d, Causa.TLS_INVALIDO, inicio, "falló el protocolo seguro: " + e.getClass().getSimpleName());
        } catch (IOException e) {
            return resultado(d, Causa.ERROR_DE_RED, inicio, e.getClass().getSimpleName());
        }
        if (d.verificaIdentidad()) {
            try {
                pruebas.verificarIdentidad();
            } catch (RuntimeException e) {
                return resultado(d, Causa.SIN_CREDENCIALES, inicio, "no se obtuvieron credenciales: " + e.getClass().getSimpleName());
            }
        }
        return resultado(d, Causa.OK, inicio, "alcanzable");
    }

    private static ResultadoDeDependencia resultado(Dependencia d, Causa causa, long inicioNanos, String detalle) {
        return new ResultadoDeDependencia(d.nombre(), causa, (System.nanoTime() - inicioNanos) / 1_000_000, detalle);
    }

    /** Las IP públicas se muestran parcialmente: el informe no debe servir de mapa a un atacante. */
    static String enmascarar(InetAddress direccion) {
        String[] octetos = direccion.getHostAddress().split("\\.");
        return octetos.length == 4 ? octetos[0] + "." + octetos[1] + ".x.x" : "(IPv6)";
    }
}

public final class ClasificadorDeSintomas {

    private ClasificadorDeSintomas() { }

    public static Hipotesis para(ResultadoDeDependencia r) {
        return switch (r.causa()) {
            case DNS_NO_RESUELVE -> new Hipotesis(r.dependencia(), "El nombre no resuelve desde este pod",
                    "Revisar DNS de la VPC (nombres y resolución activados), la zona privada y el reenviador de Route 53 Resolver");
            case DNS_PUBLICA -> new Hipotesis(r.dependencia(), "Resuelve a la IP pública: el endpoint de VPC no tiene DNS privado o no es de esta VPC",
                    "Comprobar «DNS privado» del endpoint de interfaz y que la VPC del pod sea la del endpoint");
            case TIMEOUT -> new Hipotesis(r.dependencia(), "Los paquetes se descartan: grupo de seguridad, ACL de red o ruta",
                    "Reachability Analyzer desde la interfaz del pod al destino; reglas del grupo de seguridad del destino");
            case RECHAZADA -> new Hipotesis(r.dependencia(), "Llega al destino pero nadie atiende: servicio detenido o puerto equivocado",
                    "Revisar el estado del destino (instancia, tarea o pod) y el puerto del servicio");
            case ERROR_DE_RED -> new Hipotesis(r.dependencia(), "Error de red no clasificado",
                    "Ver el detalle y los Flow Logs de la interfaz; repetir la prueba desde otro pod");
            case TLS_INVALIDO -> new Hipotesis(r.dependencia(), "Certificado vencido, nombre que no coincide o CA no confiable",
                    "Comprobar el certificado del destino y el almacén de confianza de la imagen");
            case SIN_CREDENCIALES -> new Hipotesis(r.dependencia(), "La identidad del pod no consigue credenciales (asociación, cuenta de servicio o rol)",
                    "Revisar la asociación de Pod Identity / IRSA, la cuenta de servicio y la política de confianza del rol");
            case OK -> new Hipotesis(r.dependencia(), "Sin problema en esta capa", "Pasar a la capa de aplicación (logs y trazas)");
        };
    }
}

public final class SondaSintetica {

    private static final System.Logger LOG = System.getLogger("sonda");

    private final EscaleraDeDiagnostico escalera;
    private final Duration limiteTotal;

    public SondaSintetica(EscaleraDeDiagnostico escalera, Duration limiteTotal) {
        this.escalera = escalera;
        this.limiteTotal = limiteTotal;
    }

    /** Prueba todas las dependencias en paralelo (hilos virtuales). Una dependencia colgada no frena a las demás. */
    public InformeDeSonda ejecutar(List<Dependencia> dependencias) {
        Instant inicio = Instant.now();
        long t0 = System.nanoTime();
        List<ResultadoDeDependencia> resultados = new ArrayList<>();
        try (var ejecutor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<ResultadoDeDependencia>> futuros = dependencias.stream()
                    .map(d -> ejecutor.submit(() -> escalera.diagnosticar(d)))
                    .toList();
            for (int i = 0; i < futuros.size(); i++) {
                try {
                    resultados.add(futuros.get(i).get(limiteTotal.toMillis(), TimeUnit.MILLISECONDS));
                } catch (TimeoutException | ExecutionException e) {
                    futuros.get(i).cancel(true);
                    resultados.add(new ResultadoDeDependencia(dependencias.get(i).nombre(), Causa.TIMEOUT, limiteTotal.toMillis(),
                            "la prueba superó el límite total"));
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        List<Hipotesis> hipotesis = resultados.stream().filter(r -> !r.ok()).map(ClasificadorDeSintomas::para).toList();
        for (ResultadoDeDependencia r : resultados) {
            // Una línea estructurada por dependencia: es lo que lee el filtro de métrica de la alarma "sonda"
            LOG.log(System.Logger.Level.INFO, "sonda.dependencia dependencia={0} escalon={1} ok={2} ms={3}",
                    r.dependencia(), r.causa().escalon(), r.ok(), r.ms());
        }
        return new InformeDeSonda(inicio, (System.nanoTime() - t0) / 1_000_000, resultados, hipotesis);
    }
}
```

### 2.2 Las pruebas reales (JDK y proveedor de credenciales del SDK)
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.net.InetSocketAddress;
import java.net.Socket;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;

public final class PruebasReales implements Pruebas {

    private final AwsCredentialsProvider credenciales;

    public PruebasReales(AwsCredentialsProvider credenciales) {
        this.credenciales = credenciales;
    }

    @Override
    public List<InetAddress> resolver(String host) throws IOException {
        return List.of(InetAddress.getAllByName(host));
    }

    @Override
    public void conectar(InetAddress direccion, int puerto, Duration limite) throws IOException {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(direccion, puerto), (int) limite.toMillis());
        }
    }

    @Override
    public void handshakeTls(String host, int puerto, Duration limite) throws IOException {
        // Se verifica el NOMBRE del certificado contra el host (algoritmo HTTPS), no solo que el certificado sea válido
        try (Socket base = new Socket()) {
            base.connect(new InetSocketAddress(host, puerto), (int) limite.toMillis());
            base.setSoTimeout((int) limite.toMillis());
            try (SSLSocket tls = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(base, host, puerto, true)) {
                SSLParameters parametros = tls.getSSLParameters();
                parametros.setEndpointIdentificationAlgorithm("HTTPS");
                tls.setSSLParameters(parametros);
                tls.startHandshake();
            }
        }
    }

    @Override
    public void verificarIdentidad() {
        // Resolver credenciales es lo que falla cuando la asociación del pod o el rol de la tarea están rotos.
        // Se obtienen y se descartan: nunca se registran ni se devuelven.
        credenciales.resolveCredentials();
    }
}
```

### 2.3 «¿Qué cambió?» y «¿cuánto falla?»: el triage (núcleo puro)
Reglas que salieron de incidentes reales: se **ignora el minuto en curso** (está incompleto y parece una caída), se usa la tasa de los **últimos tres minutos completos**, los **cambios se buscan alrededor del inicio del problema** y el **silencio** (cero peticiones) se trata como síntoma grave, no como «todo bien».
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.temporal.ChronoUnit;
import java.util.Comparator;
import java.util.Set;

public record Cambio(Instant cuando, String quien, String evento, String recurso) { }

public record MuestraPorMinuto(Instant minuto, double peticiones, double errores) {

    public double tasa() {
        return peticiones > 0 ? 100.0 * errores / peticiones : 0;
    }
}

public interface Cambios {
    List<Cambio> desde(Instant desde);
}

public interface Metricas {
    /** Una muestra por cada minuto del rango; los minutos sin datos valen 0. */
    List<MuestraPorMinuto> porMinuto(Instant desde, Instant hasta);
}

public enum Severidad { NINGUNA, SEV3, SEV2, SEV1 }

public record Recomendacion(String paso, String motivo) { }

public record InformeDeTriage(Severidad severidad, double tasaActualPct, boolean sinTrafico, Instant inicioDelProblema,
                              List<Cambio> cambiosSospechosos, List<Recomendacion> recomendaciones) { }

public final class TriageDeIncidente {

    /** Eventos que modifican según CloudTrail pero que no son «un cambio» que explique un incidente. */
    static final Set<String> RUIDO = Set.of("AssumeRole", "AssumeRoleWithWebIdentity", "AssumeRoleWithSAML", "ConsoleLogin",
            "GetSessionToken", "CreateLogStream", "RenewRole", "SwitchRole");

    private final Cambios cambios;
    private final Metricas metricas;
    private final Clock reloj;
    private final double umbralPct;

    public TriageDeIncidente(Cambios cambios, Metricas metricas, Clock reloj, double umbralPct) {
        this.cambios = cambios;
        this.metricas = metricas;
        this.reloj = reloj;
        this.umbralPct = umbralPct;
    }

    public InformeDeTriage evaluar(InformeDeSonda sonda) {
        Instant ahora = reloj.instant();
        Instant minutoEnCurso = ahora.truncatedTo(ChronoUnit.MINUTES);
        List<MuestraPorMinuto> completas = metricas.porMinuto(ahora.minus(30, ChronoUnit.MINUTES), ahora).stream()
                .filter(m -> m.minuto().isBefore(minutoEnCurso))
                .sorted(Comparator.comparing(MuestraPorMinuto::minuto))
                .toList();

        List<MuestraPorMinuto> ultimas = completas.subList(Math.max(0, completas.size() - 3), completas.size());
        double peticiones = ultimas.stream().mapToDouble(MuestraPorMinuto::peticiones).sum();
        double errores = ultimas.stream().mapToDouble(MuestraPorMinuto::errores).sum();
        boolean sinTrafico = ultimas.size() == 3 && peticiones == 0;
        double tasa = peticiones > 0 ? 100.0 * errores / peticiones : 0;
        Instant inicio = inicioDeLaRachaFinal(completas);

        Severidad severidad = sinTrafico || tasa >= 20 ? Severidad.SEV1 : tasa >= 5 ? Severidad.SEV2 : tasa >= umbralPct ? Severidad.SEV3 : Severidad.NINGUNA;
        if (severidad == Severidad.NINGUNA && !sonda.todoBien()) {
            severidad = Severidad.SEV3; // una dependencia falla aunque aún no se vea en los errores
        }

        List<Cambio> sospechosos = severidad == Severidad.NINGUNA ? List.of() : sospechosos(inicio, ahora);
        return new InformeDeTriage(severidad, redondear(tasa), sinTrafico, inicio, sospechosos,
                recomendaciones(severidad, sinTrafico, inicio, ahora, sospechosos, sonda));
    }

    /** Primer minuto de la racha ininterrumpida de minutos con errores sobre el umbral que llega hasta el último minuto completo. */
    private Instant inicioDeLaRachaFinal(List<MuestraPorMinuto> completas) {
        Instant inicio = null;
        for (int i = completas.size() - 1; i >= 0; i--) {
            MuestraPorMinuto m = completas.get(i);
            if (m.peticiones() > 0 && m.tasa() >= umbralPct) {
                inicio = m.minuto();
            } else {
                break;
            }
        }
        return inicio;
    }

    private List<Cambio> sospechosos(Instant inicio, Instant ahora) {
        Instant desde = inicio != null ? inicio.minus(20, ChronoUnit.MINUTES) : ahora.minus(60, ChronoUnit.MINUTES);
        Instant hasta = inicio != null ? inicio.plus(5, ChronoUnit.MINUTES) : ahora;
        Instant referencia = inicio != null ? inicio : ahora;
        return cambios.desde(desde).stream()
                .filter(c -> !RUIDO.contains(c.evento()))
                .filter(c -> !c.cuando().isBefore(desde) && !c.cuando().isAfter(hasta))
                .sorted(Comparator.comparingLong((Cambio c) -> Math.abs(Duration.between(c.cuando(), referencia).toSeconds())))
                .limit(5)
                .toList();
    }

    private List<Recomendacion> recomendaciones(Severidad sev, boolean sinTrafico, Instant inicio, Instant ahora,
                                                List<Cambio> sospechosos, InformeDeSonda sonda) {
        List<Recomendacion> r = new ArrayList<>();
        if (sev == Severidad.NINGUNA) {
            r.add(new Recomendacion("Sin incidente aparente", "Errores bajo el umbral y dependencias alcanzables"));
            return r;
        }
        if (sev == Severidad.SEV1) {
            r.add(new Recomendacion("Declarar el incidente y asignar comandante, operador, comunicación y escriba", "Severidad 1"));
        }
        if (sinTrafico) {
            r.add(new Recomendacion("Revisar DNS, CDN y WAF antes que la aplicación", "El balanceador no recibe peticiones: el fallo está antes"));
        }
        for (Cambio c : sospechosos) {
            long minutos = Math.abs(Duration.between(c.cuando(), inicio != null ? inicio : ahora).toMinutes());
            r.add(new Recomendacion("Valorar revertir «" + c.evento() + "» sobre " + c.recurso(),
                    "Lo hizo " + c.quien() + " a " + minutos + " min del " + (inicio != null ? "inicio del problema" : "momento actual") + "; mitigar primero, investigar después"));
        }
        for (Hipotesis h : sonda.hipotesis()) {
            r.add(new Recomendacion(h.siguientePaso(), h.dependencia() + ": " + h.causaProbable()));
        }
        if (r.stream().noneMatch(x -> !x.paso().startsWith("Declarar"))) {
            r.add(new Recomendacion("Escalar a desarrollo con la traza de una petición fallida", "Sin cambio reciente ni dependencia sospechosa"));
        }
        return r;
    }

    private static double redondear(double v) {
        return Math.round(v * 100) / 100.0;
    }
}
```

### 2.4 Adaptadores del SDK: CloudTrail, CloudWatch y Logs Insights
Tres detalles que muerden en producción: **CloudTrail `LookupEvents` tarda hasta ~15 minutos en reflejar un cambio y admite pocas llamadas por segundo** (por eso se limita la cantidad y se guarda el informe unos segundos); **CloudWatch omite los minutos sin datos** (hay que rellenarlos con 0); y **Logs Insights es asíncrono** (`StartQuery`, luego sondear `GetQueryResults`, con límite de tiempo y `StopQuery` si se agota).
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.LongConsumer;
import software.amazon.awssdk.services.cloudtrail.CloudTrailClient;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttribute;
import software.amazon.awssdk.services.cloudtrail.model.LookupAttributeKey;
import software.amazon.awssdk.services.cloudtrail.model.LookupEventsRequest;
import software.amazon.awssdk.services.cloudwatch.CloudWatchClient;
import software.amazon.awssdk.services.cloudwatch.model.Dimension;
import software.amazon.awssdk.services.cloudwatch.model.GetMetricDataRequest;
import software.amazon.awssdk.services.cloudwatch.model.Metric;
import software.amazon.awssdk.services.cloudwatch.model.MetricDataQuery;
import software.amazon.awssdk.services.cloudwatch.model.MetricStat;
import software.amazon.awssdk.services.cloudwatch.model.ScanBy;
import software.amazon.awssdk.services.cloudwatchlogs.CloudWatchLogsClient;
import software.amazon.awssdk.services.cloudwatchlogs.model.GetQueryResultsRequest;
import software.amazon.awssdk.services.cloudwatchlogs.model.QueryStatus;
import software.amazon.awssdk.services.cloudwatchlogs.model.StartQueryRequest;
import software.amazon.awssdk.services.cloudwatchlogs.model.StopQueryRequest;

public final class CambiosCloudTrail implements Cambios {

    private final CloudTrailClient cloudTrail;
    private final Clock reloj;
    private final int maximo;

    public CambiosCloudTrail(CloudTrailClient cloudTrail, Clock reloj, int maximo) {
        this.cloudTrail = cloudTrail;
        this.reloj = reloj;
        this.maximo = maximo;
    }

    @Override
    public List<Cambio> desde(Instant desde) {
        var peticion = LookupEventsRequest.builder()
                .startTime(desde).endTime(reloj.instant())
                // Solo eventos que MODIFICAN algo; los de lectura serían miles
                .lookupAttributes(LookupAttribute.builder().attributeKey(LookupAttributeKey.READ_ONLY).attributeValue("false").build())
                .build();
        var lista = new ArrayList<Cambio>();
        for (var pagina : cloudTrail.lookupEventsPaginator(peticion)) {
            for (var e : pagina.events()) {
                String recurso = e.hasResources() && !e.resources().isEmpty() ? String.valueOf(e.resources().get(0).resourceName()) : "(sin recurso)";
                lista.add(new Cambio(e.eventTime(), String.valueOf(e.username()), e.eventName(), recurso));
                if (lista.size() >= maximo) {
                    return lista; // LookupEvents tiene un límite bajo de llamadas por segundo: no se pagina sin fin
                }
            }
        }
        return lista;
    }
}

public final class MetricasCloudWatch implements Metricas {

    private final CloudWatchClient cloudWatch;
    private final String alb;

    public MetricasCloudWatch(CloudWatchClient cloudWatch, String sufijoDelAlb) {
        this.cloudWatch = cloudWatch;
        this.alb = sufijoDelAlb;
    }

    @Override
    public List<MuestraPorMinuto> porMinuto(Instant desde, Instant hasta) {
        Instant inicio = desde.truncatedTo(ChronoUnit.MINUTES);
        var peticion = GetMetricDataRequest.builder()
                .startTime(inicio).endTime(hasta).scanBy(ScanBy.TIMESTAMP_ASCENDING)
                .metricDataQueries(consulta("total", "RequestCount"), consulta("errores", "HTTPCode_Target_5XX_Count"))
                .build();
        Map<String, Map<Instant, Double>> porId = new HashMap<>();
        for (var pagina : cloudWatch.getMetricDataPaginator(peticion)) { // un mismo id puede venir repartido entre páginas
            for (var r : pagina.metricDataResults()) {
                var destino = porId.computeIfAbsent(r.id(), k -> new HashMap<>());
                for (int i = 0; i < r.timestamps().size(); i++) {
                    destino.put(r.timestamps().get(i).truncatedTo(ChronoUnit.MINUTES), r.values().get(i));
                }
            }
        }
        var total = porId.getOrDefault("total", Map.of());
        var errores = porId.getOrDefault("errores", Map.of());
        var muestras = new ArrayList<MuestraPorMinuto>();
        for (Instant m = inicio; m.isBefore(hasta); m = m.plus(1, ChronoUnit.MINUTES)) {
            muestras.add(new MuestraPorMinuto(m, total.getOrDefault(m, 0.0), errores.getOrDefault(m, 0.0))); // sin dato = 0
        }
        return muestras;
    }

    private MetricDataQuery consulta(String id, String metrica) {
        return MetricDataQuery.builder().id(id).returnData(true)
                .metricStat(MetricStat.builder().period(60).stat("Sum")
                        .metric(Metric.builder().namespace("AWS/ApplicationELB").metricName(metrica)
                                .dimensions(Dimension.builder().name("LoadBalancer").value(alb).build()).build())
                        .build())
                .build();
    }
}

public final class RegistrosInsights {

    private final CloudWatchLogsClient logs;
    private final LongConsumer pausaMs;

    public RegistrosInsights(CloudWatchLogsClient logs, LongConsumer pausaMs) {
        this.logs = logs;
        this.pausaMs = pausaMs;
    }

    public List<Map<String, String>> consultar(String grupo, String consulta, Instant desde, Instant hasta, Duration limite) {
        String id = logs.startQuery(StartQueryRequest.builder().logGroupName(grupo).queryString(consulta)
                .startTime(desde.getEpochSecond()).endTime(hasta.getEpochSecond()).limit(50).build()).queryId();
        long fin = System.nanoTime() + limite.toNanos();
        while (true) {
            var r = logs.getQueryResults(GetQueryResultsRequest.builder().queryId(id).build());
            QueryStatus estado = r.status();
            if (estado == QueryStatus.COMPLETE) {
                var filas = new ArrayList<Map<String, String>>();
                for (var fila : r.results()) {
                    var campos = new LinkedHashMap<String, String>();
                    fila.stream().filter(c -> !c.field().startsWith("@ptr")).forEach(c -> campos.put(c.field(), c.value()));
                    filas.add(campos);
                }
                return filas;
            }
            if (estado == QueryStatus.FAILED || estado == QueryStatus.CANCELLED || estado == QueryStatus.TIMEOUT) {
                throw new IllegalStateException("la consulta terminó en estado " + estado);
            }
            if (System.nanoTime() > fin) {
                logs.stopQuery(StopQueryRequest.builder().queryId(id).build()); // no dejar consultas corriendo (se cobran por dato escaneado)
                throw new IllegalStateException("la consulta superó el límite de " + limite.toSeconds() + " s");
            }
            pausaMs.accept(1000);
        }
    }
}
```

### 2.5 El servicio que lo junta (con caché corta)
Cuando salta la alarma, **veinte personas abren el mismo endpoint**. Sin protección, veinte `LookupEvents` por segundo agotan el límite justo cuando más se necesitan. El informe se guarda unos segundos; y si una parte falla (por ejemplo Logs Insights), el resto del informe **igual se entrega**, con un aviso.
```java
// (clase reutilizada en los bloques siguientes, ambos)
public record InformeDeIncidente(Instant generado, InformeDeSonda sonda, InformeDeTriage triage,
                                 List<Map<String, String>> excepcionesFrecuentes, List<String> avisos) { }

public final class ServicioDeIncidente {

    private static final String EXCEPCIONES = "filter nivel = \"ERROR\" | stats count(*) as veces by excepcion, operacion | sort veces desc | limit 10";

    private final SondaSintetica sonda;
    private final List<Dependencia> dependencias;
    private final TriageDeIncidente triage;
    private final RegistrosInsights registros;
    private final String grupoDeLogs;
    private final Clock reloj;
    private final Duration vigencia;
    private InformeDeIncidente guardado;

    public ServicioDeIncidente(SondaSintetica sonda, List<Dependencia> dependencias, TriageDeIncidente triage,
                               RegistrosInsights registros, String grupoDeLogs, Clock reloj, Duration vigencia) {
        this.sonda = sonda;
        this.dependencias = dependencias;
        this.triage = triage;
        this.registros = registros;
        this.grupoDeLogs = grupoDeLogs;
        this.reloj = reloj;
        this.vigencia = vigencia;
    }

    public synchronized InformeDeIncidente evaluar() {
        Instant ahora = reloj.instant();
        if (guardado != null && Duration.between(guardado.generado(), ahora).compareTo(vigencia) < 0) {
            return guardado;
        }
        var avisos = new ArrayList<String>();
        InformeDeSonda deSonda = sonda.ejecutar(dependencias);

        InformeDeTriage deTriage;
        try {
            deTriage = triage.evaluar(deSonda);
        } catch (RuntimeException e) {
            avisos.add("No se pudo calcular el triage (CloudWatch o CloudTrail): " + e.getClass().getSimpleName());
            deTriage = new InformeDeTriage(Severidad.NINGUNA, 0, false, null, List.of(),
                    List.of(new Recomendacion("Seguir el runbook a mano", "El triage automático no pudo ejecutarse; no significa que todo esté bien")));
        }

        List<Map<String, String>> excepciones = List.of();
        try {
            excepciones = registros.consultar(grupoDeLogs, EXCEPCIONES, ahora.minus(30, ChronoUnit.MINUTES), ahora, Duration.ofSeconds(20));
        } catch (RuntimeException e) {
            avisos.add("No se pudieron leer las excepciones (Logs Insights): " + e.getClass().getSimpleName());
        }
        guardado = new InformeDeIncidente(ahora, deSonda, deTriage, excepciones, avisos);
        return guardado;
    }
}
```

## 3. Spring MVC (imperativo)
```java
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.services.cloudtrail.CloudTrailClient;
import software.amazon.awssdk.services.cloudwatch.CloudWatchClient;
import software.amazon.awssdk.services.cloudwatchlogs.CloudWatchLogsClient;

@Configuration
@EnableScheduling
class IncidenteConfiguracion {

    @Bean(destroyMethod = "close")
    DefaultCredentialsProvider credenciales() {
        return DefaultCredentialsProvider.builder().build();
    }

    @Bean(destroyMethod = "close")
    CloudTrailClient cloudTrail() {
        return CloudTrailClient.create();
    }

    @Bean(destroyMethod = "close")
    CloudWatchClient cloudWatch() {
        return CloudWatchClient.create();
    }

    @Bean(destroyMethod = "close")
    CloudWatchLogsClient cloudWatchLogs() {
        return CloudWatchLogsClient.create();
    }

    @Bean
    SondaSintetica sonda(AwsCredentialsProvider credenciales) {
        return new SondaSintetica(new EscaleraDeDiagnostico(new PruebasReales(credenciales), Duration.ofSeconds(3)), Duration.ofSeconds(8));
    }

    @Bean
    List<Dependencia> dependencias(@Value("${sonda.rds}") String rds, @Value("${sonda.redis}") String redis,
                                   @Value("${sonda.sqs}") String sqs, @Value("${sonda.secretos}") String secretos) {
        return List.of(
                new Dependencia("rds-pedidos", rds, 5432, true, true, false),
                new Dependencia("redis-sesiones", redis, 6379, true, true, false),
                new Dependencia("sqs-facturacion", sqs, 443, true, true, true),
                new Dependencia("secretos", secretos, 443, true, true, true));
    }

    @Bean
    ServicioDeIncidente incidente(SondaSintetica sonda, List<Dependencia> dependencias, CloudTrailClient cloudTrail,
                                  CloudWatchClient cloudWatch, CloudWatchLogsClient logs,
                                  @Value("${incidente.alb}") String alb, @Value("${incidente.grupo-logs}") String grupo,
                                  @Value("${incidente.umbral-errores-pct}") double umbral, @Value("${incidente.cache-segundos}") long cache) {
        Clock reloj = Clock.systemUTC();
        var triage = new TriageDeIncidente(new CambiosCloudTrail(cloudTrail, reloj, 200), new MetricasCloudWatch(cloudWatch, alb), reloj, umbral);
        var registros = new RegistrosInsights(logs, ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("interrumpido");
            }
        });
        return new ServicioDeIncidente(sonda, dependencias, triage, registros, grupo, reloj, Duration.ofSeconds(cache));
    }
}

@RestController
@RequestMapping("/diagnostico")
class DiagnosticoControlador {

    private final ServicioDeIncidente servicio;
    private final SondaSintetica sonda;
    private final List<Dependencia> dependencias;

    DiagnosticoControlador(ServicioDeIncidente servicio, SondaSintetica sonda, List<Dependencia> dependencias) {
        this.servicio = servicio;
        this.sonda = sonda;
        this.dependencias = dependencias;
    }

    /** El informe completo del incidente: sonda + triage + excepciones. Solo operaciones, solo red interna. */
    @GetMapping("/incidente")
    @PreAuthorize("hasAuthority('SCOPE_operaciones')")
    InformeDeIncidente incidente() {
        return servicio.evaluar();
    }

    /** Solo la sonda, sin tocar CloudTrail ni CloudWatch (rápida y sin costo por llamada). */
    @GetMapping("/dependencias")
    @PreAuthorize("hasAuthority('SCOPE_operaciones')")
    InformeDeSonda dependencias() {
        return sonda.ejecutar(dependencias);
    }
}

@Component
class SondaProgramada {

    private final SondaSintetica sonda;
    private final List<Dependencia> dependencias;

    SondaProgramada(SondaSintetica sonda, List<Dependencia> dependencias) {
        this.sonda = sonda;
        this.dependencias = dependencias;
    }

    @Scheduled(fixedDelayString = "${sonda.intervalo-ms:60000}")
    void ejecutar() {
        sonda.ejecutar(dependencias); // la línea estructurada alimenta el filtro de métrica y la alarma de la sonda
    }
}
```

## 4. Spring WebFlux (reactivo)
Las pruebas de red del JDK y los clientes síncronos del SDK bloquean: se aíslan en `boundedElastic` (nunca en el bucle de eventos).
```java
import java.util.List;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/reactivo/diagnostico")
class DiagnosticoReactivoControlador {

    private final ServicioDeIncidente servicio;
    private final SondaSintetica sonda;
    private final List<Dependencia> dependencias;

    DiagnosticoReactivoControlador(ServicioDeIncidente servicio, SondaSintetica sonda, List<Dependencia> dependencias) {
        this.servicio = servicio;
        this.sonda = sonda;
        this.dependencias = dependencias;
    }

    @GetMapping("/incidente")
    @PreAuthorize("hasAuthority('SCOPE_operaciones')")
    Mono<InformeDeIncidente> incidente() {
        return Mono.fromCallable(servicio::evaluar).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/dependencias")
    @PreAuthorize("hasAuthority('SCOPE_operaciones')")
    Mono<InformeDeSonda> dependencias() {
        return Mono.fromCallable(() -> sonda.ejecutar(dependencias)).subscribeOn(Schedulers.boundedElastic());
    }
}
```

## 5. Quarkus (imperativo)
```java
// (clase reutilizada en los bloques siguientes)
import io.quarkus.scheduler.Scheduled;
import jakarta.annotation.security.RolesAllowed;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.services.cloudtrail.CloudTrailClient;
import software.amazon.awssdk.services.cloudwatch.CloudWatchClient;
import software.amazon.awssdk.services.cloudwatchlogs.CloudWatchLogsClient;

@ApplicationScoped
class IncidenteProductores {

    @ConfigProperty(name = "sonda.rds")
    String rds;

    @ConfigProperty(name = "sonda.redis")
    String redis;

    @ConfigProperty(name = "sonda.sqs")
    String sqs;

    @ConfigProperty(name = "sonda.secretos")
    String secretos;

    @ConfigProperty(name = "incidente.alb")
    String alb;

    @ConfigProperty(name = "incidente.grupo-logs")
    String grupo;

    @ConfigProperty(name = "incidente.umbral-errores-pct")
    double umbral;

    @ConfigProperty(name = "incidente.cache-segundos")
    long cache;

    @jakarta.enterprise.inject.Produces
    @Singleton
    SondaSintetica sonda() {
        var pruebas = new PruebasReales(DefaultCredentialsProvider.builder().build());
        return new SondaSintetica(new EscaleraDeDiagnostico(pruebas, Duration.ofSeconds(3)), Duration.ofSeconds(8));
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeIncidente incidente(SondaSintetica sonda) {
        Clock reloj = Clock.systemUTC();
        var triage = new TriageDeIncidente(new CambiosCloudTrail(CloudTrailClient.create(), reloj, 200),
                new MetricasCloudWatch(CloudWatchClient.create(), alb), reloj, umbral);
        var registros = new RegistrosInsights(CloudWatchLogsClient.create(), ms -> {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("interrumpido");
            }
        });
        return new ServicioDeIncidente(sonda, dependencias(), triage, registros, grupo, reloj, Duration.ofSeconds(cache));
    }

    List<Dependencia> dependencias() {
        return List.of(
                new Dependencia("rds-pedidos", rds, 5432, true, true, false),
                new Dependencia("redis-sesiones", redis, 6379, true, true, false),
                new Dependencia("sqs-facturacion", sqs, 443, true, true, true),
                new Dependencia("secretos", secretos, 443, true, true, true));
    }
}

@ApplicationScoped
class SondaProgramadaQuarkus {

    @Inject
    SondaSintetica sonda;

    @Inject
    IncidenteProductores productores;

    @Scheduled(every = "1m", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void ejecutar() {
        sonda.ejecutar(productores.dependencias());
    }
}

@Path("/diagnostico")
class DiagnosticoRecurso {

    @Inject
    ServicioDeIncidente servicio;

    @GET
    @Path("/incidente")
    @RolesAllowed("operaciones")
    @jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public InformeDeIncidente incidente() {
        return servicio.evaluar();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/reactivo/diagnostico")
class DiagnosticoRecursoReactivo {

    @Inject
    ServicioDeIncidente servicio;

    @GET
    @Path("/incidente")
    @RolesAllowed("operaciones")
    @jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)
    public Uni<InformeDeIncidente> incidente() {
        return Uni.createFrom().item(servicio::evaluar).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 7. Permisos
| Pieza | Acciones | Recurso |
|---|---|---|
| Sonda | Ninguna acción de AWS más allá de **resolver credenciales** (el pod ya las tiene) | — |
| Triage | `cloudtrail:LookupEvents` | `*` (la API no admite recursos más finos) |
| Triage | `cloudwatch:GetMetricData` | `*` |
| Excepciones | `logs:StartQuery`, `logs:GetQueryResults`, `logs:StopQuery` | ARN del grupo de logs de la aplicación (`StartQuery`) y `*` en `GetQueryResults` |
| Guardia (consola/CLI) | Rol de solo lectura: `ViewOnlyAccess` + `CloudWatchReadOnlyAccess` + `AWSCloudTrail_ReadOnlyAccess` | Cuenta de producción, sesión de 1 h |

Nada de esto necesita escribir en la cuenta. **Mitigar** (revertir, escalar) es un rol aparte, con aprobación.

## 8. Qué NO hacer desde Java
- No expongas el endpoint al público: revela dependencias, rutas y estado interno.
- No uses una identidad más poderosa para la sonda: si ella puede y la aplicación no, la prueba miente.
- No consultes CloudTrail ni Logs Insights en cada petición HTTP: usa el informe guardado unos segundos.
- No trates «sin datos» o «no se pudo consultar» como «todo bien»: es un aviso y se entrega en el informe.
- No dejes consultas de Logs Insights corriendo: `StopQuery` al agotar el límite.
- No pongas datos personales ni secretos en el informe ni en los logs de la sonda.
- No ejecutes estas llamadas síncronas en el bucle de eventos (WebFlux/Vert.x).
- No automatices la mitigación (rollback, escalar) desde este servicio: sugiere, una persona decide.
