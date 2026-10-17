#!/usr/bin/env bash
# Revisa lo esencial de una suscripción de carga recién creada. Solo lectura. Requiere: az login y Reader en la suscripción.
set -euo pipefail

SUB="${1:?uso: $0 <id de suscripcion> <equipo> <dev|prod>}"
EQUIPO="${2:?falta el equipo}"
ENTORNO="${3:?falta el entorno}"
SUF="${EQUIPO}-${ENTORNO}"
fallos=0

verificar() { # $1 = descripcion, $2 = comando que debe devolver texto no vacío
  if [ -n "$(eval "$2" 2>/dev/null || true)" ]; then echo "OK    $1"; else echo "FALLA $1"; fallos=$((fallos + 1)); fi
}

az account set --subscription "$SUB"

verificar "Cuelga de un grupo de administración de carga" \
  "az account management-group list --query \"[?contains(name,'modalima')].name\" -o tsv"
verificar "Existe rg-red-${SUF}" "az group show -n rg-red-${SUF} --query name -o tsv"
verificar "Existe rg-${SUF}" "az group show -n rg-${SUF} --query name -o tsv"
verificar "Etiqueta owner en el grupo de recursos" "az group show -n rg-${SUF} --query tags.owner -o tsv"
verificar "Etiqueta costcenter en el grupo de recursos" "az group show -n rg-${SUF} --query tags.costcenter -o tsv"
verificar "VNet del equipo con peering conectado" \
  "az network vnet peering list -g rg-red-${SUF} --vnet-name vnet-${SUF} --query \"[?peeringState=='Connected'].name\" -o tsv"
verificar "Presupuesto mensual" \
  "az consumption budget list --query \"[?name=='presupuesto-${SUF}'].name\" -o tsv"
verificar "Registro de actividad enviado al espacio central" \
  "az monitor diagnostic-settings subscription list --query \"value[?name=='actividad-a-central'].name\" -o tsv"
verificar "El grupo del equipo tiene Contributor solo en su grupo de recursos" \
  "az role assignment list --resource-group rg-${SUF} --role Contributor --query '[].principalId' -o tsv"
if [ "$ENTORNO" = "prod" ]; then
  verificar "Bloqueo CanNotDelete en la red de producción" \
    "az lock list -g rg-red-${SUF} --query \"[?level=='CanNotDelete'].name\" -o tsv"
fi

echo "Fallos: ${fallos}"
exit $((fallos > 0 ? 1 : 0))
