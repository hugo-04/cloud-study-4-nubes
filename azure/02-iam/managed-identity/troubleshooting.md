# Azure · Managed Identity · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `CredentialUnavailableException` / "ManagedIdentityCredential authentication unavailable" | En local no hay identidad; en Azure no está asignada | ¿Corre en Azure? Configuración → Identity del recurso | `az login` en local; asignar la identidad al recurso |
| 400 al pedir token ("identity not found") | `client_id` equivocado, o la identidad no está asignada a este recurso | `AZURE_CLIENT_ID` vs `az identity show` | Corregir el `client_id`; asignar la identidad |
| 403 del servicio con token válido | Falta rol de datos, o aún no se propagó | `az role assignment list --assignee <principalId> --all` | Asignar el rol; esperar y reiniciar |
| Funciona con system-assigned y no con user-assigned | Falta `client_id` o hay varias identidades | Variables de entorno | Fijar `AZURE_CLIENT_ID` |
| Error "multiple user assigned identities" | El recurso tiene varias y no se eligió una | Identidades asignadas | Indicar `client_id` |
| 429 al pedir tokens | Se pide un token por petición | Logs del SDK | Reutilizar el cliente (cachea token) |
| El cambio de roles no se refleja | Token en caché con claims viejas | Esperar a que expire; reiniciar | Reiniciar la app |
| Terraform: `PrincipalNotFound` al asignar rol | La identidad aún no replicó | Reintentar | `depends_on`, o `principal_type = "ServicePrincipal"` |
| SQL: `Login failed for user '<token-identified principal>'` | La identidad no existe como usuario en la base | `SELECT name FROM sys.database_principals` | `CREATE USER [id] FROM EXTERNAL PROVIDER` |
| PostgreSQL: `password authentication failed` | Usuario de BD no creado para la identidad o plugin no configurado | Usuarios de Entra en el servidor | Crear el administrador/usuario de Entra y configurar el plugin |
| Funciona sin red privada y falla con ella | DNS/ruta al servicio (no es de identidad) | `nslookup`, `ConnCheck` | Ver carpeta de red |

## Comandos útiles
```bash
az identity show -g <rg> -n <id> -o json
az role assignment list --assignee <principalId> --all -o table
az webapp identity show -g <rg> -n <app>
az containerapp show -g <rg> -n <app> --query identity
# Desde una VM con identidad (IMDS):
curl -s -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/"
```
