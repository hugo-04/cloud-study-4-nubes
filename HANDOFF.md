# HANDOFF · dónde nos quedamos y cómo continuar

## Estado (2026-10-17)
| Bloque | Estado |
|---|---|
| `azure/` capítulos 00–11 | ✅ Completo |
| `aws/` capítulos 00–11 | ✅ Completo |
| `oci/` capítulos 00–11 | ✅ Completo |
| `gcp/` capítulos 00–11 | ✅ Completo |
| `transversal/` | 🟡 terraform, kafka, spring-boot, quarkus, programacion-reactiva, patrones-de-diseno, patrones-microservicios y arquitectura-y-testing listos; falta typescript-react-angular |
| Fase final | ⬜ Reorganizar el repo y eliminar lo obsoleto (carpetas viejas de la raíz, plantilla vieja), README raíz, linkcheck |

## Pendiente, en orden
### 1. OCI ✅ terminado
Capítulos 04–11 completos (unidades con docs, Terraform validado, Java compilado y probado, NotebookLM). Generadores en `tools/gen_*.py` (atajo común: `tools/genlib.py`).

### 2. Google Cloud ✅ terminado
Capítulos 00–11 completos. Generadores en `tools/gg_*.py` (atajo común: `tools/ggen.py`; entorno `source tools/gcp-env/gcp-env.sh` y `jc <md>`). Providers `hashicorp/google` y `google-beta ~> 8.0`.

### 3. Módulos transversales (`transversal/`)
`terraform`, `kafka` (los enlaces `../../../transversal/kafka/README.md` de `aws/07-mensajeria/msk-kafka` deben resolver), `spring-boot`, `quarkus` (imperativo + reactivo), `programacion-reactiva` (WebFlux, Mutiny, RxJava), `patrones-de-diseno` (todos los GoF), `patrones-microservicios`, `arquitectura-y-testing` (TDD, BDD, hexagonal, clean, monolito vs microservicios, cuándo sí/no, organización de capas y paquetes), `typescript-react-angular`. Todo enfocado a microservicios con casos reales; cada módulo con `notebooklm.md`.

### 4. Fase final: reorganizar el repo y eliminar lo obsoleto (OBLIGATORIA al terminar todo lo anterior)
La orientación del repo cambió: antes eran carpetas numeradas mezclando nubes; ahora es **una carpeta por nube** (`azure/`, `aws/`, `oci/`, `gcp/`) **+ `transversal/`**. Al finalizar, deja el repo limpio:
1. **Verifica la migración** antes de borrar: cada tema de las carpetas viejas debe tener su equivalente en una nube o en `transversal/` (si algo útil no se migró, pásalo primero).
2. **Elimina** (con `git rm -r`) lo que ya no encaja en la nueva distribución:
   - Carpetas viejas de la raíz: `00-fundamentos`, `01-networking`, `02-comunicacion-privada-y-diagnostico`, `03-iam-seguridad`, `04-secretos-y-claves`, `05-compute`, `06-ingress-y-api`, `07-storage`, `08-mensajeria-y-streaming`, `09-bases-de-datos`, `10-politicas-y-gobierno`, `11-terraform-iac`, `12-casos-integrados`, `99-prompts-notebooklm`.
   - `PLANTILLA-SERVICIO.md` (la plantilla vigente está descrita en este archivo y en cualquier unidad reciente).
   - Cualquier archivo suelto, zip, borrador o duplicado que no pertenezca a una nube, a `transversal/`, a `tools/` o a los archivos raíz.
3. **Reorganiza lo que quede:** raíz solo con `README.md`, `CLAUDE.md`, `HANDOFF.md`, `azure/`, `aws/`, `oci/`, `gcp/`, `transversal/`, `tools/`. Sin carpetas vacías; sin nombres inconsistentes.
4. **Reescribe `README.md` raíz:** tabla de nubes y de módulos transversales con su estado, cómo navegar (nube → capítulo → servicio) y dónde están los prompts de NotebookLM.
5. **Revisión final:** `tools/linkcheck.py` sin enlaces rotos (incluidos los de `transversal/kafka`), grep de aislamiento por nube, todos los `notebooklm.md` presentes.
6. **Actualiza este `HANDOFF.md`** a "proyecto completo" (o déjalo solo con pendientes reales) y haz el push final a `main`.

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
| `tools/oci-env/oci-env.sh`, `tools/gcp-env/gcp-env.sh` | Definen `JV_DIR`, `JVQ_DIR` y la función `jc <archivo.md>` |

**Reconstruir el entorno en una sesión nueva** (las rutas `/tmp/...` del entorno anterior ya no existen):
1. Copiar `tools/maven/oci-spring-pom.xml` a `/tmp/oci-spring/pom.xml` y `oci-quarkus-pom.xml` a `/tmp/oci-quarkus/pom.xml` (idem `gcp-*`); `mvn -q compile` en cada uno y `mvn dependency:build-classpath -Dmdep.outputFile=/tmp/cp-oci.txt`.
2. Descargar OpenTofu (release de GitHub) a `/tmp/tfnew/tofu`. **Si GitHub está bloqueado por el proxy** (pasó en la nube): bajar Terraform de `releases.hashicorp.com/terraform/` a `/tmp/tfnew/tofu` y los providers (`terraform-provider-oci` 7.x, `terraform-provider-google` y `terraform-provider-google-beta` 8.x) del mismo sitio a un *filesystem mirror* (`/tmp/tfmirror/registry.terraform.io/<ns>/<nombre>/<versión>/linux_amd64/`) con `~/.terraformrc`: `provider_installation { filesystem_mirror { path = "/tmp/tfmirror" } }`.
3. `source tools/oci-env/oci-env.sh` (las rutas ya son relativas al repo; no borres `JAVA_TOOL_OPTIONS`, el proxy la necesita).
4. Flujo por unidad: escribir docs → `tofu fmt` + `tfcheck.sh` → `gen_*.py`-style con `jdoc.doc(...)` → `jc <ruta>/uso-en-java.md` → prueba rápida de la lógica pura no trivial → `nbgen` → linkcheck → grep de aislamiento → commit/push por capítulo.

Notas técnicas: los bloques de test rápido van en el paquete `chk.bN` (las clases del harness son package-private); en Python usa `'\\\\.'` para escribir `"\\."` en Java; para clientes enormes (Ec2) usa implementaciones anónimas en vez de Proxy.
