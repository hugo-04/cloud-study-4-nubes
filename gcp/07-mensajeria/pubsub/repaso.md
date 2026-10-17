# Google Cloud · Mensajería · Pub/Sub · Repaso

## Preguntas
1. ¿Qué tipos de suscripción hay?
2. ¿Qué es el ack deadline?
3. ¿Cómo obtienes orden?
4. ¿Qué hace exactly-once?
5. ¿Para qué el flow control?
6. ¿Qué es seek?
7. ¿Qué identidad usa la DLQ?
8. ¿Cuándo hacer nack?
9. ¿Cuál es el tamaño máximo de mensaje?
10. ¿Cuándo Cloud Tasks en su lugar?

## Respuestas
1. Pull, push, BigQuery y Cloud Storage.
2. El tiempo para confirmar antes de que se reentregue.
3. Con clave de orden y la opción en la suscripción.
4. Evita reentregas tras un ack exitoso en suscripciones pull.
5. Limitar mensajes en vuelo.
6. Rebobinar la suscripción a un instante o snapshot.
7. El agente de servicio de Pub/Sub.
8. Ante fallas transitorias.
9. 10 MB *(verifica)*.
10. Para tareas dirigidas a un endpoint con tasa y agenda.

## Ejercicios
1. Diseña temas y suscripciones de ModaLima.
2. Clasifica errores en transitorios y permanentes para facturación.
3. Configura flow control para 4 réplicas.
