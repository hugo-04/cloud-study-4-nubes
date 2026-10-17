#!/usr/bin/env bash
# Instalar el AWS Load Balancer Controller (ejemplo). Ajusta CLUSTER, VPC_ID y la versión.
set -euo pipefail

CLUSTER="${CLUSTER:-tienda}"
REGION="${REGION:-us-east-1}"
VPC_ID="${VPC_ID:?define VPC_ID}"
VERSION="${LBC_VERSION:?define la versión del controlador, p. ej. v2.x.y (verifica la última)}"

# 1) Política de IAM oficial de ESA versión (el JSON cambia entre versiones)
curl -fsSL -o iam_policy.json \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${VERSION}/docs/install/iam_policy.json"
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# 2) Rol + Pod Identity: ver ../terraform/main.tf (terraform apply)

# 3) Instalar con Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set replicaCount=2

# 4) Comprobar
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=20

# Diagnóstico habitual
#   kubectl describe ingress -n pedidos pedidos
#   kubectl get targetgroupbindings -A
#   kubectl describe pod -n pedidos <pod>      # condición del readiness gate
