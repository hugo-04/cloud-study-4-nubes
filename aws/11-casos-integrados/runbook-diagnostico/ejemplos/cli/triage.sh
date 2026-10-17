#!/usr/bin/env bash
# Primeros cinco minutos de un incidente (solo lectura). Uso: ./triage.sh <sufijo-alb> <cola> <dlq> <grupo-logs>
# Requiere AWS CLI v2 y permisos de solo lectura (ver "Seguridad" del README).
set -euo pipefail
ALB="${1:?sufijo del ALB, ej. app/prod-tienda/50dc6c495c0c9188}"
COLA="${2:?nombre de la cola}"
DLQ="${3:?nombre de la DLQ}"
GRUPO="${4:?grupo de logs}"
DESDE=$(date -u -d '-60 minutes' +%Y-%m-%dT%H:%M:%SZ)
AHORA=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "== 1. ¿Qué cambió en los últimos 60 min? (solo eventos que modifican)"
aws cloudtrail lookup-events --start-time "$DESDE" \
  --lookup-attributes AttributeKey=ReadOnly,AttributeValue=false --max-results 50 \
  --query 'Events[].{hora:EventTime,quien:Username,evento:EventName}' --output table

echo "== 2. ¿Cuántos 5xx por minuto? (últimos 30 min)"
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value="$ALB" --start-time "$(date -u -d '-30 minutes' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$AHORA" --period 60 --statistics Sum --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output text

echo "== 3. ¿Salud de los destinos del balanceador?"
ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerArn,'$ALB')].LoadBalancerArn" --output text)
for tg in $(aws elbv2 describe-target-groups --load-balancer-arn "$ARN" --query 'TargetGroups[].TargetGroupArn' --output text); do
  aws elbv2 describe-target-health --target-group-arn "$tg" \
    --query 'TargetHealthDescriptions[].{destino:Target.Id,estado:TargetHealth.State,motivo:TargetHealth.Reason}' --output table
done

echo "== 4. Facturación: cola y fallidos"
for q in "$COLA" "$DLQ"; do
  url=$(aws sqs get-queue-url --queue-name "$q" --query QueueUrl --output text)
  aws sqs get-queue-attributes --queue-url "$url" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed \
    --query 'Attributes' --output json
done

echo "== 5. Errores recientes por excepción (Logs Insights, espera hasta 60 s)"
ID=$(aws logs start-query --log-group-name "$GRUPO" --start-time "$(date -u -d '-30 minutes' +%s)" --end-time "$(date -u +%s)" \
  --query-string 'filter nivel = "ERROR" | stats count(*) as veces by excepcion | sort veces desc | limit 10' --query queryId --output text)
for _ in $(seq 1 30); do
  ESTADO=$(aws logs get-query-results --query-id "$ID" --query status --output text)
  [ "$ESTADO" = "Complete" ] && break
  [ "$ESTADO" = "Failed" ] && { echo "la consulta falló"; exit 1; }
  sleep 2
done
aws logs get-query-results --query-id "$ID" --query 'results[].[0].value,[1].value' --output text

echo "== 6. ¿Incidente del proveedor? (AWS Health, abiertos)"
aws health describe-events --region us-east-1 --filter eventStatusCodes=open --query 'events[].{servicio:service,region:region,tipo:eventTypeCode}' --output table \
  || echo "AWS Health API requiere plan Business/Enterprise; usa el panel de AWS Health de la consola."
