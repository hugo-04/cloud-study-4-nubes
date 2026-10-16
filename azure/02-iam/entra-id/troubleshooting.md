# Azure · Entra ID · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AADSTS700016: Application not found in the directory` | `client_id` equivocado o app de otro tenant | Revisar `appId` y tenant | Corregir el ID/tenant |
| `AADSTS7000215: Invalid client secret` | Secreto equivocado o vencido | Fecha de vencimiento en *Certificates & secrets* | Nuevo secreto o, mejor, identidad federada |
| `AADSTS50076/50079` | MFA requerido por Conditional Access | Registro de inicios de sesión | Completar MFA / usar identidad de servicio exenta del flujo interactivo |
| `AADSTS65001: consent required` | Falta consentimiento del usuario o admin | *API permissions* → estado | Consentimiento de administrador |
| `AADSTS500011: resource principal not found` | La API (resource) no tiene service principal en el tenant | Enterprise applications | `az ad sp create --id <appId de la API>` |
| `AADSTS70011: invalid scope` | Scope mal formado; en client credentials debe terminar en `/.default` | La solicitud de token | `api://<id>/.default` |
| API responde 401 con token válido | `aud` o `iss` no coinciden (v1 vs v2) | Decodificar el token (solo desarrollo) y comparar con la config | Alinear `aud`/`iss`; usar tokens v2 (`accessTokenAcceptedVersion` = 2 en el manifiesto de la API) |
| API responde 403 con token válido | Falta el scope o el app role en `scp`/`roles` | Claims del token | Conceder el permiso y consentir |
| El token no trae `roles` | El cliente no tiene asignado el app role, o se pidió un token delegado | Roles asignados al service principal | Asignar el app role (`azuread_app_role_assignment`) |
| Error 431 / cabeceras muy grandes | Demasiados grupos en el token | Claim `groups` / `_claim_names` | No depender de `groups`; usar app roles o Graph |
| `invalid_token ... Signed JWT rejected` | Reloj desfasado o claves rotadas sin caché actualizada | Hora del servidor; JWKS | Sincronizar NTP; permitir refresco de claves |
| Funciona en local, no en Azure | `DefaultAzureCredential` toma otra credencial | Habilitar logs del SDK | Definir identidad administrada y rol |
| No puedo crear app registrations | Directiva del tenant | Rol de Entra | Pedir rol Application Developer |

## Comandos útiles
```bash
az ad app show --id <appId> --query "{nombre:displayName,uri:identifierUris,roles:appRoles[].value}" -o json
az ad sp show --id <appId> --query "{id:id,nombre:displayName}" -o json
az ad group member list --group <grupo> --query "[].displayName" -o tsv
az account get-access-token --resource api://<appId>        # solo desarrollo
```
