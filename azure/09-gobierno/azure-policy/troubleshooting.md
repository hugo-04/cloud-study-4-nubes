# Azure · Azure Policy · Troubleshooting

Sigue el flujo: **¿qué dice el error (asignación, definición, campo)? → ¿la regla se está evaluando (alcance, modo, alias)? → ¿qué efecto tiene y cuándo corre? → ¿hay exenciones o exclusiones? → ¿la identidad de la asignación tiene permisos (Modify/DINE)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `RequestDisallowedByPolicy` al desplegar | Una política `Deny` rechazó el recurso | El error trae `policyAssignmentName`, `policyDefinitionDisplayName`, `policyDefinitionReferenceId` y la evaluación del campo | Corregir la configuración (la propiedad que se indica); si es legítimo, exención con fecha |
| Error `403` al **borrar** un recurso | Política `DenyAction` o bloqueo | Mensaje del error: "policy" frente a "ScopeLocked" | Quitar la etiqueta que lo activa / pedir exención / quitar el bloqueo con control de cambios |
| La política "no hace nada" (todo conforme) | Alias incorrecto, modo `Indexed` que no evalúa ese tipo, alcance equivocado, asignación en `DoNotEnforce` o con `notScopes` | Comparar con una consulta independiente de Resource Graph; `az policy assignment show` (`enforcementMode`, `notScopes`) | Corregir alias/modo/alcance; prueba que debe fallar |
| Recurso nuevo rechazado pero uno viejo "pasa" | `Deny` solo actúa al crear/modificar | El recurso viejo aparece como no conforme en el informe | Remediación (`Modify`/DINE) o corrección manual |
| El cumplimiento no se actualiza | Ciclo de evaluación pendiente (cada 24 h; ~15 min tras crear/cambiar un recurso; unos minutos tras la asignación) | Hora del último estado (`timestamp`) | `az policy state trigger-scan` y esperar |
| Cumplimiento muestra "Not started" | La asignación aún no se evaluó | Estado de la asignación | Esperar el primer ciclo o lanzar un escaneo |
| La tarea de remediación falla (autorización) | La identidad de la asignación no tiene los roles de `roleDefinitionIds` | Asignaciones de rol de la identidad en el alcance | `azurerm_role_assignment` / `az role assignment create` para esa identidad |
| La remediación no corrige un recurso | Política `Deny` (no remedia); recurso fuera del alcance; condición no cumple; recurso con bloqueo `ReadOnly` | Resultado de la tarea (por recurso) y eventos relacionados | Usar `Modify`/DINE; quitar el bloqueo temporalmente; revisar alcance |
| Remediación "exitosa" pero sigue no conforme | Evaluación pendiente o la `existenceCondition` de DINE no coincide con lo desplegado | Esperar un ciclo; revisar `existenceCondition` | Ajustar la condición o la plantilla |
| `Modify` no cambia nada en el recurso nuevo | Falta rol, el cambio no está permitido por el tipo de recurso, o `conflictEffect` | Registro de actividad de la operación | Rol correcto, revisar `operations` y `conflictEffect` |
| `The policy assignment ... identity ... location` al crear | Asignación con `Modify`/DINE sin identidad o sin `location` | Mensaje del error | Añadir `identity` y `location` |
| Una iniciativa no deja asignar | Superaste límites (200 asignaciones por alcance, 1 000 políticas por iniciativa) o hay referencias duplicadas | Mensaje del error; recuento de asignaciones | Consolidar en iniciativas; reducir asignaciones por alcance |
| Parámetros inválidos en la iniciativa | Nombre del parámetro de la definición hija mal escrito | `az policy definition show` y `parameters` | Usar el nombre exacto (p. ej., `effect`) |
| Terraform quiere quitar etiquetas | La política `Modify` las añadió | `terraform plan` | `lifecycle { ignore_changes = [tags["x"]] }` o declararlas |
| La exención no surte efecto | Referencia equivocada de regla (`policyDefinitionReferenceId`), alcance distinto, exención vencida o asignación equivocada | `az policy exemption show` (alcance, categoría, caducidad) | Corregir referencia/alcance; recrear |
| No puedo crear exenciones | Falta `Microsoft.Authorization/policyExemptions/write` o la acción `exempt` sobre la asignación | Roles del solicitante | Rol personalizado; que lo haga el equipo de gobierno |
| Una política de Kubernetes rechaza pods del sistema | Se aplica a todos los espacios de nombres | Eventos del `Deployment`/`ReplicaSet` (admission webhook) | Excluir `kube-system` y los de infraestructura |
| El complemento de Policy para AKS no evalúa | Complemento no habilitado, pods de Gatekeeper caídos, clúster sin acceso saliente | `az aks show` (`addonProfiles.azurepolicy`), pods `gatekeeper-system` | Habilitar complemento; revisar red/egreso |
| DINE no despliega nada | Se evalúa **tras** el éxito del proveedor; retraso de evaluación; plantilla/parámetros inválidos; sin permisos | Despliegues en el alcance con prefijo `PolicyDeployment_` | Revisar plantilla/identidad; lanzar remediación |
| Costos extra tras activar DINE | Diagnósticos hacia Log Analytics con todas las categorías | Costos por recurso; tabla `Usage` | Parámetros de categorías, tablas de bajo costo, retención |
| El despliegue pasa en el portal y falla en el *pipeline* | La identidad del *pipeline* y la del usuario tienen distintas condiciones (o el portal agrega etiquetas) | Comparar la solicitud | Hacer que la plantilla cumpla por sí sola |
| `AuthorizationFailed` al leer el cumplimiento | Falta *Reader* en el alcance o el recurso `Microsoft.PolicyInsights` no está registrado | `az provider show -n Microsoft.PolicyInsights` | Registrar el proveedor; dar *Reader*/*Security Reader* |

## Comandos útiles
```bash
# ¿Qué asignaciones afectan a esta suscripción? (incluye heredadas)
az policy assignment list --disable-scope-strict-match -o table
# Detalle de una asignación (modo, exclusiones, parámetros, identidad)
az policy assignment show --name modalima-guardarrailes --query "{modo:enforcementMode, noScopes:notScopes, params:parameters, identidad:identity}"
# Evaluación bajo demanda y estado
az policy state trigger-scan --no-wait
az policy state list --filter "complianceState eq 'NonCompliant'" --top 20 -o table
# Eventos de política de un recurso
az policy event list --filter "resourceId eq '<ID_DEL_RECURSO>'" -o table
```

## Secuencia recomendada
1. **Lee el error completo:** asignación, definición, `policyDefinitionReferenceId`, campo evaluado.
2. **Comprueba el alcance y el modo de aplicación** de la asignación, y exclusiones o exenciones.
3. **Revisa la regla:** alias, modo (`All`/`Indexed`), condiciones y efecto.
4. **Compara con la realidad** (Resource Graph) para detectar reglas que "no hacen nada".
5. **Si es `Modify`/DINE:** identidad, roles, `roleDefinitionIds`, tarea de remediación y despliegues `PolicyDeployment_*`.
6. **Si es un problema de tiempo:** lanza una evaluación y espera (24 h, ~15 min, unos minutos).
7. **Si es IaC:** `ignore_changes`, orden de despliegue y *drift*.
8. **Si es Kubernetes:** complemento, Gatekeeper, espacios de nombres excluidos.
