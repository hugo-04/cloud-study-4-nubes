#!/usr/bin/env bash
# ECS Express Mode: crear, consultar, actualizar y borrar. (Verifica los nombres de las opciones en la versión de tu CLI.)
set -euo pipefail
ARN="${1:-}"

cat <<'DOC'
== Crear (todo el detalle está en ejemplos/json/servicio-express.json) ==
aws ecs create-express-gateway-service --cli-input-json file://ejemplos/json/servicio-express.json

== Crear lo mínimo ==
aws ecs create-express-gateway-service \
  --service-name pedidos \
  --execution-role-arn arn:aws:iam::111122223333:role/prod-pedidos-ejecucion \
  --infrastructure-role-arn arn:aws:iam::111122223333:role/prod-express-infraestructura \
  --primary-container '{"image":"111122223333.dkr.ecr.us-east-1.amazonaws.com/pedidos:1.4.0","containerPort":8080}' \
  --health-check-path /actuator/health/readiness
DOC

if [ -n "$ARN" ]; then
  echo "== Estado y endpoint =="
  aws ecs describe-express-gateway-service --service-arn "$ARN" \
    --query "service.{estado:status.statusCode, motivo:status.statusReason, endpoints:activeConfigurations[0].ingressPaths[].endpoint, cpu:activeConfigurations[0].cpu, memoria:activeConfigurations[0].memory}" --output json
else
  echo "(pasa el ARN del servicio como primer argumento para ver su estado y endpoint)"
fi

cat <<'DOC'

== Actualizar la imagen (despliegue canary) ==
aws ecs update-express-gateway-service --service-arn <arn> \
  --primary-container '{"image":"111122223333.dkr.ecr.us-east-1.amazonaws.com/pedidos:1.5.0","containerPort":8080}'

== Ajustar el escalado ==
aws ecs update-express-gateway-service --service-arn <arn> \
  --scaling-target '{"minTaskCount":3,"maxTaskCount":15,"autoScalingMetric":"AVERAGE_CPU","autoScalingTargetValue":55}'

== Borrar ==
aws ecs delete-express-gateway-service --service-arn <arn>
DOC
