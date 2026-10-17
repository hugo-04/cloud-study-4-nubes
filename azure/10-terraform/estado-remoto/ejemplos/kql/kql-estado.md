# KQL · Auditoría del estado de Terraform

Requisito: el diagnóstico de la cuenta de estado envía `StorageRead`, `StorageWrite` y `StorageDelete` a Log Analytics (el Terraform de [`../terraform/main.tf`](../terraform/main.tf) lo crea si indicas `workspace_log_analytics_id`). Los registros tardan unos minutos en aparecer.

> Los nombres de columna y de operación pueden variar según la versión del esquema de la tabla `StorageBlobLogs`: **compruébalos en tu espacio de trabajo** (`StorageBlobLogs | take 5`) antes de crear alertas.

## A1 · ¿Quién lee o escribe el estado? (últimos 7 días)
```kusto
StorageBlobLogs
| where TimeGenerated > ago(7d)
| where Uri has ".tfstate"
| summarize operaciones = count(), ultima = max(TimeGenerated)
          by Identidad = RequesterObjectId, OperationName, IP = CallerIpAddress
| order by ultima desc
```

## A2 · Borrados de estados (esto casi nunca debe aparecer)
```kusto
StorageBlobLogs
| where TimeGenerated > ago(30d)
| where OperationName in ("DeleteBlob", "DeleteContainer")
| project TimeGenerated, OperationName, Uri, Identidad = RequesterObjectId, IP = CallerIpAddress, StatusCode
| order by TimeGenerated desc
```

## A3 · Bloqueos rotos a la fuerza
```kusto
StorageBlobLogs
| where TimeGenerated > ago(30d)
| where OperationName == "BreakBlobLease" and Uri has ".tfstate"
| project TimeGenerated, Uri, Identidad = RequesterObjectId, IP = CallerIpAddress, StatusCode
| order by TimeGenerated desc
```

## A4 · Accesos que NO son con Entra ID (claves, SAS o anónimos)
Con `shared_access_key_enabled = false` no deberían existir; si aparecen intentos, alguien lo está probando.
```kusto
StorageBlobLogs
| where TimeGenerated > ago(7d)
| where AuthenticationType != "OAuth"
| summarize intentos = count() by AuthenticationType, StatusCode, IP = CallerIpAddress
| order by intentos desc
```

## A5 · Conflictos de bloqueo (409): dos ejecuciones a la vez
```kusto
StorageBlobLogs
| where TimeGenerated > ago(7d)
| where Uri has ".tfstate" and StatusCode == 409
| summarize conflictos = count() by bin(TimeGenerated, 1h), Uri
| order by TimeGenerated desc
```

## A6 · Accesos denegados (403): permisos o firewall
```kusto
StorageBlobLogs
| where TimeGenerated > ago(7d)
| where Uri has ".tfstate" and StatusCode == 403
| summarize denegados = count() by Identidad = RequesterObjectId, StatusText, IP = CallerIpAddress
| order by denegados desc
```
