# AWS · S3 · Troubleshooting

Orden: **región y nombre del bucket → identidad (¿quién soy?) → política del rol → política del bucket → KMS → Block Public Access/ACL → endpoint de VPC → TLS**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AccessDenied` al leer/escribir | Falta permiso en rol, o política de bucket/SCP lo niega | `aws sts get-caller-identity`; simulador de IAM; CloudTrail | Permiso sobre `bucket/*` (objetos) y `bucket` (listar) |
| `AccessDenied` solo con SSE-KMS | Faltan `kms:GenerateDataKey`/`Decrypt` | Error de KMS en CloudTrail | Permisos en el rol y en la política de la clave |
| `NoSuchBucket` | Nombre mal escrito o región distinta | `aws s3api get-bucket-location` | Región correcta del cliente |
| `PermanentRedirect` / 301 | Cliente en otra región | Cabecera `x-amz-bucket-region` | Configurar región o usar la del bucket |
| `NoSuchKey` | Clave incorrecta (mayúsculas, prefijo, URL-encode) | `aws s3api head-object` / listar prefijo | Corregir la clave; decodificar eventos |
| `SlowDown` / 503 | Demasiadas solicitudes por prefijo | Métricas de solicitudes | Reintentos con *backoff*, repartir prefijos |
| Subida grande falla a medias | Sin multiparte ni reintentos | Logs del cliente | Transfer Manager; regla de abortar multipartes |
| `BucketAlreadyExists` | Nombre tomado por otra cuenta | — | Añadir cuenta/región/entorno al nombre |
| Política pública rechazada | Block Public Access activo | `get-public-access-block` | Mantenerlo; usar CloudFront+OAC o URLs firmadas |
| `AccessDenied` desde la VPC | Política con `aws:SourceVpce` y tráfico por NAT | Tabla de rutas / endpoint | Endpoint de gateway en las rutas correctas |
| Checksum no coincide | Archivo cambió durante la subida o SDK distinto | Comparar SHA-256 | Reintentar; calcular el hash antes |
| Objetos viejos no desaparecen | Versionado sin regla para no actuales | `list-object-versions` | Regla `noncurrent_version_expiration` |
| Costo inesperado | Solicitudes, KMS o transferencia | Cost Explorer por tipo de uso | Agrupar objetos, Bucket Key, CloudFront |
