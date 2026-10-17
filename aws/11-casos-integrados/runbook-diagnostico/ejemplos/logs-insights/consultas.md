# Consultas de Logs Insights para un incidente

Las cinco están creadas como consultas guardadas por el [Terraform](../terraform/main.tf). Asumen logs JSON con `nivel`, `operacion`, `excepcion`, `duracionMs` e `idTraza`.

| # | Pregunta | Consulta |
|---|---|---|
| 1 | ¿Cuántos errores por minuto y desde cuándo? | `filter nivel = "ERROR" \| stats count(*) as errores by bin(1m) \| sort @timestamp desc` |
| 2 | ¿Qué excepciones y en qué operación? | `filter nivel = "ERROR" \| stats count(*) as veces by excepcion, operacion \| sort veces desc \| limit 20` |
| 3 | ¿Qué operación es lenta? | `filter ispresent(duracionMs) \| stats pct(duracionMs, 95) as p95, max(duracionMs) as maximo by operacion \| sort p95 desc` |
| 4 | ¿Qué le pasó a UNA petición? | `filter idTraza = "…" \| sort @timestamp asc` |
| 5 | ¿Qué dice la sonda? | `filter @message like "sonda.dependencia" \| parse @message "dependencia=* escalon=* ok=* ms=*" as d, e, ok, ms \| stats count(*) as pruebas, sum(ok = "false") as fallos by d, e` |

Trucos: acota **siempre** el tiempo (se cobra por dato escaneado); consulta primero un grupo, no todos; un `idTraza` de una petición fallida (de la respuesta o del ALB) es la forma más rápida de pasar de «hay errores» a «este es el error».
