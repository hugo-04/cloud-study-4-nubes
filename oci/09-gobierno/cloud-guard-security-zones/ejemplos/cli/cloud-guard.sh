#!/usr/bin/env bash
# Cloud Guard. Uso: ./cloud-guard.sh <compartment-ocid>
set -euo pipefail
C="${1:?compartment}"
oci cloud-guard configuration get -c "$C" --query 'data.{estado:status,region:"reporting-region"}' --output table || true
echo "== Problemas abiertos CRITICAL/HIGH"
oci cloud-guard problem list -c "$C" --compartment-id-in-subtree true --access-level ACCESSIBLE --lifecycle-detail OPEN --all \
  --query 'data.items[?"risk-level"==`CRITICAL` || "risk-level"==`HIGH`].{riesgo:"risk-level",regla:"detector-rule-id",recurso:"resource-name"}' --output table
