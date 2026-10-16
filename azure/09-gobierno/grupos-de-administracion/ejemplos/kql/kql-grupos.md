# KQL y Resource Graph · Grupos de administración

Las consultas usan la tabla `resourcecontainers` de Resource Graph (grupos, suscripciones y grupos de recursos). Para acotar a un grupo, ejecútalas con ese **alcance** (en el portal: *Scope* → grupo; en la CLI/SDK: `managementGroups`).

> Resource Graph solo muestra lo que tu identidad puede leer. Las tablas y propiedades pueden cambiar: prueba cada consulta antes de automatizarla.

## A · Inventario de la jerarquía

### A1 · Cantidad de suscripciones por grupo (consulta de la documentación)
```kusto
resourcecontainers
| where type =~ 'microsoft.management/managementgroups'
| project mgname = name
| join kind=leftouter (
    resourcecontainers
    | where type =~ 'microsoft.resources/subscriptions'
    | extend mgParent = properties.managementGroupAncestorsChain
    | project id, mgname = tostring(mgParent[0].name)
  ) on mgname
| summarize suscripciones = countif(isnotempty(id)) by mgname
| order by mgname asc
```

### A2 · Cadena de ancestros de cada grupo (para dibujar el árbol)
```kusto
resourcecontainers
| where type =~ 'microsoft.management/managementgroups'
| extend ancestros = properties.details.managementGroupAncestorsChain
| mv-expand with_itemindex=nivel ancestros
| project grupo = name, nombreVisible = tostring(properties.displayName), nivel, ancestro = tostring(ancestros.name)
| order by grupo asc, nivel asc
```

### A3 · Cadena de grupos de cada suscripción
```kusto
resourcecontainers
| where type =~ 'microsoft.resources/subscriptions'
| extend cadena = properties.managementGroupAncestorsChain
| mv-expand with_itemindex=nivel cadena
| project subscriptionId, suscripcion = name, nivel, grupo = tostring(cadena.name)
| order by suscripcion asc, nivel asc
```

### A4 · Suscripciones de un grupo concreto (ejecútala con ese grupo como alcance)
```kusto
resourcecontainers
| where type =~ 'microsoft.resources/subscriptions'
| project subscriptionId, suscripcion = name, estado = tostring(properties.state)
```

## B · Controles de higiene

### B1 · Suscripciones que cuelgan directamente de la raíz del tenant (anti-patrón)
```kusto
resourcecontainers
| where type =~ 'microsoft.resources/subscriptions'
| extend cadena = properties.managementGroupAncestorsChain
| where array_length(cadena) == 1 and tostring(cadena[0].name) == tostring(tenantId)
| project subscriptionId, suscripcion = name, estado = tostring(properties.state)
```
> Si tu consulta no devuelve filas, comprueba que el ID de la raíz (el del tenant) sea el que aparece en la cadena; en algunos tenants la raíz se muestra con su nombre visible.

### B2 · Profundidad de cada grupo (alerta si pasa de 4)
```kusto
resourcecontainers
| where type =~ 'microsoft.management/managementgroups'
| extend profundidad = array_length(properties.details.managementGroupAncestorsChain)
| project grupo = name, nombreVisible = tostring(properties.displayName), profundidad
| where profundidad > 4
| order by profundidad desc
```

### B3 · Grupos sin ningún hijo directo (candidatos a borrar)
```kusto
let padres = resourcecontainers
    | where type =~ 'microsoft.management/managementgroups'
    | extend padre = tostring(properties.details.parent.name)
    | summarize hijosGrupo = count() by padre;
let suscripcionesPorGrupo = resourcecontainers
    | where type =~ 'microsoft.resources/subscriptions'
    | extend grupo = tostring(properties.managementGroupAncestorsChain[0].name)
    | summarize hijosSuscripcion = count() by grupo;
resourcecontainers
| where type =~ 'microsoft.management/managementgroups'
| project grupo = name, nombreVisible = tostring(properties.displayName)
| join kind=leftouter padres on $left.grupo == $right.padre
| join kind=leftouter suscripcionesPorGrupo on $left.grupo == $right.grupo
| where isnull(hijosGrupo) and isnull(hijosSuscripcion)
| project grupo, nombreVisible
```

### B4 · Suscripciones deshabilitadas o en advertencia (para pasarlas a "desmantelado")
```kusto
resourcecontainers
| where type =~ 'microsoft.resources/subscriptions'
| where tostring(properties.state) in~ ('Disabled', 'Warned', 'PastDue')
| extend grupo = tostring(properties.managementGroupAncestorsChain[0].name)
| project subscriptionId, suscripcion = name, estado = tostring(properties.state), grupo
```

## C · Seguridad por grupo

### C1 · Puntuación de seguridad por grupo (consulta de la documentación)
```kusto
securityresources
| where type == 'microsoft.security/securescores'
| project subscriptionId,
    subscriptionTotal = iff(properties.score.max == 0, 0.00, round(tolong(properties.weight) * todouble(properties.score.current) / tolong(properties.score.max), 2)),
    weight = tolong(iff(properties.weight == 0, 1, properties.weight))
| join kind=leftouter (
    resourcecontainers
    | where type == 'microsoft.resources/subscriptions' and properties.state == 'Enabled'
    | project subscriptionId, mgChain = properties.managementGroupAncestorsChain
  ) on subscriptionId
| mv-expand mg = mgChain
| summarize sumSubs = sum(subscriptionTotal), sumWeight = sum(weight), resultsNum = count() by tostring(mg.displayName), mgId = tostring(mg.name)
| extend secureScore = iff(tolong(resultsNum) == 0, 404.00, round(sumSubs / sumWeight * 100, 2))
| project mgName = mg_displayName, mgId, sumSubs, sumWeight, resultsNum, secureScore
| order by mgName asc
```

## D · Registro de actividad (Log Analytics)

Si enviaste el registro de actividad de un grupo a Log Analytics (configuración de diagnóstico por REST), puedes ver quién cambió la jerarquía. Las tablas y los nombres de operación pueden variar: confírmalos con una consulta abierta.

### D1 · Operaciones sobre grupos de administración en los últimos 30 días
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue startswith "MICROSOFT.MANAGEMENT/MANAGEMENTGROUPS"
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, _ResourceId
| order by TimeGenerated desc
```

### D2 · Cambios de asignaciones de políticas y roles hechos en el grupo
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue in~ ("MICROSOFT.AUTHORIZATION/POLICYASSIGNMENTS/WRITE", "MICROSOFT.AUTHORIZATION/POLICYASSIGNMENTS/DELETE",
                                "MICROSOFT.AUTHORIZATION/ROLEASSIGNMENTS/WRITE", "MICROSOFT.AUTHORIZATION/ROLEASSIGNMENTS/DELETE")
| where _ResourceId contains "/providers/Microsoft.Management/managementGroups/"
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, _ResourceId
| order by TimeGenerated desc
```
