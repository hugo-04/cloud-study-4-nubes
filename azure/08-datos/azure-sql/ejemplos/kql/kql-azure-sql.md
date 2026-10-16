# KQL · Azure SQL Database

Requiere el diagnóstico de la base hacia Log Analytics (categorías `SQLInsights`, `Errors`, `Timeouts`, `Blocks`, `Deadlocks`, `QueryStoreRuntimeStatistics`, `QueryStoreWaitStatistics`, `AutomaticTuning`) y la auditoría del servidor (`SQLSecurityAuditEvents`). Las tablas son `AzureDiagnostics` (modo AzureDiagnostics) o tablas dedicadas. *Los nombres de columnas pueden variar: ejecuta `take 5` y ajusta. Verifica el esquema vigente.*

## 1. Errores recientes por número
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL" and Category == "Errors"
| where TimeGenerated > ago(24h)
| summarize veces = count() by error_number_d, Message
| order by veces desc
```
Los números típicos de errores transitorios son 40613, 40501, 40197, 49918 y 10928/10929.

## 2. Interbloqueos (deadlocks)
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL" and Category == "Deadlocks"
| where TimeGenerated > ago(7d)
| summarize deadlocks = count() by bin(TimeGenerated, 1h), DatabaseName_s
| render timechart
```

## 3. Bloqueos prolongados
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL" and Category == "Blocks"
| where TimeGenerated > ago(24h)
| project TimeGenerated, DatabaseName_s, lock_mode_s, duration_d, blocked_process_report_s
| order by duration_d desc
| take 20
```

## 4. Consultas que agotan tiempo
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL" and Category == "Timeouts"
| where TimeGenerated > ago(24h)
| summarize timeouts = count() by bin(TimeGenerated, 15m), DatabaseName_s
| render timechart
```

## 5. CPU y E/S (métricas)
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.SQL"
| where MetricName in ("cpu_percent", "log_write_percent", "physical_data_read_percent", "workers_percent", "sessions_percent")
| where TimeGenerated > ago(6h)
| summarize maximo = max(Maximum) by MetricName, bin(TimeGenerated, 5m)
| render timechart
```

## 6. Conexiones fallidas y bloqueadas por firewall
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.SQL" and MetricName in ("connection_failed", "blocked_by_firewall")
| where TimeGenerated > ago(24h)
| summarize total = sum(Total) by MetricName, bin(TimeGenerated, 1h)
| render timechart
```

## 7. Auditoría: quién accedió a qué
```kusto
AzureDiagnostics
| where Category == "SQLSecurityAuditEvents" and TimeGenerated > ago(24h)
| where action_name_s in ("BATCH COMPLETED", "FAILED_DATABASE_AUTHENTICATION_GROUP", "DATABASE_PRINCIPAL_CHANGE_GROUP")
| summarize eventos = count() by server_principal_name_s, client_ip_s, action_name_s
| order by eventos desc
```

## 8. Inicios de sesión fallidos (ataques o configuración rota)
```kusto
AzureDiagnostics
| where Category == "SQLSecurityAuditEvents" and action_name_s == "FAILED_DATABASE_AUTHENTICATION_GROUP"
| where TimeGenerated > ago(24h)
| summarize intentos = count() by client_ip_s, server_principal_name_s
| order by intentos desc
```

## 9. Consultas con más duración (Query Store a través de diagnóstico)
```kusto
AzureDiagnostics
| where Category == "QueryStoreRuntimeStatistics" and TimeGenerated > ago(6h)
| summarize duracion_prom_ms = avg(duration_d) / 1000, ejecuciones = sum(execution_count_d) by query_hash_s
| top 10 by duracion_prom_ms desc
```

## Alertas recomendadas
| Alerta | Condición |
|---|---|
| CPU alta | `cpu_percent` > 80 % durante 15 min |
| Deadlocks | `deadlock` > 0 |
| Conexiones fallidas | `connection_failed` > 5 en 15 min |
| Almacenamiento | `storage_percent` > 85 % |
| Workers | `workers_percent` > 80 % |
| Logins fallidos | Picos de `FAILED_DATABASE_AUTHENTICATION_GROUP` |
| Defender | Cualquier alerta de amenaza |
