# Azure · Terraform · Autenticación y pipelines · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · El secreto que caducó un viernes
- **Problema:** el pipeline de producción de ModaLima falló a las 17:50 con `AADSTS7000222: the provided client secret keys are expired`. Nadie recordaba quién lo creó.
- **Causa:** un service principal con secreto de 2 años, guardado en el CI.
- **Solución:** migración a identidades administradas con credencial federada OIDC; el secreto se eliminó del CI y del directorio.
- **Lección:** lo que se rota "algún día" caduca un viernes. Lo mejor es **no tener secreto**.

## Caso 2 · El 70021 por un entorno mal escrito
- **Problema:** el login de GitHub falló con `AADSTS70021: No matching federated identity record found`.
- **Causa:** la credencial decía `environment:Prod`; el workflow usaba `environment: prod`. El `subject` distingue mayúsculas.
- **Solución:** comparar el mensaje de error (trae issuer, subject y audience recibidos) con la credencial y corregir; añadir una prueba que imprime el `sub` esperado en el PR.
- **Lección:** Azure no valida el `subject` al crearlo; el error aparece en el primer login. Compara **letra por letra**.

## Caso 3 · El plan de un PR que podía leer producción
- **Problema:** en la revisión de seguridad se vio que la identidad con rol de datos sobre el estado de producción confiaba en `repo:modalima/infra:pull_request`.
- **Causa:** cualquier PR (incluso con un workflow modificado) podía obtener esa identidad y leer los estados.
- **Solución:** entornos `dev-plan`/`prod-plan` con `sub` propio, contenedores de estado separados por entorno y plan de PR con `-lock=false` y rol de solo lectura donde era suficiente.
- **Lección:** el `subject` es parte del perímetro de seguridad. Cuanto más específico, mejor.

## Caso 4 · Apply sin aprobación "porque era solo dev"
- **Problema:** un cambio en la red de dev se aplicó con una variable equivocada y borró una subred que usaba QA.
- **Causa:** apply automático sin plan revisado.
- **Solución:** plan comentado en el PR, puerta automática (`jq`) para tipos protegidos y apply del plan guardado; producción con revisores obligatorios.
- **Lección:** la aprobación no es burocracia, es leer el plan.

## Caso 5 · `AuthorizationFailed` al crear un role assignment
- **Problema:** `apply` falló en `azurerm_role_assignment` con `does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'`.
- **Causa:** la identidad de apply tenía *Contributor*, que no puede asignar roles.
- **Solución:** *Role Based Access Control Administrator* **con condición** que solo permite *Reader* y *Key Vault Secrets User*; sin *Owner*.
- **Lección:** dar *Owner* "para que pase" convierte al pipeline en un administrador total. Delega **solo lo necesario**.

## Caso 6 · El apply cancelado y el candado huérfano
- **Problema:** alguien canceló una ejecución de apply; las siguientes fallaron con `Error acquiring the state lock`.
- **Causa:** `cancel-in-progress: true` en el grupo de concurrencia de apply mató el proceso sin soltar el candado.
- **Solución:** `force-unlock` tras confirmar que nadie aplicaba y `cancel-in-progress: false` en los grupos de apply.
- **Lección:** cancela planes, **nunca** applies. Más en [estado remoto](../estado-remoto/casos-reales.md).

## Caso 7 · El ejecutor público contra el firewall
- **Problema:** tras cerrar la red de la cuenta del estado, los trabajos fallaban con tiempo de espera.
- **Causa:** los ejecutores públicos no tienen IP estable.
- **Solución:** ejecutores propios en una red con Private Endpoint al almacén; variable `RUNNER_TF` para elegirlos sin tocar los workflows.
- **Lección:** decide **desde dónde** se opera antes de cerrar la red.

## Caso 8 · El plan guardado que "ya no aplicaba"
- **Problema:** `terraform apply tfplan` falló con `Saved plan is stale`.
- **Causa:** otro apply cambió el estado entre el plan y la aprobación (la aprobación tardó 6 horas).
- **Solución:** no es un error: se vuelve a planificar. Se acortó la ventana de aprobación y se serializó con `concurrency`.
- **Lección:** el plan guardado te protege de aplicar algo distinto de lo que revisaste.

## Caso 9 · El artefacto del plan con una contraseña
- **Problema:** una auditoría encontró `tfplan` en los artefactos de Actions, descargables por cualquier persona con acceso de lectura al repositorio.
- **Causa:** retención por defecto y plan con atributos sensibles en texto.
- **Solución:** retención de 1 día, un entorno con acceso restringido para descargas y cero contraseñas generadas por Terraform (se leen de Key Vault en tiempo de ejecución).
- **Lección:** el plan es un secreto igual que el estado.

## Caso 10 · La política que detuvo el borrado de la base de datos
- **Problema:** una refactorización cambió el nombre de un recurso `azurerm_mssql_database`; el plan mostraba destruir y crear.
- **Causa:** faltaba el bloque `moved`.
- **Solución:** la puerta de seguridad (analizador de plan) devolvió **BLOQUEAR** por borrado de un tipo protegido; se añadió `moved` y el plan quedó en cero cambios.
- **Lección:** una puerta automática atrapa lo que el cansancio de la revisión humana pasa por alto.

## Caso 11 · Drift nocturno
- **Problema:** una persona abrió el puerto 22 en un NSG desde el portal "solo un rato".
- **Causa:** cambio manual fuera de Terraform.
- **Solución:** el plan nocturno detectó la diferencia, abrió un aviso y el siguiente apply la revirtió; se retiró el permiso de escritura del portal a las personas.
- **Lección:** la deriva se detecta y corrige cuando es pequeña. El mejor control es que **nadie** tenga permisos de escritura permanentes en producción.

---

## Patrones que se repiten
| Patrón | Casos |
|---|---|
| Sin secretos: OIDC | 1, 2 |
| El `subject` es seguridad | 2, 3 |
| Separar plan/apply y entornos | 3, 5 |
| Revisar el plan (humano + automático) | 4, 8, 10 |
| Serializar y no cancelar applies | 6, 8 |
| Red y ejecutores | 7 |
| Plan y estado son secretos | 9 |
| Drift y permisos permanentes | 11 |
