# Azure · Grupos de administración · Troubleshooting

Sigue el flujo: **¿qué operación falla (crear, mover, asignar, leer)? → ¿qué permisos tienes en el origen, el destino y el elemento? → ¿hay límites o validaciones (vacío, profundidad, ID)? → ¿ya pasó la caché de 30 minutos? → ¿qué heredan las políticas y roles del nuevo grupo?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| No veo ningún grupo de administración en el portal | Nunca se usaron en el tenant, o no tienes lectura | `az account management-group list` | Pedir *Management Group Reader*; en un tenant nuevo, al primer uso se crea la raíz |
| `AuthorizationFailed` al crear un grupo | Falta `Microsoft.Management/managementGroups/write` en el padre y/o está activada la autorización de creación | `az role assignment list --scope /providers/Microsoft.Management/managementGroups/<padre>` | Rol *Management Group Contributor* en el padre; o que lo cree el *pipeline* de gobierno |
| No puedo mover una suscripción | Faltan permisos en la suscripción, el origen o el destino (§2.5) | Roles en los tres lugares | Dar los permisos o pedir que lo mueva quien los tenga |
| Puedo mover solo a algunos grupos | Tu *Owner* es **heredado**: solo puedes mover a grupos donde también eres *Owner* | Origen del rol (directo o heredado) | Rol directo en la suscripción (+ *Contributor* en destino) o ayuda de plataforma |
| Error de nombre duplicado al crear | El ID es único en el directorio | `az account management-group check-name-availability` | Otro ID (el ID no se cambia después) |
| No puedo borrar un grupo | Tiene hijos o suscripciones | `az account management-group show --name <g> --expand` | Mover o borrar los hijos primero |
| No puedo crear un hijo: nivel demasiado profundo | Máximo seis niveles (sin raíz ni suscripción) | Consulta de profundidad [B2](ejemplos/kql/kql-grupos.md) | Aplanar la jerarquía |
| Tras mover una suscripción, el portal sigue mostrando el grupo anterior | Caché de ARM (hasta 30 minutos) | Esperar y refrescar; `az account management-group subscription show` | Esperar; no repetir el movimiento |
| Tras mover, la política del grupo nuevo no se evalúa | La evaluación tarda (ver ciclos de Policy) | Estado de cumplimiento y su marca de tiempo | `az policy state trigger-scan`; esperar |
| Una suscripción nueva está bajo la raíz | No hay grupo predeterminado | `az account management-group hierarchy-settings list --name <tenantId>` | Definir el grupo predeterminado; mover las existentes |
| No puedo cambiar los ajustes de la jerarquía | Falta el rol sobre la raíz (`settings/write`) | Roles en la raíz | Rol *Hierarchy Settings Administrator* sobre la raíz (puede requerir elevar acceso para concederlo) |
| Cualquiera puede crear grupos | `requireAuthorizationForGroupCreation` está desactivado | `hierarchy-settings list` | Activarlo |
| No tengo acceso a la raíz del tenant | Por defecto nadie lo tiene | Roles en `/` y en la raíz | Un administrador global eleva su acceso (*User Access Administrator*), asigna el rol y revierte |
| Un rol personalizado no aparece al asignar en un grupo | Alcance asignable con ID mal escrito (ARM no valida) o más de un grupo en `AssignableScopes` | `az role definition list --custom-role-only` | Corregir el ID; un solo grupo por rol |
| No puedo asignar un rol con acciones de datos en un grupo | Los roles con DataActions no se asignan a nivel de grupo | Definición del rol | Asignarlo en suscripción o recurso |
| Error al mover una suscripción que tiene una asignación de un rol personalizado | La suscripción sale del alcance asignable del rol | Asignaciones de ese rol en la suscripción | Quitar la asignación, ampliar el alcance o crear otro rol |
| `terraform apply` mueve suscripciones inesperadamente | La variable de suscripciones cambió, o se mezcló `subscription_ids` con la asociación | `terraform plan` | Usar solo `azurerm_management_group_subscription_association`; revisar el `plan` antes |
| Terraform quiere recrear un grupo | Se cambió el `name` (ID), que no se puede modificar | `plan` | Mantener el ID; cambiar solo `display_name` |
| Políticas heredadas que "no entiendo" | Muchas asignaciones en niveles altos | `az policy assignment list --disable-scope-strict-match` en la suscripción | Documentar por nivel; reducir la raíz |
| `MissingSubscriptionRegistration` / proveedor no registrado | `Microsoft.Management` no está registrado en el tenant/suscripción | `az provider show -n Microsoft.Management` | `az provider register -n Microsoft.Management` |
| Resource Graph no devuelve todos los grupos | Solo ve lo que tu identidad puede leer | Roles de lectura | *Management Group Reader* en la raíz intermedia |
| No puedo poner un bloqueo en un grupo | Los grupos de administración no admiten bloqueos | — | Políticas (`DenyAction`) y RBAC |
| El SDK de Java no tiene la clase que busco | El paquete de grupos de administración está solo en beta | `mvn dependency:tree` | Resource Graph + REST con el pipeline (ver [uso en Java](uso-en-java.md)) |

## Comandos útiles
```bash
# Estructura y estado
az account management-group list -o table
az account management-group show --name mg-modalima --expand --recurse -o jsonc
az account management-group hierarchy-settings list --name "$(az account show --query tenantId -o tsv)"

# ¿Dónde está esta suscripción?
az graph query -q "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | where subscriptionId == '<ID>' | project name, properties.managementGroupAncestorsChain"

# ¿Qué políticas y roles me llegan por herencia?
az policy assignment list --scope /subscriptions/<ID> --disable-scope-strict-match -o table
az role assignment list --scope /subscriptions/<ID> --include-inherited -o table

# Registrar el proveedor
az provider register --namespace Microsoft.Management
```

## Secuencia recomendada
1. **Identifica la operación** y el alcance exacto (ID del grupo, no el nombre visible).
2. **Comprueba permisos** en el elemento, el origen y el destino (§2.5 del README).
3. **Valida límites:** grupo vacío para borrar, profundidad, ID único.
4. **Respeta las ventanas:** caché de la jerarquía (30 minutos) y ciclos de evaluación de políticas.
5. **Mira la herencia** de políticas y roles del grupo nuevo antes de mover.
6. **Si es IaC:** revisa `plan` (IDs inmutables, una sola fuente de asociación).
7. **Si es la raíz:** ajustes → rol *Hierarchy Settings Administrator*; acceso → elevación con control.
8. **Si es Java:** SDK beta → Resource Graph para leer y REST para escribir.
