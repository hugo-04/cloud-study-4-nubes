# Azure Policy · Consultas (Resource Graph y Log Analytics)

Dos lenguajes parecidos pero **no idénticos**:
- **Azure Resource Graph** (portal → *Resource Graph Explorer*, o `az graph query`): inventario y cumplimiento actual de **toda la organización** en segundos. Tablas: `resources`, `resourcecontainers`, `policyresources`.
- **Log Analytics** (KQL sobre `AzureActivity`): **historial** de rechazos y cambios (requiere enviar el registro de actividad a un workspace).

*Las tablas y propiedades pueden variar; ajusta con el Explorer si una consulta no devuelve nada.*

## A. Resource Graph · cumplimiento

### A1. No conformes por política
```kusto
policyresources
| where type == 'microsoft.policyinsights/policystates'
| where properties.complianceState == 'NonCompliant'
| summarize recursos = count() by politica = tostring(properties.policyDefinitionName), asignacion = tostring(properties.policyAssignmentName)
| order by recursos desc
```

### A2. No conformes por suscripción (con nombre)
```kusto
policyresources
| where type == 'microsoft.policyinsights/policystates'
| where properties.complianceState == 'NonCompliant'
| summarize noConformes = count() by subscriptionId
| join kind=leftouter (
    resourcecontainers
    | where type == 'microsoft.resources/subscriptions'
    | project subscriptionId, suscripcion = name
  ) on subscriptionId
| project suscripcion, noConformes
| order by noConformes desc
```

### A3. Qué recursos concretos incumplen una regla
```kusto
policyresources
| where type == 'microsoft.policyinsights/policystates'
| where properties.complianceState == 'NonCompliant'
| where tostring(properties.policyDefinitionReferenceId) == 'net03-storage-sin-acceso-publ'
| project recurso = tostring(properties.resourceId), grupo = tostring(properties.resourceGroup), dueno = tostring(properties.resourceTags)
```

### A4. Exenciones que vencen en los próximos 30 días (o ya vencidas)
```kusto
policyresources
| where type == 'microsoft.authorization/policyexemptions'
| extend expira = todatetime(properties.expiresOn), categoria = tostring(properties.exemptionCategory)
| where isnotnull(expira) and expira < now() + 30d
| project name, categoria, expira, alcance = tostring(properties.policyAssignmentId)
| order by expira asc
```

### A5. Exenciones **sin** fecha de caducidad (mala práctica)
```kusto
policyresources
| where type == 'microsoft.authorization/policyexemptions'
| where isnull(todatetime(properties.expiresOn))
| project name, alcance = id
```

### A6. Asignaciones en modo "no aplicar" (DoNotEnforce)
```kusto
policyresources
| where type == 'microsoft.authorization/policyassignments'
| where tostring(properties.enforcementMode) == 'DoNotEnforce'
| project nombre = name, alcance = tostring(properties.scope), mostrar = tostring(properties.displayName)
```

## B. Resource Graph · inventario que respalda las reglas NET-xx

### B1. NET-02/03 · IP públicas y su asociación
```kusto
resources
| where type =~ 'microsoft.network/publicipaddresses'
| project name, resourceGroup, ip = tostring(properties.ipAddress), asociadaA = tostring(properties.ipConfiguration.id)
| order by isempty(asociadaA) desc
```

### B2. NET-03 · Storage con acceso público de red
```kusto
resources
| where type =~ 'microsoft.storage/storageaccounts'
| where tostring(properties.publicNetworkAccess) != 'Disabled'
| project name, resourceGroup, acceso = tostring(properties.publicNetworkAccess), reglasDefault = tostring(properties.networkAcls.defaultAction)
```

### B3. NET-03 · Key Vault, Service Bus, Cosmos, SQL con acceso público (una sola consulta)
```kusto
resources
| where type in~ ('microsoft.keyvault/vaults', 'microsoft.servicebus/namespaces', 'microsoft.documentdb/databaseaccounts', 'microsoft.sql/servers', 'microsoft.eventhub/namespaces')
| extend acceso = tostring(properties.publicNetworkAccess)
| where acceso != 'Disabled'
| project type, name, resourceGroup, acceso
| order by type asc
```

### B4. NET-04 · Zonas DNS privadas sin ningún enlace a una red virtual
```kusto
resources
| where type =~ 'microsoft.network/privatednszones'
| project zona = name, id
| join kind=leftouter (
    resources
    | where type =~ 'microsoft.network/privatednszones/virtualnetworklinks'
    | extend zona = tostring(split(id, '/')[8])
    | summarize enlaces = count() by zona
  ) on zona
| where isnull(enlaces) or enlaces == 0
```

### B5. NET-10 · NSG con administración abierta a Internet
```kusto
resources
| where type =~ 'microsoft.network/networksecuritygroups'
| mv-expand regla = properties.securityRules
| where tostring(regla.properties.access) =~ 'Allow' and tostring(regla.properties.direction) =~ 'Inbound'
| where tostring(regla.properties.sourceAddressPrefix) in~ ('*', 'Internet', '0.0.0.0/0')
| where tostring(regla.properties.destinationPortRange) in ('22', '3389', '*')
| project nsg = name, resourceGroup, regla = tostring(regla.name), puerto = tostring(regla.properties.destinationPortRange)
```

### B6. NET-12 · Recursos sin etiqueta `owner`
```kusto
resources
| where isnull(tags['owner']) or tostring(tags['owner']) == ''
| summarize recursos = count() by type
| order by recursos desc
```

## C. Log Analytics · rechazos y cambios (requiere el registro de actividad en un workspace)

### C1. Solicitudes rechazadas por una política (Deny) en los últimos 7 días
```kusto
AzureActivity
| where TimeGenerated > ago(7d)
| where CategoryValue == 'Policy'
| where OperationNameValue has 'DENY'
| project TimeGenerated, Caller, ResourceId, Properties
| order by TimeGenerated desc
```

### C2. Despliegues fallidos por `RequestDisallowedByPolicy`
```kusto
AzureActivity
| where TimeGenerated > ago(7d)
| where ActivityStatusValue == 'Failure'
| where Properties has 'RequestDisallowedByPolicy'
| project TimeGenerated, Caller, ResourceGroup, ResourceProviderValue, Properties
| order by TimeGenerated desc
```

### C3. Quién cambió o borró asignaciones y exenciones
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where OperationNameValue has_any ('POLICYASSIGNMENTS/WRITE', 'POLICYASSIGNMENTS/DELETE', 'POLICYEXEMPTIONS/WRITE', 'POLICYEXEMPTIONS/DELETE')
| where ActivityStatusValue == 'Success'
| project TimeGenerated, Caller, OperationNameValue, ResourceId
| order by TimeGenerated desc
```

### C4. Quién más "choca" con las reglas (para ofrecer formación o ajustar la política)
```kusto
AzureActivity
| where TimeGenerated > ago(30d)
| where CategoryValue == 'Policy' and OperationNameValue has 'DENY'
| summarize rechazos = count() by Caller
| top 10 by rechazos desc
```

## Cómo leer los resultados
- **A1–A3:** priorizan el trabajo de corrección (qué política y qué equipo).
- **A4–A6:** salud del programa de gobierno (excepciones vencidas, reglas aún sin aplicar).
- **B:** pruebas independientes de que la política hace lo que dice (si B2 devuelve filas con la regla en `Deny`, algo no está bien: exenciones, `notScopes` o alias incorrecto).
- **C:** historial para auditoría y para detectar quién necesita ayuda.
