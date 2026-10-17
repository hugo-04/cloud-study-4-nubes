#!/usr/bin/env bash
# Pasos genéricos del pipeline (el paso de autenticación OIDC → external_account depende del CI).
# Uso: ./pipeline.sh plan|apply <entorno>
set -euo pipefail
ACCION="${1:?plan|apply}"; ENTORNO="${2:?entorno}"
D="entornos/$ENTORNO"
: "${GOOGLE_APPLICATION_CREDENTIALS:?falta el archivo external_account del paso de autenticación}"
terraform -chdir="$D" init -input=false
case "$ACCION" in
  plan)
    terraform -chdir="$D" fmt -check -recursive
    terraform -chdir="$D" validate
    terraform -chdir="$D" plan -input=false -out=plan.bin
    terraform -chdir="$D" show -json plan.bin > "$D/plan.json"
    # política sobre el plan (bloquea destrucciones de datos, recursos prohibidos)
    java -jar politica-plan.jar "$D/plan.json" "$ENTORNO"
    ;;
  apply)
    terraform -chdir="$D" apply -input=false plan.bin
    ;;
  *) echo "acción desconocida"; exit 2 ;;
esac
