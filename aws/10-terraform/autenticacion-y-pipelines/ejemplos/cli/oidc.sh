#!/usr/bin/env bash
# Verificación de la federación OIDC y de los roles del pipeline.
set -euo pipefail
CUENTA="$(aws sts get-caller-identity --query Account --output text)"
EMISOR="token.actions.githubusercontent.com"

echo "== 1. ¿Existe el proveedor OIDC de GitHub en esta cuenta? =="
aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '$EMISOR')]"
# Crear (una vez por cuenta; en la práctica lo hace Terraform):
# aws iam create-open-id-connect-provider --url "https://$EMISOR" --client-id-list sts.amazonaws.com

echo "== 2. Política de confianza del rol de apply (¿el sub es exacto?) =="
aws iam get-role --role-name terraform-apply-prod \
  --query 'Role.AssumeRolePolicyDocument.Statement[].Condition' --output json

echo "== 3. ¿Qué podría hacer el rol de apply? (simulación, sin ejecutar nada) =="
aws iam simulate-principal-policy \
  --policy-source-arn "arn:aws:iam::${CUENTA}:role/terraform-apply-prod" \
  --action-names sqs:CreateQueue iam:CreateUser iam:CreateAccessKey organizations:CreateAccount \
  --query 'EvaluationResults[].{Accion:EvalActionName,Decision:EvalDecision}' --output table

echo "== 4. ¿Quién asumió los roles del pipeline? (CloudTrail, 90 días) =="
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 20 \
  --query 'Events[].{Hora:EventTime,Usuario:Username}' --output table

echo "== 5. Puerta de seguridad sobre un plan guardado =="
terraform show -json tfplan > plan.json
jq -r '.resource_changes[] | select(.change.actions != ["no-op"] and .change.actions != ["read"])
       | "\(.change.actions | join(","))\t\(.address)"' plan.json | sort

echo "== 6. ¿El plan destruye recursos con datos? =="
jq -r '.resource_changes[]
       | select(.change.actions | index("delete"))
       | select(.type | IN("aws_db_instance","aws_rds_cluster","aws_dynamodb_table","aws_s3_bucket","aws_kms_key"))
       | .address' plan.json
