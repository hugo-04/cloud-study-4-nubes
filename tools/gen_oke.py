import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdoc
SEL = '''
import java.util.Map;

/** Decide qué modo de autenticación usar. Puro: recibe el entorno como mapa. */
public final class SelectorDeAutenticacion {

    /** Orden: configuración explícita > función > pod > VM > archivo local. */
    public String elegir(Map<String, String> entorno, boolean metadatosAlcanzables) {
        String explicito = entorno.get("OCI_AUTH");
        if (explicito != null && !explicito.isBlank()) {
            return explicito;
        }
        if (entorno.containsKey("OCI_RESOURCE_PRINCIPAL_VERSION")) {
            return "resource";
        }
        if (entorno.containsKey("KUBERNETES_SERVICE_HOST")) {
            return "oke";
        }
        return metadatosAlcanzables ? "instance" : "config";
    }
}
'''
POL = '''
import java.util.regex.Pattern;

/** Construye la frase de política para un pod. Valida los nombres antes de interpolar. */
public final class GeneradorDePolitica {

    private static final Pattern NOMBRE_K8S = Pattern.compile("[a-z0-9]([-a-z0-9]*[a-z0-9])?");
    private static final Pattern OCID_CLUSTER = Pattern.compile("ocid1\\\\.cluster\\\\.[a-z0-9]+\\\\.[a-z0-9-]*\\\\.[a-z0-9]+");
    private static final Pattern NOMBRE_BUCKET = Pattern.compile("[A-Za-z0-9._-]{1,256}");
    private static final Pattern NOMBRE_COMPARTIMENTO = Pattern.compile("[A-Za-z0-9._:-]{1,100}");

    public String lecturaDeBucket(String compartimento, String clusterId, String namespace, String cuenta, String bucket) {
        exigir(NOMBRE_COMPARTIMENTO, compartimento, "compartimento");
        exigir(OCID_CLUSTER, clusterId, "clúster");
        exigir(NOMBRE_K8S, namespace, "namespace");
        exigir(NOMBRE_K8S, cuenta, "cuenta de servicio");
        exigir(NOMBRE_BUCKET, bucket, "bucket");
        if (cuenta.equals("default")) {
            throw new IllegalArgumentException("no des permisos al ServiceAccount default");
        }
        return "Allow any-user to read objects in compartment " + compartimento
            + " where all {request.principal.type = 'workload'"
            + ", request.principal.cluster_id = '" + clusterId + "'"
            + ", request.principal.namespace = '" + namespace + "'"
            + ", request.principal.service_account = '" + cuenta + "'"
            + ", target.bucket.name = '" + bucket + "'}";
    }

    private static void exigir(Pattern patron, String valor, String que) {
        if (valor == null || !patron.matcher(valor).matches()) {
            throw new IllegalArgumentException(que + " con formato inválido");
        }
    }
}
'''
SDK = '''
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.GetNamespaceRequest;

/** Prueba de identidad: si puedo pedir el namespace de Object Storage, el proveedor y la red funcionan. */
public class PruebaDeIdentidad implements AutoCloseable {

    private final ObjectStorageClient cliente;

    public PruebaDeIdentidad(BasicAuthenticationDetailsProvider auth, String region) {
        this.cliente = ObjectStorageClient.builder().region(Region.fromRegionId(region)).build(auth);
    }

    public String namespaceVisible() {
        return cliente.getNamespace(GetNamespaceRequest.builder().build()).getValue();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.Map;

public class ServicioDeIdentidad {

    public record Estado(String modo, boolean funciona, String detalle) { }

    private final SelectorDeAutenticacion selector = new SelectorDeAutenticacion();
    private final GeneradorDePolitica politicas = new GeneradorDePolitica();
    private final PruebaDeIdentidad prueba;
    private final Map<String, String> entorno;

    public ServicioDeIdentidad(PruebaDeIdentidad prueba, Map<String, String> entorno) {
        this.prueba = prueba;
        this.entorno = entorno;
    }

    public Estado estado() {
        String modo = selector.elegir(entorno, false);
        try {
            prueba.namespaceVisible();
            return new Estado(modo, true, "el proveedor obtuvo credenciales y llegó al servicio");
        } catch (RuntimeException e) {
            return new Estado(modo, false, e.getClass().getSimpleName());
        }
    }

    public String politica(String compartimento, String clusterId, String namespace, String cuenta, String bucket) {
        return politicas.lecturaDeBucket(compartimento, clusterId, namespace, cuenta, bucket);
    }
}
'''
sec = dict(
  ns='Identidad', ruta='/iam/identidad', servicio='ServicioDeIdentidad',
  spring_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import org.springframework.beans.factory.annotation.Value;', 'import java.util.Map;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    PruebaDeIdentidad pruebaDeIdentidad(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new PruebaDeIdentidad(auth, region);
    }

    @Bean
    ServicioDeIdentidad servicioDeIdentidad(PruebaDeIdentidad prueba) {
        return new ServicioDeIdentidad(prueba, System.getenv());
    }
''',
  q_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import jakarta.enterprise.inject.Disposes;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region')],
  q_producer='''    PruebaDeIdentidad pruebaDeIdentidad() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new PruebaDeIdentidad(auth, region);
    }

    void cerrar(@Disposes PruebaDeIdentidad p) {
        p.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeIdentidad servicioDeIdentidad(PruebaDeIdentidad prueba) {
        return new ServicioDeIdentidad(prueba, System.getenv());
    }''',
  endpoints=[
    dict(n='estado', v='GET', p='/estado', args=[], ret='ServicioDeIdentidad.Estado', call='s.estado()'),
    dict(n='politica', v='GET', p='/politica', args=[('String', 'compartimento', 'q'), ('String', 'cluster', 'q'), ('String', 'namespace', 'q'), ('String', 'cuenta', 'q'), ('String', 'bucket', 'q')], ret='String', call='s.politica(compartimento, cluster, namespace, cuenta, bucket)', cpu=True),
  ])
jdoc.doc(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../oci/02-iam/workload-identity-oke/uso-en-java.md'),
  'IAM · Workload Identity en OKE',
  'Tres piezas: un **selector de modo de autenticación** (pod, función, VM o laptop), un **generador de la frase de política** del pod (valida cada nombre antes de interpolar) y una **prueba de identidad** con Object Storage que confirma que el proveedor `oke` y la red funcionan.',
  'oci:\n  auth: oke          # en el Deployment: variable OCI_AUTH\n  region: sa-saopaulo-1',
  'oci.auth=oke\noci.region=sa-saopaulo-1',
  [('Selector de modo', SEL, True), ('Generador de la política', POL, True), ('Prueba de identidad con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('`GetNamespace` de Object Storage', 'Cualquier política del pod sobre Object Storage; si falla con 404, aún no hay permiso suficiente'),
   ('Generar la frase', 'Ninguna: es lógica pura; la frase se aplica por Terraform')],
  ['No hagas público el endpoint `/estado` ni `/politica`: revelan configuración de seguridad.',
   'No construyas frases de política concatenando texto de usuarios sin validar (el generador valida con patrones).',
   'No uses el ServiceAccount `default` ni guardes llaves en Secrets de Kubernetes.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
