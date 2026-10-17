# AWS · Parameter Store · Troubleshooting

Orden: **¿nombre/ruta y región correctos? → ¿permiso `ssm:Get*` sobre esa ruta? → ¿es SecureString (necesita `WithDecryption` y `kms:Decrypt`)? → ¿red (endpoint `ssm`)? → ¿cuota? → ¿tipo/tamaño?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `ParameterNotFound` | Nombre sin `/` inicial, región distinta o parámetro inexistente | `aws ssm describe-parameters` | Corregir nombre/región |
| `AccessDeniedException` en `GetParametersByPath` | El ARN de permisos no cubre la ruta (falta `/*`) | Política IAM | `parameter/prod/pedidos/*` y `ssm:GetParametersByPath` |
| El valor llega cifrado/ilegible | Se pidió sin `WithDecryption` | Llamada | `WithDecryption=true` |
| `AccessDeniedException` con SecureString | Falta `kms:Decrypt` en la CMK | Política de clave | Dar permiso de clave |
| `ThrottlingException` | Demasiadas llamadas | Métricas | Caché + `GetParametersByPath` |
| `ParameterMaxVersionLimitExceeded` | 100 versiones con etiquetas | Versiones | Quitar etiquetas / borrar versiones |
| `ParameterLimitExceeded` | Tope de parámetros estándar | Cantidad | Nivel avanzado o limpiar |
| `ValidationException` por tamaño | Valor > 4 KB (estándar) | Tamaño | Nivel avanzado o dividir |
| `GetParametersByPath` no devuelve las subramas | Falta `Recursive=true` | Parámetro de la llamada | Activar recursivo |
| `GetParameters` falla con más de 10 | Límite de 10 nombres | Cantidad | Usar `ByPath` o lotes |
| Timeout desde subred privada | Sin endpoint ni NAT | Ruta/DNS | Endpoint `ssm` |
| Terraform quiere recrear parámetros | `value` cambia fuera de banda | `plan` | `ignore_changes = [value]` en los que se cargan manualmente |
