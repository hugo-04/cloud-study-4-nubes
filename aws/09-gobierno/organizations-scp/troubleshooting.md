# AWS · Organizations y SCP · Troubleshooting

Orden: **¿el error menciona una SCP? → ¿qué SCP afecta a la cuenta (por herencia)? → ¿la acción es de un servicio global? → ¿es la cuenta de administración o un rol vinculado a servicio (no afectados)? → ¿tipo de política habilitado? → ¿límites (tamaño, número)? → ¿propagación?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AccessDenied ... explicit deny in a service control policy` | Una SCP del camino deniega la acción | CloudTrail: `errorMessage`; `list-policies-for-target` de la cuenta y de sus OU | Ajustar la SCP (por el repositorio) o usar el camino aprobado |
| `... no service control policy allows the action` | Estrategia de lista de permitidos: falta `Allow` en algún nivel | SCP de cada nivel del camino | Permitir en todos los niveles o volver a `FullAWSAccess` |
| Un administrador no puede hacer algo que su política permite | Techo de la SCP | Mensaje de error; política efectiva | Revisar SCP antes de tocar IAM |
| La SCP de regiones rompe IAM, Route 53, CloudFront | Faltan servicios globales | `NotAction` de la SCP | Agregar los servicios globales a `NotAction` |
| La SCP no afecta a una cuenta | Es la cuenta de administración o un rol vinculado a servicio | Cuenta y tipo de rol | Esperado; protege la cuenta con otras medidas |
| `PolicyTypeNotEnabledException` | El tipo SCP no está habilitado en la raíz | `list-roots` (campo de tipos habilitados) | `enable-policy-type` |
| `ConstraintViolationException` | Tamaño excedido o demasiadas SCP adjuntas | Tamaño del JSON; adjuntas por destino | Minimizar; combinar sentencias; usar OU |
| `DuplicatePolicyException` / `DuplicatePolicyAttachmentException` | La política o el vínculo ya existen | `list-policies` | Hacerlo idempotente: actualizar o ignorar |
| `AWSOrganizationsNotInUseException` | Se llama desde una cuenta fuera de la organización | Cuenta de las credenciales | Usar credenciales de la administración (o del administrador delegado) |
| `CreateAccount` queda `IN_PROGRESS` | Creación asíncrona o límite | `describe-create-account-status` | Esperar; revisar motivo de fallo y cuota |
| `ConcurrentModificationException` | Cambios simultáneos en la organización | Pipeline duplicado | Serializar los cambios |
| Un cambio de SCP «no aplica» | Propagación en curso o SCP equivocada | Reintentar tras unos minutos; verificar destino | Esperar; confirmar adjunción |
| Terraform: «already exists» al adjuntar | Vínculo creado fuera de Terraform | `list-policies-for-target` | `tofu import` o eliminar el manual |
