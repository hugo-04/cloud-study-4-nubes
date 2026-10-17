# AWS · Autenticación y pipelines · Troubleshooting

Orden: **¿el workflow tiene `id-token: write`? → ¿existe el proveedor OIDC en esa cuenta? → ¿`aud` y `sub` del token coinciden con la política de confianza? → ¿el rol tiene los permisos (y el límite) necesarios? → ¿el estado es accesible desde ese rol? → ¿la sesión caducó?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Credentials could not be loaded` / no hay token | Falta `permissions: id-token: write` | Bloque `permissions` del job | Añadirlo al **job** que asume el rol |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | El `sub` o `aud` no coincide con la política de confianza | Imprime el `sub` real (el entorno/rama/PR) y compara | Ajustar la condición al `sub` exacto |
| `No OpenIDConnect provider found in your account` | Falta el proveedor OIDC en esa cuenta | `aws iam list-open-id-connect-providers` | Crear el proveedor (por cuenta) |
| `Request ARN is invalid` | `role-to-assume` mal escrito | ARN en el workflow | Corregirlo |
| Funciona en `main` pero no en PR | El `sub` de PR es `...:pull_request` | Condición del rol de `plan` | Añadir el `sub` de PR al rol de lectura |
| Funciona en dev, falla en prod | El `sub` exige `environment:prod` y el job no declara `environment` | Job: `environment: prod` | Declarar el entorno en el job |
| PR de un fork no asume el rol | Los forks no reciben token con permisos | Origen del PR | Es una protección; planifica desde una rama del repositorio |
| `AccessDenied` en `init` (estado) | El rol no tiene permiso sobre el prefijo o la clave KMS | Política de estado del rol | Conceder lectura/escritura del prefijo y KMS |
| `AccessDenied` en un servicio concreto | La política de `apply` no cubre ese servicio | Mensaje con la acción; CloudTrail | Añadir lo mínimo necesario |
| `iam:CreateRole` denegado | El límite de permisos es obligatorio | Condición `iam:PermissionsBoundary` | Definir `permissions_boundary` en el rol creado |
| `ExpiredToken` a mitad de un `apply` | Sesión de 1 h agotada | Duración del `apply` | Dividir el componente o subir la duración del rol (hasta el máximo permitido) |
| `Error acquiring the state lock` en el siguiente run | Se canceló el anterior | Ver el estado remoto | Esperar o `force-unlock` tras confirmar |
| El apply usa un plan distinto al aprobado | Se volvió a planificar | Pasos del job | Subir `tfplan` como artefacto y aplicarlo tal cual |
| La puerta bloquea un cambio legítimo | Regla demasiado estricta o cambio de riesgo real | Informe de la puerta | Excepción documentada (aprobador) o ajustar la regla |
