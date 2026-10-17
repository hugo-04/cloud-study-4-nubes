# HANDOFF · estado final y cómo retomar

## Estado (2026-10-17)
| Bloque | Estado |
|---|---|
| `azure/` capítulos 00–11 | ✅ Completo |
| `aws/` capítulos 00–11 | ✅ Completo |
| `oci/` capítulos 00–11 | ✅ Completo |
| `gcp/` capítulos 00–11 | ✅ Completo |
| `transversal/` (9 módulos) | ✅ Completo |
| Fase final | ✅ Repo reorganizado: carpetas viejas y plantilla eliminadas, README raíz reescrito, 0 enlaces rotos, aislamiento verificado, todos los `notebooklm.md` presentes |

**Proyecto completo.** No hay pendientes obligatorios. Ideas opcionales si se retoma:
- Revisar los datos marcados con «verifica» (precios, límites, versiones) cada pocos meses.
- Agregar unidades nuevas siguiendo el molde de abajo (y su fila en el README del capítulo, de la nube y su `notebooklm.md`).
- Los falsos positivos conocidos del grep de aislamiento son `oci://` (protocolo de registros de contenedores) y «Oracle» como motor de base de datos.

## Validación de todo el repo
```bash
python3 tools/linkcheck.py .                                     # enlaces relativos (debe dar «rotos: 0»)
grep -rliE "\baws\b|amazon|\boci\b|oracle|\bgcp\b|google" transversal   # aislamiento (igual por nube con sus patrones)
source tools/gcp-env/gcp-env.sh && jc <ruta>/uso-en-java.md      # Java por nube (oci-env / gcp-env; azure y aws usan sus propios proyectos)
source tools/tr-env/tr-env.sh && jc transversal/<modulo>/<archivo>.md   # Java de los transversales
TSDIR=/tmp/ts python3 tools/tscheck.py transversal/typescript-react-angular/*.md
TOFU=/tmp/tfnew/tofu bash tools/tfcheck.sh                       # todos los ejemplos terraform
```

## Molde de una unidad de servicio
```
<nube>/<NN-capitulo>/<servicio>/
  README.md          8 secciones: 1 Qué es (+analogía+ASCII) · 2 Cómo funciona por dentro · 3 Para qué sirve/cuándo NO ·
                     4 Conceptos clave · 5 Cómo se usa · 6 Seguridad (tabla Identidad|Plano de control|Plano de datos) ·
                     7 Qué hacer/NO hacer · 8 Límites/costos/versiones. Termina con "**Siguiente:** casos reales · uso en Java · troubleshooting · repaso · NotebookLM"
  casos-reales.md    4 historias (Qué pasó/Causa/Arreglo/Lección) + tabla resumen
  uso-en-java.md     1 Configuración (yaml Spring + properties Quarkus) · 2 Núcleo común (lógica pura + adaptador del SDK) ·
                     3 Spring MVC · 4 WebFlux · 5 Quarkus imperativo · 6 Quarkus Mutiny · 7 Permisos · 8 Qué NO hacer. TODO el código debe compilar.
  troubleshooting.md lista ordenada + tabla síntoma/causa/qué hacer
  repaso.md          10 preguntas, respuestas, 3 ejercicios
  notebooklm.md      prompt de video largo, solo de esa nube
  ejemplos/          terraform/ (validado), cli/ (bash -n), otros
```
Referencia viva: cualquier unidad de `oci/02-iam/*` o `oci/04-compute/*` (la más reciente).

## Herramientas (`tools/`)
| Archivo | Para qué |
|---|---|
| `jdoc.py` + `jgen.py` | Generan `uso-en-java.md` (secciones 3–6 desde una descripción de endpoints). Ver `gen_*.py` como ejemplos completos |
| `nbgen.py` | `nb(...)` crea el `notebooklm.md` de un servicio; `cap_nb(...)` el de un capítulo |
| `javacheck.py` | Compila cada bloque de código de un `.md` (modo Spring o `--quarkus`). Usa los proyectos Maven de `tools/maven/` y las variables `JV_DIR` / `JVQ_DIR`; bloques que empiezan con `// (clase reutilizada … ambos)` se acumulan para los siguientes |
| `tfcheck.sh` | `tofu init + validate` de una carpeta Terraform (`TOFU=/ruta/tofu bash tools/tfcheck.sh <abs dir>`) |
| `linkcheck.py` | Verifica enlaces relativos entre `.md` |
| `tools/oci-env/oci-env.sh`, `tools/gcp-env/gcp-env.sh`, `tools/tr-env/tr-env.sh` | Definen `JV_DIR`, `JVQ_DIR` y la función `jc <archivo.md>` (OCI, GCP y transversales) |
| `genlib.py` / `ggen.py` + `gen_*.py` / `gg_*.py` | Generadores de `uso-en-java.md` de OCI / GCP |
| `tnb.py` | `notebooklm.md` de los módulos transversales (sin nubes) |
| `tscheck.py` | Compila los bloques ```ts/```tsx de los `.md` (`TSDIR` con typescript, react, @angular/*, rxjs; `// archivo: x.ts` permite importar entre bloques) |

**Reconstruir el entorno en una sesión nueva** (las rutas `/tmp/...` del entorno anterior ya no existen):
1. Copiar `tools/maven/oci-spring-pom.xml` a `/tmp/oci-spring/pom.xml` y `oci-quarkus-pom.xml` a `/tmp/oci-quarkus/pom.xml` (idem `gcp-*` y `transversal-*` en `/tmp/tr-spring` y `/tmp/tr-quarkus`); `mvn -q compile` en cada uno y `mvn dependency:build-classpath -Dmdep.outputFile=/tmp/cp-oci.txt`.
2. Descargar OpenTofu (release de GitHub) a `/tmp/tfnew/tofu`. **Si GitHub está bloqueado por el proxy** (pasó en la nube): bajar Terraform de `releases.hashicorp.com/terraform/` a `/tmp/tfnew/tofu` y los providers (`terraform-provider-oci` 7.x, `terraform-provider-google` y `terraform-provider-google-beta` 8.x) del mismo sitio a un *filesystem mirror* (`/tmp/tfmirror/registry.terraform.io/<ns>/<nombre>/<versión>/linux_amd64/`) con `~/.terraformrc`: `provider_installation { filesystem_mirror { path = "/tmp/tfmirror" } }`.
3. TypeScript: `mkdir /tmp/ts && cd /tmp/ts && npm i typescript@5.8 react@19 @types/react@19 react-dom@19 @types/react-dom@19 @angular/core@20 @angular/common@20 @angular/forms@20 @angular/router@20 @angular/platform-browser@20 rxjs@7 zone.js`. Providers genéricos para `transversal/terraform`: `hashicorp/random` y `hashicorp/local` en el mismo *mirror*.
4. `source tools/oci-env/oci-env.sh` (las rutas ya son relativas al repo; no borres `JAVA_TOOL_OPTIONS`, el proxy la necesita).
5. Flujo por unidad: escribir docs → `tofu fmt` + `tfcheck.sh` → `gen_*.py`-style con `jdoc.doc(...)` → `jc <ruta>/uso-en-java.md` → prueba rápida de la lógica pura no trivial → `nbgen` → linkcheck → grep de aislamiento → commit/push por capítulo.

Notas técnicas: los bloques de test rápido van en el paquete `chk.bN` (las clases del harness son package-private); en Python usa `'\\\\.'` para escribir `"\\."` en Java; para clientes enormes (Ec2) usa implementaciones anónimas en vez de Proxy.
