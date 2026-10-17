#!/usr/bin/env bash
# Diagnóstico y operación de ELB (ALB/NLB).
set -euo pipefail
NOMBRE="${1:-prod-tienda-publico}"

LB=$(aws elbv2 describe-load-balancers --names "$NOMBRE" --query "LoadBalancers[0].LoadBalancerArn" --output text)
echo "== Balanceador =="
aws elbv2 describe-load-balancers --load-balancer-arns "$LB" \
  --query "LoadBalancers[0].{tipo:Type, esquema:Scheme, estado:State.Code, dns:DNSName, zonas:AvailabilityZones[].ZoneName}" --output table

echo "== Listeners y reglas =="
for L in $(aws elbv2 describe-listeners --load-balancer-arn "$LB" --query "Listeners[].ListenerArn" --output text); do
  aws elbv2 describe-rules --listener-arn "$L" \
    --query "Rules[].{prioridad:Priority, condiciones:Conditions[].Values[], accion:Actions[0].Type}" --output json
done

echo "== Salud de los destinos (la primera pista ante un 502/503) =="
for TG in $(aws elbv2 describe-target-groups --load-balancer-arn "$LB" --query "TargetGroups[].TargetGroupArn" --output text); do
  echo "-- $TG"
  aws elbv2 describe-target-health --target-group-arn "$TG" \
    --query "TargetHealthDescriptions[].{destino:Target.Id, estado:TargetHealth.State, motivo:TargetHealth.Reason, detalle:TargetHealth.Description}" --output table
done

cat <<'DOC'

== Comandos útiles (copiar y adaptar) ==
# Cambiar el reparto canary 50/50 (pesos de la regla):
aws elbv2 modify-rule --rule-arn <regla> --actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"<tg-estable>","Weight":50},{"TargetGroupArn":"<tg-canary>","Weight":50}]}}]'

# Atributos clave:
aws elbv2 describe-load-balancer-attributes --load-balancer-arn <arn> --query "Attributes[?Key=='idle_timeout.timeout_seconds']"
aws elbv2 modify-target-group-attributes --target-group-arn <tg> --attributes Key=deregistration_delay.timeout_seconds,Value=30

# Logs de acceso con Athena o descarga directa; campos útiles: elb_status_code, target_status_code, target_processing_time
DOC
