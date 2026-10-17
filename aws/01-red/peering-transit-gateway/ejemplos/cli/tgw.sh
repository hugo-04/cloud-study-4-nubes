#!/usr/bin/env bash
# Revisa un Transit Gateway: adjuntos, asociaciones y rutas. SOLO LECTURA.
set -euo pipefail
TGW="${1:?uso: $0 <tgw-id>}"

echo "== Adjuntos y su estado =="
aws ec2 describe-transit-gateway-attachments --filters "Name=transit-gateway-id,Values=$TGW" \
  --query "TransitGatewayAttachments[].{id:TransitGatewayAttachmentId, tipo:ResourceType, recurso:ResourceId, estado:State, tabla:Association.TransitGatewayRouteTableId}" \
  --output table

for RT in $(aws ec2 describe-transit-gateway-route-tables --filters "Name=transit-gateway-id,Values=$TGW" --query "TransitGatewayRouteTables[].TransitGatewayRouteTableId" --output text); do
  echo "== Rutas de la tabla $RT =="
  aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id "$RT" \
    --filters "Name=state,Values=active,blackhole" \
    --query "Routes[].{cidr:DestinationCidrBlock, estado:State, tipo:Type, adjunto:TransitGatewayAttachments[0].TransitGatewayAttachmentId}" --output table
done
