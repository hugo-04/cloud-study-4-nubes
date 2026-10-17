# AWS · Caso integrado · Tienda online · Troubleshooting

## Lista ordenada
1. **¿Se guardó el pedido?** `SELECT * FROM pedidos WHERE id = ...`
2. **¿Está en la bandeja de salida y publicado?** `publicado IS NULL` mucho tiempo = publicador caído o fallando (`intentos` alto).
3. **¿Llegó al bus?** Métricas de EventBridge: `Invocations`, `MatchedEvents`, `FailedInvocations` de la regla. Prueba el patrón con `aws events test-event-pattern`.
4. **¿La cola recibió?** `ApproximateNumberOfMessages`; si es 0 y la regla coincide → política de la cola o `FailedInvocations`.
5. **¿El consumidor lee?** Rol de tarea con `sqs:ReceiveMessage`; VPC endpoint de SQS; logs del servicio.
6. **¿Se descarta como duplicado?** Busca el `idMensaje` en la bandeja de entrada (puede ser correcto).
7. **¿Cayó a la DLQ?** Lee el mensaje (con cuidado: datos personales) y su atributo `ApproximateReceiveCount`.

## Síntoma → causa

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Pedidos sin factura | Bandeja de salida acumulada | Revisar publicador, permisos `events:PutEvents`, endpoint de EventBridge |
| `MatchedEvents` sube, cola vacía | Falta `sqs:SendMessage` para el servicio | Política de cola con `SourceArn` de la regla |
| `MatchedEvents` en 0 | El patrón no coincide (tipo de dato, mayúsculas) | `test-event-pattern` con un evento real |
| Mensajes duplicados | Visibilidad menor que procesamiento | Subir visibilidad / extenderla dinámicamente |
| DLQ crece | Mensaje venenoso o bug | Arreglar, mover de vuelta con `start-message-move-task` |
| `ThrottlingException` en `PutEvents` | Ráfaga por encima de la cuota | Reintento con *backoff* + *jitter*, solo las entradas fallidas |
| Dos pedidos iguales | Cliente sin `Idempotency-Key` | Exigir cabecera; índice único en la base |
