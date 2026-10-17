#!/usr/bin/env bash
# Operación y auditoría de KMS.
set -euo pipefail
ALIAS="${1:-alias/prod-pedidos-datos}"

echo "== Datos de la clave =="
aws kms describe-key --key-id "$ALIAS" \
  --query "KeyMetadata.{id:KeyId, estado:KeyState, uso:KeyUsage, rotacion:KeyRotationStatus, multiRegion:MultiRegion, borradoEn:DeletionDate}" --output table

echo "== Rotación automática =="
aws kms get-key-rotation-status --key-id "$ALIAS" --output table

echo "== Concesiones vigentes =="
aws kms list-grants --key-id "$ALIAS" --query "Grants[].{para:GranteePrincipal, operaciones:Operations, nombre:Name}" --output table

echo "== Cifrar y descifrar un texto corto CON contexto (≤ 4 KB) =="
CIFRADO=$(aws kms encrypt --key-id "$ALIAS" --plaintext "$(echo -n 'hola' | base64)" \
  --encryption-context servicio=pedidos,tabla=pedidos --query CiphertextBlob --output text)
aws kms decrypt --ciphertext-blob "$CIFRADO" --key-id "$ALIAS" --encryption-context servicio=pedidos,tabla=pedidos \
  --query Plaintext --output text | base64 -d; echo
echo "(si cambias el contexto, el descifrado falla: prueba servicio=otro)"

echo "== Clave de datos para cifrado de sobre (la clave en claro NO se imprime aquí) =="
aws kms generate-data-key --key-id "$ALIAS" --key-spec AES_256 --encryption-context servicio=pedidos \
  --query "{blobCifrado:CiphertextBlob}" --output json | head -c 120; echo " ..."

echo "== Uso reciente de la clave en CloudTrail =="
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue="$ALIAS" \
  --query "Events[].{hora:EventTime, evento:EventName, quien:Username}" --output table | head -30

echo "== Borrado: SIEMPRE primero deshabilitar y observar =="
echo "aws kms disable-key --key-id $ALIAS"
echo "# solo tras semanas sin errores y con aprobación:"
echo "aws kms schedule-key-deletion --key-id $ALIAS --pending-window-in-days 30"
echo "aws kms cancel-key-deletion --key-id $ALIAS   # si te arrepientes"
