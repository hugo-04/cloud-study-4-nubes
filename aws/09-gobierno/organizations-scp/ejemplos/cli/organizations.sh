#!/usr/bin/env bash
# Comandos de ejemplo para Organizations (ejecutar con credenciales de la cuenta de administración).
set -euo pipefail

aws organizations describe-organization --query 'Organization.{Id:Id,Modo:FeatureSet,Admin:MasterAccountId}'
ROOT=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations list-roots --query 'Roots[0].PolicyTypes'          # ¿SERVICE_CONTROL_POLICY en ENABLED?

# Árbol: OU de la raíz y cuentas
aws organizations list-organizational-units-for-parent --parent-id "$ROOT" --query 'OrganizationalUnits[].{Id:Id,Nombre:Name}' --output table
aws organizations list-accounts --query 'Accounts[].{Id:Id,Nombre:Name,Estado:Status}' --output table

# Habilitar el tipo SCP (una sola vez)
# aws organizations enable-policy-type --root-id "$ROOT" --policy-type SERVICE_CONTROL_POLICY

# Crear y adjuntar una SCP (primero a una OU de ENSAYO)
# POL=$(aws organizations create-policy --name proteger-seguridad --description "Protege trazas y Config" \
#   --type SERVICE_CONTROL_POLICY --content file://../json/scp-proteger-seguridad.json --query 'Policy.PolicySummary.Id' --output text)
# aws organizations attach-policy --policy-id "$POL" --target-id ou-xxxx-yyyyyyyy

# ¿Qué SCP afectan a una cuenta? (directas; revisa también las de sus OU)
# aws organizations list-policies-for-target --target-id 111122223333 --filter SERVICE_CONTROL_POLICY

# Corregir un bloqueo: desadjuntar (desde la cuenta de administración)
# aws organizations detach-policy --policy-id p-xxxxxxxx --target-id ou-xxxx-yyyyyyyy

# Estado de la creación de una cuenta
# aws organizations describe-create-account-status --create-account-request-id car-xxxxxxxx
