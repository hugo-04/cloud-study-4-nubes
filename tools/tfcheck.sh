#!/usr/bin/env bash
# valida todos los ejemplos terraform bajo el repo (o los pasados como argumento).
# Copia toda la carpeta "ejemplos" (para que file("../xml/..") funcione) y valida en ella.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOFU=${TOFU:-/tmp/tfnew/tofu}
fail=0
dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then mapfile -t dirs < <(find $ROOT -path '*/ejemplos/terraform' -type d); fi
for d in "${dirs[@]}"; do
  w=$(mktemp -d); cp -r "$(dirname "$d")"/. "$w"/
  ( cd "$w/terraform" && $TOFU init -backend=false -no-color >init.log 2>&1 && $TOFU validate -no-color >val.log 2>&1 )
  if grep -q "Success" "$w/terraform/val.log" 2>/dev/null; then echo "OK   $d"; else echo "FAIL $d"; tail -15 "$w/terraform/init.log" "$w/terraform/val.log" 2>/dev/null; fail=1; fi
  $TOFU fmt -check "$d" >/dev/null 2>&1 || echo "  (fmt pendiente en $d)"
  rm -rf "$w"
done
exit $fail
