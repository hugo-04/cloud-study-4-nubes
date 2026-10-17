import ggen
CFG = '''
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Construye las propiedades del cliente Kafka para Managed Kafka (SASL_SSL + OAUTHBEARER con tokens de Google)
 * y dimensiona particiones. Puro: solo mapas y aritmética.
 */
public final class ConfiguracionKafka {

    public record Dimension(int particiones, int consumidoresUtiles, List<String> avisos) { }

    private ConfiguracionKafka() {
    }

    public static String bootstrap(String cluster, String region, String proyecto) {
        return "bootstrap." + cluster + "." + region + ".managedkafka." + proyecto + ".cloud.goog:9092";
    }

    public static Map<String, Object> cliente(String bootstrap, String grupo) {
        var p = new LinkedHashMap<String, Object>();
        p.put("bootstrap.servers", bootstrap);
        p.put("security.protocol", "SASL_SSL");
        p.put("sasl.mechanism", "OAUTHBEARER");
        p.put("sasl.login.callback.handler.class", "com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler");
        p.put("sasl.jaas.config", "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;");
        p.put("acks", "all");
        p.put("enable.idempotence", "true");
        if (grupo != null) {
            p.put("group.id", grupo);
            p.put("enable.auto.commit", "false");
        }
        return p;
    }

    /** Particiones = techo(tasa / tasa por consumidor) con margen de crecimiento. */
    public static Dimension dimensionar(double eventosPorSegundo, double porConsumidor, double margen, int consumidoresPlaneados) {
        int base = (int) Math.ceil(eventosPorSegundo / porConsumidor);
        int particiones = (int) Math.ceil(base * (1 + margen));
        var avisos = new ArrayList<String>();
        if (consumidoresPlaneados > particiones) {
            avisos.add((consumidoresPlaneados - particiones) + " consumidores quedarán inactivos");
        }
        if (consumidoresPlaneados < base) {
            avisos.add("con " + consumidoresPlaneados + " consumidores habrá lag sostenido");
        }
        return new Dimension(particiones, Math.min(consumidoresPlaneados, particiones), avisos);
    }
}
'''
SDK = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import org.apache.kafka.clients.admin.Admin;
import org.apache.kafka.clients.admin.TopicDescription;

/** Adaptador: revisa los temas del clúster con el AdminClient estándar (réplicas e ISR). */
public class KafkaGcp implements AutoCloseable {

    public record Tema(String nombre, int particiones, int replicas, List<String> problemas) { }

    private final Admin admin;

    public KafkaGcp(String bootstrap) {
        this.admin = Admin.create(ConfiguracionKafka.cliente(bootstrap, null));
    }

    public List<Tema> revisar() {
        try {
            var nombres = admin.listTopics().names().get();
            Map<String, TopicDescription> d = admin.describeTopics(nombres).allTopicNames().get();
            var out = new ArrayList<Tema>();
            for (var t : d.values()) {
                var problemas = new ArrayList<String>();
                int rf = t.partitions().isEmpty() ? 0 : t.partitions().get(0).replicas().size();
                if (rf < 3) {
                    problemas.add("factor de réplica " + rf);
                }
                long subreplicadas = t.partitions().stream().filter(p -> p.isr().size() < p.replicas().size()).count();
                if (subreplicadas > 0) {
                    problemas.add(subreplicadas + " particiones sub-replicadas");
                }
                out.add(new Tema(t.name(), t.partitions().size(), rf, problemas));
            }
            return out;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (ExecutionException e) {
            throw new IllegalStateException("no se pudo describir el clúster", e.getCause());
        }
    }

    @Override
    public void close() {
        admin.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeKafka {

    private final KafkaGcp kafka;

    public ServicioDeKafka(KafkaGcp kafka) {
        this.kafka = kafka;
    }

    public ConfiguracionKafka.Dimension dimensionar(double eventos, double porConsumidor, int consumidores) {
        return ConfiguracionKafka.dimensionar(eventos, porConsumidor, 0.5, consumidores);
    }

    public List<KafkaGcp.Tema> revisar() {
        return kafka.revisar();
    }
}
'''
ggen.gcp('gcp/07-mensajeria/managed-kafka', 'Mensajería · Managed Kafka',
  'Con Managed Kafka se usan los **clientes Kafka estándar**; lo propio de Google es la conexión (bootstrap privado y **SASL_SSL + OAUTHBEARER** con el *login handler* de Google, que toma el token de ADC). Aquí: un constructor puro de propiedades y dimensionamiento de particiones, y un adaptador con `Admin` que revisa réplicas e ISR de cada tema. El productor y consumidor con Spring Kafka, Quarkus Messaging y reactivo están en el módulo transversal [Kafka](../../../transversal/kafka/README.md).',
  [('kafka.bootstrap', 'bootstrap.eventos-modalima.southamerica-west1.managedkafka.modalima-prod.cloud.goog:9092')],
  [('Configuración (lógica pura)', CFG, True), ('Adaptador con AdminClient', SDK, True), ('Servicio', SERV, True)],
  'Kafka', '/mensajeria/kafka', 'ServicioDeKafka', 'KafkaGcp', [],
  'return new KafkaGcp(bootstrap);',
  [dict(n='dimensionar', v='GET', p='/dimension', args=[('double', 'eventos', 'q'), ('double', 'porConsumidor', 'q'), ('int', 'consumidores', 'q')], ret='ConfiguracionKafka.Dimension', call='s.dimensionar(eventos, porConsumidor, consumidores)', cpu=True),
   dict(n='revisar', v='GET', p='/temas', args=[], ret='java.util.List<KafkaGcp.Tema>', call='s.revisar()')],
  [('Producir y consumir', '`roles/managedkafka.client` (+ ACL por tema si aplican)'),
   ('Revisar temas (Admin)', '`roles/managedkafka.client`; administrar temas: `roles/managedkafka.admin`')],
  ['No olvides la dependencia del login handler de Google: sin ella falla SASL.',
   'No uses llaves de cuenta de servicio en base64 con SASL/PLAIN si puedes usar OAUTHBEARER.',
   'No produzcas sin clave cuando importa el orden.',
   'No crees temas desde la app: créalos como código.'])
