import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdoc
HOR = '''
import java.time.DayOfWeek;
import java.time.ZonedDateTime;
import java.util.Set;

/** Etiqueta «horario»: dias-inicio-fin, por ejemplo lv-08-19 (lunes a viernes de 08:00 a 19:00). */
public record Horario(Set<DayOfWeek> dias, int inicio, int fin) {

    public static Horario analizar(String texto) {
        String[] p = texto.strip().toLowerCase().split("-");
        if (p.length != 3) {
            throw new IllegalArgumentException("formato esperado: dias-inicio-fin (lv-08-19)");
        }
        Set<DayOfWeek> dias = switch (p[0]) {
            case "lv" -> Set.of(DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY, DayOfWeek.THURSDAY, DayOfWeek.FRIDAY);
            case "ls" -> Set.of(DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY, DayOfWeek.THURSDAY, DayOfWeek.FRIDAY, DayOfWeek.SATURDAY);
            case "td" -> Set.of(DayOfWeek.values());
            default -> throw new IllegalArgumentException("días desconocidos: " + p[0]);
        };
        int ini = Integer.parseInt(p[1]);
        int fin = Integer.parseInt(p[2]);
        if (ini < 0 || fin > 24 || ini >= fin) {
            throw new IllegalArgumentException("horas inválidas: " + ini + "-" + fin);
        }
        return new Horario(dias, ini, fin);
    }

    public boolean debeEstarEncendida(ZonedDateTime ahora) {
        return dias.contains(ahora.getDayOfWeek()) && ahora.getHour() >= inicio && ahora.getHour() < fin;
    }
}
'''
PLAN = '''
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

/** Decide qué instancias encender o apagar ahora. Puro: no llama a la red. */
public final class PlanificadorDeEncendido {

    public record Instancia(String id, String nombre, String estado, String horario) { }

    public record Accion(String id, String nombre, String accion) { }

    private final ZoneId zona;

    public PlanificadorDeEncendido(ZoneId zona) {
        this.zona = zona;
    }

    public List<Accion> planificar(List<Instancia> instancias, Instant ahora) {
        var salida = new ArrayList<Accion>();
        var local = ahora.atZone(zona);
        for (Instancia i : instancias) {
            if (i.horario() == null || i.horario().isBlank()) {
                continue;
            }
            Horario h;
            try {
                h = Horario.analizar(i.horario());
            } catch (RuntimeException e) {
                continue;
            }
            boolean encendida = h.debeEstarEncendida(local);
            if (encendida && i.estado().equals("STOPPED")) {
                salida.add(new Accion(i.id(), i.nombre(), "START"));
            } else if (!encendida && i.estado().equals("RUNNING")) {
                salida.add(new Accion(i.id(), i.nombre(), "SOFTSTOP"));
            }
        }
        return salida;
    }
}
'''
SDK = '''
import com.oracle.bmc.core.ComputeClient;
import com.oracle.bmc.core.model.Instance;
import com.oracle.bmc.core.requests.InstanceActionRequest;
import com.oracle.bmc.core.requests.ListInstancesRequest;
import java.util.ArrayList;
import java.util.List;

/** Lista instancias y ejecuta acciones con el SDK. */
public class InstanciasOci {

    private final ComputeClient cliente;

    public InstanciasOci(ComputeClient cliente) {
        this.cliente = cliente;
    }

    public List<PlanificadorDeEncendido.Instancia> listar(String compartimentoId) {
        var req = ListInstancesRequest.builder().compartmentId(compartimentoId).build();
        var salida = new ArrayList<PlanificadorDeEncendido.Instancia>();
        for (Instance i : cliente.getPaginators().listInstancesRecordIterator(req)) {
            String horario = i.getFreeformTags() == null ? null : i.getFreeformTags().get("horario");
            salida.add(new PlanificadorDeEncendido.Instancia(i.getId(), i.getDisplayName(), i.getLifecycleState().getValue(), horario));
        }
        return salida;
    }

    public void ejecutar(PlanificadorDeEncendido.Accion a) {
        cliente.instanceAction(InstanceActionRequest.builder().instanceId(a.id()).action(a.accion()).build());
    }
}
'''
SERV = '''
import java.time.Clock;
import java.time.ZoneId;
import java.util.List;

public class ServicioDeHorarios {

    private final InstanciasOci instancias;
    private final PlanificadorDeEncendido planificador;
    private final Clock reloj;

    public ServicioDeHorarios(InstanciasOci instancias, ZoneId zona, Clock reloj) {
        this.instancias = instancias;
        this.planificador = new PlanificadorDeEncendido(zona);
        this.reloj = reloj;
    }

    /** Simulación: devuelve lo que se haría, sin ejecutarlo. */
    public List<PlanificadorDeEncendido.Accion> plan(String compartimentoId) {
        return planificador.planificar(instancias.listar(compartimentoId), reloj.instant());
    }

    /** Ejecuta el plan. Una acción fallida no detiene las demás. */
    public List<PlanificadorDeEncendido.Accion> aplicar(String compartimentoId) {
        var plan = plan(compartimentoId);
        for (var a : plan) {
            try {
                instancias.ejecutar(a);
            } catch (RuntimeException e) {
                // registra el id (no datos sensibles) y sigue con la siguiente
            }
        }
        return plan;
    }
}
'''
sec = dict(
  ns='Horarios', ruta='/compute/horarios', servicio='ServicioDeHorarios',
  spring_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.core.ComputeClient;', 'import org.springframework.beans.factory.annotation.Value;', 'import java.time.Clock;', 'import java.time.ZoneId;', 'import java.util.List;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    ComputeClient computeCliente(@Value("${oci.auth}") String modo, @Value("${oci.region}") String region) {
        return ComputeClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
    }

    @Bean
    ServicioDeHorarios servicioDeHorarios(ComputeClient cliente, @Value("${horarios.zona:America/Lima}") String zona) {
        return new ServicioDeHorarios(new InstanciasOci(cliente), ZoneId.of(zona), Clock.systemUTC());
    }
''',
  q_imports=['import com.oracle.bmc.Region;', 'import com.oracle.bmc.core.ComputeClient;', 'import java.time.Clock;', 'import java.time.ZoneId;', 'import java.util.List;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'region', 'oci.region')],
  q_producer='''    ServicioDeHorarios servicioDeHorarios() {
        var cliente = ComputeClient.builder().region(Region.fromRegionId(region)).build(Autenticacion.crear(modo));
        return new ServicioDeHorarios(new InstanciasOci(cliente), ZoneId.of("America/Lima"), Clock.systemUTC());
    }''',
  endpoints=[
    dict(n='plan', v='GET', p='/plan', args=[('String', 'compartimento', 'q')], ret='List<PlanificadorDeEncendido.Accion>', call='s.plan(compartimento)'),
    dict(n='aplicar', v='POST', p='/aplicar', args=[('String', 'compartimento', 'q')], ret='List<PlanificadorDeEncendido.Accion>', call='s.aplicar(compartimento)'),
  ])
jdoc.doc(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../oci/04-compute/compute-instancias/uso-en-java.md'),
  'Compute · Instancias',
  'Un **planificador de horarios**: lee la etiqueta `horario` (`lv-08-19`) de cada instancia, decide con un reloj inyectable qué encender o apagar en la zona `America/Lima` y lo ejecuta con `ComputeClient`. El endpoint `plan` simula; `aplicar` ejecuta.',
  'oci:\n  auth: instance\n  region: sa-saopaulo-1\nhorarios:\n  zona: America/Lima',
  'oci.auth=instance\noci.region=sa-saopaulo-1',
  [('Etiqueta de horario', HOR, True), ('Planificador', PLAN, True), ('Instancias con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('`ListInstances`', '`Allow dynamic-group planificador to inspect instances in compartment tienda-dev`'),
   ('`InstanceAction` (START/SOFTSTOP)', '`Allow dynamic-group planificador to use instances in compartment tienda-dev where request.operation = \'InstanceAction\'` *(verifica el verbo mínimo)*')],
  ['No apliques el plan en producción sin una lista explícita de compartimentos y una etiqueta de opt-in.',
   'No expongas `/aplicar` sin autenticación: apaga máquinas.',
   'No confundas `SOFTSTOP` (apagado ordenado) con `STOP` (corte inmediato).',
   'No uses la hora local del servidor: usa la zona explícita y un reloj inyectable.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
