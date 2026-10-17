#!/usr/bin/env bash
# Comandos de ejemplo para CloudTrail.
set -euo pipefail
TRAZA="${TRAZA:-traza-principal}"

# ¿Está registrando y entregando bien?
aws cloudtrail get-trail-status --name "$TRAZA" --query '{Registrando:IsLogging,UltimaEntrega:LatestDeliveryTime,ErrorEntrega:LatestDeliveryError,ErrorCifrado:LatestCloudWatchLogsDeliveryError}'
aws cloudtrail describe-trails --query 'trailList[].{Nombre:Name,Multirregion:IsMultiRegionTrail,Organizacion:IsOrganizationTrail,Validacion:LogFileValidationEnabled,KMS:KmsKeyId}' --output table

# Buscar en el historial (últimas 24 h): un atributo por llamada
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=StopLogging \
  --start-time "$(date -u -d '-24 hours' +%FT%TZ)" --max-results 20 \
  --query 'Events[].{Hora:EventTime,Usuario:Username,Evento:EventName}' --output table

# Todo lo que hizo un usuario (o 'root')
# aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=root --max-results 20

# Comprobar la integridad de los archivos (requiere la validación activada)
# aws cloudtrail validate-logs --trail-arn "arn:aws:cloudtrail:us-east-1:111122223333:trail/$TRAZA" --start-time 2026-10-16T00:00:00Z

# Selectores de eventos (¿qué datos se registran?)
# aws cloudtrail get-event-selectors --trail-name "$TRAZA"

# Un archivo de la traza, leído a mano
# aws s3 cp s3://prod-auditoria-111122223333/AWSLogs/111122223333/CloudTrail/us-east-1/2026/10/16/ARCHIVO.json.gz - | gunzip | head -c 2000
