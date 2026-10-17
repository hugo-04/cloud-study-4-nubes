# AWS · SQS · Troubleshooting

Orden: **¿cola y región correctas? → ¿permisos (IAM + política de cola + KMS)? → ¿visibility timeout? → ¿DLQ y receive count? → ¿FIFO (grupo/dedup)? → ¿consumidores vivos y escalando?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AccessDenied` al enviar | Falta `sqs:SendMessage` o la política de cola no autoriza al servicio | Política de la cola | `SourceArn`/`SourceAccount` correctos |
| `KMS.AccessDenied` | Cola con KMS y el rol no puede usar la clave | CloudTrail | `kms:GenerateDataKey`/`Decrypt` |
| Mensajes duplicados | Entrega al menos una vez o timeout corto | `ApproximateReceiveCount` | Idempotencia; subir timeout |
| Mensaje reaparece sin parar | Consumidor no borra o falla | Logs; DLQ | Corregir; `maxReceiveCount` |
| La cola crece | Consumidores lentos o caídos | `ApproximateNumberOfMessagesVisible`, edad del más antiguo | Escalar consumidores; revisar errores |
| No llega nada | Long polling ya vacío, filtro SNS, cola equivocada | Métricas de la cola | Revisar suscripción y filtros |
| FIFO: se detiene un grupo | Un mensaje del grupo falla y bloquea el orden | Mensajes en vuelo del grupo | DLQ + tratar el envenenado |
| `InvalidParameterValue` en FIFO | Falta `MessageGroupId` o dedup | Mensaje de error | Enviar ambos (o dedup por contenido) |
| `ReceiptHandleIsInvalid` | Timeout vencido o mensaje ya borrado | Tiempos | Borrar dentro del timeout |
| `OverLimit` | Demasiados mensajes en vuelo | Métrica de vuelo | Borrar rápido; más colas |
| DLQ vacía pero hay fallos | `maxReceiveCount` alto o retención | Redrive policy | Ajustar |
| Costo alto | Short polling, un mensaje por llamada | Costos por solicitud | Long polling + lotes |
