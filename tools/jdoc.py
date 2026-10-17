import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import jgen
AUTH = '''```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import java.io.IOException;

public final class Autenticacion {

    private Autenticacion() { }

    /** config = laptop; instance = VM; oke = pod con workload identity; resource = OCI Functions. */
    public static BasicAuthenticationDetailsProvider crear(String modo) {
        try {
            return switch (modo) {
                case "config" -> new ConfigFileAuthenticationDetailsProvider("DEFAULT");
                case "instance" -> InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                case "oke" -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder().build();
                case "resource" -> ResourcePrincipalAuthenticationDetailsProvider.builder().build();
                default -> throw new IllegalArgumentException("modo de autenticación desconocido: " + modo);
            };
        } catch (IOException e) {
            throw new IllegalStateException("no se pudo leer la configuración de OCI", e);
        }
    }
}
```
'''
def doc(path, titulo, intro, yaml, props, nucleo, sec_args, permisos, no_hacer):
    """nucleo: lista de (titulo, codigo java sin fences, ambos:bool)"""
    n = 2
    partes = [f"# Oracle OCI · {titulo} · Uso desde Java\n\nVersiones con las que se compilaron estos ejemplos: **Java 21, Spring Boot 4.1, Quarkus 3.40, OCI SDK for Java 3.97**. Verifica las vigentes.\n\n{intro}\n",
              f"## 1. Configuración\n```yaml\n# Spring Boot (application.yml)\n{yaml.strip()}\n```\n```properties\n# Quarkus (application.properties)\n{props.strip()}\n```\n",
              "## 2. Núcleo común\n", "### 2.1 Autenticación según dónde corre el código\n" + AUTH]
    for i, (t, code, ambos) in enumerate(nucleo, 2):
        pre = "// (clase reutilizada en los bloques siguientes, ambos)\n" if ambos else ""
        partes.append(f"### 2.{i} {t}\n```java\n{pre}{code.strip()}\n```\n")
    partes.append(jgen.secciones(**sec_args))
    partes.append("## 7. Permisos\n| Acción en Java | Política |\n|---|---|\n" + "\n".join(f"| {a} | {b} |" for a, b in permisos) + "\n")
    partes.append("## 8. Qué NO hacer desde Java\n" + "\n".join(f"- {x}" for x in no_hacer) + "\n")
    open(path, 'w', encoding='utf-8').write("\n".join(partes))
