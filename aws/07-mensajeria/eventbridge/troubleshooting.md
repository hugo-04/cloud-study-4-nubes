# AWS · EventBridge · Troubleshooting

Orden: **¿llegó al bus correcto? → ¿hay una regla habilitada en ESE bus? → ¿el patrón coincide (pruébalo)? → ¿el destino está autorizado? → ¿falla la entrega (`FailedInvocations`, DLQ)? → ¿el transformador produce JSON válido? → ¿el consumidor es idempotente?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `PutEvents` OK pero nadie recibe | Publicaste en el bus predeterminado y la regla está en el personalizado (o al revés) | `EventBusName` de la entrada vs. `list-rules --event-bus-name` | Indicar el bus en cada entrada |
| `FailedEntryCount > 0` | Limitación o error interno por entrada | `Entries[i].ErrorCode` | Reintentar solo esas entradas con espera creciente |
| La regla no coincide | Mayúsculas, número vs. texto, campo anidado mal escrito | `aws events test-event-pattern` | Corregir el patrón; `detail` ya es JSON (no cadena) en el evento recibido |
| Coincide pero no llega al destino | Política del recurso ausente | Métrica `FailedInvocations`, CloudTrail | Política con `events.amazonaws.com` y `aws:SourceArn` |
| Lambda no se invoca desde la regla | Falta el permiso `lambda:InvokeFunction` | Política de la función | `aws_lambda_permission` para `events.amazonaws.com` |
| El transformador falla o llega vacío | Ruta JSON inexistente o texto sin comillas en la plantilla | Mensaje en la DLQ / registros | Poner `"<campo>"` entre comillas si es texto; revisar rutas |
| Eventos en la DLQ | Destino caído, sin permiso o tamaño excedido | Atributos del mensaje de la DLQ (`ERROR_CODE`, `ERROR_MESSAGE`) | Corregir y reprocesar |
| `ThrottlingException` en `PutEvents` | Cuota por región | Métricas `ThrottledRules` / errores del SDK | Reintentos con *jitter*, repartir buses, pedir aumento |
| Evento rechazado por tamaño | `detail` demasiado grande | Tamaño en bytes | Claim Check |
| Duplicados tras un replay o reintento | Entrega al menos una vez | Misma clave de negocio repetida (`idOrden`) | Idempotencia por clave de negocio |
| La tarea programada corre a otra hora | Regla con `cron` en UTC | Expresión y zona | Scheduler con `schedule_expression_timezone` |
| Cuenta B no puede publicar en el bus de A | Falta política del bus | `describe-event-bus` | `aws_cloudwatch_event_bus_policy` |
