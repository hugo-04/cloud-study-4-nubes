#!/usr/bin/env bash
# Operación del estado remoto en S3. Ejecuta cada bloque con intención; varios modifican el estado.
set -euo pipefail
BUCKET="${BUCKET:-modalima-tfstate-111122223333}"
CLAVE="${CLAVE:-env/prod/red/terraform.tfstate}"
REGION="${AWS_REGION:-us-east-1}"

echo "== 1. Inicializar usando la configuración del backend =="
terraform init -backend-config=backend.hcl            # primera vez o tras clonar
# terraform init -migrate-state -backend-config=backend.hcl   # mover el estado local a S3
# terraform init -reconfigure -backend-config=backend.hcl     # cambiar de backend SIN mover

echo "== 2. Ver qué hay en el estado =="
terraform state list
terraform state show aws_sqs_queue.principal

echo "== 3. Verificar el bucket del estado =="
aws s3api get-bucket-versioning --bucket "$BUCKET"
aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
aws s3api get-public-access-block --bucket "$BUCKET"
aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text | python3 -m json.tool | head -40

echo "== 4. ¿Hay un candado? (existe un objeto .tflock mientras alguien aplica) =="
aws s3api head-object --bucket "$BUCKET" --key "${CLAVE}.tflock" --query '{Modificado:LastModified,Bytes:ContentLength}' || echo "sin candado"
# Solo si confirmaste que NADIE está aplicando:
# terraform force-unlock <ID-del-mensaje>

echo "== 5. Versiones del estado (para recuperar) =="
aws s3api list-object-versions --bucket "$BUCKET" --prefix "$CLAVE" \
  --query 'Versions[].{Version:VersionId,Fecha:LastModified,Actual:IsLatest,Bytes:Size}' --output table

echo "== 6. Recuperar una versión anterior (copiarla como la actual) =="
# VERSION=<VersionId elegido>
# aws s3api copy-object --bucket "$BUCKET" --key "$CLAVE" \
#   --copy-source "$BUCKET/$CLAVE?versionId=$VERSION" --server-side-encryption aws:kms
# terraform plan   # debe decir "No changes" o mostrar solo lo esperado

echo "== 7. Si el estado se borró (marcador de borrado): quitar el marcador restaura la versión previa =="
# aws s3api list-object-versions --bucket "$BUCKET" --prefix "$CLAVE" --query 'DeleteMarkers[?IsLatest].VersionId' --output text
# aws s3api delete-object --bucket "$BUCKET" --key "$CLAVE" --version-id <VersionId-del-marcador>   # solo el administrador

echo "== 8. Cirugía del estado (preferible: bloques moved/import/removed en el código) =="
# terraform state mv aws_sqs_queue.pedidos aws_sqs_queue.principal
# terraform state rm aws_s3_bucket.heredado
terraform plan -generate-config-out=generado.tf       # con bloques import { } en el código

echo "== 9. Deriva: plan nocturno que sale con código 2 si hay diferencias =="
terraform plan -detailed-exitcode -lock=false -input=false || test $? -eq 2

echo "== 10. Copia de seguridad puntual del estado =="
terraform state pull > "respaldo-$(date -u +%Y%m%dT%H%M%SZ).tfstate"   # contiene secretos: no lo subas a Git
