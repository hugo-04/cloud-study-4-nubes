#!/usr/bin/env bash
# Comandos de ejemplo para RDS / Aurora. Define CLUSTER (identificador) y, para psql, HOST y DB.
set -euo pipefail
CLUSTER="${CLUSTER:?define CLUSTER}"

# Estado, endpoints y miembros del clúster
aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" \
  --query 'DBClusters[0].{Estado:Status,Escritor:Endpoint,Lector:ReaderEndpoint,Id:DbClusterResourceId,Miembros:DBClusterMembers[].[DBInstanceIdentifier,IsClusterWriter]}'

# Conectar con un token IAM (15 min) y TLS verificado
# curl -sO https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
# TOKEN="$(aws rds generate-db-auth-token --hostname "$HOST" --port 5432 --username app_iam --region us-east-1)"
# PGPASSWORD="$TOKEN" psql "host=$HOST port=5432 dbname=${DB:-pedidos} user=app_iam sslmode=verify-full sslrootcert=global-bundle.pem"

# Ensayo de failover (¡en preproducción!) y observación
# aws rds failover-db-cluster --db-cluster-identifier "$CLUSTER"
aws rds describe-events --source-type db-cluster --source-identifier "$CLUSTER" --duration 60

# Instantánea manual antes de un cambio riesgoso
# aws rds create-db-cluster-snapshot --db-cluster-identifier "$CLUSTER" --db-cluster-snapshot-identifier "$CLUSTER-antes-de-migracion"

# PITR: crea un clúster NUEVO con los datos de hace 10 minutos (luego hay que crearle instancias)
# aws rds restore-db-cluster-to-point-in-time --source-db-cluster-identifier "$CLUSTER" \
#   --db-cluster-identifier "$CLUSTER-restaurado" --restore-to-time "$(date -u -d '-10 minutes' +%FT%TZ)" \
#   --db-subnet-group-name <grupo> --vpc-security-group-ids <sg>

# Blue/Green para una versión mayor
# aws rds create-blue-green-deployment --blue-green-deployment-name "$CLUSTER-v17" \
#   --source "$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER" --query 'DBClusters[0].DBClusterArn' --output text)" \
#   --target-engine-version 17.4
# aws rds switchover-blue-green-deployment --blue-green-deployment-identifier <bgd-id> --switchover-timeout 300

# Mantenimiento pendiente
aws rds describe-pending-maintenance-actions --filters Name=db-cluster-id,Values="$CLUSTER"
