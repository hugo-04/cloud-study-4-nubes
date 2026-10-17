#!/usr/bin/env bash
# ¿Con qué identidad estoy? Uso: ./autenticacion.sh [perfil|instance_principal]
set -euo pipefail
if [ "${1:-}" = "instance_principal" ]; then A=(--auth instance_principal); else A=(--profile "${1:-DEFAULT}"); fi
oci "${A[@]}" iam region-subscription list --query 'data[].{region:"region-name",home:"is-home-region"}' --output table
echo "== API keys de un usuario de servicio:  oci iam user api-key list --user-id <ocid>"
