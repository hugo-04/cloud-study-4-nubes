# Transversal · Terraform / OpenTofu

**Infraestructura como código** declarativa: describes en HCL **cómo debe quedar** la infraestructura y la herramienta calcula y aplica la diferencia. Terraform (HashiCorp, licencia BSL) y **OpenTofu** (bifurcación abierta de la Linux Foundation) comparten lenguaje y flujo; casi todo lo de aquí vale para ambos *(verifica diferencias de versión)*. Lo específico de cada proveedor (backends, autenticación, recursos) está en el capítulo 10 de cada nube.

## 1. Qué es

**Analogía:** un plano de arquitecto con un inspector. El plano (`.tf`) dice cómo debe quedar el edificio; el inspector (`plan`) compara plano y obra y lista las diferencias; el constructor (`apply`) las ejecuta; el libro de obra (estado) registra lo construido.

```
  código .tf ──┐
               ├─► plan ──(revisión humana + políticas)──► apply ──► recursos reales
  estado ──────┘        (diferencia = deseado − conocido)          │
     ▲                                                             │
     └──────────────────── se actualiza ◄──────────────────────────┘
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Providers** | Plugins que traducen recursos a llamadas de API; se fijan con `required_providers` y el lock file `.terraform.lock.hcl` |
| **Recursos** | Lo que Terraform crea y administra (`resource`) |
| **Fuentes de datos** | Lectura de lo que ya existe (`data`) |
| **Grafo de dependencias** | Referencias implícitas (`a.b.id`) + `depends_on` explícito; paraleliza lo independiente |
| **Estado** | Mapa código ↔ recursos reales, con atributos (¡y secretos!) |
| **Backend** | Dónde vive el estado y cómo se bloquea |
| **Plan** | Diferencia calculada; puede guardarse (`-out`) y aplicarse tal cual |
| **Ciclo de vida** | `create_before_destroy`, `prevent_destroy`, `ignore_changes`, `replace_triggered_by` |

### El lenguaje en una tabla
| Construcción | Para qué | Ejemplo corto |
|---|---|---|
| `variable` + `validation` | Entradas con reglas | `condition = contains(["dev","prod"], var.entorno)` |
| `locals` | Valores derivados | `nombre = "${var.app}-${var.entorno}"` |
| `output` | Salidas del módulo | `value = random_id.sufijo.hex` |
| `for_each` | N recursos con clave estable | `for_each = toset(var.colas)` |
| `count` | 0 o 1 (condicional) | `count = var.crear ? 1 : 0` |
| `dynamic` | Bloques anidados repetidos | `dynamic "regla" { for_each = ... }` |
| `precondition` / `postcondition` | Garantías por recurso | `condition = self.size > 0` |
| `check` | Aserciones que avisan sin bloquear | `assert { condition = ... }` |
| `moved` | Renombrar sin destruir | `from = a.x  to = a.y` |
| `import` | Adoptar recursos existentes | `import { to = a.x  id = "..." }` |
| `terraform test` | Pruebas del módulo (`*.tftest.hcl`) | `run "plan" { command = plan }` |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Entornos repetibles (dev = prod en forma) | Terraform |
| Revisar infraestructura por pull request | Terraform + plan en CI |
| Configurar el interior de una VM (paquetes, archivos) | Imagen inmutable o gestor de configuración, no Terraform |
| Desplegar versiones de la app cada hora | El pipeline de la app (Helm, despliegue del servicio), no Terraform |
| Datos de negocio (filas, usuarios finales) | Nunca |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Declarativo** | Dices el qué, no el cómo |
| **Deriva (*drift*)** | Alguien cambió algo a mano |
| **Idempotencia** | Aplicar dos veces da lo mismo |
| **Dirección** | Nombre del recurso en el estado (`module.x.tipo.nombre["k"]`) |
| **Blast radius** | Cuánto puede romper un apply: estados pequeños = radio pequeño |

## 5. Cómo se usa
1. Módulo reutilizable con validaciones, `for_each`, `precondition` y salidas: [`ejemplos/modulos/servicio/main.tf`](ejemplos/modulos/servicio/main.tf).
2. Raíz de un entorno que lo usa: [`ejemplos/raiz/main.tf`](ejemplos/raiz/main.tf).
3. Pruebas con `terraform test`: [`ejemplos/raiz/tests/servicio.tftest.hcl`](ejemplos/raiz/tests/servicio.tftest.hcl).

Flujo diario:
```bash
terraform fmt -recursive && terraform init && terraform validate
terraform plan -out=plan.bin && terraform show -json plan.bin > plan.json   # revisar + políticas
terraform apply plan.bin
terraform test                                                              # en CI, por módulo
```

## 6. Seguridad
| Riesgo | Control |
|---|---|
| Secretos en el estado | Backend privado, cifrado y con acceso solo del pipeline; preferir referencias a gestores de secretos |
| Credenciales de larga vida en CI | Federación de identidad (tokens de corta vida) |
| Applies no revisados | Plan en PR, aprobación, aplicar el plan guardado |
| Providers o módulos manipulados | Versiones fijas, lock file con hashes, registros confiables |
| Recursos inseguros | Escáneres (tflint, checkov, trivy) y políticas sobre `plan.json` |

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Estados pequeños por componente y entorno | Un estado gigante para todo |
| `for_each` con claves estables | `count` para listas que cambian de orden |
| Versiones fijas de providers y módulos | `>= 0` o `ref=main` |
| `moved` al refactorizar | Renombrar y aceptar «destroy/create» |
| `prevent_destroy` en lo que tiene datos | Confiar en que nadie hará `destroy` |
| Variables con `validation` | Documentar reglas solo en el README |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El `count` que borró colas | En ModaLima se quitó un elemento al inicio de una lista y Terraform recreó todas las colas siguientes | `for_each` con claves estables |
| El rename que destruía la base | Mover un recurso a un módulo planificó destruirlo | Bloque `moved` y política sobre el plan |
| Deriva en el viernes | Café Andino cambió un firewall a mano; el siguiente apply lo revirtió en plena venta | `plan -refresh-only` diario y cambios solo por código |
| El provider que cambió solo | Sin lock file, el CI tomó una versión mayor nueva con cambios incompatibles | Lock file versionado y `~>` en `required_providers` |

**Versiones:** Terraform 1.x / OpenTofu 1.x; los ejemplos usan solo `hashicorp/random` y `hashicorp/local` para poder validarse sin cuentas *(verifica)*.

**Siguiente:** [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
