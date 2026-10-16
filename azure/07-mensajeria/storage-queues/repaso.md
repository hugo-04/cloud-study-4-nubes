# Azure · Storage Queues · Repaso

## Preguntas de repaso
1. ¿Qué es una Storage Queue en una frase?
   - *Una cola simple y barata dentro de una cuenta de Storage: mensajes de hasta 64 KB que uno o varios trabajadores toman, procesan y borran.*
2. ¿Qué es el visibility timeout?
   - *Tiempo en que un mensaje recibido queda invisible para otros; si vence sin borrar, reaparece (reintento).*
3. ¿Para qué sirve el popReceipt?
   - *Prueba que eres quien recibió el mensaje; es obligatorio para borrar o actualizar y cambia en cada recepción o actualización.*
4. ¿Qué es el dequeueCount y cómo se usa?
   - *Número de veces que se recibió; si supera un umbral, el mensaje es venenoso y va a la cola `-poison`.*
5. ¿Qué garantía de entrega y de orden hay?
   - *Al menos una vez; sin orden garantizado.*
6. ¿Cómo hago un mensaje diferido?
   - *Enviándolo con visibilidad inicial (hasta 7 días).*
7. ¿Cómo hago reintentos con retroceso?
   - *Con `updateMessage` aumentando la invisibilidad según `dequeueCount`.*
8. ¿Qué límites debo recordar?
   - *64 KB por mensaje, 32 por recepción, TTL hasta 7 días o infinito.*
9. ¿Cuándo prefiero Service Bus?
   - *Cuando necesito DLQ nativa, orden, duplicados, tópicos o transacciones.*
10. ¿Cómo la protejo?
    - *Entra ID sin claves, roles Message Sender/Processor por separado, Private Endpoint, TLS 1.2.*
11. ¿Cómo escalo los trabajadores?
    - *Por el largo de la cola (KEDA `azure-queue`).*
12. ¿Cómo manejo trabajos largos?
    - *Renovando la invisibilidad con `updateMessage` y usando el último popReceipt.*

## Entrevista
- Diseña el procesamiento de fotos de productos con reintentos, veneno y escalado.
- Un mensaje se procesa dos veces. ¿Qué revisas y cómo lo evitas?
- ¿Por qué no se debe esperar orden FIFO y qué haces si lo necesitas?
- ¿Cuándo migrarías un flujo de Storage Queue a Service Bus?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf).
2. Envía mensajes con la [CLI](ejemplos/cli/storage-queues.sh), míralos con `peek` y recíbelos con distintas visibilidades.
3. Ejecuta el trabajador de [uso en Java](uso-en-java.md) y provoca un fallo para ver el retroceso y la cola de veneno.
4. Configura el escalado por [KEDA](ejemplos/keda/escalado-por-cola.yaml).
5. Configura Event Grid para entregar eventos de Blob a la cola y procésalos.
