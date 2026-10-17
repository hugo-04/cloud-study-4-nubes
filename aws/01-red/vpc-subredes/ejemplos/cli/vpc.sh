#!/usr/bin/env bash
# Revisa una VPC de la tienda. SOLO LECTURA. Requiere: aws configurado (perfil) y permisos ec2:Describe*.
set -euo pipefail

ENTORNO="${1:?uso: $0 <dev|prod>}"
echo "== ¿Dónde estoy parado? =="
aws sts get-caller-identity --query "{cuenta:Account, identidad:Arn}" --output table

VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-tienda-${ENTORNO}" --query "Vpcs[0].VpcId" --output text)
echo "VPC: $VPC"

echo "== Subredes: nivel, zona, CIDR e IP libres =="
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" \
  --query "Subnets[].{nivel:Tags[?Key=='nivel']|[0].Value, zona:AvailabilityZone, cidr:CidrBlock, libres:AvailableIpAddressCount}" \
  --output table

echo "== Rutas de cada tabla (¿a dónde sale cada nivel?) =="
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" \
  --query "RouteTables[].{tabla:Tags[?Key=='Name']|[0].Value, rutas:Routes[?DestinationCidrBlock=='0.0.0.0/0'].[GatewayId,NatGatewayId][]|[0]}" \
  --output table

echo "== NAT Gateways =="
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" \
  --query "NatGateways[].{id:NatGatewayId, estado:State, subred:SubnetId}" --output table

echo "== Atributos de DNS =="
aws ec2 describe-vpc-attribute --vpc-id "$VPC" --attribute enableDnsSupport --query "EnableDnsSupport.Value"
aws ec2 describe-vpc-attribute --vpc-id "$VPC" --attribute enableDnsHostnames --query "EnableDnsHostnames.Value"

echo "== Flow Logs =="
aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC" --query "FlowLogs[].{id:FlowLogId, estado:FlowLogStatus, destino:LogDestination}" --output table
