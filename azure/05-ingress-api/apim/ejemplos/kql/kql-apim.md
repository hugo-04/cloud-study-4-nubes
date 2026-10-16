# Consultas KQL para APIM

Requieren enviar `GatewayLogs` a Log Analytics (diagnósticos del recurso). Tablas: `ApiManagementGatewayLogs` (modo dedicado) o `AzureDiagnostics` con `Category == "GatewayLogs"`. Ajusta nombres de columna a tu modo.

## Errores por API, código y causa (24 h)
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h) and ResponseCode >= 400
| summarize peticiones = count() by ApiId, OperationId, ResponseCode, LastErrorReason, LastErrorSource
| order by peticiones desc
```

## ¿Es APIM o es el backend? (latencia)
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(6h)
| extend enApim = TotalTime - BackendTime
| summarize p95_total = percentile(TotalTime, 95), p95_backend = percentile(BackendTime, 95), p95_apim = percentile(enApim, 95) by ApiId
| order by p95_total desc
```

## 429 por consumidor (suscripción)
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h) and ResponseCode == 429
| summarize veces = count() by SubscriptionId = tostring(ApimSubscriptionId), ApiId
| order by veces desc
```

## Consumo por producto y suscripción
```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(30d)
| summarize llamadas = count(), errores = countif(ResponseCode >= 500) by ProductId, ApimSubscriptionId
| order by llamadas desc
```

## Seguir una petición por su correlación
```kusto
ApiManagementGatewayLogs
| where CorrelationId == "<X-Correlation-Id o x-ms-request-id>"
| project TimeGenerated, Method, Url, ResponseCode, BackendResponseCode, TotalTime, BackendTime, LastErrorReason
```

## Alerta de capacidad (métrica, no log)
Crea una alerta sobre la métrica **Capacity** del servicio: umbral 70 % durante 15 min.
