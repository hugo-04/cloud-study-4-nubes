# Consultas de Azure Resource Graph y KQL · Landing zone

Las primeras se ejecutan en **Azure Resource Graph** (`az graph query -q "..."`); las últimas en Log Analytics. Verifica los nombres de tablas y campos en tu tenant.

**1. Suscripciones y su cadena de grupos de administración (¿alguna fuera de lugar?)**
```kusto
resourcecontainers
| where type == "microsoft.resources/subscriptions"
| extend cadena = tostring(properties.managementGroupAncestorsChain[0].name)
| project suscripcion = name, id = subscriptionId, grupoInmediato = cadena, estado = tostring(properties.state)
```

**2. Grupos de recursos sin etiqueta `owner` o `costcenter`**
```kusto
resourcecontainers
| where type == "microsoft.resources/subscriptions/resourcegroups"
| where isempty(tags.owner) or isempty(tags.costcenter)
| project subscriptionId, resourceGroup = name, tags
```

**3. Redes virtuales con espacios de direcciones (para detectar solapamientos)**
```kusto
resources
| where type == "microsoft.network/virtualnetworks"
| mv-expand espacio = properties.addressSpace.addressPrefixes
| project vnet = name, subscriptionId, espacio = tostring(espacio)
| order by espacio asc
```

**4. Peerings que no están conectados**
```kusto
resources
| where type == "microsoft.network/virtualnetworks"
| mv-expand p = properties.virtualNetworkPeerings
| where tostring(p.properties.peeringState) != "Connected"
| project vnet = name, peering = tostring(p.name), estado = tostring(p.properties.peeringState), subscriptionId
```

**5. Cuentas de almacenamiento y bases con acceso público (deberían ser cero en Corp)**
```kusto
resources
| where type in ("microsoft.storage/storageaccounts", "microsoft.sql/servers")
| where tostring(properties.publicNetworkAccess) =~ "Enabled" or tostring(properties.allowBlobPublicAccess) == "true"
| project name, type, subscriptionId, resourceGroup
```

**6. Cambios de gobierno recientes (registro de actividad en Log Analytics)**
```kusto
AzureActivity
| where TimeGenerated > ago(7d)
| where OperationNameValue has_any ("MICROSOFT.AUTHORIZATION/POLICYASSIGNMENTS", "MICROSOFT.AUTHORIZATION/LOCKS", "MICROSOFT.MANAGEMENT/MANAGEMENTGROUPS")
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, ResourceGroup
| order by TimeGenerated desc
```
