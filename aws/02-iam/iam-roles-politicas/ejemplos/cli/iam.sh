#!/usr/bin/env bash
# Auditoría y pruebas de IAM. SOLO LECTURA (el simulador no ejecuta acciones).
set -euo pipefail

echo "== ¿Quién soy? =="
aws sts get-caller-identity --output table

echo "== Simular: ¿puede el rol de la app borrar objetos de facturas? (debería ser DENEGADO) =="
ROL_ARN="${1:?uso: $0 <arn-del-rol> [arn-del-bucket-objeto]}"
RECURSO="${2:-arn:aws:s3:::modalima-datos/facturas/prueba.json}"
aws iam simulate-principal-policy --policy-source-arn "$ROL_ARN" \
  --action-names s3:PutObject s3:DeleteObject --resource-arns "$RECURSO" \
  --query "EvaluationResults[].{accion:EvalActionName, decision:EvalDecision}" --output table

echo "== Claves de acceso de larga duración con más de 90 días =="
aws iam generate-credential-report >/dev/null
sleep 3
aws iam get-credential-report --query Content --output text | base64 -d \
  | awk -F, 'NR>1 && ($9=="true" || $14=="true") {print $1, "key1_last_rotated="$10, "key2_last_rotated="$15}'

echo "== Hallazgos activos de Access Analyzer =="
ANALIZADOR=$(aws accessanalyzer list-analyzers --query "analyzers[0].arn" --output text)
if [ "$ANALIZADOR" != "None" ]; then
  aws accessanalyzer list-findings-v2 --analyzer-arn "$ANALIZADOR" --filter '{"status":{"eq":["ACTIVE"]}}' \
    --query "findings[].{recurso:resource, tipo:resourceType, estado:status}" --output table
fi

echo "== Validar una política antes de aplicarla =="
echo "aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document file://ejemplos/json/politica-app-minima.json"
