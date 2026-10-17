#!/usr/bin/env bash
# Streaming. Uso: ./streaming.sh <stream-ocid>
set -euo pipefail
S="${1:?stream ocid}"
EP=$(oci streaming admin stream get --stream-id "$S" --query 'data."messages-endpoint"' --raw-output)
echo "== Endpoint: $EP"
V=$(printf '{"evento":"vista","sku":"POL-01"}' | base64 -w0); K=$(printf 'sesion-123' | base64 -w0)
oci streaming stream message put --stream-id "$S" --endpoint "$EP" --messages "[{\"key\":\"$K\",\"value\":\"$V\"}]"
C=$(oci streaming stream cursor create-cursor --stream-id "$S" --endpoint "$EP" --partition 0 --type TRIM_HORIZON --query data.value --raw-output)
oci streaming stream message get --stream-id "$S" --endpoint "$EP" --cursor "$C" --limit 5
