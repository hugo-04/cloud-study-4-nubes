# AWS · Terraform · Módulos y entornos

**Un módulo es una receta con contrato; un entorno es una cocina donde se prepara.** Los módulos te permiten escribir una vez «cómo se crea un servicio seguro» y reutilizarlo veinte veces; los entornos (`dev`, `stg`, `prod`) separan **dónde** se despliega, con su propio estado y sus propios permisos.

## 1. Qué es

**Analogía:** la **receta y las cocinas**. La receta (módulo) dice ingredientes (variables), pasos (recursos) y qué plato entrega (salidas). Cada cocina (entorno) la prepara con sus ingredientes y su propia despensa (estado), y nadie cocina en producción sin que la receta esté probada.

```
 infra/
 ├─ modulos/servicio-base/     ← la receta (variables · recursos · salidas · pruebas)   v1.3.0
 │    ├─ variables.tf  main.tf  outputs.tf  versions.tf
 │    └─ tests/servicio-base.tftest.hcl
 └─ envs/
      ├─ dev/   main.tf  dev.tfvars  backend.dev.hcl   → estado: env/dev/servicios/terraform.tfstate
      └─ prod/  main.tf  prod.tfvars backend.prod.hcl  → estado: env/prod/servicios/terraform.tfstate
                    └─ module "servicio" { source = "…//servicio-base?ref=v1.3.0"; for_each = var.servicios }
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Módulo raíz / módulo hijo** | El directorio donde ejecutas Terraform es el raíz; los que llamas con `module { source = … }` son hijos |
| **Variables con tipo y `validation`** | El contrato de entrada: tipos, valores permitidos y mensajes claros. `optional(tipo, defecto)` en objetos |
| **Salidas (`output`)** | El contrato de salida: lo que otros pueden usar (URL, ARN) |
| **`source` y versión** | Ruta local, Git (`git::https://…//ruta?ref=v1.3.0`) o registro con `version`. **Siempre fija la versión** |
| **`for_each` frente a `count`** | `for_each` con un **mapa** (clave estable); `count` con listas se rompe al cambiar el orden |
| **Entornos como carpetas** | Una carpeta por entorno con su backend, sus variables y su rol; **no** workspaces para separar prod |
| **`moved`** | Renombrar módulos o recursos sin destruir |
| **`lifecycle`** | `prevent_destroy`, `ignore_changes`, `create_before_destroy`, `replace_triggered_by` |
| **`precondition` / `postcondition` / `check`** | Reglas que se evalúan al planificar/aplicar con mensajes propios |
| **`terraform test`** | Pruebas en `.tftest.hcl` con `mock_provider`: no crean nada en AWS |
| **`default_tags` y convenciones** | Etiquetas y nombres uniformes, base del reparto de costos y del cumplimiento |
| **`.terraform.lock.hcl`** | Fija las versiones de los proveedores; se sube a Git |

## 3. Para qué sirve y cuándo NO

| ✅ Sirve para | ❌ No sirve para |
|---|---|
| Repetir un patrón seguro (cola con DLQ, rol con límite, logs con retención) | Envolver un solo recurso sin añadir reglas (un módulo vacío solo estorba) |
| Imponer estándares una vez (cifrado, etiquetas, nombres) | Módulos «dios» que crean medio mundo con cien variables |
| Probar antes de desplegar (`terraform test`) | Reemplazar la revisión del plan |
| Separar entornos con estado y permisos propios | Compartir estado entre entornos |
| Evolucionar con versiones y `moved` | Cambiar un módulo en `main` y que todos lo reciban sin aviso |

## 4. Conceptos clave

| Palabra | Significado simple |
|---|---|
| **Módulo** | Carpeta de `.tf` reutilizable con entradas y salidas |
| **Contrato** | Variables validadas + salidas documentadas: lo que prometes |
| **SemVer** | `MAJOR.MINOR.PATCH`: major rompe, minor añade, patch corrige |
| **Entorno** | Un despliegue aislado (`dev`, `stg`, `prod`) con su estado |
| **`tfvars`** | Archivo de valores para un entorno (`.tfvars` o `.tfvars.json`) |
| **Mock provider** | Proveedor simulado para pruebas sin AWS |
| **Deriva** | Diferencia entre código y realidad |
| **Radio de explosión** | Cuánto daña un error: un módulo con versión fija limita el daño |
| **Mapa de servicios** | `map(object)` donde la clave identifica al servicio de forma estable |

## 5. Cómo se usa
1. Diseña el **contrato** primero: variables con tipos y `validation`, salidas mínimas ([`ejemplos/modulos/servicio-base`](ejemplos/modulos/servicio-base)).
2. Escribe las **pruebas** del módulo ([`tests/servicio-base.tftest.hcl`](ejemplos/modulos/servicio-base/tests/servicio-base.tftest.hcl)) y ejecútalas en cada PR: `terraform test`.
3. Publica el módulo con una **etiqueta de versión** (`v1.3.0`) y un registro de cambios.
4. Crea una carpeta por entorno que lo consuma con `for_each` sobre un mapa ([`ejemplos/envs/dev`](ejemplos/envs/dev), [`prod`](ejemplos/envs/prod)) y su `backend.<env>.hcl`.
5. Mantén los valores de cada entorno en un archivo (`servicios.auto.tfvars.json`): un portal o un script puede **generarlo** ([uso en Java](uso-en-java.md)).
6. Refactoriza con `moved` y comprueba «0 to destroy» ([`hcl/convenciones-y-lifecycle.tf`](ejemplos/hcl/convenciones-y-lifecycle.tf)).
7. Sube las versiones en `dev`, observa y luego en `prod`.
8. Automatiza `fmt`, `validate`, `test`, `tflint` y análisis de seguridad ([`ejemplos/cli/modulos.sh`](ejemplos/cli/modulos.sh)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Quien publica módulos** | Merge en el repositorio de módulos (revisión obligatoria, etiquetas protegidas) | — |
| **Pipeline de cada entorno** | Su rol de `apply` (ver [autenticación](../autenticacion-y-pipelines/README.md)) | Su prefijo del estado |
| **Roles creados por el módulo** | Con **límite de permisos** y permisos mínimos sobre sus propios recursos | Solo la cola/tabla de ese servicio |
| **Equipos de aplicación** | Piden servicios mediante el mapa de variables (PR) | — |

- El módulo es **política**: cifrado, retención, etiquetas y límite de permisos viven en él y no se pueden saltar con una variable (no expongas un `cifrado = false`).
- **Nunca** pases secretos como variables de módulo (acaban en el estado): pasa el ARN del secreto.
- Etiquetas protegidas en el repositorio de módulos: una versión publicada no se reescribe.
- Cada entorno con su estado, su rol y, idealmente, su cuenta.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Fijar la versión del módulo (`?ref=v1.3.0`) | Apuntar a `main` o sin versión |
| `for_each` con mapa de claves estables | `count` sobre listas que cambian de orden |
| Entornos como carpetas con backend propio | Workspaces para separar `dev` de `prod` |
| `validation` con mensajes claros | Validar solo en el pipeline |
| Pruebas con `terraform test` | Probar «desplegando a ver qué pasa» |
| `moved` al refactorizar | Renombrar y esperar que no destruya |
| Salidas mínimas y documentadas | Exponer atributos internos |
| Subir `.terraform.lock.hcl` | Ignorarlo y que cada máquina use otro proveedor |
| Módulos pequeños y componibles | Un módulo con cien variables |
| Subir de versión primero en `dev` | Subir de versión en todos los entornos a la vez |

## 8. Límites, costos y versiones
- **Costo:** ninguno propio; pagas los recursos que crea cada módulo.
- **Versiones:** `terraform test` y `mock_provider` requieren Terraform/OpenTofu recientes (≥ 1.7/1.8) *(verifica)*; `optional()` con valor por defecto desde 1.3.
- **Límites prácticos:** módulos anidados más de tres niveles son difíciles de depurar; un `for_each` de cientos de módulos ralentiza el plan.
- **Terraform:** módulo `servicio-base` (SQS + DLQ, grupo de logs, rol con límite) y entornos; validado con `init` + `validate` + `test`.
- **Java:** validador de solicitudes (espejo de las `validation` del módulo) y generador determinista de `tfvars.json`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
