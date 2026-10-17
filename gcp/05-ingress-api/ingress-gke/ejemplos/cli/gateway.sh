#!/usr/bin/env bash
# Diagnóstico de Gateway API. Uso: ./gateway.sh <ns-gateway> <gateway> <ns-ruta> <ruta>
set -euo pipefail
kubectl -n "${1:?ns}" describe gateway "${2:?gateway}" | sed -n '/Status:/,$p'
kubectl -n "${3:?ns ruta}" get httproute "${4:?ruta}" -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
