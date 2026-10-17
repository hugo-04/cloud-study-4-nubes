#!/usr/bin/env bash
# Jerarquía y etiquetas. Uso: ./jerarquia.sh <proyecto>
set -euo pipefail
P="${1:?proyecto}"
gcloud projects get-ancestors "$P"
gcloud projects describe "$P" --format='value(labels)'
N=$(gcloud projects describe "$P" --format='value(projectNumber)')
gcloud resource-manager tags bindings list --parent "//cloudresourcemanager.googleapis.com/projects/$N" --effective
gcloud alpha resource-manager liens list --project "$P" 2>/dev/null || true
