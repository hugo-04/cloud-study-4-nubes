#!/usr/bin/env bash
# Comprobaciones de DNS y ruta. Ejecuta DENTRO del pod/VM: ./dns.sh <fqdn> [puerto]
set -euo pipefail
H="${1:?nombre}"; P="${2:-443}"
echo "== Resolución"
getent hosts "$H" || { echo "NO RESUELVE"; exit 1; }
IP=$(getent hosts "$H" | awk '{print $1; exit}')
case "$IP" in
  10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) echo "IP privada: $IP" ;;
  *) echo "IP pública o inesperada: $IP (¿se está usando el nombre público?)" ;;
esac
echo "== Conexión TCP a $IP:$P"
timeout 5 bash -c "</dev/tcp/$IP/$P" && echo "abierto" || echo "sin respuesta (timeout) o rechazado"
echo "== Zonas privadas del compartimento (con la CLI de OCI)"
echo "oci dns zone list -c <compartment-ocid> --scope PRIVATE --all"
