# Google Cloud · Storage · Eventos de Cloud Storage · Troubleshooting

## Lista ordenada
1. **¿Existe la notificación?** `gcloud storage buckets notifications list gs://<bucket>`.
2. **¿Agente con `pubsub.publisher`?**
3. **¿Prefijo y tipos correctos?**
4. **¿La suscripción entrega?** Métricas de mensajes no confirmados y DLQ.
5. **¿El push llega?** Cloud Run privado con OIDC y `run.invoker` para la cuenta de la suscripción.
6. **¿Duplicados?** Normales: deduplica.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Tema sin mensajes | Permiso del agente | `pubsub.publisher` |
| Push con 403 | Sin invoker/OIDC | Configura OIDC y rol |
| Duplicados | Al menos una vez | Generación |
| 404 al leer | Objeto reemplazado/borrado | Descarta |
| Bucle | Mismo prefijo | Separa salida |
