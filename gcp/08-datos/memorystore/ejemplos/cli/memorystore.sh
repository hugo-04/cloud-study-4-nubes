#!/usr/bin/env bash
# Memorystore. Uso: ./memorystore.sh <proyecto> <region>
set -euo pipefail
P="${1:?proyecto}"; R="${2:?region}"
gcloud memorystore instances list --project "$P" --location "$R"
gcloud redis instances list --project "$P" --region "$R" --format='table(name,tier,memorySizeGb,transitEncryptionMode,authEnabled)'
