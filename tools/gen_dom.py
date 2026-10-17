import sys; sys.path.insert(0, '/tmp/claude-0/-home-claude/91a1f301-d8cc-52b1-b5f2-6ef32b63def7/scratchpad')
import jdoc
RES = '''
import java.util.Set;

public record UsuarioResumen(String id, String usuario, boolean activo, Set<String> grupos) { }
'''
AUD = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Reglas de higiene sobre usuarios del dominio. Puro: no llama a la red. */
public final class AuditorDeUsuarios {

    public record Hallazgo(String usuario, String motivo) { }

    private final Set<String> gruposPrivilegiados;
    private final int maxPrivilegiados;

    public AuditorDeUsuarios(Set<String> gruposPrivilegiados, int maxPrivilegiados) {
        this.gruposPrivilegiados = gruposPrivilegiados;
        this.maxPrivilegiados = maxPrivilegiados;
    }

    public List<Hallazgo> revisar(List<UsuarioResumen> usuarios) {
        var salida = new ArrayList<Hallazgo>();
        int privilegiados = 0;
        for (UsuarioResumen u : usuarios) {
            if (!u.activo()) {
                continue;
            }
            if (u.grupos().isEmpty()) {
                salida.add(new Hallazgo(u.usuario(), "activo y sin grupo: o sobra o falta un permiso"));
            }
            if (u.grupos().stream().anyMatch(gruposPrivilegiados::contains)) {
                privilegiados++;
            }
        }
        if (privilegiados > maxPrivilegiados) {
            salida.add(new Hallazgo("(global)", privilegiados + " usuarios activos en grupos privilegiados; el máximo acordado es " + maxPrivilegiados));
        }
        return salida;
    }
}
'''
SDK = '''
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.identitydomains.IdentityDomainsClient;
import com.oracle.bmc.identitydomains.model.User;
import com.oracle.bmc.identitydomains.model.UserGroups;
import com.oracle.bmc.identitydomains.requests.ListUsersRequest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;

/** Lee usuarios del dominio por SCIM (paginación con startIndex base 1). */
public class UsuariosDeDominio implements AutoCloseable {

    private static final int PAGINA = 100;

    private final IdentityDomainsClient cliente;

    public UsuariosDeDominio(BasicAuthenticationDetailsProvider auth, String urlDelDominio) {
        this.cliente = IdentityDomainsClient.builder().endpoint(urlDelDominio).build(auth);
    }

    public List<UsuarioResumen> todos() {
        var salida = new ArrayList<UsuarioResumen>();
        int inicio = 1;
        while (true) {
            var req = ListUsersRequest.builder().startIndex(inicio).count(PAGINA).build();
            var users = cliente.listUsers(req).getUsers();
            List<User> pagina = users.getResources();
            if (pagina == null || pagina.isEmpty()) {
                break;
            }
            for (User u : pagina) {
                var grupos = new HashSet<String>();
                if (u.getGroups() != null) {
                    for (UserGroups g : u.getGroups()) {
                        grupos.add(g.getDisplay());
                    }
                }
                salida.add(new UsuarioResumen(u.getId(), u.getUserName(), Boolean.TRUE.equals(u.getActive()), grupos));
            }
            inicio += pagina.size();
            if (users.getTotalResults() != null && inicio > users.getTotalResults()) {
                break;
            }
        }
        return salida;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;
import java.util.function.Supplier;

public class ServicioDeDominio {

    private final Supplier<List<UsuarioResumen>> usuarios;
    private final AuditorDeUsuarios auditor;

    public ServicioDeDominio(Supplier<List<UsuarioResumen>> usuarios, AuditorDeUsuarios auditor) {
        this.usuarios = usuarios;
        this.auditor = auditor;
    }

    public List<AuditorDeUsuarios.Hallazgo> auditar() {
        return auditor.revisar(usuarios.get());
    }

    public List<AuditorDeUsuarios.Hallazgo> auditarLista(List<UsuarioResumen> lista) {
        return auditor.revisar(lista);
    }
}
'''
sec = dict(
  ns='Dominio', ruta='/iam/dominio', servicio='ServicioDeDominio',
  spring_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import org.springframework.beans.factory.annotation.Value;', 'import java.util.List;', 'import java.util.Set;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    UsuariosDeDominio usuariosDeDominio(@Value("${oci.auth}") String modo, @Value("${oci.dominio-url}") String url) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new UsuariosDeDominio(auth, url);
    }

    @Bean
    ServicioDeDominio servicioDeDominio(UsuariosDeDominio usuarios, @Value("${iam.max-privilegiados:3}") int max) {
        return new ServicioDeDominio(usuarios::todos, new AuditorDeUsuarios(Set.of("Administrators", "Domain_Administrators"), max));
    }
''',
  q_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import java.util.List;', 'import java.util.Set;', 'import jakarta.enterprise.inject.Disposes;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'url', 'oci.dominio-url')],
  q_producer='''    UsuariosDeDominio usuariosDeDominio() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new UsuariosDeDominio(auth, url);
    }

    void cerrar(@Disposes UsuariosDeDominio u) {
        u.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeDominio servicioDeDominio(UsuariosDeDominio usuarios) {
        return new ServicioDeDominio(usuarios::todos, new AuditorDeUsuarios(Set.of("Administrators", "Domain_Administrators"), 3));
    }''',
  endpoints=[
    dict(n='auditoria', v='GET', p='/auditoria', args=[], ret='List<AuditorDeUsuarios.Hallazgo>', call='s.auditar()'),
    dict(n='revisar', v='POST', p='/revisar', args=[('List<UsuarioResumen>', 'usuarios', 'b')], ret='List<AuditorDeUsuarios.Hallazgo>', call='s.auditarLista(usuarios)', cpu=True),
  ])
jdoc.doc('/home/claude/cloud-study-4-nubes/oci/02-iam/identity-domains/uso-en-java.md',
  'IAM · Identity Domains',
  'Un **auditor de higiene de usuarios** (puro: activos sin grupo, exceso de privilegiados) alimentado por la API **SCIM** del dominio con `IdentityDomainsClient`, que usa la **URL del dominio** como endpoint.',
  'oci:\n  auth: instance\n  dominio-url: https://idcs-xxxx.identity.oraclecloud.com:443\niam:\n  max-privilegiados: 3',
  'oci.auth=instance\noci.dominio-url=https://idcs-xxxx.identity.oraclecloud.com:443',
  [('Datos del usuario', RES, True), ('El auditor', AUD, True), ('Lectura SCIM con paginación', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('Listar usuarios del dominio', 'Pertenecer a un rol de administrador del dominio con lectura de usuarios (por ejemplo *User Administrator*) *(verifica el rol mínimo)*'),
   ('El auditor', 'Ninguna: es lógica pura')],
  ['No uses la URL de otro dominio: la lista saldrá vacía sin error.',
   'No guardes la salida de la auditoría con correos de personas en registros públicos.',
   'No desactives usuarios automáticamente desde esta herramienta: reporta y que una persona decida.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
