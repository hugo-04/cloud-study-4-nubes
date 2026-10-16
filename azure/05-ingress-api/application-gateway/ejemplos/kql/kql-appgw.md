# Consultas KQL para Application Gateway

Requieren los diagnósticos en **modo de recurso específico** o en `AzureDiagnostics`. Los nombres de columnas varían según el modo: ajusta si tu tabla es `AGWAccessLogs` / `AGWFirewallLogs`.

## Errores 5xx por backend (últimas 24 h)
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayAccessLog" and TimeGenerated > ago(24h)
| where httpStatus_d >= 500
| summarize errores = count() by serverRouted_s, httpStatus_d, bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

## Latencia (p50/p95) por ruta
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayAccessLog" and TimeGenerated > ago(6h)
| summarize p50 = percentile(timeTaken_d, 50), p95 = percentile(timeTaken_d, 95), peticiones = count() by requestUri_s
| top 20 by p95 desc
```

## Reglas del WAF que más bloquean (candidatas a falso positivo)
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog" and TimeGenerated > ago(7d)
| summarize veces = count() by ruleId_s, Message, action_s
| order by veces desc
```

## IPs que más disparan el WAF
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog" and action_s in ("Blocked", "Matched")
| summarize eventos = count() by clientIp_s
| top 20 by eventos desc
```

## Buscar una petición por su trace id (verifica el nombre de la columna en tu tabla)
```kusto
AzureDiagnostics
| where Category == "ApplicationGatewayAccessLog"
| where tostring(transactionId_g) == "<X-AppGW-Trace-Id>"      // el valor de la cabecera X-AppGW-Trace-Id
| project TimeGenerated, httpMethod_s, requestUri_s, httpStatus_d, serverRouted_s, timeTaken_d
```
