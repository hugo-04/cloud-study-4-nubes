# Azure · Bloqueos de recursos · Troubleshooting

Sigue el flujo: **¿qué error es (`ScopeLocked`, `AuthorizationFailed`, política)? → ¿qué bloqueos hay en la cadena (recurso, grupo, suscripción)? → ¿qué nivel tienen? → ¿quién puede quitarlo y por qué proceso? → ¿hay una segunda capa (política, pila de despliegue)?**

## Distinguir los tres "no puedes"

| Código / mensaje | Qué lo causó | Dónde mirar |
|---|---|---|
| `ScopeLocked` ("cannot perform delete operation because following scope(s) are locked") | **Bloqueo** de recursos | `az lock list` en el recurso, el grupo y la suscripción |
| `AuthorizationFailed` | **Falta de rol** (RBAC) | Asignaciones de roles del principal |
| `RequestDisallowedByPolicy` | **Política** `Deny` (creación/modificación) | Asignación y definición en el error |
| `403` con mención a una política en un **borrado** | Política **`DenyAction`** | Asignaciones con efecto `DenyAction` |
| `DeploymentBlocked` / acceso denegado con "deny assignment" | **Pila de despliegue** (`denySettings`) o aplicación administrada | `az stack … show`, asignaciones de denegación |

## Tabla de síntomas

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `ScopeLocked` al borrar un recurso | Bloqueo en el recurso o heredado | `az lock list --resource-group <rg> -o table` y `az lock list -o table` (suscripción) | Seguir el procedimiento: quitar el bloqueo (con aprobación), borrar y, si procede, volver a ponerlo |
| `ScopeLocked` al **modificar** (no al borrar) | Bloqueo `ReadOnly` | Nivel del bloqueo (`level`) | Cambiar a `CanNotDelete` si no hace falta la solo lectura |
| No sé dónde está el bloqueo | Está en un alcance superior (grupo o suscripción) | El error lista los alcances; `az lock list` sin filtros | Quitarlo o cambiarlo en el alcance indicado |
| No puedo crear el bloqueo (`AuthorizationFailed`) | Falta `Microsoft.Authorization/locks/write` | Roles del usuario | Rol personalizado "Administrador de bloqueos" u *Owner*/*User Access Administrator* |
| Puedo borrar el recurso aunque haya bloqueo | El bloqueo está en **otro** alcance (hermano) o se borró; o es un dato (blob/fila), no un recurso | Alcance del bloqueo; qué se borró | Poner el bloqueo en el alcance correcto; proteger datos con las funciones del servicio |
| No puedo escalar / iniciar la VM / lanzar el runbook | `ReadOnly` en el grupo o el recurso | Tabla de efectos del [README](README.md#24-lo-que-se-rompe-con-los-bloqueos-leerlo-antes-de-aplicarlos) | Cambiar a `CanNotDelete` o sacar ese recurso del alcance |
| La app dejó de obtener claves de almacenamiento | `ReadOnly` bloquea *List Keys* (`POST`) | Nivel del bloqueo en la cuenta | Cambiar a `CanNotDelete`; usar Entra ID en lugar de claves |
| Los despliegues nuevos fallan en el grupo (historial) | `CanNotDelete` + más de 800 despliegues | Cantidad de despliegues del grupo | Quitar el bloqueo, limpiar el historial, separar recursos críticos |
| Las copias de seguridad fallan al eliminar puntos de restauración | `CanNotDelete` en el grupo que crea el servicio de copias | Grupo y bloqueos | Quitar el bloqueo de ese grupo; proteger la *vault* con sus protecciones propias |
| `terraform destroy` falla a medias | Bloqueo no gestionado por el código | `terraform state list`, `az lock list` | Poner el bloqueo en el código con `proteger`; `proteger = false` y aplicar antes de destruir |
| `terraform apply` falla al modificar un recurso | `ReadOnly` | Mensaje `ScopeLocked` | Quitar el `ReadOnly` o cambiar a `CanNotDelete` |
| `terraform plan` quiere recrear el bloqueo | `scope` o `name` cambiados; o el bloqueo fue borrado a mano | `az lock list` y `terraform state show` | Importar (`terraform import`) o dejar que Terraform lo recree; revisar quién lo borró (registro de actividad) |
| Falla la baja de permisos de una persona | `CanNotDelete` impide borrar asignaciones de roles | Mensaje del error al borrar la asignación | Usar grupos de Entra ID; mantener asignaciones estables |
| "Bloqueo creado pero no surte efecto" | Tarda unos segundos/minutos en propagarse | Reintentar tras un minuto | Esperar; verificar con un recurso de laboratorio |
| Superado el límite de bloqueos | Más de 20 en un alcance | Mensaje del error | Un bloqueo en el grupo en lugar de uno por recurso; consolidar |
| Quiero bloquear un grupo de administración | **No** admite bloqueos | — | Usar políticas (`DenyAction`) y RBAC en ese nivel |
| No se puede borrar el grupo gestionado de una aplicación (p. ej., Databricks) | El grupo administrado lleva un bloqueo/denegación del servicio | Propiedades de la aplicación administrada | Borrar el servicio principal; el grupo se elimina con él |
| La eliminación en cascada de un grupo falla "a medias" | Un recurso hijo con bloqueo impide **todo** el borrado del grupo | `az lock list -g <rg>` | Quitar los bloqueos y volver a intentar; el borrado del grupo es atómico |
| Alerta de "bloqueo borrado" sin nadie que lo reconozca | Borrado manual no autorizado | Registro de actividad (`Caller`, `CallerIpAddress`) | Investigar; volver a crear desde código; revisar roles |

## Comandos útiles
```bash
# Todos los bloqueos de la suscripción (y de un grupo)
az lock list -o table
az lock list --resource-group rg-modalima-prod-datos -o table

# Detalle de uno
az lock show --name lock-cannotdelete-rg-modalima-prod-datos --resource-group rg-modalima-prod-datos -o jsonc

# ¿Quién quitó o puso bloqueos esta semana?
az monitor activity-log list --offset 7d --namespace Microsoft.Authorization \
  --query "[?contains(operationName.value,'locks')].{cuando:eventTimestamp, quien:caller, op:operationName.value}" -o table

# ¿Qué permisos tengo sobre bloqueos en este grupo?
az role assignment list --assignee <mi-objectId> --scope /subscriptions/<id>/resourceGroups/<rg> -o table
```

## Secuencia recomendada
1. **Lee el código del error** (`ScopeLocked`, `AuthorizationFailed`, política): cambia todo el diagnóstico.
2. **Lista los bloqueos** de la cadena completa (recurso → grupo → suscripción) y su nivel.
3. **Decide:** ¿el bloqueo es correcto (frenar el error) o excesivo (`ReadOnly` rompiendo algo)?
4. **Si hay que borrar:** sigue el procedimiento (ticket, aprobación, quitar bloqueo, borrar, restaurar el bloqueo).
5. **Si es IaC:** pon el bloqueo en el código; usa la variable `proteger`.
6. **Si se rompió algo por `ReadOnly`:** cambia a `CanNotDelete` y registra el efecto en la guía.
7. **Revisa el registro de actividad:** quién creó o quitó el bloqueo y cuándo.
8. **Considera la segunda capa:** `DenyAction` o pila de despliegue para lo que lo necesite.
