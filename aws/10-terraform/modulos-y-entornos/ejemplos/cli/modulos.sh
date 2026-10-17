#!/usr/bin/env bash
# Rutina de calidad de un módulo y de un entorno. Úsala igual en tu máquina y en el pipeline.
set -euo pipefail
MODULO="modulos/servicio-base"
ENTORNO="envs/dev"

echo "== 1. Formato y validación del módulo =="
terraform fmt -check -recursive "$MODULO"
terraform -chdir="$MODULO" init -backend=false -input=false
terraform -chdir="$MODULO" validate

echo "== 2. Pruebas del módulo (proveedor simulado: no crea nada) =="
terraform -chdir="$MODULO" test

echo "== 3. Análisis estático (si están instalados) =="
command -v tflint >/dev/null && (cd "$MODULO" && tflint --init && tflint) || echo "tflint no instalado"
command -v trivy  >/dev/null && trivy config "$MODULO" --severity HIGH,CRITICAL || echo "trivy no instalado"
command -v checkov >/dev/null && checkov -d "$MODULO" --quiet || echo "checkov no instalado"

echo "== 4. Entorno: init con su backend, validar y prueba de contrato =="
terraform -chdir="$ENTORNO" init -backend=false -input=false     # en CI real: -backend-config=backend.dev.hcl
terraform -chdir="$ENTORNO" validate
terraform -chdir="$ENTORNO" test

echo "== 5. Plan del entorno (con backend real) =="
# terraform -chdir="$ENTORNO" init -reconfigure -backend-config=backend.dev.hcl
# terraform -chdir="$ENTORNO" plan -out=tfplan -var-file=dev.tfvars
# terraform -chdir="$ENTORNO" show -json tfplan | jq '[.resource_changes[] | select(.change.actions | index("delete"))] | length'   # debe ser 0

echo "== 6. Bloqueo de proveedores para varias plataformas (subir .terraform.lock.hcl a Git) =="
terraform -chdir="$ENTORNO" providers lock -platform=linux_amd64 -platform=darwin_arm64

echo "== 7. Documentación automática del módulo (si está instalado terraform-docs) =="
command -v terraform-docs >/dev/null && terraform-docs markdown table "$MODULO" || echo "terraform-docs no instalado"

echo "== 8. Subir de versión: etiqueta anotada y protegida =="
# git tag -a v1.3.0 -m "servicio-base: retención de mensajes configurable" && git push origin v1.3.0
