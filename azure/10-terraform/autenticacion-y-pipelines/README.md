# Azure · Terraform · Autenticación y pipelines (OIDC, sin secretos)

> Un pipeline que ejecuta `terraform apply` es, en la práctica, **un administrador que nunca duerme**. Este documento es sobre cómo darle una identidad que no se pueda robar, con el mínimo de permisos y con aprobaciones donde importan.

## 1. Qué es

Para cambiar Azure, Terraform necesita una **identidad** (quién es) y **permisos** (qué puede hacer). En un portátil usas tu sesión de `az login`. En un pipeline no hay persona: hace falta una identidad de máquina.

- **Forma antigua:** un *service principal* con **secreto de cliente** guardado como secreto del pipeline. Caduca, se filtra en los registros, se copia a tres sitios y nadie lo rota.
- **Forma actual:** **federación de identidad de carga de trabajo** (*workload identity federation*, OIDC). El pipeline le muestra a Entra ID un **token de corta vida** emitido por su propia plataforma (GitHub, Azure DevOps); Entra ID lo compara con una **credencial federada** que tú registraste y, si coincide, entrega un token de acceso a Azure. **No hay secretos que guardar ni rotar.**

**Analogía:** en vez de entregar a cada contratista una llave maestra (el secreto), la recepción del edificio (Entra ID) conoce a la empresa de seguridad (GitHub) y acepta un **pase de visitante de un solo día** (el token) **solo si el nombre impreso coincide** con la lista que dejaste en recepción (el *subject*).

```
 GitHub Actions / Azure DevOps                       Entra ID                         Azure (ARM, Blobs)
 ┌───────────────────────────┐   1. pide token      ┌──────────────────┐
 │ trabajo "apply" (prod)    │ ───────────────────► │ emisor OIDC de   │
 │ id-token: write           │ ◄─────────────────── │ la plataforma    │
 └───────────┬───────────────┘   2. token (JWT):    └──────────────────┘
             │                      iss, aud, sub
             │ 3. intercambio: "este JWT por un token de Azure"
             ▼
 ┌──────────────────────────────────────────────┐
 │ Credencial federada de la identidad id-tf-... │  ¿iss, sub y aud coinciden EXACTO?
 └───────────┬──────────────────────────────────┘
             │ 4. sí: token de acceso (≈1 h)             5. terraform plan / apply
             ▼                                           ─────────────────────────────►
        Terraform (azurerm) ────────────────────────────►  roles de la identidad
```

## 2. Cómo funciona por dentro

### 2.1 El intercambio de tokens, paso a paso
1. El trabajo del pipeline pide a su plataforma un **token OIDC** (en GitHub, el trabajo necesita `permissions: id-token: write`).
2. El token es un JWT firmado con tres campos que importan: `iss` (quién lo emite), `aud` (para quién) y `sub` (quién es este trabajo).
3. Terraform (o `az login`) lo presenta a Entra ID como una **aserción de cliente** junto con el `client_id` de la identidad.
4. Entra ID busca en esa identidad una **credencial federada** cuyo `issuer`, `subject` y `audience` coincidan **exactamente** (distingue mayúsculas de minúsculas).
5. Si coincide, devuelve un token de acceso de **corta vida**; Terraform lo usa contra ARM y contra el Storage del estado.

### 2.2 Los tres campos de una credencial federada
| Campo | Valor para GitHub Actions | Notas |
|---|---|---|
| `issuer` | `https://token.actions.githubusercontent.com` | Debe coincidir con el `iss` del token. Un espacio sobrante rompe el intercambio |
| `audiences` | `api://AzureADTokenExchange` | Es obligatoria; solo se admite **un** valor |
| `subject` | Ver tabla siguiente | **Sin comodines**; máximo 600 caracteres |

Límites y trampas (documentados por Microsoft): **máximo 20 credenciales federadas por identidad o aplicación**; **no hay comodines** en ningún campo; y un `subject` mal escrito **se crea sin error** y falla recién cuando el pipeline intenta iniciar sesión.

### 2.3 Qué `subject` emite cada disparador (GitHub)
| El trabajo… | `sub` del token | Úsalo para |
|---|---|---|
| Referencia un **entorno** (`environment: prod`) | `repo:org/repo:environment:prod` | **Apply** protegido por aprobaciones |
| No tiene entorno y corre por un **push** a una rama | `repo:org/repo:ref:refs/heads/main` | Despliegues sin aprobación (dev) |
| No tiene entorno y corre por un **pull request** | `repo:org/repo:pull_request` | Plan de PR (ojo: lo puede disparar cualquier PR del repositorio) |
| No tiene entorno y corre por una etiqueta | `repo:org/repo:ref:refs/tags/v1.0.0` | Lanzamientos |

> **Regla importante:** cuando el trabajo **referencia un entorno**, el `sub` usa el entorno **aunque el disparador sea un PR**. Por eso este material usa los entornos `dev-plan`, `prod-plan`, `dev` y `prod`: el nombre del entorno queda en el `sub` y las reglas de protección del entorno se vuelven parte de la seguridad.

**Azure DevOps** usa el mismo mecanismo con otro emisor: la *conexión de servicio* con *Workload identity federation* (creada automáticamente o a mano) registra una credencial con `issuer` `https://vstoken.dev.azure.com/<id-de-la-organización>` y `subject` `sc://<organización>/<proyecto>/<nombre-de-la-conexión>`. **Verifica ambos valores en la pantalla de la conexión** al crearla.

### 2.4 Variables de entorno del proveedor `azurerm`
| Variable | Argumento del proveedor | Para qué |
|---|---|---|
| `ARM_USE_OIDC=true` | `use_oidc` | Usar el flujo OIDC |
| `ARM_CLIENT_ID` | `client_id` | `client_id` de la identidad (no es un secreto) |
| `ARM_TENANT_ID` | `tenant_id` | Tenant de Entra ID |
| `ARM_SUBSCRIPTION_ID` | `subscription_id` | **Obligatoria** desde `azurerm` 4 |
| `ARM_OIDC_TOKEN` | `oidc_token` | Pasar el JWT ya obtenido (Azure DevOps con `addSpnToEnvironment`) |
| `ARM_USE_AZUREAD` | `use_azuread_auth` (backend) | Que el backend use Entra ID en vez de claves |
| `ARM_USE_MSI` | `use_msi` | Identidad administrada de la VM/runner |

En GitHub Actions el proveedor y el backend piden el token solos (usan las variables que GitHub inyecta cuando existe `id-token: write`); **no necesitas** `azure/login` salvo que el trabajo use la CLI `az`. En Azure DevOps hay dos caminos: la tarea `AzureCLI@2` con `addSpnToEnvironment: true` (expone `servicePrincipalId`, `tenantId` e `idToken`) o las variables de conexión del proveedor; **verifica en la documentación del proveedor** cuál conviene en aplicaciones largas, porque el token inicial caduca en minutos.

### 2.5 Métodos de autenticación de Terraform en Azure
| Método | Secreto | Ideal para | Comentario |
|---|---|---|---|
| **Sesión de CLI** (`az login`) | No (sesión) | Tu portátil | Usa **tu** identidad y permisos |
| **Service principal + secreto** | **Sí** (caduca) | Casi nunca | Evítalo en pipelines nuevos |
| **Service principal + certificado** | Sí (certificado) | Sistemas que no admiten OIDC | Rota y protege el certificado |
| **OIDC / identidad federada** | **No** | **Pipelines (GitHub, Azure DevOps)** | La opción recomendada |
| **Identidad administrada** (`use_msi`) | No | Runners propios en una VM de Azure | La identidad vive en la VM |
| **Workload identity en AKS** | No | Ejecutores dentro de un clúster | Federación con la cuenta de servicio de Kubernetes |

### 2.6 Identidad administrada o aplicación (*app registration*)
Las credenciales federadas se pueden colgar de una **identidad administrada asignada por el usuario** o de un **registro de aplicación**. Para pipelines de infraestructura conviene la **identidad administrada**: es un recurso de Azure (se crea con Terraform, se etiqueta, se ve en el portal), no requiere permisos de directorio para crearla y no tiene secretos de ningún tipo. El registro de aplicación hace falta si necesitas permisos de Microsoft Graph u otros casos del directorio.

## 3. Para qué sirve y cuándo NO

**Sirve para**
- Que los pipelines operen Azure **sin secretos** que rotar, filtrar o copiar.
- **Separar permisos**: una identidad que solo planifica y otra que aplica, por entorno.
- Atar cada identidad a **un repositorio, un entorno y una rama** concretos.
- Dejar un rastro de auditoría: cada cambio tiene una identidad con nombre.

**Cuándo NO**
- Un laboratorio personal: `az login` basta.
- Sistemas que no emiten tokens OIDC (algunos servidores de CI antiguos): ahí queda el certificado, con una rotación automática.
- Si necesitas más de 20 `subject` por identidad: replantea el diseño (más identidades o entornos) en vez de forzarlo.

## 4. Conceptos clave
| Término | Significado simple |
|---|---|
| **OIDC** | Protocolo por el que una plataforma firma un token que dice "este trabajo soy yo" |
| **JWT** | El token: tres partes (cabecera, datos, firma); los datos se llaman *claims* |
| **Claim** | Un dato dentro del token: `iss`, `aud`, `sub`, `repository`, `ref`, `environment`… |
| **Credencial federada** | Regla en Azure: "confío en tokens de ESTE emisor, con ESTE subject y ESTA audiencia" |
| **Subject (`sub`)** | Cadena que identifica al trabajo: repositorio + entorno/rama/PR |
| **Identidad administrada asignada por el usuario** | Identidad que existe como recurso propio y se asigna donde haga falta |
| **Plan / apply** | Dos operaciones con riesgos distintos: leer y proponer vs. cambiar |
| **Plan guardado** | Archivo `tfplan` que `apply` ejecuta tal cual, sin recalcular |
| **Entorno protegido** | Entorno de GitHub o Azure DevOps con revisores, esperas y restricción de ramas |
| **Deriva (*drift*)** | La realidad cambió sin pasar por Terraform |
| **ABAC / condición de rol** | Condición que limita qué roles puede asignar un administrador de RBAC |

## 5. Cómo se usa

### 5.1 Diseño de identidades
Por **cada entorno**, dos identidades:

| Identidad | Roles de control (suscripción) | Rol de datos (estado) | La usa… |
|---|---|---|---|
| `id-tf-<entorno>-plan` | *Reader* | *Storage Blob Data Owner* sobre el **contenedor** (porque el `plan` toma el candado) *o* *Reader* con `plan -lock=false` | PRs, deriva nocturna |
| `id-tf-<entorno>-apply` | *Contributor* + *Role Based Access Control Administrator* **con condición** (solo los roles que de verdad asignas) | *Storage Blob Data Owner* sobre el contenedor | Solo el trabajo de apply, tras aprobación |

El archivo [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) crea todo esto (identidades, credenciales federadas y roles) a partir de un mapa de entornos, y los mismos pasos con CLI están en [`ejemplos/cli/identidades.sh`](ejemplos/cli/identidades.sh).

> *Contributor* **no** puede crear asignaciones de roles. Si tu Terraform crea `azurerm_role_assignment`, el apply necesita permiso de asignar roles; dárselo como *Owner* es demasiado. La salida es *Role Based Access Control Administrator* **con condición** que limita qué roles puede entregar.

### 5.2 Puesta en marcha en seis pasos
1. Crea el almacén del estado ([estado remoto](../estado-remoto/README.md)) y anota el ID de la cuenta.
2. Crea las identidades, las credenciales federadas y los roles (Terraform o CLI), con el `subject` que emitirá **tu** pipeline.
3. En GitHub, crea los entornos `dev-plan`, `dev`, `prod-plan`, `prod`; en `prod` pon revisores obligatorios y restringe las ramas.
4. Guarda `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` y `AZURE_SUBSCRIPTION_ID` como **variables** del entorno (no son secretos).
5. Copia los workflows de [`ejemplos/github-actions`](ejemplos/github-actions) (o el de [Azure DevOps](ejemplos/azure-devops/azure-pipelines.yml)) y el [proveedor con OIDC](ejemplos/hcl/provider-oidc.tf).
6. Haz un PR de prueba: debe planificar. Fusiona: debe aplicar en dev y esperar aprobación en prod.

### 5.3 Anatomía del pipeline
```
 Pull request ──► fmt + validate ──► plan (identidad PLAN, solo lectura) ──► comentario en el PR + puerta de seguridad
                                                                                      │ revisión humana
 Merge a main ──► plan (guarda tfplan) ──► [aprobación del entorno] ──► apply del MISMO tfplan (identidad APPLY)
 Cada noche   ──► plan completo ──► si hay diferencias: aviso (deriva)
```
- **Plan guardado:** el `apply` ejecuta `terraform apply tfplan`, el plan que se revisó, no uno nuevo. Si el estado cambió entremedio, Terraform se niega: es una protección, no un error.
- **Concurrencia:** un solo apply por estado (`concurrency` con `cancel-in-progress: false`). Cancelar un apply a medias deja el candado del estado huérfano.
- **Misma versión de Terraform** en plan y apply (y en tu portátil): fíjala.
- **Artefacto del plan:** contiene valores del estado; retención de un día y acceso restringido.

### 5.4 Ejecutores (*runners*) y red
Si el estado y las redes de destino son privados, un ejecutor público de GitHub **no llega**. Usa ejecutores propios (VM o contenedores en tu red, con identidad administrada o con acceso por Private Endpoint al almacén). En los ejemplos, la variable `RUNNER_TF` elige el ejecutor sin tocar el workflow.

### 5.5 Puertas de calidad y seguridad (en orden)
| Etapa | Herramienta | Qué evita |
|---|---|---|
| Formato | `terraform fmt -check` | Diffs ruidosos |
| Validación | `terraform validate` | Errores de sintaxis y tipos |
| Lint | `tflint` (con el plugin de Azure) | Tamaños de SKU inexistentes, argumentos obsoletos |
| Seguridad de configuración | `trivy config`, `checkov` | Almacenes públicos, TLS bajo, reglas abiertas |
| Políticas propias | `conftest` (OPA) o el [analizador en Java](uso-en-java.md) sobre `terraform show -json` | Borrar recursos protegidos, dar *Owner*, abrir a Internet |
| Costo | `infracost` | Sorpresas de factura antes de aplicar |
| Secretos | Escáner de secretos del repositorio | Claves en el código |

### 5.6 Azure DevOps en dos líneas
Conexión de servicio con *Workload identity federation*, un **entorno** con aprobaciones para el apply y dos conexiones (plan y apply) para separar permisos. Ver [`azure-pipelines.yml`](ejemplos/azure-devops/azure-pipelines.yml).

### 5.7 Quién ejecuta Terraform: pipeline, no aplicación
Tu microservicio Java **no** ejecuta Terraform. Lo que sí se construye en Java es **plataforma**: un portal de autoservicio que genera `tfvars`, lanza `plan` en un ejecutor aislado y **analiza el plan** antes de aprobar. Está en [uso en Java](uso-en-java.md).

## 6. Seguridad

### 6.1 IAM por plano
| Plano | Qué permite | Rol típico | Para quién |
|---|---|---|---|
| **Control (ARM)** | Leer la suscripción | *Reader* | Identidad de plan |
| **Control (ARM)** | Crear/cambiar/borrar recursos | *Contributor* sobre la suscripción o el grupo de recursos | Identidad de apply (solo el alcance que necesita) |
| **Control (ARM)** | Asignar roles | *Role Based Access Control Administrator* **con condición** | Identidad de apply, solo si el código asigna roles |
| **Control (ARM)** | Crear identidades y credenciales federadas | *Managed Identity Contributor* (más permisos de roles) | Equipo de plataforma, no los pipelines de aplicaciones |
| **Datos (blobs)** | Leer/escribir el estado y tomar el candado | *Storage Blob Data Owner* sobre el **contenedor** (según la documentación del backend) | Plan y apply de **su** entorno |
| **Datos (Key Vault)** | Leer secretos que Terraform necesite | *Key Vault Secrets User* | Solo si es imprescindible; mejor que Terraform no lea secretos |

### 6.2 Amenazas y defensas
| Amenaza | Cómo ocurre | Defensa |
|---|---|---|
| **Quien edita el workflow manda** | Un PR cambia el workflow y ejecuta código con la identidad | Restringe qué `sub` puede apply (entorno + rama protegida); `CODEOWNERS` sobre `.github/workflows` e `infra/`; trata los workflows como código de producción |
| **PR de un fork** | Un tercero abre un PR e intenta usar la identidad | Los PR de forks, por defecto, no reciben secretos ni permisos de escritura (verifica la configuración de tu repositorio); y no uses `pull_request_target` con código ajeno |
| **Subject demasiado amplio** | Una identidad confía en todas las ramas | Un `subject` por entorno protegido; sin comodines (Azure no los admite) |
| **Apply sin revisión** | `-auto-approve` en producción | Entorno con revisores, plan guardado y puertas automáticas |
| **Escalada de privilegios** | La identidad de apply se asigna *Owner* a sí misma | Condición de ABAC que lista los roles permitidos; nunca *Owner* ni *User Access Administrator* sin condición |
| **El plan revela secretos** | Se publica el plan o el artefacto | Retención de un día, acceso restringido; `sensitive` oculta en pantalla, no en el archivo |
| **Identidad compartida entre entornos** | Dev puede tocar producción | Dos identidades por entorno y estados en contenedores distintos |
| **Cuenta de estado abierta** | Cualquiera puede leer/escribir | Roles de datos por contenedor y red cerrada ([estado remoto](../estado-remoto/README.md)) |

### 6.3 Revisa lo que realmente puede una identidad
```bash
az role assignment list --assignee <principal-id> --all -o table
```
Revisa trimestralmente: qué roles tiene, a qué alcance y si todavía lo necesita.

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- **OIDC** en todo pipeline nuevo; migra los secretos existentes.
- **Dos identidades por entorno** (plan y apply) y **estados separados**.
- Un **entorno protegido** con revisores para cada apply de producción.
- **Plan guardado** y apply del mismo archivo.
- **Concurrencia por estado**, sin cancelar aplicaciones en curso.
- **Fijar versiones** de Terraform, del proveedor y de las acciones (idealmente por SHA).
- **Condiciones de ABAC** para asignar roles; roles mínimos y alcance estrecho.
- Escáneres y **políticas** antes de aplicar; **deriva nocturna** con aviso.

**Qué NO hacer**
- Guardar secretos de cliente en el repositorio o en variables "secretas" por comodidad.
- Dar *Owner* a la identidad del pipeline.
- Usar la misma identidad para plan y apply, o para dev y prod.
- `terraform apply -auto-approve` en producción sin plan revisado.
- Subir `tfplan` a un artefacto con retención larga.
- Cancelar un `apply` en curso (candado huérfano, estado a medias).
- Confiar en `pull_request_target` con código no revisado.
- Esperar que un `subject` mal escrito avise al crearse: se descubre en el login.

## 8. Límites, costos y versiones
- **Costo:** la federación y las identidades administradas no cuestan; pagas los ejecutores de CI y el almacenamiento del estado.
- **Límites:** 20 credenciales federadas por identidad; sin comodines; `subject` ≤ 600 caracteres; la audiencia es una sola.
- **Propagación:** una credencial recién creada puede tardar unos minutos en ser efectiva; reintenta antes de depurar.
- **Reglas de GitHub:** los revisores obligatorios y las restricciones de rama de los entornos dependen del plan de GitHub; **verifica en tu cuenta**.
- **Versiones:** `azurerm` 4 exige `subscription_id`; los nombres de variables del proveedor, las versiones de las acciones y los GUID de roles integrados cambian: **verifica en la documentación oficial**.

---
Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · Capítulo: [módulos y entornos](../modulos-y-entornos/README.md)
