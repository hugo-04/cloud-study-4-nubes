#!/usr/bin/env bash
# Entornos. Uso: ./entornos.sh <directorio_entorno>
set -euo pipefail
D="${1:?directorio}"
terraform -chdir="$D" init -input=false
terraform -chdir="$D" validate
terraform -chdir="$D" plan -refresh-only -input=false -lock=false
