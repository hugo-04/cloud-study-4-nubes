# Azure · Terraform · Módulos y entornos

> Un módulo es una receta con ingredientes (variables) y un plato terminado (salidas). Un entorno es la cocina donde la preparas. Este documento es sobre escribir recetas que otros puedan usar sin quemar la cocina.

## 1. Qué es

- **Módulo:** una carpeta con archivos `.tf` que se puede **llamar** desde otra configuración. Toda configuración de Terraform ya es un módulo (el *módulo raíz*); lo que llamas con `module "x" { source = ... }` es un *módulo hijo*.
- **Entorno:** una copia de la infraestructura con su propio estado, sus variables, sus permisos y su ritmo de cambios (dev, qa, prod).

**Analogía:** el módulo es una **receta de cocina** (ingredientes → plato); el entorno es **cada cocina** donde la preparas. La receta se mejora en un solo sitio (con versiones); cada cocina decide cuántos platos hace y con qué ingredientes, pero **no puede cambiar la receta por su cuenta**.

```
            módulos (recetas, con versión)                         entornos (cocinas)
 ┌──────────────────────────────────────────┐          ┌────────────────────────────────────────────────┐
 │ app-base v1.3.0   red v2.0.1   bd v1.1.0 │ ◄─source─┤ envs/dev   : estado dev/…tfstate   dev.tfvars  │
 └──────────────────────────────────────────┘          │ envs/qa    : estado qa/…tfstate    qa.tfvars   │
        ▲ tests + versión + changelog                  │ envs/prod  : estado prod/…tfstate  prod.tfvars │
        │                                              └────────────────────────────────────────────────┘
        └── el cambio se prueba una vez y se adopta entorno por entorno
```

## 2. Cómo funciona por dentro

### 2.1 Anatomía de un módulo
| Archivo | Contenido |
|---|---|
| `versions.tf` | Versión de Terraform y rangos de proveedores (**sin** configurar proveedores) |
| `variables.tf` | Entradas, con `type`, `description`, `default` y `validation` |
| `main.tf` (y archivos por tema) | Recursos y `locals` |
| `outputs.tf` | Salidas: lo que otros pueden usar |
| `tests/*.tftest.hcl` | Pruebas del módulo (`terraform test`) |
| `README.md` | Qué hace, ejemplo de uso, entradas y salidas |

El módulo de ejemplo completo está en [`ejemplos/modulos/app-base`](ejemplos/modulos/app-base): grupo de recursos + cuenta de almacenamiento endurecida + contenedores + lectores.

### 2.2 Cómo se llama un módulo
```hcl
module "app" {
  source   = "../modulos/app-base"        # carpeta local, repositorio Git (?ref=v1.3.0) o registro (con version)
  for_each = var.aplicaciones              # una instancia por clave

  nombre_aplicacion = each.key
  entorno           = "prod"
  dueno             = each.value.dueno
}
```
| Origen (`source`) | Versionado | Cuándo |
|---|---|---|
| Carpeta local (`../modulos/x`) | Ninguno (siempre lo último del repositorio) | Desarrollo y monorepo pequeño |
| Git (`git::https://…//app-base?ref=v1.3.0`) | Etiqueta, rama o commit | Módulos propios compartidos entre repositorios |
| Registro de Terraform (`Azure/…/azurerm`) con `version = "~> 1.3"` | Rangos semánticos | Módulos públicos o de un registro privado |

### 2.3 Las entradas y el contrato
- **`type`** (con `object`, `map`, `list`, `optional(...)` y valores por defecto) hace que el error aparezca **en el plan**, no en Azure.
- **`validation`** rechaza valores inválidos con un mensaje claro (nombres, listas permitidas).
- **`precondition`/`postcondition`** (en `lifecycle`) validan **relaciones** entre valores (el nombre completo ≤ 24 caracteres) y el **resultado** (TLS 1.2).
- **`check`** avisa de algo sin detener el plan.
- **`sensitive`** oculta en pantalla, **no** en el estado.

### 2.4 `count`, `for_each` y la dirección en el estado
Cada recurso tiene una **dirección** (`module.app["pedidos"].azurerm_storage_account.this`). Si la dirección cambia, Terraform cree que es **otro** recurso.
- `count` identifica por **posición**: borrar el elemento 0 de una lista **desplaza** a todos y puede destruirlos.
- `for_each` identifica por **clave**: estable aunque cambie el orden. **Úsalo con claves que no cambian** (nombres de aplicación, no índices).
- Las claves de `for_each` deben conocerse **al planificar**; no pueden depender de valores que Azure calcula al crear (por ejemplo un `principal_id`). Usa claves lógicas y deja el valor desconocido en el *valor*.

### 2.5 Cirugía del estado dentro del código
| Bloque | Para qué | Versión mínima |
|---|---|---|
| `moved { from = … to = … }` | Renombrar o mover (a un módulo, a `for_each`) sin destruir | Terraform 1.1 |
| `import { to = … id = … }` | Traer un recurso que ya existe | 1.5 |
| `removed { from = … lifecycle { destroy = false } }` | Dejar de administrar sin borrar | Terraform 1.7 (en OpenTofu, la parte `lifecycle` pide una versión reciente: probado con 1.10; la 1.8 la rechaza) |

Con `terraform plan -generate-config-out=generado.tf` Terraform escribe un borrador del código de lo que importas (revísalo siempre).

### 2.6 Pruebas del módulo (`terraform test`)
Un archivo `.tftest.hcl` con bloques `run` que **planifican** (o aplican) y hacen `assert`. Con `mock_provider "azurerm" {}` el proveedor se **simula**: sin credenciales, sin red, en segundos.
- `expect_failures = [var.nombre]` comprueba que una validación **rechaza** un valor malo.
- `mock_resource … defaults` da valores válidos a lo que el simulado inventaría (por ejemplo, los `id`).
- Probado aquí con OpenTofu 1.10; versiones anteriores del simulado para `azurerm` pedían el bloque `features`. **Verifica con tu versión.**

### 2.7 Proveedores, alias y varias suscripciones
- El módulo **declara** qué proveedores necesita (`required_providers`) pero **no los configura**; los configura quien lo llama.
- Para dos suscripciones, declara un proveedor con `alias` y pásalo con `providers = { azurerm = azurerm.plataforma }`; un módulo que espera alias lo declara en `configuration_aliases`.
- `azurerm` 4 exige `subscription_id` (argumento o `ARM_SUBSCRIPTION_ID`).

### 2.8 `azurerm` y `azapi`
| Proveedor | Cuándo |
|---|---|
| **`azurerm`** | Casi siempre: recursos con validaciones y atributos curados |
| **`azapi`** | Un recurso o propiedad nueva que `azurerm` todavía no cubre; llama a la API de ARM directamente (`type = "Microsoft.X/tipo@fecha-de-API"`, `body` como objeto HCL) |

### 2.9 Módulos verificados de Azure (AVM)
Microsoft mantiene **módulos verificados** (*Azure Verified Modules*) en el registro, con nombres como `avm-res-…` (recursos) y `avm-ptn-…` (patrones). Son una buena base, pero léelos como cualquier dependencia: fija la versión, revisa los *changelogs* y comprueba qué hacen por defecto. **Verifica el catálogo vigente en la documentación.**

## 3. Para qué sirve y cuándo NO

**Sirve para**
- **Reutilizar** una receta aprobada por seguridad en veinte aplicaciones.
- **Imponer estándares** (TLS, sin claves, etiquetas) donde nadie puede olvidarlos.
- **Probar** una vez y desplegar muchas.
- **Versionar** cambios y adoptarlos entorno por entorno.

**Cuándo NO**
- Un recurso que usarás una sola vez: un módulo con una sola llamada es capa extra de indirección.
- Un módulo que solo **renombra** argumentos del recurso (una "envoltura" que no añade valor).
- Módulos "navaja suiza" con 60 variables: son más difíciles de leer que el recurso.

## 4. Conceptos clave
| Término | Significado simple |
|---|---|
| **Módulo raíz / hijo** | La carpeta donde ejecutas Terraform / la que llamas con `module` |
| **Entrada / salida** | `variable` / `output`: el contrato del módulo |
| **Dirección** | Nombre completo de un recurso en el estado |
| **Versión semántica** | `MAYOR.MENOR.PARCHE`; mayor = puede romper, menor = añade, parche = corrige |
| **Restricción de versión** | `~> 4.0` = cualquier 4.x; `>= 1.7, < 2.0` = rango explícito |
| **Archivo de bloqueo** | `.terraform.lock.hcl`: versiones exactas de proveedores; se versiona en Git |
| **Alias de proveedor** | Una segunda configuración del mismo proveedor (otra suscripción) |
| **Mock** | Proveedor simulado para pruebas |
| **Deriva (*drift*)** | La realidad cambió sin pasar por Terraform |
| **Composición** | Módulos pequeños que se combinan, en vez de un módulo gigante |

## 5. Cómo se usa

### 5.1 Estructura del repositorio
```
infra/
├── modulos/                      # recetas (o un repositorio aparte con etiquetas)
│   └── app-base/
│       ├── main.tf  variables.tf  outputs.tf  versions.tf  README.md
│       └── tests/app-base.tftest.hcl
└── envs/                         # una carpeta (y un estado) por entorno
    ├── dev/   main.tf  dev.tfvars   backend.dev.hcl
    └── prod/  main.tf  prod.tfvars  backend.prod.hcl
```
Un **directorio por entorno** (no *workspaces*): permisos, estados y ritmo de cambio distintos. Más en [estado remoto](../estado-remoto/README.md).

### 5.2 Ciclo de vida de un módulo
1. **Diseña el contrato:** pocas variables, nombres claros, valores seguros por defecto.
2. **Escribe pruebas** con proveedor simulado (`terraform test`).
3. **Documenta** con un `README.md` y un ejemplo.
4. **Publica una versión** (etiqueta Git `v1.3.0`) y un *changelog*.
5. **Adopta en dev**, luego qa, luego prod, cambiando `?ref=`.
6. **Cambios que rompen** → versión mayor y guía de migración (con bloques `moved`).

### 5.3 Convenciones que ahorran dolores
| Tema | Convención |
|---|---|
| Nombres | `<tipo>-<aplicación>-<entorno>-<región>` y calcular el nombre en un `locals` (un solo lugar); respeta los límites de cada tipo |
| Etiquetas | `aplicacion`, `entorno`, `dueno`, `gestionado = "terraform"`; el módulo las pone, no cada llamador |
| Variables | `type` y `description` siempre; `validation` para nombres y listas permitidas |
| Salidas | Solo lo que otros necesitan; nada de secretos |
| `for_each` | Claves estables (nombres), nunca índices |
| Seguridad por defecto | El módulo sale **seguro** (sin claves, TLS 1.2); abrir cosas exige pedirlo |

### 5.4 Varias aplicaciones con un módulo
[`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) llama al módulo con `for_each` sobre un mapa de aplicaciones: añadir una aplicación es **añadir una entrada** en `tfvars`, no copiar código. [`envs/dev`](ejemplos/envs/dev/main.tf) y [`envs/prod`](ejemplos/envs/prod/main.tf) muestran la forma real: mismo módulo, distinto estado y distintos valores.

### 5.5 Migrar sin destruir
| Situación | Receta |
|---|---|
| Mover un recurso a un módulo | `moved { from = azurerm_x.a  to = module.m.azurerm_x.a }` |
| Pasar un módulo de una llamada a `for_each` | `moved { from = module.pedidos  to = module.app["pedidos"] }` |
| Adoptar infraestructura creada a mano | `import` + `-generate-config-out`, o `aztfexport` para un grupo de recursos entero |
| Dejar de administrar | `removed` con `destroy = false` |
| Cambiar de `count` a `for_each` | `moved` por cada instancia (`[0]` → `["clave"]`) |

**Regla:** después de cada cambio de este tipo, el `plan` debe decir **"0 to destroy"**. Si dice otra cosa, no apliques.

### 5.6 Cuatro formas de equivocarse con módulos
1. **Un módulo gigante** que crea toda la aplicación: cualquier cambio toca todo. Mejor módulos pequeños y una *composición*.
2. **Sin versión** (`source` local en producción o `?ref=main`): cada `init` puede traer cambios inesperados.
3. **Configurar el proveedor dentro del módulo:** impide usar `for_each`, alias y borrar el módulo limpiamente.
4. **Salidas con secretos:** terminan en el estado y en los registros.

## 6. Seguridad

### 6.1 IAM por plano
| Plano | Qué permite | Rol típico | Quién |
|---|---|---|---|
| **Control** | Crear y cambiar recursos del entorno | *Contributor* sobre la suscripción o el grupo de recursos | Identidad de **apply** del entorno ([autenticación y pipelines](../autenticacion-y-pipelines/README.md)) |
| **Control** | Asignar roles desde el módulo | *Role Based Access Control Administrator* con condición | Solo si el módulo crea `azurerm_role_assignment` |
| **Datos** | Leer/escribir el estado del entorno | *Storage Blob Data Owner* sobre el contenedor de ese entorno | Plan y apply de **ese** entorno únicamente |
| **Repositorio** | Aprobar cambios a módulos y entornos | `CODEOWNERS`, ramas protegidas | Equipo de plataforma y seguridad |

### 6.2 Seguridad del propio código
- **Cadena de suministro:** los módulos de terceros ejecutan lo que hagan con tus credenciales. Fija versiones, lee el código, usa un registro o espejo propio si puedes.
- **Seguro por defecto:** el módulo que escribes es la política: sin claves, TLS 1.2, sin acceso público. Que abrir cosas exija un argumento explícito y una revisión.
- **Escáneres sobre el módulo** (`trivy config`, `checkov`) y sobre el plan de cada entorno.
- **Un módulo no debe recibir ni devolver secretos.** Que lea de Key Vault con identidad, no que reciba la contraseña como variable.
- **Cambios en módulos = cambios en todos los entornos:** revisión obligatoria y adopción gradual.

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Módulos **pequeños**, con contrato claro, pruebas y `README.md`.
- **Versionar** (etiquetas) y fijar la versión en cada entorno.
- `for_each` con **claves estables**; `moved` al reorganizar.
- Un **directorio y un estado por entorno**; mismo código, distintas variables.
- `.terraform.lock.hcl` en Git; `terraform fmt`, `validate` y `test` en el pipeline.
- Seguridad **por defecto** en el módulo y validaciones que expliquen el error.

**Qué NO hacer**
- Copiar y pegar el módulo en cada entorno.
- `source` sin versión en producción, ni `?ref=main`.
- `count` con listas que cambian de orden.
- Configurar proveedores dentro de módulos.
- Usar `-target` como rutina, ni `terraform state` a mano si existe un bloque equivalente.
- Guardar secretos en `tfvars` del repositorio.
- Módulos con decenas de variables "por si acaso".

## 8. Límites, costos y versiones
- **Costo:** Terraform no cuesta; los módulos y entornos multiplican recursos reales: etiqueta y controla dev y qa.
- **Versiones mínimas:** `moved` 1.1, `import` 1.5, `check` 1.5, `terraform test` 1.6, `mock_provider` y `removed` 1.7 (en OpenTofu, `removed` con `lifecycle` y el simulado de `azurerm` funcionan en 1.10; no en 1.8). **Verifica la versión de tu herramienta** (Terraform u OpenTofu).
- **OpenTofu:** compatible en lo esencial, con diferencias de versión; no mezcles herramientas sobre el mismo estado sin comprobarlo.
- **`azapi`:** sigue la API de ARM; la fecha de API en `type` y el esquema cambian: **verifica la documentación**.
- **Nombres:** los límites de caracteres de cada tipo de recurso cambian poco, pero **compruébalos** en la documentación de reglas de nombres de Azure.

---
Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · Capítulo: [índice de Terraform en Azure](../README.md)
