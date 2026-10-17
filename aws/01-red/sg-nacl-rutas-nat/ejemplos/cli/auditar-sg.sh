#!/usr/bin/env bash
# Auditoría de grupos de seguridad. SOLO LECTURA. Requiere ec2:Describe*.
set -euo pipefail
VPC="${1:?uso: $0 <vpc-id>}"

echo "== Reglas de ENTRADA abiertas a internet (excepto 80/443) =="
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" --query 'SecurityGroups[].GroupId' --output text | tr '\t' ',')" \
  --query "SecurityGroupRules[?IsEgress==\`false\` && (CidrIpv4=='0.0.0.0/0' || CidrIpv6=='::/0') && !(FromPort==\`80\` || FromPort==\`443\`)].{sg:GroupId, proto:IpProtocol, desde:FromPort, hasta:ToPort, descripcion:Description}" \
  --output table

echo "== SG sin interfaces asociadas (candidatos a limpiar) =="
USADOS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --query "NetworkInterfaces[].Groups[].GroupId" --output text | tr '\t' '\n' | sort -u)
TODOS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text | tr '\t' '\n' | sort -u)
comm -13 <(echo "$USADOS") <(echo "$TODOS") || true

echo "== Reglas con todos los puertos (protocolo -1) =="
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$(echo "$TODOS" | paste -sd, -)" \
  --query "SecurityGroupRules[?IpProtocol=='-1' && IsEgress==\`false\`].{sg:GroupId, origen:CidrIpv4}" --output table

echo "== Métrica de puertos agotados en NAT (última hora) =="
for NAT in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" --query "NatGateways[?State=='available'].NatGatewayId" --output text); do
  echo "NAT $NAT"
  aws cloudwatch get-metric-statistics --namespace AWS/NATGateway --metric-name ErrorPortAllocation \
    --dimensions Name=NatGatewayId,Value="$NAT" \
    --start-time "$(date -u -d '-1 hour' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 300 --statistics Sum --query "Datapoints[].Sum" --output text
done
