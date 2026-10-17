# AWS · IAM Identity Center · Troubleshooting

Orden: **¿la persona está en el grupo del directorio? → ¿el grupo llegó a Identity Center (SCIM)? → ¿hay asignación a esa cuenta con ese conjunto de permisos? → ¿se aprovisionó el rol en la cuenta? → ¿la sesión/token caducó? → ¿SCP o límite recortan?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| La persona no ve ninguna cuenta en el portal | Sin asignaciones o grupo sin sincronizar | Grupos del usuario en Identity Center | Sincronizar SCIM; asignar |
| Ve la cuenta pero no el conjunto de permisos | Asignación faltante para ese grupo | Asignaciones de la cuenta | Crear asignación |
| Cambié el conjunto de permisos y no aplica | Falta **reaprovisionar** en las cuentas | Estado de aprovisionamiento | Reaprovisionar / esperar |
| `aws sso login` falla o abre página en blanco | Región/URL de inicio mal | `sso_start_url`, `sso_region` | Corregir el perfil |
| `The SSO session associated with this profile has expired` | Token caducado | `aws sso login` | Iniciar sesión otra vez |
| El SDK de Java no usa el perfil SSO | Faltan los módulos `sso` y `ssooidc` | Classpath | Añadir dependencias |
| `AccessDenied` aunque el conjunto es administrador | SCP o límite de permisos | Mensaje de error | Revisar SCP de la OU |
| El nombre del rol cambia entre cuentas | Sufijo hash `AWSReservedSSO_…_xxxx` | Rol en IAM | No lo referencies por nombre completo; usa condiciones o el prefijo |
| Un usuario sigue con acceso tras la baja | Sesión viva hasta que caduque | Duración de sesión | Sesiones cortas; revocar sesiones activas |
| SCIM falla con 429 o duplicados | Límites o atributos repetidos | Registros del proveedor | Reintentar; limpiar duplicados |
| No puedo eliminar un conjunto de permisos | Tiene asignaciones | Asignaciones | Quitar asignaciones primero |
