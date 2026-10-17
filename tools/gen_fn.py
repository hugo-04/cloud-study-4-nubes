import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdoc
HANDLER = '''
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Locale;

/** El cuerpo de la función (se declara en func.yaml: com.modalima.NormalizadorDePedido::handleRequest). */
public class NormalizadorDePedido {

    /** Entrada: «idPedido|monto|moneda». Salida: «ID|monto con 2 decimales|MONEDA». */
    public String handleRequest(String entrada) {
        if (entrada == null || entrada.length() > 200) {
            throw new IllegalArgumentException("entrada vacía o demasiado grande");
        }
        String[] p = entrada.strip().split("\\\\|");
        if (p.length != 3) {
            throw new IllegalArgumentException("formato esperado: idPedido|monto|moneda");
        }
        BigDecimal monto = new BigDecimal(p[1].strip()).setScale(2, RoundingMode.HALF_UP);
        if (monto.signum() <= 0) {
            throw new IllegalArgumentException("el monto debe ser positivo");
        }
        return p[0].strip().toUpperCase(Locale.ROOT) + "|" + monto.toPlainString() + "|" + p[2].strip().toUpperCase(Locale.ROOT);
    }
}
'''
RETRY = '''
import java.time.Duration;
import java.util.function.DoubleSupplier;
import java.util.function.Supplier;

/** Reintentos con espera exponencial y «full jitter». Puro: el sueño y el azar se inyectan. */
public class Reintentador {

    /** Falla que vale la pena reintentar (429, 502, 503, 504, cortes de red). */
    public static class FallaTransitoria extends RuntimeException {
        public FallaTransitoria(String mensaje, Throwable causa) {
            super(mensaje, causa);
        }
    }

    public interface Durmiente {
        void dormir(Duration d);
    }

    private final int maxIntentos;
    private final Duration base;
    private final Duration tope;
    private final DoubleSupplier azar;
    private final Durmiente durmiente;

    public Reintentador(int maxIntentos, Duration base, Duration tope, DoubleSupplier azar, Durmiente durmiente) {
        this.maxIntentos = maxIntentos;
        this.base = base;
        this.tope = tope;
        this.azar = azar;
        this.durmiente = durmiente;
    }

    public Duration espera(int intento) {
        long techo = Math.min(tope.toMillis(), base.toMillis() * (1L << Math.min(intento, 20)));
        return Duration.ofMillis((long) (azar.getAsDouble() * techo));
    }

    public <T> T ejecutar(Supplier<T> operacion) {
        for (int intento = 0; ; intento++) {
            try {
                return operacion.get();
            } catch (FallaTransitoria e) {
                if (intento + 1 >= maxIntentos) {
                    throw e;
                }
                durmiente.dormir(espera(intento));
            }
        }
    }
}
'''
SDK = '''
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.functions.FunctionsInvokeClient;
import com.oracle.bmc.functions.FunctionsManagementClient;
import com.oracle.bmc.functions.requests.GetFunctionRequest;
import com.oracle.bmc.functions.requests.InvokeFunctionRequest;
import com.oracle.bmc.model.BmcException;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Invoca funciones: cada función tiene su propio endpoint de invocación. */
public class FuncionesOci implements AutoCloseable {

    private static final Set<Integer> TRANSITORIOS = Set.of(429, 502, 503, 504);

    private final BasicAuthenticationDetailsProvider auth;
    private final FunctionsManagementClient gestion;
    private final Map<String, FunctionsInvokeClient> invocadores = new ConcurrentHashMap<>();

    public FuncionesOci(BasicAuthenticationDetailsProvider auth, FunctionsManagementClient gestion) {
        this.auth = auth;
        this.gestion = gestion;
    }

    public String invocar(String functionId, String cuerpo) {
        var cliente = invocadores.computeIfAbsent(functionId, id -> {
            String endpoint = gestion.getFunction(GetFunctionRequest.builder().functionId(id).build()).getFunction().getInvokeEndpoint();
            return FunctionsInvokeClient.builder().endpoint(endpoint).build(auth);
        });
        var req = InvokeFunctionRequest.builder()
            .functionId(functionId)
            .fnInvokeType(InvokeFunctionRequest.FnInvokeType.Sync)
            .invokeFunctionBody(new ByteArrayInputStream(cuerpo.getBytes(StandardCharsets.UTF_8)))
            .build();
        try (var in = cliente.invokeFunction(req).getInputStream()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (BmcException e) {
            if (TRANSITORIOS.contains(e.getStatusCode())) {
                throw new Reintentador.FallaTransitoria("función no disponible (" + e.getStatusCode() + ")", e);
            }
            throw e;
        } catch (IOException e) {
            throw new Reintentador.FallaTransitoria("corte al leer la respuesta", e);
        }
    }

    @Override
    public void close() {
        invocadores.values().forEach(FunctionsInvokeClient::close);
        gestion.close();
    }
}
'''
SERV = '''
import java.time.Duration;
import java.util.concurrent.ThreadLocalRandom;

public class ServicioDeFunciones {

    private final FuncionesOci funciones;
    private final Reintentador reintentos;

    public ServicioDeFunciones(FuncionesOci funciones) {
        this.funciones = funciones;
        this.reintentos = new Reintentador(4, Duration.ofMillis(200), Duration.ofSeconds(3),
            () -> ThreadLocalRandom.current().nextDouble(), d -> {
                try {
                    Thread.sleep(d.toMillis());
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException("interrumpido", e);
                }
            });
    }

    public record Solicitud(String functionId, String cuerpo) { }

    public String normalizar(Solicitud s) {
        return reintentos.ejecutar(() -> funciones.invocar(s.functionId(), s.cuerpo()));
    }
}
'''
sec = dict(
  ns='Funciones', ruta='/compute/funciones', servicio='ServicioDeFunciones',
  spring_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import com.oracle.bmc.functions.FunctionsManagementClient;', 'import org.springframework.beans.factory.annotation.Value;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    FuncionesOci funcionesOci(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        var gestion = FunctionsManagementClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new FuncionesOci(auth, gestion);
    }

    @Bean
    ServicioDeFunciones servicioDeFunciones(FuncionesOci funciones) {
        return new ServicioDeFunciones(funciones);
    }
''',
  q_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import com.oracle.bmc.functions.FunctionsManagementClient;', 'import jakarta.enterprise.inject.Disposes;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region')],
  q_producer='''    FuncionesOci funcionesOci() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        var gestion = FunctionsManagementClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new FuncionesOci(auth, gestion);
    }

    void cerrar(@Disposes FuncionesOci f) {
        f.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeFunciones servicioDeFunciones(FuncionesOci funciones) {
        return new ServicioDeFunciones(funciones);
    }''',
  endpoints=[
    dict(n='normalizar', v='POST', p='/normalizar', args=[('ServicioDeFunciones.Solicitud', 's2', 'b')], ret='String', call='s.normalizar(s2)'),
  ])
jdoc.doc(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../oci/04-compute/functions/uso-en-java.md'),
  'Compute · Functions',
  'Dos lados de una función: **el cuerpo** (un manejador Java puro que la FDK invoca, declarado en `func.yaml`) y **el cliente** que la llama con `FunctionsInvokeClient`, con reintentos de espera exponencial y *jitter* solo ante fallas transitorias.',
  'oci:\n  auth: instance\n  region: sa-saopaulo-1',
  'oci.auth=instance\noci.region=sa-saopaulo-1',
  [('El cuerpo de la función', HANDLER, True), ('Reintentos con jitter', RETRY, True), ('Invocación con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('Invocar una función', '`Allow dynamic-group app-pedidos to use fn-invocation in compartment tienda-prod`'),
   ('`GetFunction` (descubrir el endpoint)', '`Allow dynamic-group app-pedidos to read fn-function in compartment tienda-prod`'),
   ('Dentro de la función (resource principal)', '`Allow dynamic-group funciones-tienda to read objects in compartment tienda-prod where target.bucket.name = \'comprobantes\'`')],
  ['No reintentes errores definitivos (400, 404, 401): solo 429/502/503/504 y cortes de red.',
   'No reintentes funciones no idempotentes sin una clave de idempotencia en el cuerpo.',
   'No pongas secretos en la configuración de la función: léelos de Vault.',
   'No uses `Thread.sleep` en el bucle de eventos (en WebFlux/Mutiny el SDK ya corre en un hilo aparte).',
   'No registres el cuerpo completo de las solicitudes.'])
