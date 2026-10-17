#!/usr/bin/env bash
# Verifica identidad por pod en EKS. SOLO LECTURA.
# Requiere kubectl apuntando al clúster y permisos de lectura en EKS/IAM.
set -euo pipefail
CLUSTER="${1:?uso: $0 <cluster> <namespace> <pod>}"
NS="${2:?}"
POD="${3:?}"

echo "== Complemento del agente de Pod Identity =="
aws eks describe-addon --cluster-name "$CLUSTER" --addon-name eks-pod-identity-agent \
  --query "addon.{estado:status, version:addonVersion}" --output table || echo "(no instalado)"

echo "== Asociaciones de Pod Identity =="
aws eks list-pod-identity-associations --cluster-name "$CLUSTER" \
  --query "associations[].{ns:namespace, sa:serviceAccount, id:associationId}" --output table

echo "== Proveedor OIDC del clúster (IRSA) =="
aws eks describe-cluster --name "$CLUSTER" --query "cluster.identity.oidc.issuer" --output text
aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[].Arn" --output text

echo "== Variables de credenciales dentro del pod =="
kubectl -n "$NS" exec "$POD" -- sh -c 'env | grep -E "^AWS_(ROLE_ARN|WEB_IDENTITY_TOKEN_FILE|CONTAINER_CREDENTIALS_FULL_URI|CONTAINER_AUTHORIZATION_TOKEN_FILE)" | sed "s/=.*/=<presente>/"' || echo "(sin variables de credenciales: el pod caerá al rol del nodo)"

echo "== ¿Quién cree AWS que es el pod? (requiere AWS CLI dentro de la imagen) =="
kubectl -n "$NS" exec "$POD" -- aws sts get-caller-identity 2>/dev/null || echo "Sin AWS CLI en la imagen: usa el endpoint /iam/identidad de la aplicación (ver uso en Java)"

echo "== Opciones del IMDS del nodo (debe ser IMDSv2 y salto 1) =="
echo "aws ec2 describe-instances --filters Name=tag:eks:cluster-name,Values=$CLUSTER --query 'Reservations[].Instances[].MetadataOptions'"
