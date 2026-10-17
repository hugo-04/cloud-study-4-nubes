# Consultas de Azure Resource Graph · Lo que Terraform administra (y lo que no)

Se ejecutan en **Azure Resource Graph** (portal › *Resource Graph Explorer*, o `az graph query -q "..."`). Usan el lenguaje Kusto, pero **no** son Log Analytics: las tablas son `resources`, `resourcecontainers`, etc.

## 1. Recursos que NO están etiquetados como gestionados por Terraform
```kusto
resources
| where isnull(tags['gestionado']) or tags['gestionado'] != 'terraform'
| summarize cantidad = count() by type, subscriptionId
| order by cantidad desc
```

## 2. Recursos sin dueño
```kusto
resources
| where isnull(tags['dueno']) or tags['dueno'] == ''
| project nombre = name, tipo = type, grupo = resourceGroup, suscripcion = subscriptionId
```

## 3. Cuentas de almacenamiento que aún permiten claves o acceso público a blobs
```kusto
resources
| where type =~ 'microsoft.storage/storageaccounts'
| extend claves = tostring(properties.allowSharedKeyAccess), publico = tostring(properties.allowBlobPublicAccess), tls = tostring(properties.minimumTlsVersion)
| where claves != 'false' or publico != 'false' or tls != 'TLS1_2'
| project nombre = name, grupo = resourceGroup, claves, publico, tls, etiqueta = tostring(tags['gestionado'])
```

## 4. Grupos de recursos huérfanos (vacíos) con etiqueta de Terraform
```kusto
resourcecontainers
| where type == 'microsoft.resources/subscriptions/resourcegroups' and tags['gestionado'] == 'terraform'
| project grupo = name, suscripcion = subscriptionId
| join kind=leftanti (resources | summarize n = count() by grupo = resourceGroup, suscripcion = subscriptionId) on grupo, suscripcion
```

## 5. Distribución por entorno y aplicación
```kusto
resources
| where tags['gestionado'] == 'terraform'
| summarize recursos = count() by entorno = tostring(tags['entorno']), aplicacion = tostring(tags['aplicacion'])
| order by entorno asc, recursos desc
```

> Nombres de propiedades como `allowSharedKeyAccess` pueden variar con la versión de la API: **verifica** con `resources | where type =~ '...' | take 1` y revisa las propiedades reales.
