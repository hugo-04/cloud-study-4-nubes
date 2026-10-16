#!/usr/bin/env bash
# Cost Management con Azure CLI y az rest (versión de estudio). Es una guía de comandos, no la ejecutes de golpe.
# Los presupuestos y las exportaciones con umbrales/destinos se crean mejor con REST, Terraform o Bicep:
# `az consumption budget create` NO permite definir umbrales ni correos (el presupuesto no avisaría de nada).
set -euo pipefail

SUB="$(az account show --query id -o tsv)"
SCOPE="/subscriptions/$SUB"
DIR="$(dirname "$0")/../json"
API_COSTOS="2023-11-01"      # consultas y pronósticos (verifica la versión vigente)
API_PRESUPUESTOS="2023-05-01"
API_EXPORT="2023-08-01"      # 2023-08-01 o posterior para almacenamiento con firewall

# ---------------------------------------------------------------------------------------------
# 1) CONSULTAR el costo (API de consultas)
# ---------------------------------------------------------------------------------------------
# Costo del mes agrupado por la etiqueta "owner"
az rest --method post \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.CostManagement/query?api-version=$API_COSTOS" \
  --body @"$DIR/consulta-costo-por-etiqueta.json" -o json

# Costo diario por grupo de recursos
az rest --method post \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.CostManagement/query?api-version=$API_COSTOS" \
  --body @"$DIR/consulta-costo-diario-por-grupo.json" -o json

# Pronóstico de lo que resta del mes
az rest --method post \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.CostManagement/forecast?api-version=$API_COSTOS" \
  --body @"$DIR/pronostico-fin-de-mes.json" -o json

# ---------------------------------------------------------------------------------------------
# 2) GRUPO DE ACCIONES (qué pasa al alcanzar un umbral)
# ---------------------------------------------------------------------------------------------
az monitor action-group create \
  --name ag-finops --resource-group rg-modalima-finops --short-name finops \
  --action email finops finops@modalima.example \
  --action webhook apagar-sandbox https://func-finops-modalima.azurewebsites.net/api/apagar usecommonalertschema

# ---------------------------------------------------------------------------------------------
# 3) PRESUPUESTOS
# ---------------------------------------------------------------------------------------------
# Con umbrales, roles y grupo de acciones: REST (edita <ID_SUSCRIPCION> en el JSON antes)
az rest --method put \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.Consumption/budgets/presupuesto-mensual?api-version=$API_PRESUPUESTOS" \
  --body @"$DIR/presupuesto-suscripcion.json"

az consumption budget list -o table
az consumption budget show --budget-name presupuesto-mensual
# az consumption budget delete --budget-name presupuesto-mensual

# ---------------------------------------------------------------------------------------------
# 4) EXPORTACIÓN DIARIA a Storage (edita <ID_SUSCRIPCION> en el JSON antes)
# ---------------------------------------------------------------------------------------------
az rest --method put \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.CostManagement/exports/export-modalima-diario?api-version=$API_EXPORT" \
  --body @"$DIR/exportacion-diaria.json"

# Ejecutarla ahora
az rest --method post \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.CostManagement/exports/export-modalima-diario/run?api-version=$API_EXPORT"

# Ver sus ejecuciones
az rest --method get \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.CostManagement/exports/export-modalima-diario/runHistory?api-version=$API_EXPORT"

# ---------------------------------------------------------------------------------------------
# 5) ALERTAS
# ---------------------------------------------------------------------------------------------
# Alertas de costo activas del alcance (presupuesto, anomalía, crédito…)
az rest --method get \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.CostManagement/alerts?api-version=$API_COSTOS" \
  --query "value[].{tipo:properties.definition.type, estado:properties.status, origen:properties.details.reason, fecha:properties.creationTime}" -o table
# La alerta de anomalías se crea con el portal, Terraform (azurerm_cost_anomaly_alert) o la API de acciones programadas (kind InsightAlert).

# ---------------------------------------------------------------------------------------------
# 6) ETIQUETAS: recursos sin etiqueta "owner" (Resource Graph; más consultas en kql/kql-costos.md)
# ---------------------------------------------------------------------------------------------
az graph query -q "
resources
| where isnull(tags['owner']) or tags['owner'] == ''
| summarize recursos = count() by subscriptionId, resourceGroup, type
| order by recursos desc
| take 50
" -o table

# ---------------------------------------------------------------------------------------------
# 7) RESPUESTA MANUAL en Sandbox: desasignar las VM etiquetadas auto-apagar=si (lo que haría la Function)
# ---------------------------------------------------------------------------------------------
# az vm list --query "[?tags.\"auto-apagar\"=='si'].id" -o tsv | xargs -r az vm deallocate --no-wait --ids
