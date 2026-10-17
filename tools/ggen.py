"""Atajo para uso-en-java.md de Google Cloud: adaptador (construido con credenciales ADC) + servicio."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jgen
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
AUTH = '''```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.google.auth.oauth2.GoogleCredentials;
import com.google.auth.oauth2.ImpersonatedCredentials;
import java.io.IOException;
import java.util.List;

public final class Credenciales {

    private static final List<String> ALCANCE = List.of("https://www.googleapis.com/auth/cloud-platform");

    private Credenciales() { }

    /**
     * ADC (Application Default Credentials): en la laptop, «gcloud auth application-default login»;
     * en GKE, Cloud Run, Functions o Compute Engine, la cuenta de servicio adjunta (sin llaves).
     * suplantar = correo de una cuenta de servicio para actuar como ella, o "ninguna".
     */
    public static GoogleCredentials crear(String suplantar) {
        try {
            var base = GoogleCredentials.getApplicationDefault().createScoped(ALCANCE);
            if (suplantar == null || suplantar.isBlank() || "ninguna".equals(suplantar)) {
                return base;
            }
            return ImpersonatedCredentials.create(base, suplantar, null, ALCANCE, 3600);
        } catch (IOException e) {
            throw new IllegalStateException("no hay credenciales ADC disponibles", e);
        }
    }
}
```
'''

def gcp(rel, titulo, intro, cfg, nucleo, ns, ruta, servicio, adaptador, imports, cuerpo, endpoints, permisos, no_hacer):
    """cfg: (clave, valor) extra; se agregan gcp.proyecto y gcp.suplantar. cuerpo usa 'cred', 'proyecto' y las variables de cfg."""
    claves = [('gcp.proyecto', 'modalima-prod'), ('gcp.suplantar', 'ninguna')] + cfg
    var = lambda k: k.split('.')[-1]
    yaml_lines, ultimo = [], None
    for k, v in claves:
        a, b = k.split('.', 1)
        if a != ultimo: yaml_lines.append(f"{a}:"); ultimo = a
        yaml_lines.append(f"  {b}: {v}")
    props = "\n".join(f"{k}={v.strip(chr(34))}" for k, v in claves)
    pre = '        GoogleCredentials cred = Credenciales.crear(suplantar);\n'
    body = pre + "\n".join("        " + l for l in cuerpo.strip().splitlines())
    sargs = ", ".join(f'@Value("${{{k}}}") String {var(k)}' for k, _ in claves)
    base_imp = ['import com.google.auth.oauth2.GoogleCredentials;'] + imports
    sec = dict(ns=ns, ruta=ruta, servicio=servicio,
        spring_imports=base_imp + ['import org.springframework.beans.factory.annotation.Value;'],
        spring_beans=f'''    @Bean(destroyMethod = "close")
    {adaptador} adaptador({sargs}) {{
{body}
    }}

    @Bean
    {servicio} servicio({adaptador} a) {{
        return new {servicio}(a);
    }}
''',
        q_imports=base_imp + ['import jakarta.enterprise.inject.Disposes;'],
        q_fields=[('String', var(k), k) for k, _ in claves],
        q_producer=f'''    {adaptador} adaptador() {{
{body}
    }}

    void cerrar(@Disposes {adaptador} a) {{
        a.close();
    }}

    @jakarta.enterprise.inject.Produces
    @Singleton
    {servicio} servicio({adaptador} a) {{
        return new {servicio}(a);
    }}''',
        endpoints=endpoints)
    partes = [f"# Google Cloud · {titulo} · Uso desde Java\n\nVersiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, Google Cloud libraries-bom 26.90**. Verifica las vigentes.\n\n{intro}\n",
              "## 1. Configuración\n```yaml\n# Spring Boot (application.yml)\n" + "\n".join(yaml_lines) + "\n```\n```properties\n# Quarkus (application.properties)\n" + props + "\n```\n",
              "## 2. Núcleo común\n", "### 2.1 Credenciales según dónde corre el código\n" + AUTH]
    for i, (t, code, ambos) in enumerate(nucleo, 2):
        p = "// (clase reutilizada en los bloques siguientes, ambos)\n" if ambos else ""
        partes.append(f"### 2.{i} {t}\n```java\n{p}{code.strip()}\n```\n")
    partes.append(jgen.secciones(**sec))
    partes.append("## 7. Permisos\n| Acción en Java | Rol de IAM (mínimo) |\n|---|---|\n" + "\n".join(f"| {a} | {b} |" for a, b in permisos) + "\n")
    partes.append("## 8. Qué NO hacer desde Java\n" + "\n".join(f"- {x}" for x in no_hacer) + "\n")
    open(os.path.join(ROOT, rel, 'uso-en-java.md'), 'w', encoding='utf-8').write("\n".join(partes))
