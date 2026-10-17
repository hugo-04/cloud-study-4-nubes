#!/usr/bin/env bash
# Operación de Secrets Manager. Los valores NUNCA se imprimen en pantalla ni en logs.
set -euo pipefail
ID="${1:-prod/pedidos/db}"

echo "== Datos del secreto (sin valor) =="
aws secretsmanager describe-secret --secret-id "$ID" \
  --query "{nombre:Name, clave:KmsKeyId, rotacion:RotationEnabled, ultimaRotacion:LastRotatedDate, proxima:NextRotationDate, borrado:DeletedDate}" --output table

echo "== Versiones y etiquetas =="
aws secretsmanager list-secret-version-ids --secret-id "$ID" \
  --query "Versions[].{version:VersionId, etiquetas:VersionStages, creada:CreatedDate}" --output table

echo "== Crear el secreto SIN pasar el valor por la línea de comandos (se lee de un archivo temporal protegido) =="
cat <<'DOC'
umask 077
cat > /tmp/valor.json   # pega el JSON y termina con Ctrl-D (o genera el valor en un script seguro)
aws secretsmanager put-secret-value --secret-id prod/pedidos/db --secret-string file:///tmp/valor.json
shred -u /tmp/valor.json
DOC

echo "== Iniciar una rotación ahora =="
echo "aws secretsmanager rotate-secret --secret-id $ID"

echo "== Restaurar un secreto marcado para borrar =="
echo "aws secretsmanager restore-secret --secret-id $ID"

echo "== ¿Quién leyó el secreto en las últimas 24 h? (CloudTrail) =="
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time "$(date -u -d '-24 hours' +%FT%TZ)" \
  --query "Events[].{hora:EventTime, quien:Username}" --output table | head -30

echo "== Leer el valor SOLO para una prueba controlada (cuidado: queda en el historial si lo imprimes) =="
echo "aws secretsmanager get-secret-value --secret-id $ID --query SecretString --output text | jq -r .username"
