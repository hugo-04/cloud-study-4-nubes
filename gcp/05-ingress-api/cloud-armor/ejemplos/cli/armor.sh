#!/usr/bin/env bash
# Cloud Armor. Uso: ./armor.sh <proyecto> <politica>
set -euo pipefail
P="${1:?proyecto}"; N="${2:?politica}"
gcloud compute security-policies describe "$N" --project "$P" --format='table(rules[].priority,rules[].action,rules[].preview,rules[].match.expr.expression)'
gcloud logging read 'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"' \
  --project "$P" --limit 10 --format='table(timestamp,httpRequest.requestUrl,jsonPayload.enforcedSecurityPolicy.priority)'
