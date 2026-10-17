# AWS · Lambda · Troubleshooting

Orden: **¿se invoca? (métricas Invocations/Errors/Throttles) → ¿falla Init o falla el handler? (logs, `REPORT`, `Init Duration`) → ¿permisos (rol de ejecución / política de recurso)? → ¿red (VPC)? → ¿timeout/memoria? → ¿reintentos/DLQ?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| No se invoca | Falta política de recurso o el origen está mal configurado | `get-policy`; estado del mapping | Permiso `lambda:InvokeFunction` con `SourceArn` |
| `Task timed out after N seconds` | Timeout bajo o llamada bloqueada (VPC sin salida) | Logs | Subir timeout, revisar red |
| `Runtime exited with error: signal: killed` / `OutOfMemoryError` | Memoria insuficiente | `REPORT` → `Max Memory Used` | Subir memoria |
| `Init Duration` alto | Muchas clases, framework pesado | `REPORT` | SnapStart, menos dependencias, más memoria |
| `Throttles` / `TooManyRequestsException` | Concurrencia agotada | Métrica `ConcurrentExecutions` | Reservada, `maximum_concurrency`, pedir aumento |
| `AccessDeniedException` en el código | Falta permiso en el rol de **ejecución** | Logs; rol | Añadir permiso |
| Mensajes SQS duplicados | Lote completo reintentado | Logs | `ReportBatchItemFailures` + idempotencia |
| Mensajes reaparecen mientras se procesan | Visibilidad menor que el timeout | Atributos de la cola | Visibilidad ≥ 6×timeout |
| Mensajes en bucle infinito | Sin DLQ ni `maxReceiveCount` | Redrive policy | DLQ en la cola |
| Sin salida a Internet | Función en VPC sin NAT | Rutas de la subred | NAT o endpoints |
| `ResourceConflictException` al desplegar | Actualización en curso | Estado de la función | Esperar `LastUpdateStatus=Successful` |
| `RequestEntityTooLargeException` | Payload > límite | Tamaño | Claim Check con S3 |
| SnapStart: errores tras restaurar | Estado capturado obsoleto (conexiones, semillas) | Logs de restauración | Reinicializar tras restore (hooks) |
| No llegan logs | Rol sin `logs:*` o grupo con otro nombre | Rol | Permisos de logs |
