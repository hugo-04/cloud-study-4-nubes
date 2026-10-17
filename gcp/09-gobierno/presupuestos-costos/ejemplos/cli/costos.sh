#!/usr/bin/env bash
# Presupuestos. Uso: ./costos.sh <cuenta_facturacion> <proyecto>
set -euo pipefail
B="${1:?cuenta}"; P="${2:?proyecto}"
gcloud billing budgets list --billing-account "$B" --format='table(displayName,amount.specifiedAmount.units,thresholdRules.list())'
gcloud billing projects describe "$P"
gcloud recommender recommendations list --project "$P" --location southamerica-west1-a \
  --recommender google.compute.instance.MachineTypeRecommender --format='table(description,primaryImpact.costProjection.cost.units)'
