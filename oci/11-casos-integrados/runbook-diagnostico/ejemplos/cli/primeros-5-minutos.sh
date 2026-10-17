#!/usr/bin/env bash
# Primeros cinco minutos. Uso: ./primeros-5-minutos.sh <compartment-ocid> <lb-ocid> <backend-set>
set -uo pipefail
C="${1:?compartment}"; LB="${2:?lb}"; BS="${3:?backend set}"
INI=$(date -u -d '-15 minutes' +%Y-%m-%dT%H:%M:%SZ); FIN=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "== 1) Impacto: 5xx del LB (últimos 15 min)"
oci monitoring metric-data summarize-metrics-data -c "$C" --namespace oci_lbaas \
  --query-text "HttpResponses5xx[1m]{resourceId = \"$LB\"}.sum()" --start-time "$INI" --end-time "$FIN" \
  --query 'data[0]."aggregated-datapoints"[-5:]' 2>/dev/null || echo "no se pudo comprobar"
echo "== 2) Salud de backends"; oci lb backend-set-health get --load-balancer-id "$LB" --backend-set-name "$BS" || echo "no se pudo comprobar"
echo "== 3) ¿Qué cambió? (Audit, última hora)"
oci audit event list -c "$C" --start-time "$(date -u -d '-1 hour' +%FT%TZ)" --end-time "$FIN" --all \
  --query 'data[?!(starts_with(data."event-name",`Get`) || starts_with(data."event-name",`List`))].{t:"event-time",que:data."event-name",quien:data.identity."principal-name"}' --output table || true
echo "== 4) Pods:  kubectl -n tienda get pods -o wide; kubectl -n tienda rollout history deploy/pedidos"
