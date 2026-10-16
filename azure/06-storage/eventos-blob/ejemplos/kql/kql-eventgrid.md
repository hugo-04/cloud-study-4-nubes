# KQL · Eventos de Blob (Event Grid)

Requiere diagnóstico del tópico del sistema hacia Log Analytics (categorías `DeliveryFailures`, `PublishFailures` y `DataPlaneRequests`). Los nombres de columnas pueden variar: si una consulta falla, ejecuta primero `AegDeliveryFailureLogs | take 5` y ajusta. *Verifica el esquema vigente en la doc oficial.*

## 1. Fallos de entrega recientes
```kusto
AegDeliveryFailureLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, EventSubscriptionName, Message
| order by TimeGenerated desc
| take 100
```

## 2. Fallos de entrega por suscripción y causa
```kusto
AegDeliveryFailureLogs
| where TimeGenerated > ago(24h)
| summarize fallos = count() by EventSubscriptionName, Message
| order by fallos desc
```

## 3. Fallos al publicar (la cuenta no pudo entregar al tópico)
```kusto
AegPublishFailureLogs
| where TimeGenerated > ago(24h)
| take 50
```

## 4. Tendencia de fallos por hora
```kusto
AegDeliveryFailureLogs
| where TimeGenerated > ago(3d)
| summarize fallos = count() by bin(TimeGenerated, 1h), EventSubscriptionName
| render timechart
```

## 5. Quién borra blobs (complemento: registros de Storage)
```kusto
StorageBlobLogs
| where TimeGenerated > ago(24h) and OperationName == "DeleteBlob"
| summarize borrados = count() by CallerIpAddress, AuthenticationType, UserAgentHeader
| order by borrados desc
```

## 6. Subidas completadas por prefijo (para comparar con *Matched Events*)
```kusto
StorageBlobLogs
| where TimeGenerated > ago(24h) and OperationName in ("PutBlob", "PutBlockList")
| extend ruta = tostring(split(parse_url(Uri).Path, "/")[2])
| summarize subidas = count() by ruta
| order by subidas desc
```

## Alertas recomendadas
| Alerta | Condición |
|---|---|
| Fallos de entrega | Métrica *Delivery Failed Events* > 0 durante 10 min |
| Dead-letter | Métrica *Dead Lettered Events* > 0 |
| Eventos descartados | Métrica *Dropped Events* > 0 |
| Sin eventos esperados | *Matched Events* = 0 durante la ventana de trabajo |
