#!/usr/bin/env bash
# Operación de la organización (cuenta de administración). Solo lectura salvo donde se indica.

# 1. Cuentas y su estado
aws organizations list-accounts --query 'Accounts[].[Id,Name,Status]' --output table

# 2. ¿En qué OU está una cuenta?
aws organizations list-parents --child-id 111122223333

# 3. Crear una cuenta (ASÍNCRONO y casi irreversible: se hace por revisión, no a mano)
# aws organizations create-account --account-name pagos-dev --email aws+pagos-dev@modalima.example \
#     --tags Key=equipo,Value=pagos Key=centroDeCostos,Value=CC-2210
# aws organizations describe-create-account-status --create-account-request-id car-xxxxxxxx

# 4. Mover una cuenta de OU
# aws organizations move-account --account-id 111122223333 --source-parent-id ou-ab12-aaaaaaaa --destination-parent-id ou-ab12-bbbbbbbb

# 5. ¿El trail de organización está activo y válido?
aws cloudtrail describe-trails --include-shadow-trails false \
  --query 'trailList[?IsOrganizationTrail].[Name,IsMultiRegionTrail,LogFileValidationEnabled]' --output table
aws cloudtrail get-trail-status --name modalima-organizacion --query '[IsLogging,LatestDeliveryError]'

# 6. ¿Qué SCP aplican a una OU?
aws organizations list-policies-for-target --target-id ou-ab12-aaaaaaaa --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].Name'
