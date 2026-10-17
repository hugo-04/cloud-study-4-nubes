# Oracle OCI · Storage · Claim check · Repaso

## Preguntas
1. ¿Qué problema resuelve el claim check?
2. ¿Qué lleva el ticket?
3. ¿En qué orden se escriben objeto y ticket?
4. ¿Quién borra la carga?
5. ¿Para qué la huella SHA-256?
6. ¿Qué es un sobre híbrido?
7. ¿Por qué el ticket no debe ser una PAR?
8. ¿Qué pasa con un objeto huérfano?
9. ¿Cómo debe ser el consumidor ante tickets repetidos?
10. ¿Cuándo no vale la pena?

## Respuestas
1. Enviar cargas más grandes que el máximo de la cola.
2. Bucket, objeto, huella y tamaño.
3. Primero el objeto, después el ticket.
4. El ciclo de vida del bucket.
5. Verificar que se leyó exactamente lo enviado.
6. Uno que va en línea si cabe y por referencia si no.
7. Porque el consumidor debe usar su propia identidad y la URL sería una credencial en la cola.
8. El ciclo de vida lo borra.
9. Idempotente.
10. Con mensajes pequeños.

## Ejercicios
1. Elige el umbral del sobre híbrido para la cola de pedidos de ModaLima.
2. Calcula el costo mensual de 100.000 cargas de 2 MB guardadas 7 días.
3. Diseña cómo borrar las cargas de un cliente que pide eliminar sus datos.
