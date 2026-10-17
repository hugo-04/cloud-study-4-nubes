#!/usr/bin/env bash
# Operación diaria de ECS Fargate.
set -euo pipefail
CLUSTER="${1:-prod}"; SERVICIO="${2:-pedidos}"

echo "== Estado del servicio =="
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICIO" \
  --query "services[0].{deseadas:desiredCount, corriendo:runningCount, pendientes:pendingCount, despliegues:deployments[].{estado:rolloutState, tareas:runningCount, def:taskDefinition}}" --output json

echo "== Últimos eventos (la pista más rápida) =="
aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICIO" \
  --query "services[0].events[:8].[createdAt,message]" --output text

echo "== Tareas detenidas recientes y por qué =="
for t in $(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICIO" --desired-status STOPPED --query "taskArns[:5]" --output text); do
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$t" \
    --query "tasks[0].{motivo:stoppedReason, contenedores:containers[].{n:name, codigo:exitCode, razon:reason}}" --output json
done

cat <<'DOC'

== Comandos útiles (copiar y adaptar) ==
# Forzar un despliegue con la misma definición (re-lee secretos y reinicia tareas):
aws ecs update-service --cluster prod --service pedidos --force-new-deployment

# Tarea única (migración) con comando distinto:
aws ecs run-task --cluster prod --launch-type FARGATE --task-definition pedidos \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-aaa],securityGroups=[sg-bbb],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"app","command":["java","-jar","/app/migraciones.jar"]}]}'

# Shell dentro de un contenedor (requiere enable_execute_command y permisos SSM):
aws ecs execute-command --cluster prod --task <id> --container app --interactive --command "/bin/sh"

# Escalado manual temporal:
aws ecs update-service --cluster prod --service pedidos --desired-count 6
DOC
