# Consultas KQL · Incidente en la tienda

Se usan en Log Analytics (Application Insights en modo espacio de trabajo). Ajusta nombres de operaciones y tablas a tu entorno.

**1. ¿Desde cuándo y cuánto? Tasa de errores por minuto**
```kusto
AppRequests
| where TimeGenerated > ago(2h)
| summarize total = count(), errores = countif(toint(ResultCode) >= 500), p95_ms = percentile(DurationMs, 95) by bin(TimeGenerated, 1m)
| extend tasa = round(100.0 * errores / total, 2)
| order by TimeGenerated asc
```

**2. ¿Qué operación falla? (ordenadas por impacto)**
```kusto
AppRequests
| where TimeGenerated > ago(1h) and toint(ResultCode) >= 500
| summarize errores = count(), ultima = max(TimeGenerated) by Name, ResultCode
| order by errores desc
```

**3. ¿Qué dependencia falla? (SQL, Service Bus, Blob, Redis…)**
```kusto
AppDependencies
| where TimeGenerated > ago(1h)
| summarize llamadas = count(), fallos = countif(Success == false), p95_ms = percentile(DurationMs, 95) by Target, Type
| extend tasa_fallo = round(100.0 * fallos / llamadas, 2)
| where fallos > 0
| order by tasa_fallo desc
```

**4. Tipo de excepción más frecuente (para saber en qué escalón está)**
```kusto
AppExceptions
| where TimeGenerated > ago(1h)
| summarize n = count() by ExceptionType, OuterMessage = substring(OuterMessage, 0, 120)
| top 10 by n desc
```

**5. Seguir una petición de punta a punta (reemplaza el identificador de operación)**
```kusto
let op = "REEMPLAZA_AQUI";
union AppRequests, AppDependencies, AppTraces, AppExceptions
| where OperationId == op
| project TimeGenerated, Tipo = Type, Nombre = coalesce(Name, Message), Resultado = coalesce(ResultCode, tostring(Success)), DurationMs
| order by TimeGenerated asc
```

**6. Resultados de la sonda sintética (por dependencia y escalón)**
```kusto
AppTraces
| where TimeGenerated > ago(1h) and Message startswith "sonda.dependencia"
| extend dependencia = tostring(Properties.dependencia), ok = tobool(Properties.ok), escalon = tostring(Properties.escalon), ms = todouble(Properties.ms)
| summarize ejecuciones = count(), fallos = countif(ok == false), p95_ms = percentile(ms, 95) by dependencia, escalon
| order by fallos desc
```

**7. Rechazos del WAF y de APIM (¿bloqueamos a clientes buenos?)**
```kusto
AzureDiagnostics
| where TimeGenerated > ago(1h) and Category in ("FrontDoorWebApplicationFirewallLog", "GatewayLogs")
| summarize eventos = count() by Category, action_s = tostring(column_ifexists("action_s", "")), ResponseCode = tostring(column_ifexists("responseCode_d", ""))
| order by eventos desc
```

**8. Cambios de configuración antes del incidente (registro de actividad)**
```kusto
AzureActivity
| where TimeGenerated > ago(6h) and ActivityStatusValue == "Success" and CategoryValue == "Administrative"
| where OperationNameValue !has "READ"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, Resource = tostring(split(ResourceId, "/")[-1])
| order by TimeGenerated desc
```
