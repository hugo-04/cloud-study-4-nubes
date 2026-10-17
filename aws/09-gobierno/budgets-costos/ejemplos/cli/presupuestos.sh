#!/usr/bin/env bash
# Presupuestos, costos y anomalías con la CLI. Budgets y Cost Explorer son globales: usan us-east-1.
set -euo pipefail
export AWS_DEFAULT_REGION=us-east-1
CUENTA="$(aws sts get-caller-identity --query Account --output text)"
AQUI="$(cd "$(dirname "$0")" && pwd)"
JSON="$AQUI/../json"

echo "== 1. Activar las etiquetas de asignación de costos (tardan hasta ~24 h en verse) =="
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status TagKey=equipo,Status=Active TagKey=entorno,Status=Active

aws ce list-cost-allocation-tags --status Active --query 'CostAllocationTags[].TagKey'

echo "== 2. Crear un presupuesto por equipo con avisos pronosticados y reales =="
aws budgets create-budget \
  --account-id "$CUENTA" \
  --budget "file://$JSON/presupuesto-equipo.json" \
  --notifications-with-subscribers "file://$JSON/avisos.json"

aws budgets describe-budgets --account-id "$CUENTA" \
  --query 'Budgets[].{Nombre:BudgetName,Limite:BudgetLimit.Amount,Real:CalculatedSpend.ActualSpend.Amount,Pronostico:CalculatedSpend.ForecastedSpend.Amount}' \
  --output table

echo "== 3. Costo del mes agrupado por la etiqueta equipo (cada solicitud tiene costo: no la pongas en un bucle) =="
aws ce get-cost-and-usage --cli-input-json "file://$JSON/ce-consulta-por-etiqueta.json" \
  --query 'ResultsByTime[].Groups[].{Equipo:Keys[0],Monto:Metrics.UnblendedCost.Amount}' --output table

echo "== 4. ¿En qué servicio se fue la plata este mes? =="
aws ce get-cost-and-usage \
  --time-period Start="$(date -u +%Y-%m-01)",End="$(date -u -d "$(date -u +%Y-%m-01) +1 month" +%Y-%m-%d)" \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[].Groups[?Metrics.UnblendedCost.Amount>`1`].[Keys[0],Metrics.UnblendedCost.Amount]' --output text

echo "== 5. Pronóstico de fin de mes (el inicio debe ser hoy o posterior) =="
aws ce get-cost-forecast \
  --time-period Start="$(date -u +%Y-%m-%d)",End="$(date -u -d "$(date -u +%Y-%m-01) +1 month" +%Y-%m-%d)" \
  --metric UNBLENDED_COST --granularity MONTHLY

echo "== 6. Monitor de anomalías por servicio =="
aws ce create-anomaly-monitor \
  --anomaly-monitor 'MonitorName=por-servicio,MonitorType=DIMENSIONAL,MonitorDimension=SERVICE'

echo "== 7. Anomalías de los últimos 7 días =="
aws ce get-anomalies \
  --date-interval StartDate="$(date -u -d '7 days ago' +%Y-%m-%d)",EndDate="$(date -u +%Y-%m-%d)" \
  --query 'Anomalies[].{Servicio:RootCauses[0].Service,Impacto:Impact.TotalImpact,Inicio:AnomalyStartDate}' --output table

echo "== 8. Presupuestos con su estado =="
aws budgets describe-budget-actions-for-account --account-id "$CUENTA" \
  --query 'Actions[].{Presupuesto:BudgetName,Tipo:ActionType,Estado:Status}' --output table || true
