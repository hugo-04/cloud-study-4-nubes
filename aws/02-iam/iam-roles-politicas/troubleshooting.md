# AWS · IAM · Roles y políticas · Troubleshooting

Orden: **¿quién soy realmente (`get-caller-identity`)? → ¿hay un Deny explícito (identidad, recurso, SCP, límite, sesión)? → ¿falta el Allow? → ¿condiciones (red, MFA, etiquetas, región)? → ¿KMS?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AccessDenied` con mensaje «not authorized to perform … because no identity-based policy allows» | Falta el Allow | Mensaje de error y simulador | Añadir la acción al recurso correcto |
| «… with an explicit deny in a service control policy» | SCP de la organización | Mensaje de error | Pedir excepción o usar región/servicio permitido |
| «… with an explicit deny in a resource-based policy» | Política del recurso niega | Política del bucket/cola/clave | Ajustar condición (p. ej. endpoint, organización) |
| Entre cuentas: `AccessDenied` aunque mi rol permite | Falta la política de recurso | Política del recurso destino | Añadir principal del otro lado |
| Funciona con admin y no con el rol de la app | Se omitió un permiso asociado (KMS, `PassRole`) | CloudTrail del `AccessDenied` | Añadir lo que falta, mínimo |
| `iam:PassRole` denegado al crear Lambda/ECS | Falta `PassRole` sobre ese rol | Mensaje de error | `PassRole` al ARN, `PassedToService` |
| `InvalidClientTokenId` / `ExpiredToken` | Credenciales caducadas o inválidas | `aws sts get-caller-identity` | Renovar sesión; revisar reloj |
| `AssumeRole` denegado | Confianza no incluye al principal o falta `sts:AssumeRole` | Política de confianza | Corregir confianza y permiso |
| Política rechazada por tamaño | Límite de caracteres | Tamaño del JSON | Dividir, comodines sensatos, ABAC |
| `MalformedPolicyDocument` | ARN o acción mal escritos | Validador de Access Analyzer | `aws accessanalyzer validate-policy` |
| Cambios de IAM «no aplican» | Consistencia eventual (segundos) | Reintentar | Esperar y reintentar con backoff |
| Acceso externo inesperado | Política de recurso con `Principal: *` | Access Analyzer | Acotar principal/condición |
