# Azure · Workload Identity · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AADSTS70021: No matching federated identity record found` | `subject`, `issuer` o `audience` no coinciden | Compara `sub` del token proyectado con el subject de la credencial | Recrear la credencial con los valores exactos |
| `AADSTS700211 ... issuer` | El issuer registrado no es el del clúster | `az aks show --query oidcIssuerProfile.issuerUrl` | Usar ese issuer |
| El pod no tiene `AZURE_FEDERATED_TOKEN_FILE` | Falta la etiqueta en el **pod**, el ServiceAccount sin anotación, o webhook no activo | `kubectl get pod -o yaml`; `kubectl get mutatingwebhookconfiguration` | Etiqueta `azure.workload.identity/use: "true"` en la plantilla del pod; anotar el SA |
| `CredentialUnavailableException` | Variables ausentes | `env \| grep AZURE_` dentro del pod | Corregir lo anterior |
| El pod usa otra identidad | Quedó `AZURE_CLIENT_SECRET` u otras variables | `env` del pod | Quitar variables heredadas |
| Timeout al pedir token | Salida a `login.microsoftonline.com` bloqueada | `nslookup`/`curl` desde el pod | Permitir el destino en el firewall/NSG |
| 403 en Key Vault/Storage | La identidad no tiene rol de datos | `az role assignment list --assignee <principalId>` | Asignar rol |
| El token funciona al principio y luego falla | Token de ServiceAccount expirado y no se renueva | Versión del SDK; logs | Actualizar `azure-identity`; el SDK relee el archivo |
| Funciona en un namespace y no en otro | Subject distinto | Credencial federada | Crear otra credencial |
| Cambié el clúster y dejó de funcionar | Nuevo issuer URL | Issuer del clúster nuevo | Actualizar la credencial federada |
| Pipeline de GitHub: `AADSTS70021` | Subject de GitHub no coincide (rama, entorno, pull request) | Claim `sub` del token de GitHub | Alinear el subject (`ref:` vs `environment:`) |

## Comandos útiles
```bash
az aks show -g <rg> -n <aks> --query "{oidc:oidcIssuerProfile, wi:securityProfile.workloadIdentity}" -o json
az identity federated-credential list --identity-name <id> -g <rg> -o table
kubectl -n <ns> get sa <sa> -o yaml
kubectl -n <ns> describe pod <pod> | grep -i -E "AZURE_|azure.workload"
kubectl -n <ns> logs deploy/<app> | grep -i -E "AADSTS|credential"
```
