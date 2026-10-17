import ggen
VAL = '''
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Valida labels obligatorios y su formato, y que el tag de entorno sea coherente con el label. Puro.
 */
public final class ValidadorDeEtiquetas {

    public record Resultado(String recurso, boolean cumple, List<String> problemas) { }

    private static final Pattern FORMATO = Pattern.compile("[a-z][a-z0-9_-]{0,62}");
    private static final Set<String> ENTORNOS = Set.of("prod", "no-prod", "compartido");

    private ValidadorDeEtiquetas() {
    }

    public static Resultado validar(String recurso, Map<String, String> labels, Set<String> obligatorios, String tagEntorno) {
        var p = new ArrayList<String>();
        for (String k : obligatorios) {
            if (!labels.containsKey(k)) {
                p.add("falta label " + k);
            }
        }
        labels.forEach((k, v) -> {
            if (!FORMATO.matcher(k).matches()) {
                p.add("clave con formato inválido: " + k);
            }
            if (!v.isEmpty() && !v.matches("[a-z0-9_-]{1,63}")) {
                p.add("valor con formato inválido en " + k);
            }
        });
        if (tagEntorno == null) {
            p.add("sin tag de entorno (ni propio ni heredado)");
        } else if (!ENTORNOS.contains(tagEntorno)) {
            p.add("tag de entorno desconocido: " + tagEntorno);
        } else if (labels.containsKey("entorno") && !labels.get("entorno").equals(tagEntorno)) {
            p.add("label entorno=" + labels.get("entorno") + " contradice el tag " + tagEntorno);
        }
        return new Resultado(recurso, p.isEmpty(), p);
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.resourcemanager.v3.ProjectsClient;
import com.google.cloud.resourcemanager.v3.ProjectsSettings;
import com.google.cloud.resourcemanager.v3.TagBindingsClient;
import com.google.cloud.resourcemanager.v3.TagBindingsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Adaptador: recorre los proyectos de una carpeta y valida labels y el tag efectivo «entorno». */
public class JerarquiaGcp implements AutoCloseable {

    private final ProjectsClient proyectos;
    private final TagBindingsClient tags;

    public JerarquiaGcp(GoogleCredentials cred) {
        var cp = FixedCredentialsProvider.create(cred);
        try {
            this.proyectos = ProjectsClient.create(ProjectsSettings.newBuilder().setCredentialsProvider(cp).build());
            this.tags = TagBindingsClient.create(TagBindingsSettings.newBuilder().setCredentialsProvider(cp).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public List<ValidadorDeEtiquetas.Resultado> auditar(String carpeta, Set<String> obligatorios) {
        var out = new ArrayList<ValidadorDeEtiquetas.Resultado>();
        for (var p : proyectos.searchProjects("parent:folders/" + carpeta).iterateAll()) {
            String entorno = null;
            // p.getName() = projects/<número>; los tags efectivos incluyen los heredados de carpetas
            for (var t : tags.listEffectiveTags("//cloudresourcemanager.googleapis.com/" + p.getName()).iterateAll()) {
                if (t.getNamespacedTagKey().endsWith("/entorno")) {
                    entorno = t.getNamespacedTagValue().substring(t.getNamespacedTagValue().lastIndexOf('/') + 1);
                }
            }
            out.add(ValidadorDeEtiquetas.validar(p.getProjectId(), p.getLabelsMap(), obligatorios, entorno));
        }
        return out;
    }

    @Override
    public void close() {
        proyectos.close();
        tags.close();
    }
}
'''
SERV = '''
import java.util.List;
import java.util.Map;
import java.util.Set;

public class ServicioDeEtiquetas {

    private static final Set<String> OBLIGATORIOS = Set.of("equipo", "entorno", "centro-costo");
    private final JerarquiaGcp gcp;

    public ServicioDeEtiquetas(JerarquiaGcp gcp) {
        this.gcp = gcp;
    }

    /** Para el pipeline: valida antes de aplicar. */
    public ValidadorDeEtiquetas.Resultado validar(String recurso, String tagEntorno, Map<String, String> labels) {
        return ValidadorDeEtiquetas.validar(recurso, labels, OBLIGATORIOS, tagEntorno);
    }

    public List<ValidadorDeEtiquetas.Resultado> auditar(String carpeta) {
        return gcp.auditar(carpeta, OBLIGATORIOS);
    }
}
'''
ggen.gcp('gcp/09-gobierno/jerarquia-etiquetas', 'Gobierno · Jerarquía y etiquetas',
  'Dos piezas: un **validador puro** de labels obligatorios y su formato (minúsculas, ≤ 63 caracteres) que además comprueba que el tag `entorno` (el que manda en IAM y políticas) no contradiga al label; y un adaptador que recorre los proyectos de una carpeta con `ProjectsClient.searchProjects` y lee sus **tags efectivos** (incluidos los heredados) con `TagBindingsClient.listEffectiveTags`.',
  [],
  [('Validador (lógica pura)', VAL, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Etiquetas', '/gobierno/etiquetas', 'ServicioDeEtiquetas', 'JerarquiaGcp', [],
  'return new JerarquiaGcp(cred);',
  [dict(n='validar', v='POST', p='/validacion', args=[('String', 'recurso', 'q'), ('String', 'tagEntorno', 'q'), ('java.util.Map<String, String>', 'labels', 'b')], ret='ValidadorDeEtiquetas.Resultado', call='s.validar(recurso, tagEntorno, labels)', cpu=True),
   dict(n='auditar', v='GET', p='/carpetas/{carpeta}', args=[('String', 'carpeta', 'p')], ret='java.util.List<ValidadorDeEtiquetas.Resultado>', call='s.auditar(carpeta)')],
  [('Listar proyectos', '`roles/resourcemanager.folderViewer` en la carpeta'),
   ('Leer tags efectivos', '`roles/resourcemanager.tagViewer`')],
  ['No uses labels para decisiones de seguridad.',
   'No des permisos de edición de tags a los equipos: `tagUser` sobre valores concretos.',
   'No corrijas labels a mano en la consola: hazlo en el código de infraestructura.',
   'No ejecutes la auditoría con una cuenta con permisos de escritura.'])
