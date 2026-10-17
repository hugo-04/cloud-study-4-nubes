import ggen
PLAN = '''
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;

/** Planifica tareas: nombre determinista (idempotencia), agenda acotada y tamaño máximo. Puro. */
public class PlanificadorDeTareas {

    public record Plan(String nombre, Instant ejecutarEn, byte[] cuerpo) { }

    private final Clock reloj;

    public PlanificadorDeTareas(Clock reloj) {
        this.reloj = reloj;
    }

    /** Un recordatorio por carrito y día: crear dos veces el mismo plan da el mismo nombre. */
    public Plan recordatorioDeCarrito(String idCarrito, Duration espera, String cuerpoJson) {
        if (!idCarrito.matches("C-[0-9]{1,12}")) {
            throw new IllegalArgumentException("carrito inválido");
        }
        if (espera.isNegative() || espera.compareTo(Duration.ofDays(30)) > 0) {
            throw new IllegalArgumentException("la agenda máxima es de 30 días");
        }
        byte[] cuerpo = cuerpoJson.getBytes(StandardCharsets.UTF_8);
        if (cuerpo.length > 100 * 1024) {
            throw new IllegalArgumentException("cuerpo demasiado grande: guarda los datos y envía una referencia");
        }
        Instant ahora = reloj.instant();
        String dia = LocalDate.ofInstant(ahora, ZoneOffset.UTC).toString().replace("-", "");
        return new Plan("recordatorio-" + idCarrito + "-" + dia, ahora.plus(espera), cuerpo);
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.api.gax.rpc.AlreadyExistsException;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.tasks.v2.CloudTasksClient;
import com.google.cloud.tasks.v2.CloudTasksSettings;
import com.google.cloud.tasks.v2.HttpMethod;
import com.google.cloud.tasks.v2.HttpRequest;
import com.google.cloud.tasks.v2.OidcToken;
import com.google.cloud.tasks.v2.QueueName;
import com.google.cloud.tasks.v2.Task;
import com.google.cloud.tasks.v2.TaskName;
import com.google.protobuf.ByteString;
import com.google.protobuf.Timestamp;
import java.io.IOException;
import java.io.UncheckedIOException;

/** Adaptador: crea tareas HTTP con OIDC; el nombre repetido se trata como éxito idempotente. */
public class TareasGcp implements AutoCloseable {

    public record Creada(String nombre, boolean nueva) { }

    private final CloudTasksClient cliente;
    private final String proyecto;
    private final String region;
    private final String cola;
    private final String url;
    private final String cuentaDespacho;

    public TareasGcp(GoogleCredentials cred, String proyecto, String region, String cola, String url, String cuentaDespacho) {
        try {
            this.cliente = CloudTasksClient.create(CloudTasksSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
        this.region = region;
        this.cola = cola;
        this.url = url;
        this.cuentaDespacho = cuentaDespacho;
    }

    public Creada crear(PlanificadorDeTareas.Plan p) {
        var nombre = TaskName.of(proyecto, region, cola, p.nombre()).toString();
        var tarea = Task.newBuilder().setName(nombre)
            .setScheduleTime(Timestamp.newBuilder().setSeconds(p.ejecutarEn().getEpochSecond()))
            .setHttpRequest(HttpRequest.newBuilder().setUrl(url).setHttpMethod(HttpMethod.POST)
                .putHeaders("Content-Type", "application/json").setBody(ByteString.copyFrom(p.cuerpo()))
                .setOidcToken(OidcToken.newBuilder().setServiceAccountEmail(cuentaDespacho).setAudience(url.replaceFirst("(https://[^/]+).*", "$1"))))
            .build();
        try {
            cliente.createTask(QueueName.of(proyecto, region, cola), tarea);
            return new Creada(p.nombre(), true);
        } catch (AlreadyExistsException e) {
            return new Creada(p.nombre(), false); // ya estaba programada: idempotente
        }
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.time.Clock;
import java.time.Duration;

public class ServicioDeRecordatorios {

    private final TareasGcp tareas;
    private final PlanificadorDeTareas planificador = new PlanificadorDeTareas(Clock.systemUTC());

    public ServicioDeRecordatorios(TareasGcp tareas) {
        this.tareas = tareas;
    }

    public TareasGcp.Creada programar(String idCarrito) {
        var plan = planificador.recordatorioDeCarrito(idCarrito, Duration.ofHours(24), "{\\"carrito\\":\\"" + idCarrito + "\\"}");
        return tareas.crear(plan);
    }
}
'''
ggen.gcp('gcp/07-mensajeria/cloud-tasks', 'Mensajería · Cloud Tasks',
  'Un **programador de recordatorios idempotente**: la lógica pura genera un **nombre de tarea determinista** por carrito y día, valida la agenda (≤ 30 días) y el tamaño; el adaptador crea la tarea HTTP con `CloudTasksClient.createTask`, hora programada y **token OIDC** de la cuenta de despacho, y trata `ALREADY_EXISTS` como éxito (la tarea ya estaba programada).',
  [('tareas.region', 'southamerica-west1'), ('tareas.cola', 'recordatorios'), ('tareas.url', 'https://correos-abc123-tl.a.run.app/recordatorio'), ('tareas.cuenta', 'tasks-despacho@modalima-prod.iam.gserviceaccount.com')],
  [('Planificador (lógica pura)', PLAN, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Recordatorios', '/mensajeria/recordatorios', 'ServicioDeRecordatorios', 'TareasGcp', [],
  'return new TareasGcp(cred, proyecto, region, cola, url, cuenta);',
  [dict(n='programar', v='POST', p='/{carrito}', args=[('String', 'carrito', 'p')], ret='TareasGcp.Creada', call='s.programar(carrito)')],
  [('Crear tareas', '`roles/cloudtasks.enqueuer` en la cola + `roles/iam.serviceAccountUser` sobre la SA de despacho'),
   ('Despachar al destino', '`roles/run.invoker` para la SA de despacho')],
  ['No crees tareas sin nombre si el productor puede reintentar.',
   'No pongas datos personales completos ni secretos en el cuerpo.',
   'No respondas 500 en el destino ante datos inválidos: reintentará hasta el tope.',
   'No uses Cloud Tasks para difundir a varios sistemas: eso es Pub/Sub.'])
