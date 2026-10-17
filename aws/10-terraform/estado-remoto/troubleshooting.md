# AWS · Estado remoto · Troubleshooting

Orden: **¿el backend apunta al bucket y la región correctos? → ¿tienes permiso sobre el prefijo (y KMS)? → ¿hay un candado vigente (¿de quién?)? → ¿la versión de Terraform es compatible con el estado? → ¿el estado y la realidad coinciden (deriva)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Error acquiring the state lock` | Otro `apply` en curso o un proceso que murió | El mensaje trae ID, quién y desde cuándo | Esperar; si el proceso murió, `terraform force-unlock <ID>` tras confirmar que nadie aplica |
| `AccessDenied` al hacer `init` | Falta `s3:ListBucket`, `GetObject` o permiso de KMS | CloudTrail del rol; política del rol | Conceder permisos **solo** sobre el prefijo y la clave |
| `NoSuchBucket` / `PermanentRedirect` | Bucket inexistente o región equivocada | `aws s3api get-bucket-location` | Corregir `bucket` y `region` |
| `Backend configuration changed` | Cambió el bloque `backend` | Diferencia con el `init` anterior | `terraform init -reconfigure` (sin mover) o `-migrate-state` (moviendo) |
| `Failed to save state` | Se perdió el permiso o la conexión al final del `apply` | Mensaje y `errored.tfstate` local | Reintentar `terraform state push errored.tfstate` con permisos correctos |
| `state snapshot was created by Terraform vX` | Estado escrito por una versión más nueva | `terraform version` | Usar la versión igual o mayor; fijar `required_version` |
| El plan quiere destruir tras renombrar | Falta `moved` | Plan: `must be replaced` | Añadir `moved { from = ... to = ... }` |
| `already exists` al crear | El recurso ya existía fuera de Terraform | Consola/CLI | `import` (o `-generate-config-out`) |
| Cambios que nadie hizo en el plan | Deriva por edición manual | `plan -detailed-exitcode` nocturno | Revertir el cambio manual o actualizar el código |
| `terraform_remote_state` no lee | Permisos, salida inexistente o clave equivocada | `terraform output` del componente origen | Permiso `GetObject` y publicar la salida |
| Plan muy lento | Estado enorme o demasiadas lecturas | Cantidad de recursos | Dividir; usar `-target` solo en emergencias |
| Se ve un `.tflock` viejo en el bucket | Proceso interrumpido | `LastModified` del objeto | Confirmar y `force-unlock`; el auditor de Java los lista |
| Recuperé una versión y el plan sigue distinto | La versión restaurada era anterior a cambios reales | `serial` y fecha de la versión | Restaurar una más reciente o importar lo faltante |
