#!/usr/bin/env bash
# Pruebas de STS. No modifica nada.
set -euo pipefail

echo "== ¿Quién soy? =="
aws sts get-caller-identity --output table

ROL="${1:-arn:aws:iam::444455556666:role/lector-logs}"
EXTERNAL_ID="${EXTERNAL_ID:-}"

echo "== Asumir el rol y ver cuándo caduca (las credenciales NO se imprimen) =="
ARGS=(--role-arn "$ROL" --role-session-name "diagnostico-${USER:-persona}" --duration-seconds 900)
[ -n "$EXTERNAL_ID" ] && ARGS+=(--external-id "$EXTERNAL_ID")
aws sts assume-role "${ARGS[@]}" --query "{vence:Credentials.Expiration, sesion:AssumedRoleUser.Arn}" --output table

cat <<'CFG'

# ~/.aws/config: perfil que asume el rol automáticamente y refresca
[profile lector-logs]
role_arn = arn:aws:iam::444455556666:role/lector-logs
source_profile = default
role_session_name = lectura-logs-persona
external_id = <valor-secreto>
duration_seconds = 3600
sts_regional_endpoints = regional
CFG

echo
echo "== Descifrar un mensaje de error codificado (permiso sts:DecodeAuthorizationMessage) =="
echo "aws sts decode-authorization-message --encoded-message <MENSAJE> --query DecodedMessage --output text | jq ."
