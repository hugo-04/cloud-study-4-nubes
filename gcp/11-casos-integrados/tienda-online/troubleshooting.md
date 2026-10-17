# Google Cloud · Caso integrado · Tienda online · Troubleshooting

## Lista ordenada
1. **¿Se escribió el outbox?** `SELECT estado, count(*) FROM outbox GROUP BY estado`.
2. **¿El relay corre?** Logs de su ejecución y filas `PENDIENTE` envejeciendo.
3. **¿Publica?** Errores de permisos (`pubsub.publisher`) o del endpoint regional con orden.
4. **¿Las suscripciones entregan?** Backlog y DLQ por suscripción.
5. **¿El consumidor deduplica?** Inbox con clave única.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Pendientes que crecen | Relay detenido | Revisa el disparador del relay |
| `PERMISSION_DENIED` al publicar | Rol | `pubsub.publisher` en el tema |
| Mensajes en la DLQ | Consumidor falla | Revisa y reprocesa |
| Duplicados | Sin inbox | Agrega la clave única |
| Desorden | Sin clave de orden | Orden por pedido |
