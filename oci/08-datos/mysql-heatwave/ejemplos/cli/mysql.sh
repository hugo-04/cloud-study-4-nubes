#!/usr/bin/env bash
# MySQL HeatWave. Uso: ./mysql.sh <db-system-ocid>
set -euo pipefail
D="${1:?db system ocid}"
oci mysql db-system get --db-system-id "$D" \
  --query 'data.{nombre:"display-name",estado:"lifecycle-state",forma:"shape-name",ha:"is-highly-available",heatwave:"is-heat-wave-cluster-attached"}' --output table
oci mysql db-system get --db-system-id "$D" --query 'data.endpoints[].{host:hostname,ip:"ip-address",puerto:port,modos:modes}' --output table
echo "== Conexión de prueba:  mysqlsh --sql --ssl-mode=REQUIRED -h <ip> -u app_catalogo -p"
