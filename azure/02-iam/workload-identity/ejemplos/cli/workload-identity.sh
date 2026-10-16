#!/usr/bin/env bash
# Workload Identity en AKS: habilitar OIDC, crear identidad, credencial federada y rol.
# Material de estudio. Verifica los flags con `az aks update --help` en tu version de CLI.
set -euo pipefail

RG=rg-estudio-wi
LOC=eastus2
AKS=aks-estudio-wi
NS=modalima
SA=sa-api
KV=kv-wi-$RANDOM$RANDOM

az group create -n "$RG" -l "$LOC" >/dev/null

# 1) Clúster con OIDC issuer y workload identity
az aks create -g "$RG" -n "$AKS" --node-count 1 --generate-ssh-keys \
  --enable-oidc-issuer --enable-workload-identity >/dev/null
OIDC=$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)
echo "Issuer: $OIDC"

# 2) Identidad de Azure para la aplicacion
az identity create -g "$RG" -n id-api-pedidos >/dev/null
CLIENT=$(az identity show -g "$RG" -n id-api-pedidos --query clientId -o tsv)
PRINCIPAL=$(az identity show -g "$RG" -n id-api-pedidos --query principalId -o tsv)

# 3) Key Vault con RBAC y rol para la identidad
az keyvault create -g "$RG" -n "$KV" -l "$LOC" --enable-rbac-authorization true >/dev/null
KVID=$(az keyvault show -n "$KV" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$KVID"

# 4) Credencial federada: confia en el ServiceAccount EXACTO
az identity federated-credential create --name fc-api \
  --identity-name id-api-pedidos -g "$RG" \
  --issuer "$OIDC" \
  --subject "system:serviceaccount:$NS:$SA" \
  --audiences api://AzureADTokenExchange

# 5) Kubernetes: namespace, ServiceAccount con el client-id y un pod de prueba
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
sed "s/__CLIENT_ID__/$CLIENT/" ../yaml/serviceaccount.yaml | kubectl apply -f -
kubectl apply -f ../yaml/deployment.yaml

echo "Cuando el pod este Running: kubectl -n $NS exec deploy/api -- env | grep AZURE_"

# Limpieza: az group delete -n "$RG" --yes --no-wait
