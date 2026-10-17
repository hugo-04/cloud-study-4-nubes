# Azure · Terraform · Autenticación y pipelines · Troubleshooting

Orden de revisión: **¿el pipeline obtuvo el token? → ¿Entra ID lo aceptó (issuer, subject, audiencia)? → ¿la identidad tiene el rol de control? → ¿tiene el rol de datos del estado? → ¿la red llega al estado?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Unable to get ACTIONS_ID_TOKEN_REQUEST_URL env variable` | Falta `id-token: write` | Bloque `permissions` del workflow o del trabajo | Añadir `permissions: id-token: write` (en el trabajo o en el flujo) |
| `AADSTS70021: No matching federated identity record found` | `subject` distinto al emitido | Compara el subject del mensaje con la credencial (mayúsculas incluidas) | Corregir el `subject`; revisar si el trabajo usa `environment` |
| `AADSTS700211` (issuer) | `issuer` distinto | `az identity federated-credential list` | `https://token.actions.githubusercontent.com` (sin espacios) |
| `AADSTS700212` (audiencia) | `audience` distinta | Idem | `api://AzureADTokenExchange` |
| `AADSTS70025`: el cliente no tiene credenciales federadas | La identidad no tiene ninguna credencial | Lista las credenciales de la identidad | Crear la credencial; esperar unos minutos |
| `AADSTS700016: Application not found` | `client_id` o `tenant_id` equivocados | Variables del entorno de GitHub | Usar el `client_id` de la **identidad**, no el `principal_id` |
| Funciona en `dev`, falla en `prod` | El trabajo no usa el entorno esperado | El campo `environment:` del trabajo | Alinear el entorno con el `subject` |
| `subscription_id is a required provider property` | `azurerm` 4 sin suscripción | `ARM_SUBSCRIPTION_ID` o argumento | Definir la variable o el argumento |
| `AuthorizationFailed` al crear recursos | Falta rol de control | `az role assignment list --assignee <id> --all` | Rol en el alcance correcto (suscripción o grupo de recursos) |
| `AuthorizationFailed` en `roleAssignments/write` | *Contributor* no asigna roles | Roles de la identidad | *RBAC Administrator* con condición |
| `403 AuthorizationPermissionMismatch` en el backend | Falta el rol de datos sobre el contenedor | Roles de datos | *Storage Blob Data Owner* sobre el contenedor y `use_azuread_auth` |
| `Error acquiring the state lock` | Otro trabajo en curso o candado huérfano | Panel de ejecuciones | Esperar; si está huérfano, `force-unlock` ([estado remoto](../estado-remoto/troubleshooting.md)) |
| Tiempo de espera contra el estado | Ejecutor público con firewall cerrado | `nslookup` desde el ejecutor | Ejecutor propio con Private Endpoint y DNS privado |
| `Saved plan is stale` | El estado cambió tras el plan | Orden de las ejecuciones | Volver a planificar; serializar con `concurrency` |
| `Inconsistent dependency lock file` o proveedor distinto | Versiones distintas de Terraform o del proveedor entre plan y apply | `terraform version` y `.terraform.lock.hcl` en cada trabajo | Fijar versiones y versionar el archivo de bloqueo `.terraform.lock.hcl` |
| `apply tfplan` no encuentra o no puede leer el plan | El artefacto no se descargó en la ruta esperada, o se generó con otro código/versión | Estructura de carpetas del trabajo | `download-artifact` a la ruta de trabajo, mismo commit y `init` antes de `apply` |
| El token caduca en un apply largo (Azure DevOps) | Token inicial de corta vida | Hora del error vs. inicio | Variables de conexión del proveedor para renovar el token; dividir el estado |
| `RequestDisallowedByPolicy` | Una política de Azure niega el recurso | Mensaje con el nombre de la política | Cumplir la política o pedir una excepción formal |
| Credencial recién creada sin efecto | Propagación | Hora de creación | Reintentar tras unos minutos |
| `You have reached the maximum of 20 federated identity credentials` | Demasiados `subject` en una identidad | `list` de credenciales | Más identidades o entornos; evitar un `subject` por rama |
| El plan comentado en el PR queda truncado | Límite de tamaño del comentario | Longitud de `plan.txt` | `head -c`, o subir el plan como artefacto de corta vida |

## Comandos útiles
```bash
# ¿Qué credenciales federadas tiene la identidad?
az identity federated-credential list -g rg-identidades-terraform --identity-name id-tf-prod-apply -o table

# ¿Qué roles tiene (con su condición)?
az role assignment list --assignee <principal-id> --all --query "[].{rol:roleDefinitionName, ambito:scope, condicion:condition}" -o table

# Decodificar las partes de un JWT (SIN pegarlo en sitios web): iss, aud, sub
echo "$JWT" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq '{iss, aud, sub, ref, environment}'

# Con quién estoy operando
az account show --query "{usuario:user.name, tipo:user.type, sub:id}" -o json
terraform providers
```

## Secuencia recomendada
1. **Token:** ¿el trabajo tiene `id-token: write`? ¿Es el entorno correcto? Imprime el `sub` (sin imprimir el token completo).
2. **Federación:** compara `issuer`, `subject` y `audience` del error con la credencial, letra por letra.
3. **Identidad:** ¿es el `client_id` de la identidad correcta para ese entorno?
4. **Roles de control:** ¿rol suficiente en el alcance? ¿falta asignar roles con condición?
5. **Roles de datos:** ¿rol sobre el **contenedor** del estado?
6. **Red y ejecutor:** ¿llega al almacén (DNS, Private Endpoint, firewall)?
7. **Plan guardado y versiones:** ¿misma versión, mismo código, estado sin cambios?
