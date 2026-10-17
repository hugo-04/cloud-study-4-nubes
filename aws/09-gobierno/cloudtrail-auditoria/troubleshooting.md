# AWS · CloudTrail · Troubleshooting

Orden: **¿hay una traza activa y registrando? → ¿el bucket y la clave KMS permiten a CloudTrail escribir? → ¿el evento es de administración o de datos (y está habilitado)? → ¿es la región correcta? → ¿esperaste el retraso normal? → ¿los permisos de lectura son suficientes?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| No llegan archivos al bucket | Política del bucket sin permiso para CloudTrail; traza detenida | `get-trail-status` (`LatestDeliveryError`, `IsLogging`) | Política con `cloudtrail.amazonaws.com` (`GetBucketAcl`, `PutObject`) y `aws:SourceArn` |
| `InsufficientEncryptionPolicyException` | La política de la clave KMS no permite a CloudTrail | Política de la clave | Permitir `GenerateDataKey*` y `DescribeKey` a `cloudtrail.amazonaws.com` con contexto de cifrado |
| `InvalidCloudWatchLogsRoleArnException` | Rol hacia CloudWatch Logs mal configurado | Rol y política | `logs:CreateLogStream`, `PutLogEvents` sobre el grupo |
| No veo el evento reciente | Retraso normal (minutos) | Hora del evento vs. ahora | Esperar; consultar de nuevo |
| No veo eventos de datos (S3, Lambda) | No están habilitados en la traza | `get-event-selectors` / selectores avanzados | Habilitar solo donde aportan |
| `LookupEvents` no encuentra | Solo administración, 90 días, una región, un atributo | Región y filtros | Usar la traza + Athena para más alcance |
| `LookupEvents` con `ThrottlingException` | Más de ~2 solicitudes por segundo | Frecuencia de llamadas | Pausas entre páginas, reintentos con espera, tope de páginas |
| Eventos de otra cuenta no aparecen | La traza no es de organización | `describe-trails` | Traza de organización desde la cuenta de administración |
| `errorCode: AccessDenied` con mensaje de SCP | Una SCP deniega la acción | `errorMessage` del evento | Revisar SCP ([Organizations](../organizations-scp/README.md)) |
| Athena devuelve 0 filas | Partición, región o fechas distintas a las de los archivos | Ruta S3 y proyección | Ajustar `projection` y el rango de fechas |
| Athena lento/caro | Consulta sin filtrar por fecha | Bytes escaneados | Filtrar por partición y columnas |
| `validate-logs` informa archivos inválidos | Modificación o ausencia de archivos | Salida del comando | Investigar: puede ser una manipulación; restaurar desde copia protegida |
| Factura de CloudTrail alta | Eventos de datos amplios o copias de administración adicionales | Cost Explorer por tipo de uso | Acotar selectores; una traza por región/organización |
