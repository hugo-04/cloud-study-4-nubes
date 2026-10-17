import genlib
ROT = '''
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** Política de rotación de API keys de usuarios de servicio. Puro: reloj inyectado. */
public class PoliticaDeRotacion {

    public record Llave(String usuario, String huella, Instant creada, boolean activa) { }

    public enum Accion { OK, ROTAR_PRONTO, ROTAR_YA, BORRAR_VIEJA }

    public record Veredicto(Llave llave, Accion accion, long dias) { }

    private final Clock reloj;
    private final Duration aviso;
    private final Duration maximo;

    public PoliticaDeRotacion(Clock reloj, Duration aviso, Duration maximo) {
        this.reloj = reloj;
        this.aviso = aviso;
        this.maximo = maximo;
    }

    /** Por usuario: la más nueva es la vigente; las demás activas deberían borrarse tras la rotación. */
    public List<Veredicto> evaluar(List<Llave> llaves) {
        var out = new ArrayList<Veredicto>();
        Instant ahora = reloj.instant();
        llaves.stream().filter(Llave::activa).map(Llave::usuario).distinct().forEach(u -> {
            var delUsuario = llaves.stream().filter(l -> l.usuario().equals(u) && l.activa())
                .sorted(Comparator.comparing(Llave::creada).reversed()).toList();
            for (int i = 0; i < delUsuario.size(); i++) {
                var l = delUsuario.get(i);
                long dias = Duration.between(l.creada(), ahora).toDays();
                Accion a;
                if (i > 0) {
                    a = Accion.BORRAR_VIEJA;
                } else if (dias >= maximo.toDays()) {
                    a = Accion.ROTAR_YA;
                } else if (dias >= aviso.toDays()) {
                    a = Accion.ROTAR_PRONTO;
                } else {
                    a = Accion.OK;
                }
                out.add(new Veredicto(l, a, dias));
            }
        });
        return out;
    }
}
'''
SDK = '''
import com.oracle.bmc.identity.IdentityClient;
import com.oracle.bmc.identity.model.ApiKey;
import com.oracle.bmc.identity.requests.ListApiKeysRequest;
import java.util.ArrayList;
import java.util.List;

/** Adaptador del SDK: API keys de los usuarios de servicio indicados. */
public class LlavesOci implements AutoCloseable {

    private final IdentityClient cliente;

    public LlavesOci(IdentityClient cliente) {
        this.cliente = cliente;
    }

    public List<PoliticaDeRotacion.Llave> llaves(List<String> usuarios) {
        var out = new ArrayList<PoliticaDeRotacion.Llave>();
        for (String u : usuarios) {
            for (ApiKey k : cliente.listApiKeys(ListApiKeysRequest.builder().userId(u).build()).getItems()) {
                out.add(new PoliticaDeRotacion.Llave(u, k.getFingerprint(), k.getTimeCreated().toInstant(),
                    k.getLifecycleState() == ApiKey.LifecycleState.Active));
            }
        }
        return out;
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
import java.util.List;

public class ServicioDeRotacion {

    private final LlavesOci llaves;
    private final PoliticaDeRotacion politica = new PoliticaDeRotacion(Clock.systemUTC(), Duration.ofDays(75), Duration.ofDays(90));

    public ServicioDeRotacion(LlavesOci llaves) {
        this.llaves = llaves;
    }

    public List<PoliticaDeRotacion.Veredicto> revisar(List<String> usuariosDeServicio) {
        return politica.evaluar(llaves.llaves(usuariosDeServicio)).stream()
            .filter(v -> v.accion() != PoliticaDeRotacion.Accion.OK)
            .toList();
    }
}
'''
genlib.oci('oci/10-terraform/autenticacion-y-pipelines', 'Terraform · Autenticación y pipelines',
  'Un **vigilante de rotación de llaves** de los usuarios de servicio que usan los runners externos: lee sus API keys con `IdentityClient.listApiKeys` y decide por usuario: la más nueva se evalúa por edad (aviso a los 75 días, rotación obligatoria a los 90) y cualquier otra llave activa debe borrarse. Los runners dentro de OCI no necesitan esto: usan instance principal.',
  [],
  [('Política de rotación (lógica pura)', ROT, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Rotacion', '/terraform/llaves', 'ServicioDeRotacion', 'LlavesOci',
  ['import com.oracle.bmc.identity.IdentityClient;', 'import java.util.List;'],
  'return new LlavesOci(IdentityClient.builder().region(Region.fromRegionId(region)).build(auth));',
  [dict(n='revisar', v='POST', p='/revision', args=[('List<String>', 'usuarios', 'b')], ret='List<PoliticaDeRotacion.Veredicto>', call='s.revisar(usuarios)')],
  [('Listar API keys de usuarios', '`Allow dynamic-group auditoria to inspect users in tenancy` *(verifica el permiso exacto para listar llaves)*')],
  ['No crees ni borres llaves automáticamente sin un procedimiento de rotación probado (nueva → desplegar → borrar vieja).',
   'No registres huellas junto con nombres de usuario en canales abiertos.',
   'No uses API keys en runners que corren dentro de OCI.'])
