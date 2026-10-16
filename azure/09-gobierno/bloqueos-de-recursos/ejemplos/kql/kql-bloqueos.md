# KQL y Resource Graph · Bloqueos de recursos

Los bloqueos son recursos de **plano de control** (`Microsoft.Authorization/locks`). Quedan registrados en el **registro de actividad** de la suscripción; para consultarlos con KQL, envía el registro de actividad a un workspace de Log Analytics (configuración de diagnóstico de la suscripción, categoría *Administrative*).

> Las tablas y columnas pueden cambiar: prueba cada consulta en tu workspace antes de convertirla en alerta.

## A · Registro de actividad (tabla `AzureActivity`)

### A1 · ¿Quién creó o modificó bloqueos en los últimos 30 días?
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue =~ "MICROSOFT.AUTHORIZATION/LOCKS/WRITE"
| where ActivityStatusValue in ("Success", "Succeeded")
| project TimeGenerated, Caller, ResourceGroup, _ResourceId, Properties
| order by TimeGenerated desc
```

### A2 · ¿Quién BORRÓ bloqueos? (lo importante: es el paso previo a un borrado)
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue =~ "MICROSOFT.AUTHORIZATION/LOCKS/DELETE"
| where ActivityStatusValue in ("Success", "Succeeded")
| project TimeGenerated, Caller, CallerIpAddress, ResourceGroup, _ResourceId
| order by TimeGenerated desc
```

### A3 · Intentos de borrar algo bloqueado (errores `ScopeLocked`)
```kusto
AzureActivity
| where TimeGenerated > ago(7d)
| where ActivityStatusValue in ("Failure", "Failed")
| where Properties has "ScopeLocked"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, _ResourceId
| order by TimeGenerated desc
```

### A4 · "Quitar bloqueo y borrar" en menos de 1 hora (patrón sospechoso)
```kusto
let quitados = AzureActivity
    | where TimeGenerated > ago(7d)
    | where OperationNameValue =~ "MICROSOFT.AUTHORIZATION/LOCKS/DELETE"
    | where ActivityStatusValue in ("Success", "Succeeded")
    | project QuitadoEn = TimeGenerated, Caller, ResourceGroup;
let borrados = AzureActivity
    | where TimeGenerated > ago(7d)
    | where OperationNameValue endswith "/DELETE" and OperationNameValue !has "AUTHORIZATION/LOCKS"
    | where ActivityStatusValue in ("Success", "Succeeded")
    | project BorradoEn = TimeGenerated, Caller, ResourceGroup, Operacion = OperationNameValue, _ResourceId;
quitados
| join kind=inner borrados on Caller, ResourceGroup
| where BorradoEn between (QuitadoEn .. (QuitadoEn + 1h))
| project QuitadoEn, BorradoEn, Caller, ResourceGroup, Operacion, _ResourceId
| order by BorradoEn desc
```

### A5 · Volumen diario de cambios de bloqueos (para ver ráfagas)
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue has "AUTHORIZATION/LOCKS"
| summarize operaciones = count() by bin(TimeGenerated, 1d), OperationNameValue
| render timechart
```

## B · Resource Graph (consulta de inventario)

### B1 · Grupos de recursos de producción (para comparar con `az lock list`)
```kusto
resourcecontainers
| where type == "microsoft.resources/subscriptions/resourcegroups"
| where tags["env"] =~ "prod"
| project subscriptionId, resourceGroup = name, owner = tostring(tags["owner"])
| order by subscriptionId asc, resourceGroup asc
```

### B2 · Recursos de producción sin las etiquetas que activan la política `DenyAction`
```kusto
resources
| where isnull(tags["env"]) or tags["env"] == ""
| summarize recursos = count() by subscriptionId, resourceGroup, type
| order by recursos desc
| take 50
```

### B3 · Tipos de recursos críticos que deberían estar bajo un grupo bloqueado
```kusto
resources
| where type in~ (
    "microsoft.keyvault/vaults",
    "microsoft.sql/servers",
    "microsoft.documentdb/databaseaccounts",
    "microsoft.network/privatednszones",
    "microsoft.operationalinsights/workspaces")
| project subscriptionId, resourceGroup, name, type, env = tostring(tags["env"])
| order by resourceGroup asc
```

## C · Alerta recomendada
Crea una alerta del registro de actividad (ver [Terraform](../terraform/main.tf)) con `operationName = Microsoft.Authorization/locks/delete`, o una alerta de consulta de registros con **A2** cada 5 minutos y umbral `> 0`.
