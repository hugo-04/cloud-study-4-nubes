# Azure · Terraform · Estado remoto (backend `azurerm`)

> Terraform puede crear la red más hermosa del mundo, pero si pierde su **estado** olvida que la creó. Este documento es sobre dónde se guarda esa memoria en Azure, cómo se protege y qué hacer cuando se complica.

## 1. Qué es

El **estado** (*state*) es un archivo JSON donde Terraform anota **qué recursos reales corresponden a cada bloque de tu código** (qué `azurerm_virtual_network.vnet` es qué red de Azure, con su ID y sus atributos). Un **backend** es el lugar donde se guarda ese archivo. En Azure, el backend `azurerm` lo guarda como un **blob** en una cuenta de almacenamiento.

**Analogía:** el **libro de obra** de un edificio. Los planos (tu código) dicen cómo *debe* quedar; el libro de obra dice qué *se construyó ya* y con qué número de lote. Sin el libro, el constructor no sabe si el muro ya existe y lo levanta otra vez (o no se atreve a tocar nada).

```
 Tu código (.tf)  ──►  terraform plan  ──►  compara  ◄──  Estado (blob JSON)  ◄──►  Recursos reales en Azure
   "así debe quedar"        │                                "esto construí"            (refresco: consulta ARM)
                            ▼
                 diferencia = lo que hará apply
```

```
Cuenta de almacenamiento (privada, sin claves)
 └─ contenedor "tfstate"
     ├─ plataforma/gobierno.tfstate
     ├─ plataforma/red-hub.tfstate
     ├─ dev/red.tfstate            ← un blob por componente y entorno
     ├─ dev/app-pedidos.tfstate
     └─ prod/app-pedidos.tfstate
```

## 2. Cómo funciona por dentro

### 2.1 El archivo de estado
Un archivo JSON con, entre otras, estas partes (la estructura la define Terraform; **no lo edites a mano**):

| Campo | Para qué sirve |
|---|---|
| `version` | Versión del formato del archivo |
| `terraform_version` | Con qué versión se escribió por última vez (una versión más antigua **no podrá** leerlo después) |
| `serial` | Contador que sube en cada cambio: detecta copias viejas |
| `lineage` | Identificador único de **ese** estado: evita mezclar estados distintos |
| `outputs` | Los `output` del código, con sus valores |
| `resources` | Cada recurso: tipo, nombre, proveedor, ID real y **todos sus atributos** |

> **Los atributos incluyen valores sensibles en texto claro** (contraseñas generadas, cadenas de conexión, claves). `sensitive = true` solo los oculta en la pantalla, **no en el archivo**. El estado es tan sensible como un secreto.

### 2.2 Qué hace cada comando con el estado
| Comando | Lee estado | Cambia estado | Cambia Azure |
|---|---|---|---|
| `terraform plan` | Sí (y **refresca** consultando Azure) | No (con `-refresh-only`, solo propone) | No |
| `terraform apply` | Sí | **Sí** | **Sí** |
| `terraform destroy` | Sí | Sí | Sí (borra) |
| `terraform import` / bloque `import` | Sí | Sí (agrega) | No |
| `terraform state mv` / bloque `moved` | Sí | Sí (renombra la dirección) | No |
| `terraform state rm` / bloque `removed` | Sí | Sí (olvida el recurso) | No (con `removed` y `destroy = false`) |
| `terraform force-unlock` | No | No | No (solo suelta el bloqueo) |

### 2.3 Bloqueo del estado (*locking*)
Cuando una operación puede **escribir**, el backend `azurerm` toma un **arrendamiento (*lease*) del blob**, que sirve de candado. Si un segundo `apply` intenta tomarlo, falla con `Error acquiring the state lock` y muestra quién lo tiene (ID, usuario, hora). Al terminar, Terraform suelta el candado. Si el proceso muere a medias (pipeline cancelado, red caída), el candado puede quedar **huérfano** y hay que liberarlo a mano (con `terraform force-unlock <ID>`, o rompiendo el lease; ver [troubleshooting](troubleshooting.md)).

### 2.4 Configuración parcial del backend
El bloque `backend` **no admite variables ni referencias**. Lo que cambia entre entornos (cuenta, contenedor) se pasa con `-backend-config`:

```bash
terraform init -backend-config=backend.hcl     # archivo con cuenta, contenedor y use_azuread_auth
```
El código solo declara la **clave** (`key`) del componente: [`ejemplos/hcl/backend.tf`](ejemplos/hcl/backend.tf) y [`ejemplos/hcl/backend.hcl.ejemplo`](ejemplos/hcl/backend.hcl.ejemplo).

### 2.5 Autenticación contra el almacén
| Método | Argumento (variable de entorno) | Cuándo |
|---|---|---|
| **Entra ID del usuario** (la sesión de `az login`) | `use_azuread_auth = true` (`ARM_USE_AZUREAD`) | Estudio y administración manual |
| **OIDC / identidad federada** | `use_oidc = true` (`ARM_USE_OIDC`) + `client_id`, `tenant_id`, `subscription_id` | **Pipelines** (la opción recomendada; ver [autenticación y pipelines](../autenticacion-y-pipelines/README.md)) |
| Identidad administrada (`use_msi`) | `use_msi = true` (`ARM_USE_MSI`) | Ejecutores dentro de Azure (VM, runners propios) |
| Clave de la cuenta / SAS | `access_key` / `sas_token` | **Evítalas:** secretos de larga vida; desactívalas en la cuenta |

Con `use_azuread_auth`, la documentación del backend indica que la identidad necesita el rol **Storage Blob Data Owner** (o *Container Blob Data Owner*) sobre el almacén.

## 3. Para qué sirve y cuándo NO

**Sirve para**
- Que **todo el equipo y los pipelines** compartan la misma memoria (nadie tiene "su copia").
- **Evitar aplicaciones simultáneas** (bloqueo).
- **Recuperar** versiones anteriores (versionado del blob) y sobrevivir a una máquina perdida.
- Dividir la infraestructura en **piezas pequeñas** con estados independientes.

**Cuándo NO hace falta**
- Un laboratorio de una tarde, de una sola persona, que destruirás al terminar: el estado local basta (pero **nunca lo subas a Git**).
- Recursos que solo vas a crear por CLI o portal.

**Alternativas**
| Opción | Nota |
|---|---|
| **HCP Terraform / Terraform Enterprise** | Estado, bloqueo y ejecución administrados por HashiCorp (servicio aparte, de pago según el plan) |
| **Bicep / Deployment Stacks** | Azure guarda el "estado" en el propio ARM; no hay archivo que cuidar (solo Azure) |
| **Backend `azurerm` (este documento)** | Control total, costo mínimo, todo dentro de tu suscripción |

## 4. Conceptos clave

| Término | Significado simple |
|---|---|
| **State** | Mapa "recurso del código ↔ recurso real" |
| **Backend** | Dónde se guarda y cómo se bloquea el estado |
| **Lease (arrendamiento)** | Candado de un blob con dueño; es lo que impide aplicar dos veces a la vez |
| **Clave (`key`)** | Nombre del blob del estado, p. ej. `dev/red.tfstate` |
| **Workspace** | Varios estados con el mismo código y el mismo backend (ver recomendación abajo) |
| **Bootstrap** | El arranque del huevo y la gallina: crear el almacén del estado antes de poder guardar estado |
| **Drift** | La realidad cambió sin pasar por Terraform |
| **Refresh** | Terraform consulta Azure para actualizar lo que sabe de cada recurso |
| **Estado dividido** | Un estado por componente y entorno para limitar el daño y acelerar los planes |
| **`terraform_remote_state`** | Leer las salidas de **otro** estado (ve todo su contenido) |
| **Cirugía del estado** | `state mv`, `state rm`, `import`: cambiar la memoria sin tocar Azure |

## 5. Cómo se usa

### 5.1 Arranque (*bootstrap*) en cuatro pasos
1. **Crea el almacén con estado local**, usando [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) (cuenta endurecida, versionado, borrado suave, bloqueo `CanNotDelete`, roles).
2. **Anota la configuración** que imprime el `output` (`configuracion_del_backend`) en un `backend.hcl`.
3. **Migra el estado del propio almacén** a sí mismo: añade `backend.tf` y ejecuta `terraform init -migrate-state -backend-config=backend.hcl`; borra el estado local.
4. **Da acceso** a las identidades con la variable `accesos` (rol sobre el **contenedor**, no sobre toda la cuenta).

Los comandos están en [`ejemplos/cli/estado.sh`](ejemplos/cli/estado.sh).

### 5.2 Cuántos estados y cómo nombrarlos
Divide por **ciclo de vida, dueño y radio de daño**: lo que cambia rara vez y rompe todo (red central, gobierno) no comparte estado con lo que cambia a diario (una aplicación).

| Clave | Contiene | Lo cambia |
|---|---|---|
| `plataforma/gobierno.tfstate` | Grupos de administración, políticas, presupuestos | Equipo de plataforma |
| `plataforma/red-hub.tfstate` | Red central, DNS privado, firewall | Equipo de plataforma |
| `dev/red.tfstate`, `prod/red.tfstate` | Red del entorno | Plataforma |
| `dev/app-pedidos.tfstate`, `prod/app-pedidos.tfstate` | Una aplicación y sus recursos | El equipo de la aplicación |

Convención: `<entorno>/<componente>.tfstate`. Un planificador (`plan`) tarda más cuanto más recursos tenga el estado, porque refresca **cada uno**; si tus planes pasan de varios minutos, es señal de dividir.

### 5.3 Una cuenta o varias
| Enfoque | Ventaja | Desventaja |
|---|---|---|
| **Una cuenta para todo** | Simple y barata | Quien administre la cuenta ve todos los estados; un error afecta a todo |
| **Una cuenta para no producción y otra para producción** | Permisos y red separados; el radio de daño se parte en dos | Dos bootstraps y dos conjuntos de accesos |
| **Una por suscripción o por equipo** | Aislamiento máximo | Mucha administración |

La opción intermedia (producción separada) es la que más se ve en la práctica.

### 5.4 Lectura entre estados
`terraform_remote_state` permite que el componente de la aplicación lea la subred creada por el de red ([`ejemplos/hcl/lectura-entre-estados.tf`](ejemplos/hcl/lectura-entre-estados.tf)), pero **quien lea el estado ajeno puede ver todo su contenido**, secretos incluidos. Cuando puedas, lee el recurso con un *data source* de `azurerm`: pides el dato por su nombre y no necesitas acceso al estado.

### 5.5 Workspaces: mejor carpetas y claves
Los *workspaces* guardan varios estados con el **mismo backend y las mismas credenciales**. Para dev y prod (que deben tener **permisos distintos**) conviene separar por **clave y por carpeta de entorno**, no por workspace.

### 5.6 Cirugía del estado
| Necesidad | Forma recomendada |
|---|---|
| Renombrar o mover un recurso en el código | Bloque `moved { from = ... to = ... }` (queda en el código y en la revisión) |
| Traer un recurso que ya existe | Bloque `import { to = ... id = ... }` |
| Dejar de administrar un recurso **sin borrarlo** | Bloque `removed { from = ... lifecycle { destroy = false } }` |
| Ver la diferencia con la realidad sin cambiar nada | `terraform plan -refresh-only` |
| Liberar un candado huérfano | `terraform force-unlock <ID>` |

`terraform state mv/rm` siguen existiendo, pero son cambios **fuera de la revisión de código**: úsalos con una copia a mano y un `plan` después.

## 6. Seguridad

Controles del almacén (los aplica el Terraform del ejemplo):

| Control | Valor | Por qué |
|---|---|---|
| Claves de la cuenta | **Desactivadas** (`shared_access_key_enabled = false`) | Solo Entra ID: nada que filtrar ni rotar |
| Acceso anónimo a blobs | **Desactivado** | Un estado nunca es público |
| TLS mínimo | 1.2 | Cifrado en tránsito |
| Solo HTTPS | Sí | Idem |
| Firewall | `Deny` por defecto + IP/subredes de los ejecutores (o Private Endpoint) | Reduce quién puede siquiera intentar |
| Versionado de blobs | **Sí** | Recuperar un estado dañado o sobrescrito |
| Borrado suave (blobs y contenedores) | 30 días | Recuperar un borrado accidental |
| Bloqueo `CanNotDelete` | En la cuenta | Evita borrar la cuenta entera por error |
| Redundancia | ZRS (o GRS si necesitas otra región) | Sobrevivir a la caída de una zona |
| Diagnóstico a Log Analytics | Lectura, escritura y borrado | Saber quién tocó el estado ([KQL](ejemplos/kql/kql-estado.md)) |

### IAM por plano
| Plano | Qué permite | Rol típico | Quién |
|---|---|---|---|
| **Control (ARM)** | Cambiar la cuenta: firewall, claves, versionado | *Contributor* sobre el grupo de recursos del estado | Solo plataforma |
| **Control (ARM)** | Asignar roles | *Owner* / *User Access Administrator* | Solo plataforma |
| **Datos (blobs)** | Leer y escribir estados, tomar el candado | *Storage Blob Data Owner* (según la doc del backend), **sobre el contenedor** | Identidad de `apply` de cada entorno |
| **Datos (blobs)** | Leer estados (revisión, auditoría) | *Storage Blob Data Reader* | Muy pocas personas: el estado contiene secretos |

> El `plan` también toma el candado (escribe), así que la identidad que solo planifica **también** necesita escribir en el contenedor. Separa los entornos por **contenedor o por cuenta** para que la identidad de dev no pueda leer el estado de producción.

### Red
Si cierras la cuenta con firewall, **el ejecutor debe poder llegar a ella**: IP fijas de salida, subredes con punto de servicio o, mejor, *Private Endpoint* con su zona DNS privada (`privatelink.blob.core.windows.net`) y ejecutores dentro de la red (runners propios). Los ejecutores públicos de los pipelines **no** tienen IP estables.

### Los archivos de plan también son sensibles
`terraform plan -out=tfplan` contiene los valores del estado y de los cambios: trátalo como un secreto (artefacto con retención corta y acceso restringido).

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Backend **remoto, privado, sin claves, versionado y con borrado suave** desde el primer día.
- **Un estado por componente y entorno**; producción en cuenta o contenedor aparte.
- Cambiar nombres y direcciones con **`moved`**, **`import`** y **`removed`** (revisables).
- Revisar el **diagnóstico** del almacén: borrados, bloqueos rotos, accesos fallidos.
- Tener un **simulacro de recuperación**: restaurar una versión anterior en un entorno de pruebas.
- Documentar el **bootstrap** (quién, con qué permisos, cómo se rehace).

**Qué NO hacer**
- Subir `terraform.tfstate` o `tfplan` a Git o a un artefacto público.
- Usar la **clave de la cuenta** o un SAS en el backend.
- Editar el JSON del estado a mano.
- Usar `-lock=false` "para que pase".
- Poner todo en un único estado gigante.
- Dar acceso de lectura al estado "porque es solo lectura": ahí viven los secretos.
- Ejecutar `force-unlock` sin confirmar que **nadie** está aplicando.

## 8. Límites, costos y versiones

- **Costo:** céntimos al mes (almacenamiento y operaciones de blobs); el versionado suma según cuántas versiones guardes.
- **Un bloqueo por estado:** dos personas no pueden aplicar al mismo estado a la vez; por eso el estado dividido también acelera al equipo.
- **Compatibilidad:** un estado escrito por una versión nueva de Terraform puede no abrirse con una antigua; **fija la versión** (`required_version`) y actualiza al equipo y a los pipelines juntos.
- **OpenTofu:** usa el mismo backend `azurerm` y formato compatible; verifica las diferencias de versión antes de mezclar herramientas sobre el mismo estado. El bloque `removed` con `lifecycle { destroy = false }` funciona en Terraform 1.7+ y en OpenTofu reciente (probado con 1.10; la 1.8 lo rechaza).
- **Valores que cambian con la versión:** nombres de argumentos del backend y roles requeridos; **verifica en la documentación oficial** de tu versión.

---
Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md)
