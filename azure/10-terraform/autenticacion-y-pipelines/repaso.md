# Azure · Terraform · Autenticación y pipelines · Repaso

## Preguntas de repaso
1. ¿Qué problema tiene un service principal con secreto en un pipeline?
   - *El secreto caduca, se filtra y se copia; hay que rotarlo y guardarlo.*
2. ¿Qué es la federación de identidad de carga de trabajo (OIDC)?
   - *El pipeline presenta un token de corta vida de su plataforma; Entra ID lo cambia por un token de Azure si coincide con una credencial federada. No hay secretos.*
3. ¿Qué tres campos se comparan en una credencial federada?
   - *`issuer`, `subject` y `audience`, de forma exacta (distingue mayúsculas).*
4. ¿Cuál es el emisor y la audiencia para GitHub Actions?
   - *`https://token.actions.githubusercontent.com` y `api://AzureADTokenExchange`.*
5. ¿Qué `sub` emite un trabajo que referencia el entorno `prod`?
   - *`repo:org/repo:environment:prod`, incluso si lo dispara un pull request.*
6. ¿Qué permiso necesita el trabajo de GitHub para pedir el token?
   - *`permissions: id-token: write`.*
7. ¿Cuántas credenciales federadas admite una identidad y se aceptan comodines?
   - *20 como máximo; no se aceptan comodines.*
8. ¿Qué pasa si el `subject` está mal escrito al crear la credencial?
   - *Se crea sin error y falla recién en el login (por ejemplo, `AADSTS70021`).*
9. ¿Por qué dos identidades por entorno?
   - *Plan (lectura) y apply (cambios) tienen riesgos distintos; si se filtra la de plan, no se puede cambiar nada.*
10. ¿Por qué *Contributor* no basta si el código crea asignaciones de roles?
    - *No puede escribir `roleAssignments`; hace falta *RBAC Administrator*, mejor con condición.*
11. ¿Qué hace la condición del administrador de RBAC?
    - *Limita qué roles puede asignar o quitar la identidad (lista de GUID de roles).*
12. ¿Por qué la identidad de plan también necesita rol de datos sobre el estado?
    - *Porque el `plan` toma el candado (escribe); alternativa: rol de lectura y `plan -lock=false`.*
13. ¿Qué es un plan guardado y por qué se usa?
    - *`terraform apply tfplan` ejecuta exactamente lo que se revisó; si el estado cambió, se niega.*
14. ¿Por qué `cancel-in-progress: false` en el apply?
    - *Cancelar un apply a medias deja el candado huérfano y el estado inconsistente.*
15. ¿Para qué sirve el entorno protegido de producción?
    - *Revisores obligatorios y restricción de ramas; además el nombre del entorno forma parte del `subject`.*
16. ¿Qué hace el plan nocturno?
    - *Detecta deriva (diferencias entre código y realidad) y avisa.*
17. ¿Qué hace un analizador de planes y por qué no registra los valores?
    - *Lee `terraform show -json`, detecta borrados protegidos, roles privilegiados y exposición pública; no registra valores porque el plan contiene secretos.*
18. ¿Cuándo hacen falta ejecutores propios?
    - *Cuando el estado o las redes de destino son privados (sin IP pública estable).*
19. ¿Qué diferencia hay entre identidad administrada y registro de aplicación para pipelines?
    - *La identidad administrada es un recurso de Azure sin secretos ni permisos de directorio; el registro de aplicación sirve cuando necesitas Graph u otros casos del directorio.*
20. ¿Por qué tu microservicio Java no ejecuta Terraform?
    - *Es una herramienta de pipeline; en Java se construye plataforma (analizar planes, portal de autoservicio) con control y aislamiento.*

## Mini-ejercicios
1. Escribe las dos credenciales federadas (plan y apply) de `dev` para el repositorio `modalima/infra-azure`.
2. Diseña los roles de `id-tf-prod-apply` si el código crea grupos de recursos, redes y asignaciones de *Reader*; indica el alcance de cada rol.
3. Escribe el `jq` que impide aplicar si el plan borra una cuenta de almacenamiento o un Key Vault.
4. Un PR muestra `AADSTS70021`. Enumera 4 comprobaciones en orden.
5. Define el flujo de aprobación de producción: quién aprueba, qué ve y qué puerta automática corre antes.
6. Migra un pipeline que usa `ARM_CLIENT_SECRET` a OIDC sin interrumpir despliegues (pasos y verificaciones).

## Frases para recordar
- **Sin secretos: el pipeline muestra un pase de un día, no una llave maestra.**
- **El `subject` es parte de la seguridad; el entorno protegido es parte del `subject`.**
- **Plan lee, apply cambia: dos identidades por entorno.**
- **Aplica el plan que revisaste, de uno en uno, y nunca canceles un apply.**
- **Quien edita el workflow manda: trátalo como código de producción.**
