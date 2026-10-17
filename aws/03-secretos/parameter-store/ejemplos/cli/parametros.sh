#!/usr/bin/env bash
# Operación de Parameter Store.
set -euo pipefail
RAMA="${1:-/prod/pedidos}"

echo "== Toda la rama (SecureString se muestra cifrado a propósito) =="
aws ssm get-parameters-by-path --path "$RAMA" --recursive \
  --query "Parameters[].{nombre:Name, tipo:Type, version:Version}" --output table

echo "== Con descifrado (¡no lo pegues en tickets ni logs!) =="
echo "aws ssm get-parameters-by-path --path $RAMA --recursive --with-decryption --query 'Parameters[].[Name,Value]' --output text"

echo "== Crear/actualizar un parámetro =="
cat <<'DOC'
aws ssm put-parameter --name /prod/pedidos/http/timeout-ms --type String --value 3000 --overwrite
# SecureString con tu CMK (el valor desde un archivo, no desde la línea de comandos):
aws ssm put-parameter --name /prod/pedidos/pagos/api-clave --type SecureString \
  --key-id alias/prod-pedidos-datos --value file:///tmp/valor.txt --overwrite
DOC

echo "== Historial y etiquetas =="
aws ssm get-parameter-history --name "$RAMA/http/timeout-ms" \
  --query "Parameters[].{version:Version, cuando:LastModifiedDate, quien:LastModifiedUser}" --output table 2>/dev/null || echo "(parámetro de ejemplo inexistente)"
echo "aws ssm label-parameter-version --name $RAMA/http/timeout-ms --parameter-version 3 --labels estable"

echo "== Leer un secreto de Secrets Manager por la API de parámetros =="
echo "aws ssm get-parameter --name /aws/reference/secretsmanager/prod/pedidos/db --with-decryption --query Parameter.Value --output text | jq -r .username"
