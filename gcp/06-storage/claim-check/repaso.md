# Google Cloud · Storage · Claim check · Repaso

## Preguntas
1. ¿Qué resuelve el claim check?
2. ¿Qué lleva el ticket?
3. ¿Por qué la generación?
4. ¿En qué orden se escribe?
5. ¿Quién borra la carga?
6. ¿Qué es el sobre híbrido?
7. ¿Qué roles necesita el productor?
8. ¿Qué hace el consumidor ante tickets repetidos?
9. ¿Qué pasa con un huérfano?
10. ¿Cuándo no usarlo?

## Respuestas
1. Mensajes grandes caros o lentos.
2. Objeto, generación, huella y tamaño.
3. Para leer la versión exacta enviada.
4. Primero el objeto, después el ticket.
5. El ciclo de vida.
6. En línea si cabe, por referencia si no.
7. `storage.objectCreator` y `pubsub.publisher`.
8. Es idempotente.
9. El ciclo de vida lo borra.
10. Con mensajes pequeños.

## Ejercicios
1. Elige el umbral del sobre.
2. Calcula el costo de 100.000 cargas de 3 MB por 7 días.
3. Diseña el borrado de cargas de un cliente.
