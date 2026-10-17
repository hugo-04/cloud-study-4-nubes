import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdoc
VAL = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/** Revisa una especificación de tarea antes de gastar dinero en crearla. Puro: sin SDK. */
public class ValidadorDeTarea {

    public record Tarea(String idTrabajo, String imagen, double ocpus, double memoriaGb, Map<String, String> entorno) { }

    private static final Pattern OCIR = Pattern.compile("^[a-z0-9-]+\\\\.ocir\\\\.io/[a-z0-9]+/[a-z0-9._/-]+(:[A-Za-z0-9._-]+|@sha256:[a-f0-9]{64})$");
    private static final Set<String> SOSPECHOSAS = Set.of("PASSWORD", "PASSWD", "SECRET", "TOKEN", "API_KEY", "PRIVATE_KEY");

    public List<String> errores(Tarea t) {
        var errores = new ArrayList<String>();
        if (t.idTrabajo() == null || !t.idTrabajo().matches("[a-z0-9-]{3,60}")) {
            errores.add("idTrabajo: solo minúsculas, dígitos y guiones (3 a 60)");
        }
        if (t.imagen() == null || !OCIR.matcher(t.imagen()).matches()) {
            errores.add("imagen: debe ser de OCIR con etiqueta fija o digest");
        } else if (t.imagen().endsWith(":latest") || !t.imagen().substring(t.imagen().lastIndexOf('/')).matches(".*[:@].*")) {
            errores.add("imagen: prohibido latest o sin etiqueta");
        }
        if (t.ocpus() < 1 || t.ocpus() > 16) {
            errores.add("ocpus: entre 1 y 16");
        }
        double ratio = t.memoriaGb() / t.ocpus();
        if (ratio < 1 || ratio > 16) {
            errores.add("memoria: entre 1 y 16 GB por OCPU");
        }
        t.entorno().keySet().stream()
            .filter(k -> SOSPECHOSAS.stream().anyMatch(s -> k.toUpperCase(Locale.ROOT).contains(s)))
            .forEach(k -> errores.add("entorno: '" + k + "' parece un secreto; léelo de Vault"));
        return errores;
    }

    /** Clave de idempotencia determinista: el mismo trabajo siempre produce el mismo token. */
    public String tokenDeReintento(Tarea t) {
        return ("tarea-" + t.idTrabajo()).substring(0, Math.min(64, ("tarea-" + t.idTrabajo()).length()));
    }
}
'''
SDK = '''
import com.oracle.bmc.containerinstances.ContainerInstanceClient;
import com.oracle.bmc.containerinstances.model.ContainerInstance;
import com.oracle.bmc.containerinstances.model.CreateContainerDetails;
import com.oracle.bmc.containerinstances.model.CreateContainerInstanceDetails;
import com.oracle.bmc.containerinstances.model.CreateContainerInstanceShapeConfigDetails;
import com.oracle.bmc.containerinstances.model.CreateContainerVnicDetails;
import com.oracle.bmc.containerinstances.requests.CreateContainerInstanceRequest;
import com.oracle.bmc.containerinstances.requests.GetContainerInstanceRequest;
import java.util.List;
import java.util.Map;

/** Adaptador del SDK: traduce la tarea validada a CreateContainerInstance. */
public class LanzadorOci implements AutoCloseable {

    public record Destino(String compartimentoId, String dominio, String subredId) { }

    private final ContainerInstanceClient cliente;
    private final Destino destino;

    public LanzadorOci(ContainerInstanceClient cliente, Destino destino) {
        this.cliente = cliente;
        this.destino = destino;
    }

    public String lanzar(ValidadorDeTarea.Tarea t, String token) {
        var detalles = CreateContainerInstanceDetails.builder()
            .compartmentId(destino.compartimentoId())
            .availabilityDomain(destino.dominio())
            .displayName(t.idTrabajo())
            .shape("CI.Standard.E4.Flex")
            .shapeConfig(CreateContainerInstanceShapeConfigDetails.builder()
                .ocpus((float) t.ocpus()).memoryInGBs((float) t.memoriaGb()).build())
            .containerRestartPolicy(ContainerInstance.ContainerRestartPolicy.Never)
            .gracefulShutdownTimeoutInSeconds(60L)
            .vnics(List.of(CreateContainerVnicDetails.builder()
                .subnetId(destino.subredId()).isPublicIpAssigned(false).build()))
            .containers(List.of(CreateContainerDetails.builder()
                .displayName(t.idTrabajo())
                .imageUrl(t.imagen())
                .environmentVariables(t.entorno())
                .build()))
            .freeformTags(Map.of("trabajo", t.idTrabajo()))
            .build();
        var resp = cliente.createContainerInstance(CreateContainerInstanceRequest.builder()
            .createContainerInstanceDetails(detalles)
            .opcRetryToken(token)
            .build());
        return resp.getContainerInstance().getId();
    }

    public String estado(String id) {
        return cliente.getContainerInstance(GetContainerInstanceRequest.builder().containerInstanceId(id).build())
            .getContainerInstance().getLifecycleState().getValue();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.Map;

public class ServicioDeTareas {

    public record Solicitud(String idTrabajo, String imagen, double ocpus, double memoriaGb, Map<String, String> entorno) { }

    public record Resultado(boolean aceptada, String instanciaId, java.util.List<String> errores) { }

    private final ValidadorDeTarea validador = new ValidadorDeTarea();
    private final LanzadorOci lanzador;

    public ServicioDeTareas(LanzadorOci lanzador) {
        this.lanzador = lanzador;
    }

    public Resultado lanzar(Solicitud s) {
        var t = new ValidadorDeTarea.Tarea(s.idTrabajo(), s.imagen(), s.ocpus(), s.memoriaGb(),
            s.entorno() == null ? Map.of() : s.entorno());
        var errores = validador.errores(t);
        if (!errores.isEmpty()) {
            return new Resultado(false, null, errores);
        }
        return new Resultado(true, lanzador.lanzar(t, validador.tokenDeReintento(t)), java.util.List.of());
    }

    public String estado(String id) {
        return lanzador.estado(id);
    }
}
'''
BEAN = '''        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        var cliente = ContainerInstanceClient.builder().region(Region.fromRegionId(region)).build(auth);
        return new LanzadorOci(cliente, new LanzadorOci.Destino(compartimento, dominio, subred));'''
sec = dict(
  ns='Tareas', ruta='/compute/tareas', servicio='ServicioDeTareas',
  spring_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import com.oracle.bmc.containerinstances.ContainerInstanceClient;', 'import org.springframework.beans.factory.annotation.Value;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    LanzadorOci lanzadorOci(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region,
                            @Value("${tareas.compartimento}") String compartimento, @Value("${tareas.dominio}") String dominio,
                            @Value("${tareas.subred}") String subred) {
''' + BEAN + '''
    }

    @Bean
    ServicioDeTareas servicioDeTareas(LanzadorOci lanzador) {
        return new ServicioDeTareas(lanzador);
    }
''',
  q_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import com.oracle.bmc.containerinstances.ContainerInstanceClient;', 'import jakarta.enterprise.inject.Disposes;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region'), ('String', 'compartimento', 'tareas.compartimento'), ('String', 'dominio', 'tareas.dominio'), ('String', 'subred', 'tareas.subred')],
  q_producer='''    LanzadorOci lanzadorOci() {
''' + BEAN + '''
    }

    void cerrar(@Disposes LanzadorOci l) {
        l.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeTareas servicioDeTareas(LanzadorOci lanzador) {
        return new ServicioDeTareas(lanzador);
    }''',
  endpoints=[
    dict(n='lanzar', v='POST', p='/lanzar', args=[('ServicioDeTareas.Solicitud', 's2', 'b')], ret='ServicioDeTareas.Resultado', call='s.lanzar(s2)'),
    dict(n='estado', v='GET', p='/{id}', args=[('String', 'id', 'p')], ret='String', call='s.estado(id)'),
  ])
jdoc.doc(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../oci/04-compute/container-instances/uso-en-java.md'),
  'Compute · Container Instances',
  'Un **orquestador de lotes**: recibe una especificación de tarea, la **valida** (imagen de OCIR con etiqueta fija, sin `latest`, sin secretos en variables de entorno, proporción memoria/OCPU razonable) y recién entonces llama a `createContainerInstance` con un `opcRetryToken` determinista, para que un reintento nunca cree dos instancias.',
  'oci:\n  auth: instance\n  region: sa-saopaulo-1\ntareas:\n  compartimento: ocid1.compartment.oc1..aaaa\n  dominio: "Uocm:SA-SAOPAULO-1-AD-1"\n  subred: ocid1.subnet.oc1.sa-saopaulo-1.aaaa',
  'oci.auth=instance\noci.region=sa-saopaulo-1\ntareas.compartimento=ocid1.compartment.oc1..aaaa\ntareas.dominio=Uocm:SA-SAOPAULO-1-AD-1\ntareas.subred=ocid1.subnet.oc1.sa-saopaulo-1.aaaa',
  [('Validador de la tarea (lógica pura)', VAL, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('Crear y consultar instancias', '`Allow dynamic-group orquestador to manage compute-container-instances in compartment lotes-prod`'),
   ('Conectar la VNIC', '`Allow dynamic-group orquestador to use subnets in compartment red-prod` (+ `use vnics`, `use network-security-groups`)'),
   ('Descargar la imagen de OCIR', '`Allow dynamic-group contenedores-reportes to read repos in compartment ocir`'),
   ('Dentro del contenedor', '`Allow dynamic-group contenedores-reportes to read secret-bundles in compartment lotes-prod where target.secret.id = \'ocid1.vaultsecret…\'`')],
  ['No reintentes `createContainerInstance` sin `opcRetryToken`.',
   'No pases contraseñas ni tokens en `environmentVariables`: se ven en la API y la consola.',
   'No uses `latest`: valida la etiqueta antes de llamar al SDK.',
   'No esperes el fin del lote con un bucle de `getContainerInstance` cada segundo: consulta con espera creciente o usa eventos.',
   'No dejes instancias `INACTIVE` sin borrar.'])
