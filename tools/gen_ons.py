import genlib
AGR = '''
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/** Agrupa alertas repetidas por clave en ventanas: la primera sale, las demás se cuentan. Puro: reloj inyectado. */
public class AgrupadorDeAlertas {

    public record Alerta(String clave, String titulo, String detalle) { }

    public record Publicable(String titulo, String cuerpo) { }

    private record Ventana(Instant inicio, int suprimidas) { }

    private final Clock reloj;
    private final Duration ventana;
    private final Map<String, Ventana> abiertas = new ConcurrentHashMap<>();

    public AgrupadorDeAlertas(Clock reloj, Duration ventana) {
        this.reloj = reloj;
        this.ventana = ventana;
    }

    public Optional<Publicable> registrar(Alerta a) {
        Instant ahora = reloj.instant();
        var previa = abiertas.get(a.clave());
        if (previa != null && ahora.isBefore(previa.inicio().plus(ventana))) {
            abiertas.put(a.clave(), new Ventana(previa.inicio(), previa.suprimidas() + 1));
            return Optional.empty();
        }
        abiertas.put(a.clave(), new Ventana(ahora, 0));
        String extra = previa != null && previa.suprimidas() > 0
            ? "\\n(+" + previa.suprimidas() + " repeticiones en la ventana anterior)" : "";
        return Optional.of(new Publicable(recortar(a.titulo(), 120), recortar(a.detalle(), 2000) + extra));
    }

    private static String recortar(String s, int max) {
        String limpio = s == null ? "" : s.replaceAll("[\\\\p{Cntrl}&&[^\\\\n]]", " ");
        return limpio.length() <= max ? limpio : limpio.substring(0, max - 1) + "…";
    }
}
'''
SDK = '''
import com.oracle.bmc.ons.NotificationDataPlaneClient;
import com.oracle.bmc.ons.model.MessageDetails;
import com.oracle.bmc.ons.requests.PublishMessageRequest;

/** Adaptador del SDK: publica en un tema. */
public class TemaOci implements AutoCloseable {

    private final NotificationDataPlaneClient cliente;
    private final String temaId;

    public TemaOci(NotificationDataPlaneClient cliente, String temaId) {
        this.cliente = cliente;
        this.temaId = temaId;
    }

    public String publicar(String titulo, String cuerpo) {
        return cliente.publishMessage(PublishMessageRequest.builder().topicId(temaId)
                .messageDetails(MessageDetails.builder().title(titulo).body(cuerpo).build()).build())
            .getPublishResult().getMessageId();
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

public class ServicioDeAlertas {

    public record Resultado(boolean publicada, String idMensaje) { }

    private final TemaOci tema;
    private final AgrupadorDeAlertas agrupador = new AgrupadorDeAlertas(Clock.systemUTC(), Duration.ofMinutes(5));

    public ServicioDeAlertas(TemaOci tema) {
        this.tema = tema;
    }

    public Resultado alertar(AgrupadorDeAlertas.Alerta a) {
        return agrupador.registrar(a)
            .map(p -> new Resultado(true, tema.publicar(p.titulo(), p.cuerpo())))
            .orElse(new Resultado(false, null));
    }
}
'''
genlib.oci('oci/07-mensajeria/notifications', 'Mensajería · Notifications',
  'Un **publicador de alertas sin tormentas**: la lógica pura agrupa alertas por clave en ventanas de 5 minutos (la primera sale, las demás se cuentan y se informan en la siguiente) y limpia títulos y cuerpos; el adaptador publica con `NotificationDataPlaneClient.publishMessage`.',
  [('alertas.tema', 'ocid1.onstopic.oc1.sa-saopaulo-1.aaaa')],
  [('Agrupador de alertas (lógica pura)', AGR, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Alertas', '/mensajeria/alertas', 'ServicioDeAlertas', 'TemaOci',
  ['import com.oracle.bmc.ons.NotificationDataPlaneClient;'],
  'return new TemaOci(NotificationDataPlaneClient.builder().region(Region.fromRegionId(region)).build(auth), tema);',
  [dict(n='alertar', v='POST', p='', args=[('AgrupadorDeAlertas.Alerta', 'a', 'b')], ret='ServicioDeAlertas.Resultado', call='s.alertar(a)')],
  [('Publicar en el tema', "`Allow dynamic-group app-tienda to use ons-topics in compartment tienda-prod where target.topic.id = '<ocid>'`")],
  ['No publiques una alerta por cada error: agrupa.',
   'No incluyas datos personales, tokens ni *stack traces* completos.',
   'No uses Notifications como cola de trabajo con reintentos largos.',
   'No bloquees el hilo de eventos al publicar en WebFlux/Mutiny.'])
