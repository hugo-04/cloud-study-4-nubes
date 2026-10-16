# KQL · Event Hubs

Requiere diagnóstico del namespace hacia Log Analytics (modo de destino *específico del recurso* o *AzureDiagnostics*). Las tablas por categoría llevan prefijo `AZMS`. *Los nombres de columnas pueden variar: ejecuta `take 5` y ajusta. Verifica el esquema vigente en la doc oficial.*

## 1. Operaciones de administración (quién creó/borró event hubs o grupos)
```kusto
AZMSOperationalLogs
| where TimeGenerated > ago(24h)
| project TimeGenerated, OperationName, ActivityName, Status = EventName, Caller, Message
| order by TimeGenerated desc
```

## 2. Conexiones y autorizaciones (quién se conecta, desde dónde, y rechazos)
```kusto
AZMSRuntimeAuditLogs
| where TimeGenerated > ago(1h)
| summarize conexiones = count() by ActivityName, Status = tostring(Status_s), Protocol = tostring(Protocol_s)
| order by conexiones desc
```

## 3. Errores de aplicación de Kafka (usuario/coordinador)
```kusto
union isfuzzy=true AZMSKafkaUserErrorLogs, AZMSKafkaCoordinatorLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, Type, Message
| order by TimeGenerated desc
| take 100
```
Ayuda a ver *rebalances* frecuentes, tiempos de sesión vencidos y fallos de metadatos.

## 4. Limitación (`ThrottledRequests`) por hora
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.EVENTHUB" and MetricName == "ThrottledRequests"
| where TimeGenerated > ago(3d)
| summarize limitadas = sum(Total) by bin(TimeGenerated, 1h)
| render timechart
```
Si crece junto con `IncomingBytes`, necesitas más TU/PU o repartir mejor.

## 5. Rendimiento entrante vs. saliente
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.EVENTHUB"
| where MetricName in ("IncomingMessages", "OutgoingMessages")
| where TimeGenerated > ago(6h)
| summarize total = sum(Total) by MetricName, bin(TimeGenerated, 5m)
| render timechart
```
Si `OutgoingMessages` queda muy por debajo de `IncomingMessages` por horas, los consumidores se están atrasando.

## 6. Capture: archivos y retraso
```kusto
AZMSArchiveLogs
| where TimeGenerated > ago(24h)
| summarize archivos = count() by EventHub = tostring(EventHub_s), Estado = tostring(Status_s)
```
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.EVENTHUB" and MetricName == "CaptureBacklog"
| summarize maximo = max(Maximum) by bin(TimeGenerated, 15m)
| render timechart
```

## 7. Auto-inflate (cuándo subió y cuándo llegó al tope)
```kusto
AZMSAutoscaleLogs
| where TimeGenerated > ago(7d)
| project TimeGenerated, Message
| order by TimeGenerated desc
```

## 8. Conexiones rechazadas por red
```kusto
AZMSVNetConnectionEvents
| where TimeGenerated > ago(24h)
| summarize rechazos = count() by Action = tostring(Action_s), Origen = tostring(SubscriptionId_s)
```

## Alertas recomendadas
| Alerta | Condición |
|---|---|
| Limitación | `ThrottledRequests` > 0 durante 5 min |
| Errores de servidor | `ServerErrors` > 0 |
| Errores de usuario altos | `UserErrors` anormal (credenciales, permisos) |
| Capture atrasado | `CaptureBacklog` > umbral durante 15 min |
| Tráfico cae a cero en horario | `IncomingMessages` = 0 |
| **Lag del consumidor** | Métrica propia (Micrometer/Prometheus) o `AdminClient` (ver uso en Java) |
| Auto-inflate en el tope | Mensaje en `AZMSAutoscaleLogs` |
