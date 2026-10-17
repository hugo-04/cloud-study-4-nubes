#!/usr/bin/env bash
# Comandos de ejemplo para MSK. Define CLUSTER_ARN; para los comandos de Kafka, ejecútalos desde un host dentro de la VPC.
set -euo pipefail
CLUSTER_ARN="${CLUSTER_ARN:?define CLUSTER_ARN}"

# Estado del clúster y nodos
aws kafka describe-cluster-v2 --cluster-arn "$CLUSTER_ARN" --query 'ClusterInfo.{Estado:State,Tipo:ClusterType}'
aws kafka list-nodes --cluster-arn "$CLUSTER_ARN"

# Direcciones de conexión (usa la cadena con IAM: BootstrapBrokerStringSaslIam)
BS="$(aws kafka get-bootstrap-brokers --cluster-arn "$CLUSTER_ARN" --query BootstrapBrokerStringSaslIam --output text)"
echo "bootstrap: $BS"

# --- Desde un cliente dentro de la VPC (Kafka CLI + aws-msk-iam-auth en libs/) ---
CFG=../properties/client-iam.properties
# Crear un tópico con la configuración correcta
kafka-topics.sh --bootstrap-server "$BS" --command-config "$CFG" --create \
  --topic pedidos.orden.creada.v1 --partitions 6 --replication-factor 3 \
  --config min.insync.replicas=2 --config retention.ms=259200000
kafka-topics.sh --bootstrap-server "$BS" --command-config "$CFG" --describe --topic pedidos.orden.creada.v1

# Producir y consumir de prueba
# echo '{"idOrden":"ord-1"}' | kafka-console-producer.sh --bootstrap-server "$BS" --producer.config "$CFG" --topic pedidos.orden.creada.v1
# kafka-console-consumer.sh --bootstrap-server "$BS" --consumer.config "$CFG" --topic pedidos.orden.creada.v1 --from-beginning --group prueba

# Lag de un grupo
kafka-consumer-groups.sh --bootstrap-server "$BS" --command-config "$CFG" --describe --group facturacion

# Reprocesar: mover el grupo a una fecha (el grupo debe estar detenido)
# kafka-consumer-groups.sh --bootstrap-server "$BS" --command-config "$CFG" --group facturacion \
#   --topic pedidos.orden.creada.v1 --reset-offsets --to-datetime 2026-10-14T00:00:00.000 --execute

# Ampliar almacenamiento de los brokers (aprovisionado)
# aws kafka update-broker-storage --cluster-arn "$CLUSTER_ARN" --current-version <version> \
#   --target-broker-ebs-volume-info '[{"KafkaBrokerNodeId":"ALL","VolumeSizeGB":300}]'
