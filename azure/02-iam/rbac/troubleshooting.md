# Azure · RBAC · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AuthorizationFailed ... does not have authorization to perform action` | Falta el rol en ese alcance | `az role assignment list --assignee <id> --all -o table` | Asignar el rol mínimo en el alcance correcto |
| 403 siendo Owner/Contributor sobre el recurso | La operación es del **plano de datos** | ¿Es leer blobs/secretos/mensajes? | Asignar el rol de datos |
| `AuthorizationPermissionMismatch` (Storage) | Falta rol de datos Blob | Roles de la identidad | *Storage Blob Data Reader/Contributor* |
| Key Vault: `Caller is not authorized to perform action on resource` | El vault usa RBAC y falta rol, o usa access policies | Modelo de permisos del vault | Rol *Key Vault Secrets User* o política de acceso |
| Se asignó el rol y sigue el 403 | Propagación o token en caché | Esperar unos minutos; nuevo token | Reiniciar la aplicación / volver a iniciar sesión |
| `RoleAssignmentExists` | Ya existe esa asignación | Listar asignaciones | Ignorar o importar al estado de Terraform |
| `PrincipalNotFound` al asignar | La identidad se acaba de crear y aún no replica | Reintentar | Esperar; en Terraform usar `principal_type` y dependencias |
| `LinkedAuthorizationFailed` | Falta permiso sobre el recurso al que se enlaza (por ejemplo asignar una identidad a un recurso) | Mensaje de error | Dar el permiso `.../action` indicado |
| No puedo asignar roles | No tengo `roleAssignments/write` | Mi rol en ese alcance | Pedir a un Owner/User Access Administrator |
| `RoleDefinitionLimitExceeded` | Demasiados roles personalizados | Cantidad de roles | Reutilizar o limpiar |
| Asignaciones a un usuario que ya se fue (`Unknown`) | La identidad fue eliminada | Asignaciones con tipo "Unknown" | Eliminar la asignación huérfana |
| Una persona ve más de lo esperado | Herencia desde un alcance superior | `--include-inherited` | Quitar o acotar la asignación superior |

## Comandos útiles
```bash
az role assignment list --assignee <objectId> --all -o table
az role assignment list --scope <scope> --include-inherited -o table
az role definition list --name "<rol>" --query "[].permissions" -o json
az role assignment list --all --query "[?principalName==null]" -o table     # huérfanas
az monitor activity-log list --offset 1d --query "[?contains(operationName.value,'roleAssignments')]" -o table
```
