# Consultas KQL · Clickstream

Requieren que el espacio de nombres envíe sus métricas y registros a Log Analytics, y la aplicación sus trazas y solicitudes (Application Insights en modo basado en espacio de trabajo). Los nombres de tablas y categorías de registros de Event Hubs pueden variar: verifica en tu espacio de trabajo.

**1. Limitaciones (throttling): señal de que falta capacidad**
```kusto
AzureMetrics
| where TimeGenerated > ago(6h) and ResourceProvider == "MICROSOFT.EVENTHUB" and MetricName == "ThrottledRequests"
| summarize limitadas = sum(Total) by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**2. Entrada frente a salida (si la salida no sigue a la entrada, hay retraso)**
```kusto
AzureMetrics
| where TimeGenerated > ago(6h) and ResourceProvider == "MICROSOFT.EVENTHUB" and MetricName in ("IncomingMessages", "OutgoingMessages")
| summarize total = sum(Total) by MetricName, bin(TimeGenerated, 5m)
| render timechart
```

**3. Errores y latencia del colector (API que recibe los clics)**
```kusto
AppRequests
| where TimeGenerated > ago(1h) and Name has "/api/clics"
| summarize solicitudes = count(), errores = countif(toint(ResultCode) >= 500), limitadas = countif(toint(ResultCode) == 429), p95_ms = percentile(DurationMs, 95) by bin(TimeGenerated, 5m)
```

**4. Eventos tardíos descartados por el agregador (propiedad personalizada)**
```kusto
AppTraces
| where TimeGenerated > ago(24h) and Message startswith "clics.tardio"
| summarize descartados = count() by bin(TimeGenerated, 15m)
```

**5. Clave caliente: sesiones con más eventos en una hora (el colector registra una muestra)**
```kusto
AppTraces
| where TimeGenerated > ago(1h) and Message startswith "clics.muestra"
| extend sesion = tostring(Properties.sesionId)
| summarize eventos = count() by sesion
| top 20 by eventos desc
```

**6. Retraso del agregador (marca de tiempo del evento frente a la hora de procesarlo)**
```kusto
AppTraces
| where TimeGenerated > ago(1h) and Message startswith "clics.lote"
| extend retraso_s = todouble(Properties.retrasoSegundos)
| summarize p50 = percentile(retraso_s, 50), p95 = percentile(retraso_s, 95) by bin(TimeGenerated, 5m)
```
