# AWS · KMS · Troubleshooting

Orden: **¿alias/ARN y región correctos? → ¿estado de la clave (`Enabled`)? → ¿la política de la clave permite a la cuenta/rol? → ¿IAM permite la acción sobre esa clave? → ¿contexto de cifrado igual? → ¿cuotas? → ¿red (endpoint)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AccessDeniedException` en `Decrypt`/`GenerateDataKey` | Falta permiso IAM **o** la política de clave no habilita IAM | Política de clave (¿incluye la raíz de la cuenta?) | Añadir la raíz a la política de clave y el permiso IAM |
| Entre cuentas: denegado | Falta de un lado | Política de clave del dueño + IAM del consumidor | Ambos lados |
| `DisabledException` | Clave deshabilitada | `describe-key` | `enable-key` |
| `KMSInvalidStateException` / `pending deletion` | Clave en borrado | `describe-key` | `cancel-key-deletion` |
| `InvalidCiphertextException` | Contexto distinto, clave distinta o dato corrupto | Contexto usado al cifrar | Mismo contexto y misma clave |
| `IncorrectKeyException` | `keyId` distinto al que cifró | `keyId` de `Decrypt` | Usar la clave correcta |
| `ThrottlingException` / `LimitExceededException` | Cuota por región | Métricas | Bucket Keys, caché, reintentos con backoff |
| `NotFoundException: alias/…` | Alias inexistente o región incorrecta | `list-aliases` | Crear o corregir |
| Timeout desde subred privada | Sin endpoint ni NAT | Ruta/DNS | Endpoint `kms` |
| S3/SQS responden `KMS.AccessDenied` | El principal que llama no puede usar la clave | Rol del que llama + `kms:ViaService` | Dar `kms:Decrypt/GenerateDataKey` |
| `ValidationException` con `Encrypt` | Datos > 4 KB | Tamaño | Cifrado de sobre |
| Costos de KMS altos | Muchas solicitudes | Métricas por clave | Bucket Keys, reducir claves, caché |
