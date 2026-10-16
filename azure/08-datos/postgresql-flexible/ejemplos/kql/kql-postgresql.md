# KQL · PostgreSQL Flexible Server

Requiere el diagnóstico del servidor hacia Log Analytics (categorías `PostgreSQLLogs`, `PostgreSQLFlexSessions`, `PostgreSQLFlexQueryStoreRuntime`, `PostgreSQLFlexQueryStoreWaitStats`, `PostgreSQLFlexTableStats`, `PostgreSQLFlexDatabaseXacts`). Se consultan en `AzureDiagnostics` o en tablas dedicadas. *Los nombres de columnas pueden variar: ejecuta `take 5` y ajusta. Verifica el esquema vigente.*

## 1. Errores y advertencias del servidor
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL" and Category == "PostgreSQLLogs"
| where TimeGenerated > ago(24h) and errorLevel_s in ("ERROR", "FATAL", "PANIC", "WARNING")
| summarize veces = count() by errorLevel_s, sqlerrcode_s, Message
| order by veces desc
| take 50
```

## 2. Consultas lentas (requiere `log_min_duration_statement`)
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL" and Category == "PostgreSQLLogs"
| where Message has "duration:" and TimeGenerated > ago(6h)
| extend ms = todouble(extract(@"duration: ([0-9\.]+) ms", 1, Message))
| where ms > 500
| project TimeGenerated, ms, Message
| order by ms desc
| take 30
```

## 3. Inicios de sesión fallidos
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL" and Category == "PostgreSQLLogs"
| where Message has_any ("password authentication failed", "authentication failed", "no pg_hba.conf entry")
| where TimeGenerated > ago(24h)
| summarize intentos = count() by bin(TimeGenerated, 1h)
| render timechart
```

## 4. Sesiones por aplicación y estado
```kusto
AzureDiagnostics
| where Category == "PostgreSQLFlexSessions" and TimeGenerated > ago(1h)
| summarize sesiones = dcount(pid_s) by application_name_s, state_s, usename_s
| order by sesiones desc
```

## 5. Consultas más costosas (Query Store)
```kusto
AzureDiagnostics
| where Category == "PostgreSQLFlexQueryStoreRuntime" and TimeGenerated > ago(6h)
| summarize total_ms = sum(todouble(mean_time_d) * todouble(calls_d)), llamadas = sum(todouble(calls_d)) by query_id_s
| top 10 by total_ms desc
```

## 6. Esperas (¿qué espera el servidor: bloqueos, E/S, CPU?)
```kusto
AzureDiagnostics
| where Category == "PostgreSQLFlexQueryStoreWaitStats" and TimeGenerated > ago(6h)
| summarize esperas = sum(todouble(calls_d)) by event_type_s, event_s
| top 10 by esperas desc
```

## 7. Tablas con muchas filas muertas (autovacuum)
```kusto
AzureDiagnostics
| where Category == "PostgreSQLFlexTableStats" and TimeGenerated > ago(6h)
| summarize muertas = max(todouble(n_dead_tup_d)), vivas = max(todouble(n_live_tup_d)) by schemaname_s, relname_s
| extend pct_muertas = round(100.0 * muertas / (muertas + vivas + 1), 1)
| top 10 by pct_muertas desc
```

## 8. Métricas: CPU, memoria, conexiones y almacenamiento
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where MetricName in ("cpu_percent", "memory_percent", "active_connections", "storage_percent")
| where TimeGenerated > ago(6h)
| summarize maximo = max(Maximum) by MetricName, bin(TimeGenerated, 5m)
| render timechart
```

## 9. Retraso de réplicas
```kusto
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL" and MetricName in ("physical_replication_delay_in_seconds", "logical_replication_delay_in_bytes")
| where TimeGenerated > ago(6h)
| summarize maximo = max(Maximum) by MetricName, bin(TimeGenerated, 5m)
| render timechart
```

## Alertas recomendadas
| Alerta | Condición |
|---|---|
| CPU / memoria | > 80–85 % sostenido 15 min |
| Almacenamiento | `storage_percent` > 85 % (no se reduce después) |
| Conexiones | `active_connections` cerca de `max_connections` |
| Conexiones fallidas | `connections_failed` > umbral |
| Retraso de réplica | `physical_replication_delay_in_seconds` > 30 s |
| `FATAL` / `PANIC` en los registros | Cualquier ocurrencia |
| Transacciones muy antiguas | Consulta programada sobre `pg_stat_activity` |
