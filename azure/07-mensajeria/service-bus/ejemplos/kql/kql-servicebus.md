# KQL · Service Bus

Requiere diagnóstico del namespace hacia Log Analytics (categorías de operaciones, auditoría de ejecución y filtrado de red). Los nombres de tablas/columnas pueden variar según el modo de destino (tablas dedicadas o `AzureDiagnostics`): si una consulta falla, ejecuta `take 5` y ajusta. *Verifica el esquema vigente en la doc oficial.*

## 1. Operaciones fallidas (modo AzureDiagnostics)
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SERVICEBUS" and Category == "OperationalLogs"
| where TimeGenerated > ago(1h) and Status_s != "Succeeded"
| project TimeGenerated, OperationName, Status_s, EventName_s, EntityName = tostring(split(Resource, "/")[0])
| order by TimeGenerated desc
```

## 2. Rechazos por red (firewall/Private Endpoint)
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SERVICEBUS" and Category == "VNetAndIPFilteringLogs"
| where TimeGenerated > ago(24h)
| summarize rechazos = count() by IPAddress_s, Action_s, Reason_s
| order by rechazos desc
```

## 3. Auditoría de acceso en tiempo de ejecución (quién envía/recibe)
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SERVICEBUS" and Category == "RuntimeAuditLogs"
| where TimeGenerated > ago(1h)
| summarize eventos = count() by ActivityName_s, Status_s
| order by eventos desc
```

## 4. Mensajes en DLQ por entidad (métrica)
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.SERVICEBUS" and MetricName == "DeadletteredMessages"
| where TimeGenerated > ago(24h)
| summarize dlq = max(Maximum) by bin(TimeGenerated, 15m), Resource
| render timechart
```

## 5. Antigüedad de la cola: mensajes activos creciendo
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.SERVICEBUS" and MetricName == "ActiveMessages"
| where TimeGenerated > ago(6h)
| summarize activos = max(Maximum) by bin(TimeGenerated, 5m), Resource
| render timechart
```

## 6. Throttling y errores del servidor
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.SERVICEBUS" and MetricName in ("ThrottledRequests", "ServerErrors", "UserErrors")
| where TimeGenerated > ago(24h)
| summarize total = sum(Total) by MetricName, bin(TimeGenerated, 30m)
| render timechart
```

## Alertas recomendadas
| Alerta | Condición |
|---|---|
| DLQ con mensajes | `DeadletteredMessages` > 0 |
| Cola creciendo | `ActiveMessages` en aumento sostenido durante 15 min |
| Throttling | `ThrottledRequests` > 0 |
| CPU/memoria (Premium) | `NamespaceCpuUsage` o `NamespaceMemoryUsage` > 70 % |
| Errores del servidor | `ServerErrors` > 0 |
