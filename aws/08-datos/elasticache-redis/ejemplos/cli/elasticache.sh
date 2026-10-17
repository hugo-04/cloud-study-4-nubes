#!/usr/bin/env bash
# Comandos de ejemplo para ElastiCache. Define RG (id del grupo de replicación) y, para redis-cli, HOST y USUARIO.
set -euo pipefail
RG="${RG:?define RG}"

# Estado, endpoints y cifrado
aws elasticache describe-replication-groups --replication-group-id "$RG" \
  --query 'ReplicationGroups[0].{Estado:Status,Failover:AutomaticFailover,MultiAZ:MultiAZ,TLS:TransitEncryptionEnabled,Reposo:AtRestEncryptionEnabled,Primario:NodeGroups[0].PrimaryEndpoint.Address,Lectura:NodeGroups[0].ReaderEndpoint.Address}'

# Ensayo de failover (el DNS cambia al nuevo primario; mide cuánto tarda tu aplicación en recuperarse)
# aws elasticache test-failover --replication-group-id "$RG" --node-group-id 0001

# Métricas clave (últimos 60 min): memoria, expulsiones, CPU del motor
for M in DatabaseMemoryUsagePercentage Evictions EngineCPUUtilization CurrConnections; do
  aws cloudwatch get-metric-statistics --namespace AWS/ElastiCache --metric-name "$M" \
    --dimensions Name=ReplicationGroupId,Value="$RG" \
    --start-time "$(date -u -d '-60 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 300 --statistics Maximum --query "Datapoints[].Maximum" --output text | sed "s/^/$M: /"
done

# Desde un host dentro de la VPC (el grupo no tiene IP pública):
# redis-cli --tls -h "$HOST" -p 6379 --user "$USUARIO" --pass "$SECRETO" PING
# redis-cli --tls ... INFO memory
# redis-cli --tls ... SLOWLOG GET 20
# redis-cli --tls ... --scan --pattern 'app:prod:producto:*' | head      # SCAN, nunca KEYS
# redis-cli --tls ... MEMORY USAGE app:prod:producto:A1
# redis-cli --tls ... TTL app:prod:producto:A1
# redis-cli --tls ... --bigkeys                                          # mejor en una réplica
