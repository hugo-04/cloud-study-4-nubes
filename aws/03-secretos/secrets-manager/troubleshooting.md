# AWS · Secrets Manager · Troubleshooting

Orden: **¿es el ARN/nombre correcto y de la región correcta? → ¿permiso IAM (`GetSecretValue`)? → ¿KMS (`kms:Decrypt`) y política de la clave? → ¿red (endpoint de VPC, DNS)? → ¿el secreto está en borrado programado? → ¿rotación fallida?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `ResourceNotFoundException` | Nombre/ARN o región equivocados | `describe-secret` en esa región | Corregir región/nombre |
| `AccessDeniedException` en `GetSecretValue` | Falta permiso o el ARN no coincide (sufijo aleatorio) | Política del rol | ARN con `-??????` o comodín del sufijo |
| `AccessDeniedException` con `kms:Decrypt` | Sin permiso sobre la CMK o la política de la clave no lo permite | Política de la clave | Dar `kms:Decrypt` y habilitar en la clave |
| Entre cuentas falla aun con política de recurso | Clave `aws/secretsmanager` no compartible | Clave del secreto | CMK propia |
| `InvalidRequestException: secret is scheduled for deletion` | Secreto marcado para borrar | `describe-secret` | `restore-secret` |
| Timeout al leer desde una subred privada | Sin endpoint de VPC ni NAT | Ruta y DNS | Endpoint `secretsmanager` |
| `ThrottlingException` | Demasiadas lecturas | Métricas de API | Caché con TTL |
| La rotación falla | La Lambda no llega a la base o no tiene permiso | Registros de la Lambda | Red (SG), permisos, endpoint |
| `password authentication failed` tras rotar | Pool con clave vieja | Versión en uso | Recargar y recrear conexiones |
| Rotación atascada en `AWSPENDING` | Falló un paso intermedio | Etiquetas de versión | Revisar la Lambda; reintentar `rotate-secret` |
| La tarea de ECS no inicia (`ResourceInitializationError`) | El rol de **ejecución** no puede leer el secreto o no hay ruta | Evento de la tarea | Permiso del rol de ejecución y endpoint |
| `terraform apply` muestra el secreto en el plan | `secret_string` en el código | Estado | No lo gestiones por Terraform; ver ejemplo |
