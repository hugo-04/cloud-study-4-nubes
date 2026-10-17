# Google Cloud · Mensajería · Pub/Sub · Troubleshooting

## Lista ordenada
1. **¿Se publica?** Errores del `Publisher` (permisos, tamaño, clave de orden pausada tras error).
2. **¿Mensajes no confirmados crecen?** Métrica `num_undelivered_messages` y antigüedad del más viejo.
3. **¿Reentregas?** Ack deadline corto o procesamiento lento; extiende o acelera.
4. **¿Push falla?** Respuestas no 2xx, OIDC y `run.invoker`.
5. **¿DLQ?** Permisos del agente de servicio.
6. **¿Orden?** Clave de orden + opción de la suscripción + mismo endpoint regional.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `PERMISSION_DENIED` al publicar | Falta `publisher` | Rol en el tema |
| Mensajes duplicados | Al menos una vez / ack tardío | Idempotencia, extender plazo |
| Publicación con clave «pausada» | Error previo con esa clave | `resumePublish(clave)` |
| Backlog creciente | Consumidores lentos | Escalar, flow control |
| Push 403 | Invoker/OIDC | Configura la cuenta |
