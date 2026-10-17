#!/usr/bin/env bash
# Pipeline genérico de infraestructura (cualquier CI). Uso: ./pipeline.sh <carpeta-componente> <plan|apply>
set -euo pipefail
DIR="${1:?carpeta}"; FASE="${2:?plan|apply}"
cd "$DIR"
tofu fmt -check -recursive
tofu init -input=false
tofu validate
if [ "$FASE" = "plan" ]; then
  tofu plan -input=false -out=plan.bin
  tofu show -no-color plan.bin > plan.txt        # adjuntar al PR para revisión humana
else
  test -f plan.bin || { echo "falta plan.bin aprobado"; exit 1; }
  tofu apply -input=false plan.bin                # aplica EXACTAMENTE lo revisado
fi
