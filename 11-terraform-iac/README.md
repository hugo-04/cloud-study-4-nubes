# 11 · Terraform: infraestructura como código en las 4 nubes

**Terraform** es una herramienta **fuera de cualquier nube**: con el mismo lenguaje (HCL) y el mismo flujo creas recursos en **Azure**, **AWS**, **OCI** y **GCP**. Aprender Terraform **una vez** te sirve para las cuatro.

---

## 1. Qué es (con analogía)

Un **plano de arquitecto con un inspector**.

| En la obra | En Terraform |
|---|---|
| El plano: "así debe quedar el edificio" | Los archivos `.tf` (estado **deseado**) |
| El inspector compara plano y obra real | `terraform plan` (qué cambiaría) |
| El constructor ejecuta las diferencias | `terraform apply` |
| El libro de obra con lo construido | El **state** (estado real conocido) |
| Demoler lo construido | `terraform destroy` |

> Terraform es **declarativo**: describes **cómo debe quedar**, no los pasos. Él calcula la diferencia.

---

## 2. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Crear entornos **repetibles** (dev, QA, prod iguales).
- **Revisar** cambios de infraestructura como código (pull requests).
- **Documentar** lo que existe: el código es la fuente de verdad.
- Reconstruir un entorno completo tras un desastre.
- Detectar y corregir **drift** (alguien cambió algo a mano).

**Cuándo NO**
- Un recurso de prueba que borrarás en una hora: basta el portal o la CLI.
- Tareas **operativas** puntuales (reiniciar un servicio, rotar un secreto): usa scripts o automatización.
- Para **desplegar aplicaciones** a cada commit: usa un pipeline de aplicación; Terraform es para la **infraestructura**.

### Alternativas nativas

| Nube | Herramienta nativa | Nota |
|---|---|---|
| Azure | **Bicep** / ARM | Solo Azure; muy bien integrada |
| AWS | **CloudFormation** / CDK | Solo AWS |
| OCI | **Resource Manager** | Ejecuta Terraform administrado |
| GCP | **Infrastructure Manager** | Basado en Terraform (Deployment Manager está discontinuado: verifica) |
| Multi | **OpenTofu**, Pulumi | OpenTofu es una bifurcación de Terraform con licencia abierta |

---

## 3. Conceptos clave

| Término | Definición simple |
|---|---|
| **Provider** | El "plugin" que habla con una nube (`azurerm`, `aws`, `oci`, `google`) |
| **Resource** | Algo que Terraform crea y administra |
| **Data source** | Algo que **ya existe** y solo lees |
| **Variable** | Parámetro de entrada |
| **Output** | Valor que expones (un ID, una URL) |
| **Local** | Valor calculado interno |
| **Module** | Un conjunto reutilizable de recursos |
| **State** | Archivo con el mapa "recurso en código ↔ recurso real" |
| **Backend** | Dónde se guarda el state (local o remoto) |
| **Plan** | Vista previa de los cambios |
| **Drift** | Diferencia entre el código y lo que existe de verdad |
| **Import** | Traer un recurso existente al control de Terraform |
| **Lifecycle** | Reglas especiales (`prevent_destroy`, `ignore_changes`) |
| **`count` / `for_each`** | Crear varias copias de un recurso |

---

## 4. El flujo de trabajo

```
terraform fmt        ← ordena el formato
terraform init       ← descarga providers y configura el backend
terraform validate   ← revisa la sintaxis y referencias
terraform plan       ← ¿qué va a cambiar?  (lo revisas como un pull request)
terraform apply      ← ejecuta
terraform destroy    ← borra lo que Terraform creó
```

**Cómo leer un plan:**

| Símbolo | Significa |
|---|---|
| `+` | Se crea |
| `~` | Se modifica |
| `-` | Se destruye |
| `-/+` | Se **destruye y se vuelve a crear** (¡cuidado con bases de datos!) |

---

## 5. Providers y autenticación en cada nube

| Nube | Provider | Autenticación para estudio | Autenticación en pipelines |
|---|---|---|---|
| Azure | `hashicorp/azurerm` | `az login` | OIDC con una identidad federada |
| AWS | `hashicorp/aws` | Perfil / `aws sso login` | OIDC con un rol asumible |
| OCI | `oracle/oci` | `~/.oci/config` (API key o sesión) | Identidad de workload / principal de instancia |
| GCP | `hashicorp/google` | `gcloud auth application-default login` | Workload Identity Federation |

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"      # fija el rango para evitar cambios sorpresa
    }
  }
}
```

> **Fija versiones** de Terraform y de providers, y **sube** el archivo `.terraform.lock.hcl` si tu equipo lo decide (este repo lo ignora por ser de estudio).

---

## 6. El state: lo más importante y lo más peligroso

El state guarda IDs y **muchas veces valores sensibles en texto plano** (contraseñas generadas, claves).

**Reglas**
1. **Nunca** subas `terraform.tfstate` a Git (el `.gitignore` de este repo lo bloquea).
2. Usa un **backend remoto** con **bloqueo** (*locking*) para que dos personas no apliquen a la vez.
3. Cifra y **versiona** el almacenamiento del state; restringe el acceso (es tan sensible como un vault).
4. Un state **por componente y entorno** (no uno gigante).

### Backends remotos

**Azure** (Storage Account + contenedor; bloqueo por *lease* del blob)
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstatemodalima01"
    container_name       = "tfstate"
    key                  = "dev/red.tfstate"
    use_azuread_auth     = true     # sin claves de cuenta
  }
}
```

**AWS** (S3, con bloqueo)
```hcl
terraform {
  backend "s3" {
    bucket       = "modalima-tfstate"
    key          = "dev/red.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true   # bloqueo nativo en S3 (versiones recientes); antes se usaba una tabla DynamoDB
  }
}
```

**GCP** (Cloud Storage, con bloqueo integrado)
```hcl
terraform {
  backend "gcs" {
    bucket = "modalima-tfstate"
    prefix = "dev/red"
  }
}
```

**OCI**
- Usa el backend de **OCI** si tu versión de Terraform lo incluye, o el backend `s3` apuntando al **endpoint compatible con S3** de Object Storage, o **OCI Resource Manager** (administra el state por ti). Verifica la opción vigente.

> Tras cambiar el backend: `terraform init -migrate-state` (mover) o `-reconfigure` (reiniciar la configuración).

---

## 7. Estructura de repositorio recomendada

```
infra/
├── modules/
│   ├── red/               ← módulo reutilizable (vnet + subnets + reglas)
│   └── storage-privado/
├── envs/
│   ├── dev/
│   │   ├── main.tf        ← usa los módulos con valores de dev
│   │   └── backend.tf
│   └── prod/
│       ├── main.tf
│       └── backend.tf
└── README.md
```

Un **módulo** recibe variables, crea recursos y devuelve outputs:

```hcl
# envs/dev/main.tf
module "red" {
  source        = "../../modules/red"
  nombre        = "modalima-dev"
  espacio_ip    = ["10.10.0.0/16"]
  subnets       = { app = "10.10.1.0/24", pe = "10.10.9.0/27" }
}

output "subnet_pe_id" {
  value = module.red.subnet_ids["pe"]
}
```

---

## 8. Variables, outputs y secretos

```hcl
variable "ubicacion" {
  type        = string
  description = "Región de Azure"
  default     = "eastus2"
}

variable "password_admin" {
  type      = string
  sensitive = true       # no se muestra en el plan, pero SÍ queda en el state
}

locals {
  etiquetas = {
    proyecto = "cloud-study"
    entorno  = "estudio"
    owner    = "hugo"
  }
}
```

- Los valores van en `*.tfvars` (**ignorado** por `.gitignore`) o en variables de entorno `TF_VAR_nombre`.
- Mejor aún: **no pases contraseñas**; genera identidades administradas y lee secretos desde el vault (módulo 04).

---

## 9. El mismo ejemplo en las 4 nubes

En la carpeta [`ejemplos/`](ejemplos/) hay **un laboratorio equivalente por nube**: una **red privada** con una subnet de aplicación, reglas de acceso mínimas y un **storage privado**.

| Pieza | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Contenedor lógico | Resource Group | (cuenta) | (compartimento existente) | (proyecto existente) |
| Red | `azurerm_virtual_network` | `aws_vpc` | `oci_core_vcn` | `google_compute_network` |
| Subnet | `azurerm_subnet` | `aws_subnet` | `oci_core_subnet` | `google_compute_subnetwork` |
| Filtro de tráfico | `azurerm_network_security_group` | `aws_security_group` | `oci_core_network_security_group` | `google_compute_firewall` |
| Salida controlada | (NAT Gateway: opcional) | (NAT: opcional) | Service Gateway | **Cloud NAT** |
| Storage | `azurerm_storage_account` | `aws_s3_bucket` | `oci_objectstorage_bucket` | `google_storage_bucket` |
| Acceso privado al storage | **Private Endpoint** + zona DNS privada | **Gateway Endpoint** de S3 | **Service Gateway** | Private Google Access |
| Cifrado en tránsito | TLS 1.2 mínimo | Bucket policy que niega sin TLS | TLS por defecto | TLS por defecto |
| Acceso público | Bloqueado | Bloqueado | `NoPublicAccess` | `public_access_prevention = enforced` |

**Cómo correrlo (ejemplo Azure)**
```bash
cd 11-terraform-iac/ejemplos/azure
az login
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# ... estudiar, probar ...

terraform destroy        # SIEMPRE al terminar
```

> Los 4 ejemplos pasan `init` + `validate` + `fmt` (comprobado con OpenTofu 1.8 contra los providers publicados), pero **no se ejecutaron `plan`/`apply` contra cuentas reales**. Haz tu propio `plan` y revisa los nombres de atributos según la versión del provider que instales (cambian entre versiones mayores).

---

## 10. Pipeline de Terraform (CI/CD)

Flujo sano:

```
Pull request → fmt / validate / análisis de seguridad / plan (comentado en el PR)
                        │ aprobación humana
Merge a main  → apply (en un entorno protegido con aprobación)
```

Ejemplo con GitHub Actions y **OIDC** (sin secretos guardados) hacia Azure:

```yaml
name: terraform
on:
  pull_request:
    paths: ["11-terraform-iac/**"]
  push:
    branches: [main]

permissions:
  id-token: write       # necesario para OIDC
  contents: read
  pull-requests: write

env:
  ARM_USE_OIDC: "true"
  ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}

jobs:
  plan:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: 11-terraform-iac/ejemplos/azure
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
      - run: terraform init
      - run: terraform validate
      - run: terraform plan -out=tfplan

  apply:
    needs: plan
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: produccion          # exige aprobación manual
    defaults:
      run:
        working-directory: 11-terraform-iac/ejemplos/azure
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init
      - run: terraform apply -auto-approve
```
> Verifica las versiones de las *actions* y que el plan **aplicado** sea el **revisado** (en pipelines serios se guarda el plan como artefacto).

**Herramientas de calidad y seguridad**

| Herramienta | Para qué |
|---|---|
| `terraform fmt` / `validate` | Formato y sintaxis |
| **tflint** | Buenas prácticas y errores del provider |
| **Trivy / Checkov** | Configuraciones inseguras (bucket público, puerto abierto) |
| **OPA / Conftest / Sentinel** | Políticas propias sobre el plan |
| **Infracost** | Estimar costo antes de aplicar |

---

## 11. Buenas prácticas de Terraform

**Qué hacer**
- State **remoto, cifrado, versionado y con bloqueo**.
- **Fijar versiones** de Terraform y providers.
- Un state **por componente y entorno**; módulos pequeños y con una responsabilidad.
- `prevent_destroy` en lo que **no** debe borrarse (bases de datos, claves, vaults).
- Etiquetas comunes en todos los recursos.
- Revisar **siempre** el plan; prestar atención a `-/+`.
- Detectar **drift** con un `plan` programado.
- Identidades **federadas** (OIDC) en pipelines.

**Qué NO hacer**
- Subir `tfstate` o `*.tfvars` con secretos al repositorio.
- Aplicar desde una laptop a producción.
- Cambiar recursos **a mano** en el portal ("después lo pongo en el código").
- Poner **todo** en un solo state o un solo archivo gigante.
- Usar `provisioner "local-exec"` para configurar servidores (hay mejores herramientas).
- Ignorar un plan que quiere **destruir y recrear** una base de datos.
- Dejar versiones de providers sin fijar.

### Ejemplo: proteger un recurso crítico

```hcl
resource "azurerm_key_vault" "kv" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

### Refactorizar sin destruir

```hcl
moved {
  from = azurerm_virtual_network.vnet
  to   = module.red.azurerm_virtual_network.vnet
}
```

### Traer lo que ya existe (import)

```hcl
import {
  to = azurerm_resource_group.rg
  id = "/subscriptions/<SUB>/resourceGroups/rg-existente"
}
```

---

## 12. Casos de uso de vida real

### Caso 1 · "Alguien cambió una regla en el portal"
- **Problema:** una regla de NSG se abrió a mano durante una prueba y quedó así.
- **Cómo se detectó:** un `terraform plan` programado mostró **drift** (`~` sobre la regla).
- **Solución:** `apply` para devolverla al estado del código; y una política que impide cambios manuales en producción.
- **Lección:** el código manda; lo hecho en el portal se revierte o se importa.

### Caso 2 · Dos personas aplicando a la vez
- **Problema:** dos compañeros ejecutaron `apply` casi al mismo tiempo y uno vio `Error acquiring the state lock`.
- **Qué pasó bien:** el **bloqueo** del backend evitó que corrompieran el state.
- **Lección:** el backend remoto con lock no es opcional.

### Caso 3 · El plan quería destruir la base de datos
- **Problema:** al renombrar un recurso, el plan mostró `-/+` sobre el servidor SQL.
- **Solución:** detener el `apply`, usar `moved` para el cambio de dirección o ajustar el nombre, y añadir `prevent_destroy`.
- **Lección:** **leer el plan** es tu trabajo más importante.

### Caso 4 · La contraseña en el repositorio
- **Problema:** se subió `terraform.tfstate` con una contraseña generada.
- **Solución:** rotar la contraseña, limpiar el historial, backend remoto, `.gitignore` y escaneo de secretos.
- **Lección:** el state es **tan sensible como un secreto**.

### Caso 5 · Un módulo de red para todos los entornos
- **Problema:** dev y prod tenían redes parecidas pero no iguales, y los errores solo aparecían en producción.
- **Solución:** un módulo de red con variables; `dev` y `prod` lo usan con distintos valores.
- **Lección:** los módulos reducen sorpresas entre entornos.

---

## 13. Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Error acquiring the state lock` | Otra ejecución en curso o un lock huérfano | Esperar; si es huérfano y seguro, `terraform force-unlock <ID>` |
| Error de autenticación del provider | Sesión vencida o credenciales faltantes | `az login` / `aws sso login` / `gcloud auth application-default login` / revisar `~/.oci/config` |
| `already exists` | El recurso existe pero no está en el state | `terraform import` o bloque `import` |
| `Unsupported argument` / `Unsupported block` | Atributo de otra versión del provider | Revisar la documentación de **tu versión** y actualizar el código |
| Cambios que aparecen siempre en el plan | La nube modifica un atributo (valor por defecto) | `lifecycle { ignore_changes = [...] }` con criterio |
| `Cycle` (dependencia circular) | Recursos que se referencian entre sí | Romper la referencia o separar en módulos |
| El plan quiere recrear algo | Atributo que fuerza reemplazo (`-/+`) | Revisar `forces replacement` en el plan |
| Throttling / `429` | Demasiadas llamadas a la API | Bajar `-parallelism`, reintentar |
| Nombre de vault/storage en uso | Soft delete o nombre global ocupado | Cambiar nombre o recuperar/purgar |
| Backend cambió y falla `init` | Configuración de backend nueva | `terraform init -reconfigure` o `-migrate-state` |

---

## 14. Repaso y entrevista

**Repaso**
1. ¿Qué significa que Terraform sea declarativo?
2. ¿Por qué el state es sensible y cómo se protege?
3. ¿Qué indica `-/+` en un plan?
4. ¿Qué es el drift y cómo lo detectas?
5. ¿Qué equivale a Terraform en Azure, AWS, OCI y GCP como herramienta nativa?

**Entrevista**
- Diseña la estructura de repositorio y el pipeline para infraestructura de dev, QA y prod.
- ¿Cómo autenticas un pipeline en las tres nubes sin guardar secretos?
- Un `plan` quiere destruir una base de datos: ¿qué haces?
