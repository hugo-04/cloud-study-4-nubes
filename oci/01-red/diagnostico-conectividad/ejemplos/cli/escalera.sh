#!/usr/bin/env bash
# Escalera de diagnóstico desde el recurso que falla. Uso: ./escalera.sh <host> <puerto> [tls]
set -uo pipefail
H="${1:?host}"; P="${2:?puerto}"; TLS="${3:-}"
echo "1) DNS"; IPS=$(getent ahosts "$H" | awk '{print $1}' | sort -u); [ -z "$IPS" ] && { echo "  FALLA: no resuelve"; exit 1; }; echo "  $IPS"
IP=$(echo "$IPS" | head -1)
echo "4) Puerto $IP:$P (distingue timeout de rechazo)"
if timeout 5 bash -c "</dev/tcp/$IP/$P" 2>/dev/null; then echo "  abierto"; else
  rc=$?; [ $rc -eq 124 ] && echo "  TIMEOUT: ruta o reglas de seguridad (escalones 2-3)" || echo "  RECHAZADA: la red llega, nadie escucha (escalón 4)"; exit 1; fi
if [ -n "$TLS" ]; then echo "5) TLS"; echo | openssl s_client -connect "$H:$P" -servername "$H" -verify_hostname "$H" 2>/dev/null | grep -E "Verify return code|subject=|notAfter" ; fi
echo "6) Si todo lo anterior está bien y la API responde 401/403: es identidad (política IAM / grupo dinámico)."
