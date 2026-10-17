import ggen
MAN = '''
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Lógica del manejador de un mensaje de Pub/Sub recibido como CloudEvent. Pura y probable sin la plataforma. */
public class ManejadorDeFoto {

    /** Forma del cuerpo que entrega Pub/Sub (push o CloudEvent messagePublished). */
    public record Envoltura(Mensaje message, String subscription) { }

    public record Mensaje(String data, String messageId, Map<String, String> attributes) { }

    public record Resultado(String estado, String detalle) { }

    private final Set<String> procesados = ConcurrentHashMap.newKeySet(); // en producción: almacén compartido

    public Resultado manejar(Envoltura e) {
        if (e == null || e.message() == null || e.message().messageId() == null) {
            return new Resultado("DESCARTADO", "mensaje incompleto");
        }
        if (!procesados.add(e.message().messageId())) {
            return new Resultado("DUPLICADO", e.message().messageId());
        }
        String objeto = new String(Base64.getDecoder().decode(e.message().data() == null ? "" : e.message().data()), StandardCharsets.UTF_8);
        if (!objeto.matches("fotos/[A-Za-z0-9_-]{1,80}\\\\.(jpg|png)")) {
            return new Resultado("DESCARTADO", "objeto fuera de convención");
        }
        String salida = "miniaturas/" + objeto.substring("fotos/".length()); // determinista y en otro prefijo/bucket
        return new Resultado("PROCESAR", salida);
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.functions.v2.FunctionServiceClient;
import com.google.cloud.functions.v2.FunctionServiceSettings;
import com.google.cloud.functions.v2.ServiceConfig;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;

/** Adaptador: inventario y auditoría de funciones del proyecto (todas las regiones). */
public class FuncionesGcp implements AutoCloseable {

    public record Hallazgo(String funcion, String mensaje) { }

    private final FunctionServiceClient cliente;
    private final String proyecto;

    public FuncionesGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = FunctionServiceClient.create(FunctionServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public List<Hallazgo> auditar() {
        var h = new ArrayList<Hallazgo>();
        for (var f : cliente.listFunctions("projects/" + proyecto + "/locations/-").iterateAll()) {
            String n = f.getName().substring(f.getName().lastIndexOf('/') + 1);
            var sc = f.getServiceConfig();
            if (sc.getIngressSettings() == ServiceConfig.IngressSettings.ALLOW_ALL) {
                h.add(new Hallazgo(n, "ingress abierto a Internet: ¿es un webhook con firma?"));
            }
            if (sc.getMaxInstanceCount() == 0 || sc.getMaxInstanceCount() > 100) {
                h.add(new Hallazgo(n, "sin máximo de instancias razonable"));
            }
            if (sc.getServiceAccountEmail().endsWith("-compute@developer.gserviceaccount.com")) {
                h.add(new Hallazgo(n, "usa la cuenta por defecto de Compute"));
            }
            String rt = f.getBuildConfig().getRuntime();
            if (rt.startsWith("java") && Integer.parseInt(rt.substring(4)) < 21) {
                h.add(new Hallazgo(n, "runtime " + rt + ": actualiza a java21"));
            }
        }
        return h;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeFunciones {

    private final FuncionesGcp funciones;
    private final ManejadorDeFoto manejador = new ManejadorDeFoto();

    public ServicioDeFunciones(FuncionesGcp funciones) {
        this.funciones = funciones;
    }

    /** Misma lógica que la función: aquí se expone como endpoint push de Pub/Sub para probarla. */
    public ManejadorDeFoto.Resultado recibir(ManejadorDeFoto.Envoltura e) {
        return manejador.manejar(e);
    }

    public List<FuncionesGcp.Hallazgo> auditar() {
        return funciones.auditar();
    }
}
'''
ggen.gcp('gcp/04-compute/cloud-functions', 'Compute · Cloud Run functions',
  'Dos piezas: la **lógica pura del manejador** de un mensaje de Pub/Sub (decodifica base64, deduplica por `messageId`, valida el nombre y calcula una salida determinista en otro prefijo), que se usa tal cual dentro de la función ([`ejemplos/funcion/MiniaturaFuncion.java`](ejemplos/funcion/MiniaturaFuncion.java)) o en un endpoint *push*; y un **auditor de funciones** con `FunctionServiceClient.listFunctions` (ingress abierto, sin máximo de instancias, cuenta por defecto, runtime viejo).',
  [],
  [('Manejador (lógica pura)', MAN, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Funciones', '/compute/funciones', 'ServicioDeFunciones', 'FuncionesGcp', ['import java.util.List;'],
  'return new FuncionesGcp(cred, proyecto);',
  [dict(n='recibir', v='POST', p='/push', args=[('ManejadorDeFoto.Envoltura', 'e', 'b')], ret='ManejadorDeFoto.Resultado', call='s.recibir(e)', cpu=True),
   dict(n='auditar', v='GET', p='/auditoria', args=[], ret='List<FuncionesGcp.Hallazgo>', call='s.auditar()')],
  [('Listar funciones', '`roles/cloudfunctions.viewer`')],
  ['No proceses dos veces el mismo `messageId`.',
   'No escribas la salida donde dispara el evento.',
   'No dejes el ingress abierto sin verificar firmas.',
   'No hagas trabajo de minutos en una función de eventos.'])
