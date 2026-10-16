#!/usr/bin/env bash
# Azure Policy con la CLI (versión de estudio). Léelo por bloques; no lo ejecutes entero de golpe.
# Requisitos: az (con sesión iniciada), jq. Para consultas de Resource Graph: az extension add --name resource-graph
set -euo pipefail

SUB=$(az account show --query id -o tsv)
SCOPE="/subscriptions/$SUB"
JSON_DIR="$(dirname "$0")/../json"

# ---------------------------------------------------------------------------
# 1) Explorar: buscar políticas integradas y descubrir alias
# ---------------------------------------------------------------------------
# Políticas integradas cuyo nombre menciona "public network access"
az policy definition list \
  --query "[?policyType=='BuiltIn' && contains(displayName, 'public network access')].{nombre:displayName, id:name}" \
  -o table

# Ver una definición completa (regla, parámetros, efectos permitidos)
az policy definition show --name b2982f36-99f2-4db5-8eff-283140c09693 --query "{nombre:displayName, modo:mode, parametros:parameters, regla:policyRule}" -o json

# Alias de un tipo de recurso (para escribir condiciones sin adivinar)
az provider show --namespace Microsoft.ServiceBus --expand "resourceTypes/aliases" \
  --query "resourceTypes[?resourceType=='namespaces'].aliases[].name" -o tsv | grep -i publicNetworkAccess

# ---------------------------------------------------------------------------
# 2) Crear una definición personalizada a partir de nuestro JSON
#    (la CLI recibe la regla y los parámetros por separado, sin el envoltorio "properties")
# ---------------------------------------------------------------------------
F="$JSON_DIR/servicebus-sin-acceso-publico.json"
jq '.properties.policyRule' "$F" > /tmp/regla.json
jq '.properties.parameters' "$F" > /tmp/parametros.json

az policy definition create \
  --name modalima-servicebus-sin-acceso-publico \
  --display-name "ModaLima - Service Bus sin acceso público de red" \
  --mode All \
  --rules /tmp/regla.json \
  --params /tmp/parametros.json \
  --metadata category="Service Bus" version=1.0.0 \
  --subscription "$SUB"

# ---------------------------------------------------------------------------
# 3) Crear una iniciativa (conjunto) con dos políticas
# ---------------------------------------------------------------------------
cat > /tmp/definiciones-iniciativa.json <<JSON
[
  {
    "policyDefinitionReferenceId": "net03-storage-sin-acceso-publ",
    "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/b2982f36-99f2-4db5-8eff-283140c09693",
    "parameters": { "effect": { "value": "[parameters('efecto')]" } }
  },
  {
    "policyDefinitionReferenceId": "net03-servicebus-sin-acceso-publ",
    "policyDefinitionId": "$SCOPE/providers/Microsoft.Authorization/policyDefinitions/modalima-servicebus-sin-acceso-publico",
    "parameters": { "efecto": { "value": "[parameters('efecto')]" } }
  }
]
JSON

az policy set-definition create \
  --name modalima-guardarrailes-mini \
  --display-name "ModaLima - Guardarraíles (mini)" \
  --definitions /tmp/definiciones-iniciativa.json \
  --params '{"efecto":{"type":"String","allowedValues":["Audit","Deny","Disabled"],"defaultValue":"Audit"}}' \
  --subscription "$SUB"

# ---------------------------------------------------------------------------
# 4) Asignar SIN bloquear (DoNotEnforce) y con mensaje de no conformidad
# ---------------------------------------------------------------------------
az policy assignment create \
  --name modalima-guardarrailes-mini \
  --display-name "ModaLima - Guardarraíles (mini)" \
  --policy-set-definition "$SCOPE/providers/Microsoft.Authorization/policySetDefinitions/modalima-guardarrailes-mini" \
  --scope "$SCOPE" \
  --enforcement-mode DoNotEnforce \
  --params '{"efecto":{"value":"Audit"}}' \
  --non-compliance-messages '[{"message":"Acceso público no permitido: usa Private Endpoint. Dudas: gobierno@modalima.example"}]'

# Cuando el impacto sea aceptable: cambia a modo de aplicación y a Deny
az policy assignment update \
  --name modalima-guardarrailes-mini --scope "$SCOPE" \
  --enforcement-mode Default \
  --params '{"efecto":{"value":"Deny"}}'

# ---------------------------------------------------------------------------
# 5) Cumplimiento
# ---------------------------------------------------------------------------
az policy state trigger-scan --no-wait                       # evaluación bajo demanda de la suscripción
az policy state summarize --query "results.{noConformes:nonCompliantResources, politicas:nonCompliantPolicies}"
az policy state list \
  --filter "complianceState eq 'NonCompliant'" \
  --query "[].{recurso:resourceId, politica:policyDefinitionName, asignacion:policyAssignmentName}" -o table

# A escala con Resource Graph (consulta KQL)
az graph query -q "policyresources
| where type == 'microsoft.policyinsights/policystates'
| where properties.complianceState == 'NonCompliant'
| summarize recursos = count() by politica = tostring(properties.policyDefinitionName)
| order by recursos desc" --first 20 -o table

# ---------------------------------------------------------------------------
# 6) Exención con fecha de caducidad (solo una regla de la iniciativa, solo un grupo de recursos)
# ---------------------------------------------------------------------------
ASIGNACION_ID=$(az policy assignment show --name modalima-guardarrailes-mini --scope "$SCOPE" --query id -o tsv)

az policy exemption create \
  --name lab-storage-publico \
  --display-name "Laboratorio: Storage con acceso público (temporal)" \
  --description "Demostración del curso. Dueño: plataforma." \
  --policy-assignment "$ASIGNACION_ID" \
  --policy-definition-reference-ids net03-storage-sin-acceso-publ \
  --exemption-category Waiver \
  --expires-on 2027-03-31T00:00:00Z \
  --scope "$SCOPE/resourceGroups/rg-laboratorio-politicas"

# ---------------------------------------------------------------------------
# 7) Modify con identidad + remediación de lo existente
# ---------------------------------------------------------------------------
az policy assignment create \
  --name modalima-heredar-env \
  --display-name "ModaLima - Heredar la etiqueta env del grupo de recursos" \
  --policy ea3f2387-9b95-492a-a190-fcdc54f7b070 \
  --scope "$SCOPE" \
  --params '{"tagName":{"value":"env"}}' \
  --mi-system-assigned --location eastus2 \
  --identity-scope "$SCOPE" --role Contributor     # con la CLI sí puedes conceder el rol aquí mismo

az policy remediation create \
  --name remediar-heredar-env \
  --policy-assignment modalima-heredar-env

az policy remediation list --query "[].{nombre:name, estado:provisioningState}" -o table

# ---------------------------------------------------------------------------
# 8) Limpieza del laboratorio
# ---------------------------------------------------------------------------
# az policy exemption delete --name lab-storage-publico --scope "$SCOPE/resourceGroups/rg-laboratorio-politicas"
# az policy assignment delete --name modalima-heredar-env --scope "$SCOPE"
# az policy assignment delete --name modalima-guardarrailes-mini --scope "$SCOPE"
# az policy set-definition delete --name modalima-guardarrailes-mini
# az policy definition delete --name modalima-servicebus-sin-acceso-publico
