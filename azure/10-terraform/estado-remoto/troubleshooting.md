# Azure · Terraform · Estado remoto · Troubleshooting

Orden de revisión: **¿llego a la cuenta (red/DNS)? → ¿me autentico (identidad, método)? → ¿tengo permiso de datos (rol)? → ¿está bloqueado el estado? → ¿el estado es el correcto (versión, serial)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Error acquiring the state lock` | Otra ejecución en curso, o candado huérfano | El mensaje trae ID, quién y desde cuándo; revisa pipelines activos | Esperar; si está huérfano y nadie aplica: `terraform force-unlock <ID>` |
| `force-unlock` no funciona | El lease sigue tomado por otro proceso | `az storage blob show` → `properties.lease` | `az storage blob lease break` (último recurso, tras confirmar) |
| `403 AuthorizationPermissionMismatch` | Sin rol de datos, o el método de autenticación no es Entra ID | Roles de datos del principal sobre el contenedor; `use_azuread_auth` | Asignar *Storage Blob Data Owner* sobre el contenedor; usar `use_azuread_auth = true` |
| `403` con `KeyBasedAuthenticationNotPermitted` | El backend usa clave de cuenta y las claves están desactivadas | Configuración del backend | Cambiar a `use_azuread_auth` (u OIDC) y `init -reconfigure` |
| `403 AuthorizationFailure` / "This request is not authorized to perform this operation" | Firewall de la cuenta | Red de la cuenta, IP de salida del ejecutor | Permitir IP o subred, o usar Private Endpoint y DNS privado |
| Tiempo de espera / `no such host` | DNS privado mal enlazado o ruta inexistente | `nslookup <cuenta>.blob.core.windows.net` desde el ejecutor | Zona `privatelink.blob.core.windows.net` enlazada a la red; revisar rutas |
| `ContainerNotFound` / `StorageAccountNotFound` | Nombre mal escrito en `backend.hcl` o recurso borrado | `az storage container exists` | Corregir; restaurar contenedor con borrado suave |
| `Backend configuration changed` | El backend cambió desde el último `init` | Diferencia entre `backend.hcl` y `.terraform/terraform.tfstate` | `terraform init -reconfigure` (solo apuntar) o `-migrate-state` (copiar) |
| `Failed to get existing workspaces` | Sin permisos para listar blobs | Roles de datos | Rol de datos con permiso de listado |
| `state snapshot was created by Terraform vX, which is newer than current vY` | Estado escrito por una versión más nueva | `terraform version` y `terraform_version` del estado | Actualizar Terraform; fijar `required_version` en el equipo |
| `Error: Unsupported state file format` | Archivo editado a mano o corrupto | Versiones del blob | Restaurar versión anterior |
| `Inconsistent lineage` | Estado de otro componente en la misma clave | `lineage` del blob | Revisar `key`; restaurar |
| El `plan` quiere crear todo otra vez | Estado vacío, clave equivocada o backend equivocado | `terraform state list`; clave del backend | Corregir clave; restaurar versión del blob |
| El `plan` quiere destruir un recurso que renombraste | Cambió la dirección en el código | Línea `-/+` o `-` en el plan | Bloque `moved`; **no** aplicar |
| `already exists` al crear | El recurso existe pero no está en el estado | `terraform state list` | Bloque `import` (o `import` por línea de comandos) |
| Drift: cambios que aparecen siempre | Un valor lo cambia Azure o alguien a mano | `terraform plan -refresh-only` | Declarar el valor, `ignore_changes` con criterio o corregir en Azure |
| El plan tarda muchísimo | Estado grande, muchos recursos que refrescar | Cantidad de recursos (cuenta las líneas de `terraform state list`) | Dividir el estado; `-refresh=false` solo para diagnosticar |
| `429 Too Many Requests` en el plan | Demasiadas llamadas a ARM | Respuesta del provider | Bajar `-parallelism`; dividir el estado |
| Se perdió el estado completo | Borrado accidental o cuenta eliminada | Borrado suave del contenedor, versiones | Restaurar contenedor/blob; si no, recrear con bloques `import` |
| El estado contiene secretos visibles | Atributos sensibles de los recursos | `terraform show -json` (con cuidado) | Menos secretos en Terraform (Key Vault, identidad administrada); restringir lectura |
| `terraform_remote_state` falla | Sin lectura al otro estado o clave distinta | Roles; `key` | Permiso de lectura **mínimo** o usar un *data source* |
| El `output` no aparece en otro componente | Nunca se aplicó el componente de origen | Salidas en el estado | Aplicar el origen primero |

## Comandos útiles
```bash
# Inventario con estado de bloqueo
az storage blob list --account-name <cuenta> --container-name tfstate --auth-mode login \
  --query "[].{clave:name, bytes:properties.contentLength, lease:properties.lease.state, bloqueo:properties.lease.status}" -o table

# Cuál es la identidad con la que estás operando
az account show --query "{usuario:user.name, sub:id, tenant:tenantId}" -o json

# Roles de datos de un principal sobre el contenedor
az role assignment list --assignee <principal-id> --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<cuenta>" -o table

# Resolución DNS de la cuenta desde el ejecutor
nslookup <cuenta>.blob.core.windows.net

# Qué hay en el estado y qué cambiaría la realidad
terraform state list
terraform plan -refresh-only
```

## Secuencia recomendada
1. **Red y DNS:** ¿resuelve la cuenta a la IP esperada (privada si hay Private Endpoint)? ¿está permitida la IP/subred del ejecutor?
2. **Autenticación:** ¿qué método usa el backend (`use_azuread_auth`, OIDC, MSI)? ¿la sesión está vigente?
3. **Rol de datos:** ¿el principal tiene el rol sobre el **contenedor**? (los roles de control como *Contributor* no dan acceso a los datos).
4. **Bloqueo:** ¿quién lo tiene, desde cuándo, sigue vivo ese proceso?
5. **Estado:** ¿clave correcta, `lineage` correcto, versión de Terraform compatible?
6. **Recuperación:** versionado y borrado suave antes de tocar nada; copia del blob a mano.
7. **Corrección en código:** `moved`, `import`, `removed` y un `plan` limpio antes de cualquier `apply`.
