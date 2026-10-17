# Google Cloud · Mensajería · Eventarc · Repaso

## Preguntas
1. ¿Qué formato usan los eventos?
2. ¿Qué fuentes hay?
3. ¿Qué tiene un disparador?
4. ¿Qué transporte suele usar?
5. ¿Cómo deduplicas?
6. ¿Qué hace falta para eventos de Audit Logs de lectura?
7. ¿Qué roles necesita la SA del disparador?
8. ¿Qué destinos admite?
9. ¿Cuándo usar Pub/Sub directo?
10. ¿Qué es el modo binario?

## Respuestas
1. CloudEvents.
2. Servicios de Google directos, Audit Logs, canales propios y terceros.
3. Filtros, destino, cuenta de servicio y transporte.
4. Pub/Sub.
5. Por `ce-id` y `ce-source`.
6. Activar los Data Access logs de ese servicio.
7. `eventarc.eventReceiver` y `run.invoker` sobre el destino.
8. Cloud Run, Cloud Run functions, GKE, Workflows y HTTP interno.
9. Para eventos de negocio de alto volumen entre tus servicios.
10. Atributos en cabeceras `ce-*` y datos en el cuerpo.

## Ejercicios
1. Escribe el disparador para cambios de firewall.
2. Diseña el receptor que alerta miembros externos en IAM.
3. Calcula el volumen de eventos de un filtro amplio vs preciso.
