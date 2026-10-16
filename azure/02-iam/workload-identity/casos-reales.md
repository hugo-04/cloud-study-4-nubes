# Azure · Workload Identity · Casos reales

## Caso 1 · Pods leyendo Key Vault sin secretos
- **Problema:** los pods guardaban el secreto de una app registration para leer Key Vault; vencía y rompía despliegues.
- **Solución:** workload identity: ServiceAccount `sa-api` ↔ credencial federada ↔ identidad con *Key Vault Secrets User*.
- **Resultado:** sin secreto que rotar.
- **Lección:** federar en vez de compartir secretos.

## Caso 2 · Cambió el namespace y dejó de funcionar
- **Problema:** al mover la aplicación de `pruebas` a `modalima`, los pods recibieron `AADSTS70021: No matching federated identity record found`.
- **Causa:** la credencial federada tenía `subject = system:serviceaccount:pruebas:sa-api`.
- **Solución:** crear otra credencial con el namespace nuevo.
- **Lección:** el subject es literal.

## Caso 3 · `DefaultAzureCredential` usaba el secreto equivocado
- **Problema:** aunque había workload identity, el pod seguía autenticándose con una aplicación vieja.
- **Causa:** quedó la variable `AZURE_CLIENT_SECRET` en el Deployment; `DefaultAzureCredential` prueba primero las variables de entorno.
- **Solución:** eliminar `AZURE_CLIENT_SECRET`/`AZURE_CLIENT_ID` heredados de otra configuración.
- **Lección:** limpia la configuración antigua.

## Caso 4 · Despliegue desde GitHub Actions sin secretos
- **Problema:** el pipeline guardaba un secreto de service principal.
- **Solución:** credencial federada en una managed identity con subject `repo:modalima/tienda:environment:produccion`; el job usa `azure/login` con OIDC.
- **Resultado:** solo los jobs del entorno `produccion` (con aprobación) pueden desplegar.
- **Lección:** el subject puede atar el acceso a un entorno protegido.

## Caso 5 · Clúster con salida restringida
- **Problema:** los pods no lograban obtener token; timeouts al pedirlo.
- **Causa:** el firewall de salida bloqueaba `login.microsoftonline.com`.
- **Solución:** permitir ese destino en el firewall.
- **Lección:** el intercambio de tokens también sale a internet (Entra ID).

## Caso 6 · El pod olvidó la etiqueta
- **Problema:** el ServiceAccount estaba bien anotado pero el pod no recibía el token.
- **Causa:** faltaba la etiqueta `azure.workload.identity/use: "true"` en el **pod** (no en el Deployment).
- **Solución:** ponerla en `spec.template.metadata.labels`.
- **Lección:** la etiqueta va en la plantilla del pod.
