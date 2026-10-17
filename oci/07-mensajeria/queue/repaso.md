# Oracle OCI · Mensajería · Queue · Repaso

## Preguntas
1. ¿Qué es la visibilidad de un mensaje?
2. ¿Qué es el receipt?
3. ¿Cuándo se borra un mensaje?
4. ¿Qué hace el long polling?
5. ¿Qué es la DLQ?
6. ¿Qué garantía de entrega ofrece?
7. ¿Cómo implementas backoff?
8. ¿Qué endpoint usa `QueueClient`?
9. ¿Cuándo prefieres Streaming?
10. ¿Qué haces con un mensaje de 2 MB?

## Respuestas
1. El tiempo en que queda oculto para otros consumidores tras recibirlo.
2. El comprobante de entrega para borrar o actualizar el mensaje.
3. Cuando terminó de procesarse con éxito.
4. Espera en el servidor hasta que haya mensajes o venza el tiempo.
5. Una cola donde van los mensajes que superaron los intentos.
6. Al menos una vez.
7. Extendiendo la visibilidad según el número de entrega.
8. El `messages_endpoint` de la cola.
9. Cuando varios consumidores deben leer lo mismo o hay que releer.
10. Claim check: objeto en Object Storage y referencia en la cola.

## Ejercicios
1. Elige visibilidad, retención y DLQ para la cola de facturación de ModaLima.
2. Diseña la tabla de idempotencia del consumidor de correos.
3. Escribe el procedimiento para reprocesar la DLQ.
