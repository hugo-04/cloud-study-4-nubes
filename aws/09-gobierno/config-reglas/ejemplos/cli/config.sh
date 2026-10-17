#!/usr/bin/env bash
# Comandos de ejemplo para AWS Config.
set -euo pipefail

# ¿Está grabando y entregando?
aws configservice describe-configuration-recorder-status --query 'ConfigurationRecordersStatus[].{Nombre:name,Grabando:recording,Ultimo:lastStatus}'
aws configservice describe-delivery-channel-status --query 'DeliveryChannelsStatus[].{Canal:name,S3:configHistoryDeliveryInfo.lastStatus}'

# Resumen: ¿cuántas reglas incumplen?
aws configservice describe-compliance-by-config-rule --query 'ComplianceByConfigRules[?Compliance.ComplianceType==`NON_COMPLIANT`].ConfigRuleName' --output text

# Detalle de una regla: qué recursos incumplen
REGLA="${REGLA:-etiquetas-obligatorias}"
aws configservice get-compliance-details-by-config-rule --config-rule-name "$REGLA" --compliance-types NON_COMPLIANT \
  --query 'EvaluationResults[].{Tipo:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceType,Id:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,Nota:Annotation}' --output table

# Forzar una evaluación (útil tras corregir)
# aws configservice start-config-rules-evaluation --config-rule-names "$REGLA"

# Consulta avanzada
# aws configservice select-resource-config --expression "SELECT resourceId WHERE resourceType = 'AWS::EC2::Volume' AND configuration.encrypted = false"

# Historial de un recurso (qué cambió y cuándo)
# aws configservice get-resource-config-history --resource-type AWS::EC2::SecurityGroup --resource-id sg-0abc123 --limit 5

# Probar una regla personalizada sin guardar resultados (modo de prueba)
# aws configservice put-evaluations --result-token "TEST" --test-mode --evaluations ComplianceResourceType=AWS::EC2::Instance,ComplianceResourceId=i-0abc,ComplianceType=NON_COMPLIANT,Annotation="falta centro-costo",OrderingTimestamp=2026-10-16T15:04:05Z

# Remediación
# aws configservice describe-remediation-configurations --config-rule-names "$REGLA"
# aws configservice describe-remediation-execution-status --config-rule-name "$REGLA"
