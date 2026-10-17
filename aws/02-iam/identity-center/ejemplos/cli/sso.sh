#!/usr/bin/env bash
# Configura y prueba el acceso por Identity Center desde la CLI.
set -euo pipefail

cat <<'CFG'
# ~/.aws/config  (un sso-session compartido y un perfil por cuenta/rol)
[sso-session modalima]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile dev-desarrollo]
sso_session = modalima
sso_account_id = 111122223333
sso_role_name = Desarrollo
region = us-east-1

[profile prod-lectura]
sso_session = modalima
sso_account_id = 444455556666
sso_role_name = SoloLectura
region = us-east-1
CFG

echo
echo "== Iniciar sesión (abre el navegador, pide MFA) =="
echo "aws sso login --sso-session modalima"
echo
echo "== Probar quién eres con un perfil =="
echo "aws sts get-caller-identity --profile dev-desarrollo"
echo
echo "== Listar las cuentas y roles a los que tienes acceso =="
echo "TOKEN=\$(ls -t ~/.aws/sso/cache/*.json | head -1 | xargs jq -r .accessToken)"
echo "aws sso list-accounts --access-token \"\$TOKEN\" --region us-east-1 --output table"
echo
echo "== Exportar credenciales temporales para una herramienta que no entienda SSO =="
echo "aws configure export-credentials --profile dev-desarrollo --format env"
echo
echo "== Cerrar sesión =="
echo "aws sso logout"
