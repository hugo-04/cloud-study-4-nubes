#!/usr/bin/env bash
# Operación diaria de Lambda.
set -euo pipefail
FN="${1:-prod-pedidos-procesar}"

echo "== Configuración =="
aws lambda get-function-configuration --function-name "$FN" \
  --query "{runtime:Runtime, memoria:MemorySize, timeout:Timeout, snapStart:SnapStart.ApplyOn, estado:State, ultimaActualizacion:LastUpdateStatus, vpc:VpcConfig.VpcId}" --output table

echo "== Alias y versiones =="
aws lambda list-aliases --function-name "$FN" --query "Aliases[].{alias:Name, version:FunctionVersion, reparto:RoutingConfig.AdditionalVersionWeights}" --output table

echo "== Origenes de eventos =="
aws lambda list-event-source-mappings --function-name "$FN" \
  --query "EventSourceMappings[].{origen:EventSourceArn, estado:State, lote:BatchSize, fallosParciales:FunctionResponseTypes, maxConcurrencia:ScalingConfig.MaximumConcurrency}" --output table

echo "== Concurrencia reservada =="
aws lambda get-function-concurrency --function-name "$FN" --output text || true

cat <<'DOC'

== Comandos útiles (copiar y adaptar) ==
# Invocar con el evento de ejemplo:
aws lambda invoke --function-name prod-pedidos-procesar --payload fileb://ejemplos/json/evento-sqs.json --cli-binary-format raw-in-base64-out /tmp/salida.json && cat /tmp/salida.json

# Desplegar un JAR nuevo, publicar versión y mover el alias (con 10 % de tráfico a la nueva):
aws lambda update-function-code --function-name prod-pedidos-procesar --s3-bucket mi-bucket-artefactos --s3-key pedidos/1.4.0.jar
aws lambda wait function-updated --function-name prod-pedidos-procesar
V=$(aws lambda publish-version --function-name prod-pedidos-procesar --query Version --output text)
aws lambda update-alias --function-name prod-pedidos-procesar --name prod --routing-config "AdditionalVersionWeights={\"$V\"=0.1}"

# Logs en vivo:
aws logs tail /aws/lambda/prod-pedidos-procesar --follow --since 10m
# Solo el resumen de cada invocación (duración, memoria usada, Init):
aws logs filter-log-events --log-group-name /aws/lambda/prod-pedidos-procesar --filter-pattern '"REPORT RequestId"' --max-items 10
DOC
