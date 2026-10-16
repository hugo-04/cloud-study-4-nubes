# Consultas KQL para Front Door

Requieren los diagnósticos del perfil hacia Log Analytics (modo `AzureDiagnostics` o tablas dedicadas `AFDAccessLog`, `AFDWebApplicationFirewallLog`, `AFDHealthProbeLog`). Ajusta nombres de columna a tu modo.

## Errores por código y origen (24 h)
```kusto
AzureDiagnostics
| where Category == "FrontDoorAccessLog" and TimeGenerated > ago(24h)
| where toint(httpStatusCode_s) >= 500
| summarize errores = count() by httpStatusCode_s, originName_s, bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

## Buscar una petición por X-Azure-Ref
```kusto
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| where trackingReference_s == "<valor de X-Azure-Ref>"
| project TimeGenerated, requestUri_s, httpStatusCode_s, originName_s, timeToFirstByte_s, cacheStatus_s, clientIp_s
```

## Tasa de aciertos de caché
```kusto
AzureDiagnostics
| where Category == "FrontDoorAccessLog" and TimeGenerated > ago(24h)
| summarize total = count(), aciertos = countif(cacheStatus_s startswith "HIT") by bin(TimeGenerated, 1h)
| extend porcentaje = round(100.0 * aciertos / total, 1)
```

## Reglas del WAF que más actúan
```kusto
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog" and TimeGenerated > ago(7d)
| summarize veces = count() by ruleName_s, action_s
| order by veces desc
```

## Salud de los orígenes (sondas)
```kusto
AzureDiagnostics
| where Category == "FrontDoorHealthProbeLog" and TimeGenerated > ago(6h)
| summarize pruebas = count(), fallos = countif(httpStatusCode_s !startswith "2") by originName_s, bin(TimeGenerated, 30m)
```
