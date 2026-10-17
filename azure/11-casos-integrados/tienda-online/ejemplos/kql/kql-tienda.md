# KQL · Tienda online (Log Analytics / Application Insights)

Los nombres de tablas y columnas dependen de cómo conectes los diagnósticos (espacio de trabajo con Application Insights basado en Log Analytics). **Verifica con un evento real.**

## 1. Latencia y errores de la API de pedidos (percentil 95 por minuto)
```kusto
AppRequests
| where TimeGenerated > ago(1h) and Name has "POST /api/pedidos"
| summarize p95 = percentile(DurationMs, 95), errores = countif(Success == false), total = count() by bin(TimeGenerated, 1m)
| order by TimeGenerated asc
```

## 2. Qué dependencia hace lenta la API (SQL, Service Bus, Blob)
```kusto
AppDependencies
| where TimeGenerated > ago(1h)
| summarize p95 = percentile(DurationMs, 95), fallos = countif(Success == false), llamadas = count() by Type, Target
| order by p95 desc
```

## 3. Traza completa de un pedido (de la API al evento)
```kusto
union AppRequests, AppDependencies, AppTraces
| where OperationId == "<id-de-operacion>"
| project TimeGenerated, Tipo = Type, Nombre = coalesce(Name, Message), Duracion = DurationMs, Exito = Success
| order by TimeGenerated asc
```

## 4. Mensajes muertos (DLQ) y mensajes activos por entidad
```kusto
AzureMetrics
| where TimeGenerated > ago(6h) and ResourceProvider == "MICROSOFT.SERVICEBUS"
| where MetricName in ("DeadletteredMessages", "ActiveMessages")
| summarize maximo = max(Maximum) by MetricName, bin(TimeGenerated, 15m), Resource
| order by TimeGenerated asc
```

## 5. Bandeja de salida atascada (lo publica el servicio; lo emite como traza)
```kusto
AppTraces
| where TimeGenerated > ago(1h) and Message startswith "bandeja_salida.pendientes"
| extend pendientes = toint(Properties.pendientes)
| summarize maximo = max(pendientes) by bin(TimeGenerated, 5m)
// Alerta si el máximo crece durante 15 minutos seguidos
```

## 6. Reinicios de pods de la tienda
```kusto
KubePodInventory
| where TimeGenerated > ago(6h) and Namespace == "tienda"
| summarize reinicios = max(ContainerRestartCount) by Name, ContainerStatusReason
| where reinicios > 0
| order by reinicios desc
```

## 7. Bloqueos del WAF por regla (Front Door)
```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h) and Category == "FrontDoorWebApplicationFirewallLog" and action_s == "Block"
| summarize bloqueos = count() by ruleName_s, clientIP_s
| top 20 by bloqueos desc
```
