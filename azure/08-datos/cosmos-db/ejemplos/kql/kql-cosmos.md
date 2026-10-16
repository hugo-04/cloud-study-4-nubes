# KQL · Azure Cosmos DB (API para NoSQL)

Requiere el diagnóstico de la cuenta hacia Log Analytics con `log_analytics_destination_type = "Dedicated"` / `--export-to-resource-specific true` (tablas `CDBDataPlaneRequests`, `CDBPartitionKeyRUConsumption`, `CDBQueryRuntimeStatistics`, `CDBPartitionKeyStatistics`, `CDBControlPlaneRequests`). *Los nombres de columnas pueden variar: ejecuta `take 5` y ajusta. Verifica el esquema vigente.*

## 1. Solicitudes limitadas (429) por contenedor y operación
```kusto
CDBDataPlaneRequests
| where TimeGenerated > ago(1h) and StatusCode == 429
| summarize limitadas = count() by DatabaseName, CollectionName, OperationName, bin(TimeGenerated, 5m)
| order by TimeGenerated desc, limitadas desc
```

## 2. Operaciones que más RU consumen
```kusto
CDBDataPlaneRequests
| where TimeGenerated > ago(24h)
| summarize ru_total = sum(RequestCharge), solicitudes = count(), ru_promedio = avg(RequestCharge)
    by CollectionName, OperationName
| order by ru_total desc
| take 20
```

## 3. ¿Hay una partición caliente? RU por clave de partición
```kusto
CDBPartitionKeyRUConsumption
| where TimeGenerated > ago(1h)
| summarize ru = sum(RequestCharge) by CollectionName, PartitionKey, PartitionKeyRangeId
| order by ru desc
| take 20
```
Si pocas claves concentran casi todas las RU, la clave de partición reparte mal.

## 4. Particiones lógicas más grandes (cerca del límite de 20 GB)
```kusto
CDBPartitionKeyStatistics
| where TimeGenerated > ago(1d)
| summarize tamano_gb = max(SizeKb) / 1024.0 / 1024.0 by CollectionName, PartitionKey
| where tamano_gb > 5
| order by tamano_gb desc
```

## 5. Consultas caras
```kusto
CDBQueryRuntimeStatistics
| where TimeGenerated > ago(24h)
| summarize veces = count() by QueryText, DatabaseName, CollectionName
| order by veces desc
| take 20
```
Cruza el `ActivityId` con `CDBDataPlaneRequests` para ver RU y duración por ejecución:
```kusto
CDBDataPlaneRequests
| where TimeGenerated > ago(6h) and OperationName == "Query" and RequestCharge > 100
| project TimeGenerated, CollectionName, RequestCharge, DurationMs, ActivityId, ClientIpAddress, UserAgent
| order by RequestCharge desc
| take 30
```

## 6. Latencia por operación (percentiles)
```kusto
CDBDataPlaneRequests
| where TimeGenerated > ago(1h)
| summarize p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99)
    by OperationName
| order by p99 desc
```

## 7. Errores de autenticación y autorización (401/403)
```kusto
CDBDataPlaneRequests
| where TimeGenerated > ago(24h) and StatusCode in (401, 403)
| summarize veces = count() by StatusCode, ClientIpAddress, UserAgent, OperationName
| order by veces desc
```
403 con identidades nuevas suele ser **falta de rol de datos** (no basta ser *Contributor* de Azure).

## 8. Conflictos de concurrencia (412) y duplicados (409)
```kusto
CDBDataPlaneRequests
| where TimeGenerated > ago(24h) and StatusCode in (409, 412)
| summarize veces = count() by StatusCode, CollectionName, OperationName
```

## 9. Cambios de configuración (plano de control)
```kusto
CDBControlPlaneRequests
| where TimeGenerated > ago(7d)
| project TimeGenerated, OperationName, Caller, ResourceGroup, Level, ResultDescription
| order by TimeGenerated desc
```

## 10. Alerta sugerida (consulta para una regla de registros)
```kusto
CDBDataPlaneRequests
| where TimeGenerated > ago(15m) and StatusCode == 429
| summarize limitadas = count() by bin(TimeGenerated, 5m)
| where limitadas > 100
```
