# Azure · Key Vault · Troubleshooting

Orden de diagnóstico: **Identidad → Permiso → Red → DNS → Servicio** (RPDSI, ver [Red · diagnóstico](../../01-red/diagnostico-conectividad/README.md)). Primero ejecuta [KeyVaultCheck.java](ejemplos/java/KeyVaultCheck.java) dentro del entorno que falla.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `403 ForbiddenByRbac` / `Caller is not authorized to perform action ... secrets/getSecret/action` | Falta rol de **datos** (Contributor no basta) | `az role assignment list --assignee <principalId> --scope <kvId>` | Asignar *Key Vault Secrets User* |
| Acabas de asignar el rol y sigue el 403 | Propagación de RBAC (minutos) o token en caché con claims viejos | Esperar 5–10 min; reiniciar la app | Reintentar; no cambies permisos "a ciegas" |
| `403 ForbiddenByFirewall` / `Client address is not authorized` | Firewall del vault o acceso público cerrado | `az keyvault show --query properties.networkAcls` | Private Endpoint o permitir la IP/subred |
| El nombre resuelve a IP **pública** estando en la VNet | Zona `privatelink.vaultcore.azure.net` sin enlace a esa VNet | `nslookup <vault>.vault.azure.net` desde la app | Enlazar la zona (ver Red · Private Endpoint) |
| Timeout (sin respuesta) | NSG/UDR/firewall bloquea 443 hacia el PE, o DNS apunta mal | `curl -v` / `Test-NetConnection` al puerto 443 | Revisar ruta y reglas |
| `401 Unauthorized` / `AKV10032: Invalid issuer` | Token de otro tenant o audiencia equivocada | Decodifica el JWT (`iss`, `aud`) | Usar el tenant correcto; audiencia `https://vault.azure.net` |
| `SecretNotFound` (404) | Nombre/versión/vault equivocados | `az keyvault secret list --vault-name` | Corregir la referencia |
| 404 en un secreto que "sí existía" | Está **deshabilitado**, **expirado** o borrado (soft delete) | `az keyvault secret list-deleted`; atributos `enabled`/`exp` | Reactivar, rotar o `recover` |
| `Secret is currently in a deleted but recoverable state` al crear | Mismo nombre en soft delete | `az keyvault secret list-deleted` | `az keyvault secret recover` |
| `VaultAlreadyExists` / "name already in use" | Nombre global ocupado o vault borrado reservando el nombre | `az keyvault list-deleted` | Elegir otro nombre, o `az keyvault recover` |
| No puedo purgar un vault borrado | *Purge protection* activa | Propiedades del vault | Esperar la retención (es la protección funcionando) |
| `429 Too Many Requests` | Lecturas sin caché | Métricas *ServiceApiHit* / *Saturation* | Cachear; un vault por app/entorno |
| `CredentialUnavailableException` | No hay identidad en este entorno | Variables `AZURE_*`, `IDENTITY_ENDPOINT`, `az login` | Asignar identidad / workload identity |
| App Service muestra `@Microsoft.KeyVault(...)` literal | Referencia no resuelta: identidad, rol, red o sintaxis | Portal: estado de la referencia; *Diagnose and solve problems* | Habilitar identidad, rol, integración VNet, DNS |
| La referencia resuelve el valor **viejo** | La app aún no refrescó la versión | Versión en la URL (¿fija?) | Quitar la versión de la URL; reiniciar |
| Pod en `ContainerCreating` con `FailedMount` | CSI no puede leer el vault (identidad federada, rol, red) | `kubectl describe pod`; logs de `csi-secrets-store-provider-azure` | Revisar subject federado, rol y red |
| Secreto rotado pero el pod usa el viejo | Variable de entorno (no se refresca) o rotación del CSI desactivada | `kubectl exec ... env`; add-on con `--enable-secret-rotation` | Leer desde archivo o reiniciar el pod |
| `Bad request: invalid secret name` | Nombre con caracteres no permitidos (puntos, guiones bajos) | — | Solo letras, números y guiones (usa `objectAlias` en CSI) |
| `Forbidden` al crear secretos siendo Owner | Owner es plano de control; faltan roles de datos | Roles asignados | Asignarte *Secrets Officer* |
| Cifrado CMK: el servicio perdió acceso a los datos | Clave deshabilitada/borrada/expirada o identidad sin *Crypto Service Encryption User* | Estado de la clave y de la identidad | Habilitar o recuperar la clave; devolver el rol |
| `unwrapKey` falla tras rotar la clave | Se usó la versión nueva para desenvolver algo envuelto con la vieja | `keyId` guardado vs versión actual | Guardar el `keyId` de la versión en cada paquete |
| Certificado no renueva | Política sin acción de renovación, o CA integrada sin configurar | `az keyvault certificate show` | Definir *lifetime action* o emitir con la CA |
| Los eventos de vencimiento no llegan | No hay *system topic* o suscripción | `az eventgrid system-topic list` | Crear topic y suscripción |

## Comandos útiles
```bash
az keyvault show -n <kv> --query "{rbac:properties.enableRbacAuthorization, red:properties.networkAcls, publico:properties.publicNetworkAccess, purge:properties.enablePurgeProtection}" -o json
az role assignment list --scope $(az keyvault show -n <kv> --query id -o tsv) -o table
az keyvault secret show --vault-name <kv> -n <secreto> --query "{activo:attributes.enabled, vence:attributes.expires, id:id}" -o json
az keyvault list-deleted -o table
az keyvault secret list-deleted --vault-name <kv> -o table
nslookup <kv>.vault.azure.net
```

## Consulta KQL de auditoría (Log Analytics)
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where TimeGenerated > ago(1h)
| summarize n = count() by OperationName, ResultSignature, CallerIPAddress
| order by n desc
```
Picos de `Forbidden` = permisos o red; picos de `TooManyRequests` = falta de caché.
