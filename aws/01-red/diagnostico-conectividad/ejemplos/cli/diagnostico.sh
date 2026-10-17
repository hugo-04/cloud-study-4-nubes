#!/usr/bin/env bash
# Lanza un análisis de Reachability Analyzer y muestra el resultado.
# uso: diagnostico.sh <eni-origen> <eni-destino> <puerto>
# Requiere: ec2:CreateNetworkInsightsPath, StartNetworkInsightsAnalysis, DescribeNetworkInsightsAnalyses (y Delete* para limpiar)
set -euo pipefail
ORIGEN="${1:?uso: $0 <eni-origen> <eni-destino> <puerto>}"
DESTINO="${2:?}"
PUERTO="${3:?}"

PATH_ID=$(aws ec2 create-network-insights-path --source "$ORIGEN" --destination "$DESTINO" \
  --protocol tcp --destination-port "$PUERTO" --query "NetworkInsightsPath.NetworkInsightsPathId" --output text)
echo "Ruta de análisis: $PATH_ID"

ANALISIS=$(aws ec2 start-network-insights-analysis --network-insights-path-id "$PATH_ID" \
  --query "NetworkInsightsAnalysis.NetworkInsightsAnalysisId" --output text)
echo "Análisis: $ANALISIS (esperando)"

for _ in $(seq 1 30); do
  ESTADO=$(aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$ANALISIS" \
    --query "NetworkInsightsAnalyses[0].Status" --output text)
  [ "$ESTADO" != "running" ] && break
  sleep 3
done

aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$ANALISIS" \
  --query "NetworkInsightsAnalyses[0].{estado:Status, alcanzable:NetworkPathFound, explicaciones:Explanations[].{codigo:ExplanationCode, componente:Component.Id}}" \
  --output json

# Limpieza opcional: aws ec2 delete-network-insights-analysis --network-insights-analysis-id "$ANALISIS"
#                    aws ec2 delete-network-insights-path --network-insights-path-id "$PATH_ID"
