# KQL · Storage Queues

Requiere el diagnóstico del servicio de colas (`queueServices/default`) hacia Log Analytics (categorías `StorageRead`, `StorageWrite`, `StorageDelete`). Tabla: `StorageQueueLogs`. *Los nombres de columnas pueden variar: ejecuta `take 5` y ajusta. Verifica el esquema vigente.*

## 1. Operaciones por tipo y resultado
```kusto
StorageQueueLogs
| where TimeGenerated > ago(1h)
| summarize operaciones = count() by OperationName, StatusText
| order by operaciones desc
```

## 2. Errores de servidor o limitación
```kusto
StorageQueueLogs
| where TimeGenerated > ago(24h)
| where StatusText in ("ServerBusy", "ServerTimeout", "ClientThrottlingError", "OperationTimedOut")
| summarize errores = count() by bin(TimeGenerated, 15m), StatusText
| render timechart
```

## 3. Quién envía y quién procesa (identidad)
```kusto
StorageQueueLogs
| where TimeGenerated > ago(24h) and OperationName in ("PutMessage", "GetMessages", "DeleteMessage")
| extend Quien = tostring(RequesterObjectId)
| summarize operaciones = count() by OperationName, Quien
| order by operaciones desc
```

## 4. Acceso denegado (permisos o red)
```kusto
StorageQueueLogs
| where TimeGenerated > ago(24h) and StatusCode in (401, 403)
| summarize intentos = count() by CallerIpAddress, AuthenticationType, StatusText
| order by intentos desc
```

## 5. Relación enviados / borrados por hora (¿se acumula trabajo?)
```kusto
StorageQueueLogs
| where TimeGenerated > ago(24h) and OperationName in ("PutMessage", "DeleteMessage")
| summarize n = count() by OperationName, bin(TimeGenerated, 1h)
| render timechart
```
Si los `PutMessage` superan a los `DeleteMessage` durante horas, la cola crece.

## 6. Mensajes en la cola (métrica de la cuenta)
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.STORAGE" and MetricName == "QueueMessageCount"
| where TimeGenerated > ago(6h)
| summarize promedio = avg(Average) by bin(TimeGenerated, 5m)
| render timechart
```
La métrica es por servicio de colas (no por cola): para vigilar la cola de veneno individual, programa un trabajo que lea `approximateMessageCount` y lo publique como métrica propia, o usa el SDK en una alerta.

## Alertas recomendadas
| Alerta | Condición |
|---|---|
| Cola de veneno no vacía | `approximateMessageCount` > 0 en `tareas-poison` (métrica propia o Function programada) |
| Cola creciente | `QueueMessageCount` sube durante 30 min |
| Limitación | Errores `ServerBusy` / `ClientThrottlingError` |
| Acceso denegado | 401/403 repetidos |
