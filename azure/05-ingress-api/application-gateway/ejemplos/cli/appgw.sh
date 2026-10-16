#!/usr/bin/env bash
# Application Gateway por CLI: diagnóstico y operaciones comunes sobre el gateway creado con ../terraform.
# Confirma flags con `az network application-gateway --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-agw
AGW=agw-modalima
WAF=waf-modalima

echo "== 1) Salud de los backends (lo primero ante un 502) =="
az network application-gateway show-backend-health -g "$RG" -n "$AGW" \
  --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].{servidor:address, salud:health, detalle:healthProbeLog}" -o table

echo "== 2) Estado de aprovisionamiento =="
az network application-gateway show -g "$RG" -n "$AGW" --query "{estado:provisioningState, op:operationalState, sku:sku.name}" -o table

echo "== 3) Sondas, configuración HTTP y listeners =="
az network application-gateway probe list -g "$RG" --gateway-name "$AGW" -o table
az network application-gateway http-settings list -g "$RG" --gateway-name "$AGW" -o table
az network application-gateway http-listener list -g "$RG" --gateway-name "$AGW" -o table

echo "== 4) Política WAF: modo y reglas gestionadas =="
az network application-gateway waf-policy show -g "$RG" -n "$WAF" --query "{modo:policySettings.mode, estado:policySettings.state}" -o table
az network application-gateway waf-policy managed-rule rule-set list -g "$RG" --policy-name "$WAF" -o table

echo "== 5) Pasar a Prevention (después de medir en Detection) =="
az network application-gateway waf-policy policy-setting update -g "$RG" --policy-name "$WAF" --mode Prevention --state Enabled

echo "== 6) Excluir un campo concreto de una regla (falso positivo) =="
az network application-gateway waf-policy managed-rule exclusion add -g "$RG" --policy-name "$WAF" \
  --match-variable RequestArgNames --selector-match-operator Equals --selector comentario

echo "== 7) Probar con la IP del gateway sin tocar el DNS =="
IP=$(az network public-ip show -g "$RG" -n pip-agw-modalima --query ipAddress -o tsv)
curl -sv --resolve api.modalima.example:443:"$IP" https://api.modalima.example/actuator/health/readiness -o /dev/null
openssl s_client -connect "$IP":443 -servername api.modalima.example </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates

echo "== 8) Reglas de NSG de la subred (revisa GatewayManager 65200-65535) =="
az network nsg rule list -g "$RG" --nsg-name nsg-agw -o table
