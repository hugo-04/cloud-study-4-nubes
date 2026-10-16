#!/usr/bin/env bash
# AKS de producción (referencia): VNet propia, Azure CNI Overlay + Cilium, Entra ID + Azure RBAC sin cuentas
# locales, 3 zonas, pools system/user/spot, ACR, KEDA, Key Vault CSI, Workload Identity y upgrades controlados.
# Ejecuta por secciones. Confirma flags con `az aks create --help` en tu versión de la CLI.
set -euo pipefail

RG=rg-estudio-aks
LOC=eastus2
VNET=vnet-aks
SNET=snet-aks-nodos
AKS=aks-modalima
ACR=acrmodalima$RANDOM
ADMIN_GROUP="${AKS_ADMIN_GROUP_ID:?define AKS_ADMIN_GROUP_ID (objectId del grupo de Entra ID)}"

az group create -n "$RG" -l "$LOC" >/dev/null

echo "== 1) Red: VNet y subred de nodos (con Overlay solo los NODOS usan IP de la subred) =="
az network vnet create -g "$RG" -n "$VNET" --address-prefixes 10.90.0.0/16 \
  --subnet-name "$SNET" --subnet-prefixes 10.90.0.0/22 >/dev/null
SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SNET" --query id -o tsv)

echo "== 2) ACR (Premium permite Private Link) =="
az acr create -g "$RG" -n "$ACR" --sku Premium --admin-enabled false >/dev/null

echo "== 3) Workspace de logs =="
LAW=$(az monitor log-analytics workspace create -g "$RG" -n law-aks -l "$LOC" --query id -o tsv)

echo "== 4) Clúster =="
az aks create -g "$RG" -n "$AKS" -l "$LOC" \
  --tier standard \
  --kubernetes-version "$(az aks get-versions -l "$LOC" --query "values[?isDefault].version | [0]" -o tsv)" \
  --nodepool-name system --node-count 3 --node-vm-size Standard_D2s_v5 --zones 1 2 3 \
  --enable-cluster-autoscaler --min-count 3 --max-count 5 \
  --nodepool-taints CriticalAddonsOnly=true:NoSchedule \
  --os-sku AzureLinux \
  --vnet-subnet-id "$SUBNET_ID" \
  --network-plugin azure --network-plugin-mode overlay --pod-cidr 192.168.0.0/16 \
  --network-dataplane cilium --network-policy cilium \
  --service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10 \
  --enable-aad --enable-azure-rbac --aad-admin-group-object-ids "$ADMIN_GROUP" --disable-local-accounts \
  --enable-oidc-issuer --enable-workload-identity \
  --enable-addons azure-keyvault-secrets-provider --enable-secret-rotation --rotation-poll-interval 2m \
  --enable-keda \
  --enable-azure-monitor-metrics \
  --enable-addons monitoring --workspace-resource-id "$LAW" \
  --attach-acr "$ACR" \
  --auto-upgrade-channel patch --node-os-upgrade-channel NodeImage \
  --generate-ssh-keys
# Clúster PRIVADO (el API server solo con IP privada): añade --enable-private-cluster y ejecuta kubectl desde la VNet.
# API pública restringida:  --api-server-authorized-ip-ranges 203.0.113.0/24
# Salida por NAT Gateway:   asocia un NAT Gateway a la subred y usa --outbound-type userAssignedNATGateway

echo "== 5) Pools de usuario: normal y spot para batch =="
az aks nodepool add -g "$RG" --cluster-name "$AKS" -n userapi --mode User \
  --node-vm-size Standard_D4s_v5 --zones 1 2 3 \
  --enable-cluster-autoscaler --min-count 2 --max-count 10 \
  --max-surge 33% --labels carga=api --os-sku AzureLinux --vnet-subnet-id "$SUBNET_ID"

az aks nodepool add -g "$RG" --cluster-name "$AKS" -n batch --mode User \
  --node-vm-size Standard_D4s_v5 \
  --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --enable-cluster-autoscaler --min-count 0 --max-count 5 \
  --node-taints kubernetes.azure.com/scalesetpriority=spot:NoSchedule \
  --labels carga=batch --vnet-subnet-id "$SUBNET_ID"

echo "== 6) Ventana de mantenimiento (actualizaciones solo los sábados de madrugada) =="
az aks maintenanceconfiguration add -g "$RG" --cluster-name "$AKS" -n aksManagedAutoUpgradeSchedule \
  --schedule-type Weekly --day-of-week Saturday --interval-weeks 1 --start-time 02:00 --duration 4 --utc-offset=-05:00

echo "== 7) Acceso: tú y tu equipo (Azure RBAC for Kubernetes) =="
AKSID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
YO=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$YO" --assignee-principal-type User \
  --role "Azure Kubernetes Service Cluster User Role" --scope "$AKSID" >/dev/null
az role assignment create --assignee-object-id "$YO" --assignee-principal-type User \
  --role "Azure Kubernetes Service RBAC Writer" --scope "$AKSID/namespaces/modalima" >/dev/null || true
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli          # usa tu sesión de `az login`
kubectl get nodes -o wide

echo "== 8) Aplicar los manifiestos de ejemplo =="
# kubectl apply -f ../yaml/00-namespace.yaml
# kubectl apply -f ../yaml/10-deployment.yaml
# kubectl apply -f ../yaml/20-hpa-pdb.yaml
# kubectl apply -f ../yaml/30-networkpolicy.yaml

echo "== 9) Ahorro en laboratorio =="
# az aks stop  -g "$RG" -n "$AKS"
# az aks start -g "$RG" -n "$AKS"

echo "== 10) Actualizar manualmente (cuando no usas canal automático) =="
# az aks get-upgrades -g "$RG" -n "$AKS" -o table
# az aks upgrade -g "$RG" -n "$AKS" --kubernetes-version <versión>

echo "Limpieza: az group delete -n $RG --yes --no-wait"
