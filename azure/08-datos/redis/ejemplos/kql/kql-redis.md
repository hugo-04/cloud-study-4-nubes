# KQL · Azure Managed Redis

Requiere el diagnóstico de la instancia hacia Log Analytics (categoría `ConnectionEvents` → tabla `REDConnectionEvents`, y métricas `AllMetrics` → tabla `AzureMetrics`). *El servicio gestionado no registra cada comando: para diagnosticar comandos lentos usa `SLOWLOG` y `INFO` desde un cliente (ver [redis-cli](../redis-cli/comandos.md)). Verifica el esquema vigente con `take 5`.*

Columnas de `REDConnectionEvents`: `TimeGenerated`, `ClientIp`, `ConnectionId`, `EventEpochTime`, `EventType` (`new_conn`, `auth`, `close_conn`), `EventStatus` (resultado de la autenticación), `OperationName`, `PrivateLinkIPv6`, `_ResourceId`.

## 1. Conexiones nuevas por cliente (¿quién se conecta y con qué frecuencia?)
```kusto
REDConnectionEvents
| where TimeGenerated > ago(1h) and EventType == "new_conn"
| summarize conexiones = count() by ClientIp, bin(TimeGenerated, 5m)
| order by conexiones desc
```
Muchas conexiones nuevas por minuto = clientes que no reutilizan conexiones (falta de pool o cliente creado por solicitud).

## 2. Fallos de autenticación
```kusto
REDConnectionEvents
| where TimeGenerated > ago(24h) and EventType == "auth" and EventStatus != 0
| summarize fallos = count() by ClientIp, EventStatus
| order by fallos desc
```
*Confirma el significado de `EventStatus`; en general 0 indica éxito.* Un pico justo cada hora suele indicar **token de Entra que expira sin renovarse**.

## 3. Conexiones que se abren y cierran sin parar (tormenta de reconexiones)
```kusto
REDConnectionEvents
| where TimeGenerated > ago(1h) and EventType in ("new_conn", "close_conn")
| summarize abiertas = countif(EventType == "new_conn"), cerradas = countif(EventType == "close_conn") by bin(TimeGenerated, 1m)
| order by TimeGenerated desc
```

## 4. Duración aproximada de las conexiones
```kusto
REDConnectionEvents
| where TimeGenerated > ago(6h) and EventType in ("new_conn", "close_conn")
| summarize inicio = minif(todatetime(unixtime_seconds_todatetime(EventEpochTime)), EventType == "new_conn"),
            fin = maxif(todatetime(unixtime_seconds_todatetime(EventEpochTime)), EventType == "close_conn")
    by ConnectionId, ClientIp
| where isnotnull(inicio) and isnotnull(fin)
| extend segundos = datetime_diff('second', fin, inicio)
| summarize p50 = percentile(segundos, 50), p95 = percentile(segundos, 95) by ClientIp
```
Conexiones que duran justo ~1 hora apuntan otra vez al vencimiento del token.

## 5. Memoria y expulsiones (métricas)
```kusto
AzureMetrics
| where TimeGenerated > ago(6h) and ResourceProvider == "MICROSOFT.CACHE"
| where MetricName in ("usedmemorypercentage", "evictedkeys")
| summarize maximo = max(Maximum) by MetricName, bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

## 6. Tasa de aciertos de la caché
```kusto
AzureMetrics
| where TimeGenerated > ago(24h) and ResourceProvider == "MICROSOFT.CACHE"
| where MetricName in ("cachehits", "cachemisses")
| summarize total = sum(Total) by MetricName, bin(TimeGenerated, 1h)
| evaluate pivot(MetricName, sum(total))
| extend tasa_aciertos = round(100.0 * cachehits / (cachehits + cachemisses), 1)
```

## 7. Carga del servidor y clientes conectados
```kusto
AzureMetrics
| where TimeGenerated > ago(6h) and ResourceProvider == "MICROSOFT.CACHE"
| where MetricName in ("serverLoad", "connectedclients", "operationsPerSecond", "cacheLatency")
| summarize maximo = max(Maximum) by MetricName, bin(TimeGenerated, 15m)
| order by MetricName asc, TimeGenerated desc
```

## 8. Salud de la geo-replicación
```kusto
AzureMetrics
| where TimeGenerated > ago(24h) and MetricName == "geoReplicationHealthy"
| summarize minimo = min(Minimum) by bin(TimeGenerated, 15m)
| where minimo < 1
```

## 9. Alerta sugerida: conexiones nuevas anómalas
```kusto
REDConnectionEvents
| where TimeGenerated > ago(15m) and EventType == "new_conn"
| summarize nuevas = count() by bin(TimeGenerated, 5m)
| where nuevas > 500
```
