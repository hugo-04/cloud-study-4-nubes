#!/usr/bin/env bash
# Comandos de ejemplo para SNS. Define TOPIC_ARN y SUB_ARN.
set -euo pipefail
TOPIC_ARN="${TOPIC_ARN:?define TOPIC_ARN}"

# Publicar con atributos tipados (Number para el importe)
aws sns publish --topic-arn "$TOPIC_ARN" \
  --message '{"tipo":"OrdenCreada","version":1,"idOrden":"ord-48213","total":189.90}' \
  --message-attributes '{"tipo":{"DataType":"String","StringValue":"OrdenCreada"},"total":{"DataType":"Number","StringValue":"189.90"},"envio":{"DataType":"String","StringValue":"domicilio"},"pais":{"DataType":"String","StringValue":"PE-LIM"}}'

# Ver suscripciones y su política de filtro
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN"
# aws sns get-subscription-attributes --subscription-arn "$SUB_ARN"

# Cambiar el filtro de una suscripción
# aws sns set-subscription-attributes --subscription-arn "$SUB_ARN" \
#   --attribute-name FilterPolicy --attribute-value file://../json/politica-filtro.json

# Filtrar por el cuerpo del mensaje en vez de por atributos
# aws sns set-subscription-attributes --subscription-arn "$SUB_ARN" \
#   --attribute-name FilterPolicyScope --attribute-value MessageBody
