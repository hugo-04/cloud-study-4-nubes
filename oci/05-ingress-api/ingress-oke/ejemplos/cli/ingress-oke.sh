#!/usr/bin/env bash
# Diagnóstico de la entrada a OKE. Uso: ./ingress-oke.sh <namespace> <ingress|service> <nombre>
set -euo pipefail
NS="${1:?namespace}"; TIPO="${2:?ingress|service}"; N="${3:?nombre}"
kubectl -n "$NS" get "$TIPO" "$N" -o wide
echo "== Eventos (errores del controlador aparecen aquí)"
kubectl -n "$NS" describe "$TIPO" "$N" | sed -n '/Events:/,$p'
echo "== Endpoints listos"
kubectl -n "$NS" get endpointslices -o wide | head -20
