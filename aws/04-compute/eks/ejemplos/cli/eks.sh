#!/usr/bin/env bash
# Operación diaria de EKS.
set -euo pipefail
CLUSTER="${1:-prod-tienda}"

echo "== Datos del clúster =="
aws eks describe-cluster --name "$CLUSTER" \
  --query "cluster.{estado:status, version:version, endpoint:endpoint, publico:resourcesVpcConfig.endpointPublicAccess, privado:resourcesVpcConfig.endpointPrivateAccess}" --output table

echo "== Grupos de nodos y su salud =="
for ng in $(aws eks list-nodegroups --cluster-name "$CLUSTER" --query "nodegroups[]" --output text); do
  aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$ng" \
    --query "nodegroup.{nombre:nodegroupName, estado:status, version:version, escala:scalingConfig, problemas:health.issues}" --output json
done

echo "== Add-ons =="
aws eks list-addons --cluster-name "$CLUSTER" --query "addons[]" --output text | tr '\t' '\n' | while read -r a; do
  aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$a" \
    --query "addon.{nombre:addonName, version:addonVersion, estado:status}" --output text
done

echo "== Quién tiene acceso =="
aws eks list-access-entries --cluster-name "$CLUSTER" --output text

cat <<'DOC'

== Comandos útiles (copiar y adaptar) ==
aws eks update-kubeconfig --name prod-tienda --region us-east-1
kubectl auth whoami
kubectl get nodes -o wide
kubectl -n pedidos get pods -o wide
kubectl -n pedidos describe pod <pod>
kubectl -n pedidos logs <pod> --previous
kubectl -n pedidos rollout status deployment/pedidos
kubectl -n pedidos rollout undo deployment/pedidos
kubectl top pods -n pedidos

# Versiones de add-ons compatibles con tu versión de Kubernetes:
aws eks describe-addon-versions --kubernetes-version 1.34 --addon-name vpc-cni --query "addons[0].addonVersions[:3].addonVersion"
DOC
