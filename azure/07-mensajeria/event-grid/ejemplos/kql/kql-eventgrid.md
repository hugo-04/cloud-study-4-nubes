# KQL · Event Grid (tópicos personalizados, dominios y del sistema)

Requiere diagnóstico del tópico/dominio hacia Log Analytics (categorías `DeliveryFailures`, `PublishFailures`, `DataPlaneRequests`). Los nombres de columnas pueden variar: si una consulta falla, ejecuta `take 5` y ajusta. *Verifica el esquema vigente en la doc oficial.*

## 1. Fallos de entrega recientes
```kusto
AegDeliveryFailureLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, EventSubscriptionName, Message
| order by TimeGenerated desc
| take 100
```

## 2. Fallos por suscripción y causa
```kusto
AegDeliveryFailureLogs
| where TimeGenerated > ago(24h)
| summarize fallos = count() by EventSubscriptionName, Message
| order by fallos desc
```

## 3. Fallos de publicación (rechazos al enviar: permisos, formato, tamaño)
```kusto
AegPublishFailureLogs
| where TimeGenerated > ago(24h)
| summarize rechazos = count() by Message
| order by rechazos desc
```

## 4. Solicitudes de plano de datos (quién publica y desde dónde)
```kusto
AegDataPlaneRequests
| where TimeGenerated > ago(1h)
| summarize solicitudes = count() by OperationName, ResultType
| order by solicitudes desc
```

## 5. Tendencia de fallos
```kusto
AegDeliveryFailureLogs
| where TimeGenerated > ago(3d)
| summarize fallos = count() by bin(TimeGenerated, 1h), EventSubscriptionName
| render timechart
```

## Alertas recomendadas
| Alerta | Condición |
|---|---|
| Entregas fallidas | `DeliveryAttemptFailCount` > 0 durante 10 min |
| Dead-letter | `DeadLetteredCount` > 0 |
| Eventos descartados | `DroppedEventCount` > 0 |
| Publicaciones rechazadas | `PublishFailCount` > 0 |
| Sin eventos esperados | `PublishSuccessCount` = 0 en horario de trabajo |
