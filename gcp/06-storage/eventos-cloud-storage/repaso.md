# Google Cloud · Storage · Eventos de Cloud Storage · Repaso

## Preguntas
1. ¿Qué caminos hay para eventos de Cloud Storage?
2. ¿Qué tipos de evento existen?
3. ¿Qué identifica la versión exacta?
4. ¿Quién publica en el tema?
5. ¿Qué garantía de entrega hay?
6. ¿Cómo evitas un bucle?
7. ¿Qué atributos trae la notificación?
8. ¿Cómo autenticas un push a Cloud Run?
9. ¿Para qué una DLQ?
10. ¿Trae el contenido del archivo?

## Respuestas
1. Notificaciones a Pub/Sub y Eventarc.
2. Finalize, delete, archive y metadata update.
3. La generación.
4. El agente de servicio de Cloud Storage.
5. Al menos una vez.
6. Prefijo en la notificación y salida en otro bucket.
7. `bucketId`, `objectId`, `objectGeneration`, `eventType`, entre otros.
8. Con OIDC y `run.invoker`.
9. Apartar mensajes que siempre fallan.
10. No.

## Ejercicios
1. Diseña las notificaciones del bucket de fotos de ModaLima.
2. Escribe la deduplicación por generación.
3. Configura la DLQ y su alerta.
