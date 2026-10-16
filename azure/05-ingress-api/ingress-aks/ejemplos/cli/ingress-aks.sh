#!/usr/bin/env bash
# Ingress en AKS: add-on de application routing, entrada interna, certificado de Key Vault,
# y Application Gateway for Containers con Gateway API. Ejecuta por secciones.
# Confirma flags con `az aks approuting --help` y la guía de AGC de tu versión.
set -euo pipefail

RG=rg-estudio-aks
AKS=aks-modalima
KV=kv-modalima-estudio01
DNS_RG=rg-dns
ZONA=modalima.example

echo "== 1) Habilitar el add-on de application routing =="
az aks approuting enable -g "$RG" -n "$AKS"
kubectl get ingressclass

echo "== 2) Integrar Key Vault (certificados) y Azure DNS =="
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)
az aks approuting update -g "$RG" -n "$AKS" --enable-kv --attach-kv "$KV_ID"
ZONA_ID=$(az network dns zone show -g "$DNS_RG" -n "$ZONA" --query id -o tsv)
az aks approuting zone add -g "$RG" -n "$AKS" --ids "$ZONA_ID" --attach-zones

echo "== 3) Aplicar Services e Ingress =="
kubectl apply -f ../yaml/10-ingress-approuting.yaml
kubectl get ingress -n modalima

echo "== 4) Probar sin tocar el DNS =="
IP=$(kubectl get ingress api-modalima -n modalima -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -vk --resolve api.modalima.example:443:"$IP" https://api.modalima.example/pedidos/health

echo "== 5) Application Gateway for Containers: instalar el ALB Controller =="
# Antes: aplica ../terraform (recurso AGC, frontend, asociación, identidad).
ALB_CLIENT_ID=$(tofu -chdir=../terraform output -raw alb_client_id 2>/dev/null || echo "<client-id>")
helm install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller \
  --namespace azure-alb-system --create-namespace \
  --set albController.namespace=azure-alb-system \
  --set albController.podIdentity.clientID="$ALB_CLIENT_ID"
kubectl get pods -n azure-alb-system
kubectl get gatewayclass            # azure-alb-external

echo "== 6) Gateway y rutas =="
kubectl create namespace plataforma --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace modalima gateway-acceso=permitido --overwrite
kubectl apply -f ../yaml/20-gateway-api-agc.yaml
kubectl get gateway,httproute -A
kubectl describe gateway gw-modalima -n plataforma | sed -n '/Status:/,$p'
