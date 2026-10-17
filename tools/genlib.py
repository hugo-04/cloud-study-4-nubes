"""Atajo para uso-en-java.md de OCI: un adaptador (construido con auth) + un servicio (construido con el adaptador)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdoc
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

def oci(rel, titulo, intro, cfg, nucleo, ns, ruta, servicio, adaptador, imports, cuerpo, endpoints, permisos, no_hacer, extra_cfg_spring=None):
    """cfg: lista de (clave, valor). Las claves 'oci.auth' y 'oci.region' se agregan solas.
    cuerpo: líneas Java que usan 'auth', 'region' y los campos de cfg (nombre = última parte de la clave) y terminan en
    'return new <adaptador>(...);'."""
    claves = [('oci.auth', 'instance'), ('oci.region', 'sa-saopaulo-1')] + cfg
    var = lambda k: k.split('.')[-1]
    yaml_lines, ultimo = [], None
    for k, v in claves:
        a, b = k.split('.', 1)
        if a != ultimo: yaml_lines.append(f"{a}:"); ultimo = a
        yaml_lines.append(f"  {b}: {v}")
    props = "\n".join(f"{k}={v.strip(chr(34))}" for k, v in claves)
    pre = '        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(auth_);\n'
    body = pre + "\n".join("        " + l for l in cuerpo.strip().splitlines())
    sargs = ", ".join(f'@Value("${{{k}}}") String {var(k) if k != "oci.auth" else "auth_"}' for k, _ in claves)
    base_imp = ['import com.oracle.bmc.Region;', 'import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;'] + imports
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
        q_fields=[('String', var(k) if k != 'oci.auth' else 'auth_', k) for k, _ in claves],
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
    jdoc.doc(os.path.join(ROOT, rel, 'uso-en-java.md'), titulo, intro, "\n".join(yaml_lines), props, nucleo, sec, permisos, no_hacer)
