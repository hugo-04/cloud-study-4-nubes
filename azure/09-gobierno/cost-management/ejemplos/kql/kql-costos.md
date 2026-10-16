# KQL y Resource Graph · Cost Management

El **costo** se consulta con la API de Cost Management (ver [JSON](../json/) y [Java](../../uso-en-java.md)); **Resource Graph** sirve para el **inventario que explica el costo**: recursos sin dueño, huérfanos y etiquetas. Prueba cada consulta antes de automatizarla: las propiedades pueden cambiar.

## A · Etiquetas (sin etiqueta no hay reparto de costos)

### A1 · Recursos sin alguna etiqueta obligatoria, por suscripción y grupo
```kusto
resources
| where isnull(tags['owner']) or tags['owner'] == ''
     or isnull(tags['env']) or tags['env'] == ''
     or isnull(tags['cost-center']) or tags['cost-center'] == ''
| summarize recursos = count() by subscriptionId, resourceGroup
| order by recursos desc
| take 100
```

### A2 · Cobertura de cada etiqueta (porcentaje de recursos que la tienen)
```kusto
resources
| summarize total = count(),
            conOwner = countif(isnotempty(tags['owner'])),
            conEnv = countif(isnotempty(tags['env'])),
            conCostCenter = countif(isnotempty(tags['cost-center']))
| extend pctOwner = round(100.0 * conOwner / total, 1),
         pctEnv = round(100.0 * conEnv / total, 1),
         pctCostCenter = round(100.0 * conCostCenter / total, 1)
```

### A3 · Valores de `env` fuera de lo permitido (typos que rompen los presupuestos filtrados por etiqueta)
```kusto
resources
| where isnotempty(tags['env'])
| where tostring(tags['env']) !in~ ('prod', 'staging', 'dev', 'sandbox')
| summarize recursos = count() by valor = tostring(tags['env'])
| order by recursos desc
```

### A4 · Recursos por dueño y tipo (para el informe mensual por equipo)
```kusto
resources
| extend owner = tostring(tags['owner'])
| summarize recursos = count() by owner, type
| order by owner asc, recursos desc
```

## B · Recursos huérfanos (gastan sin servir)

### B1 · Discos sin conectar
```kusto
resources
| where type =~ 'microsoft.compute/disks'
| where tostring(properties.diskState) =~ 'Unattached'
| project name, resourceGroup, subscriptionId, sku = tostring(sku.name), tamanoGB = toint(properties.diskSizeGB), location
| order by tamanoGB desc
```

### B2 · IP públicas sin asociar
```kusto
resources
| where type =~ 'microsoft.network/publicipaddresses'
| where isnull(properties.ipConfiguration) and isnull(properties.natGateway)
| project name, resourceGroup, subscriptionId, sku = tostring(sku.name), location
```

### B3 · Interfaces de red sin máquina ni Private Endpoint
```kusto
resources
| where type =~ 'microsoft.network/networkinterfaces'
| where isnull(properties.virtualMachine) and isnull(properties.privateEndpoint)
| project name, resourceGroup, subscriptionId, location
```

### B4 · Planes de App Service sin aplicaciones
```kusto
resources
| where type =~ 'microsoft.web/serverfarms'
| where toint(properties.numberOfSites) == 0
| project name, resourceGroup, subscriptionId, sku = tostring(sku.name), location
```

## C · Candidatos a ahorro en entornos no productivos

### C1 · Máquinas virtuales de Dev/Sandbox sin la etiqueta de auto-apagado
```kusto
resources
| where type =~ 'microsoft.compute/virtualmachines'
| where tostring(tags['env']) in~ ('dev', 'sandbox')
| where isempty(tags['auto-apagar'])
| project name, resourceGroup, subscriptionId, tamano = tostring(properties.hardwareProfile.vmSize), env = tostring(tags['env'])
```

### C2 · Recursos de Sandbox con más de 30 días (revisar si siguen haciendo falta)
```kusto
resources
| where tostring(tags['env']) =~ 'sandbox'
| where todatetime(properties.timeCreated) < ago(30d)
| project name, type, resourceGroup, subscriptionId, creado = todatetime(properties.timeCreated)
| order by creado asc
| take 100
```
> `properties.timeCreated` no existe en todos los tipos de recursos: úsala solo donde esté disponible.

## D · Registro de actividad (Log Analytics)

### D1 · Cambios de presupuestos en los últimos 30 días (¿quién subió o borró un presupuesto?)
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue in~ ("MICROSOFT.CONSUMPTION/BUDGETS/WRITE", "MICROSOFT.CONSUMPTION/BUDGETS/DELETE")
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, _ResourceId
| order by TimeGenerated desc
```

### D2 · Cambios de exportaciones y acciones programadas
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue startswith "MICROSOFT.COSTMANAGEMENT/"
| where OperationNameValue has_any ("WRITE", "DELETE")
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, _ResourceId
| order by TimeGenerated desc
```
