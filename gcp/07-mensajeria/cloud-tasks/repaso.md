# Google Cloud · Mensajería · Cloud Tasks · Repaso

## Preguntas
1. ¿Qué diferencia hay con Pub/Sub?
2. ¿Cómo se deduplica?
3. ¿Qué controla la tasa?
4. ¿Cómo se agenda una tarea?
5. ¿Cómo se autentica ante Cloud Run?
6. ¿Qué roles necesita el productor?
7. ¿Qué código de respuesta detiene los reintentos?
8. ¿Cuál es el tamaño máximo?
9. ¿Cuándo usar Cloud Scheduler?
10. ¿Debe ser idempotente el destino?

## Respuestas
1. Va a un destino concreto con tasa y agenda; Pub/Sub difunde a suscripciones.
2. Con el nombre de la tarea.
3. `maxDispatchesPerSecond` y `maxConcurrentDispatches`.
4. Con `scheduleTime`.
5. Con OIDC de una cuenta de servicio.
6. `cloudtasks.enqueuer` y `iam.serviceAccountUser` sobre la SA de despacho.
7. Un 2xx.
8. 1 MB *(verifica)*.
9. Para tareas periódicas.
10. Sí.

## Ejercicios
1. Diseña la cola de recordatorios de carrito.
2. Escribe el nombre determinista de las tareas de envío.
3. Configura la tasa para una API externa de 10 llamadas/s.
