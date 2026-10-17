#!/usr/bin/env bash
# Revisa los endpoints de una VPC y verifica el DNS privado. SOLO LECTURA.
# Para la parte de DNS ejecútalo DESDE DENTRO de la VPC (contenedor, bastión con SSM).
set -euo pipefail
VPC="${1:?uso: $0 <vpc-id> [region]}"
REGION="${2:-us-east-1}"

echo "== Endpoints de la VPC =="
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" --region "$REGION" \
  --query "VpcEndpoints[].{servicio:ServiceName, tipo:VpcEndpointType, estado:State, dnsPrivado:PrivateDnsEnabled}" --output table

echo "== Endpoints de interfaz y sus subredes (¿una por AZ usada?) =="
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" "Name=vpc-endpoint-type,Values=Interface" --region "$REGION" \
  --query "VpcEndpoints[].{servicio:ServiceName, subredes:length(SubnetIds)}" --output table

echo "== DNS: ¿resuelven a IP privada? (desde dentro de la VPC) =="
for SVC in sqs secretsmanager sts logs ecr.api; do
  H="$SVC.$REGION.amazonaws.com"
  IP=$( (getent hosts "$H" || true) | awk '{print $1}' | head -1)
  case "$IP" in
    10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*) echo "OK     $H -> $IP (privada)";;
    "") echo "FALLA  $H no resuelve";;
    *) echo "PÚBLICA $H -> $IP (revisa DNS privado)";;
  esac
done
