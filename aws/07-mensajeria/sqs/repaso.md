# AWS · SQS · Repaso

## Preguntas
1. ¿Diferencia entre cola estándar y FIFO?
   - *Estándar: alto rendimiento, orden no garantizado, duplicados posibles. FIFO: orden por grupo y deduplicación.*
2. ¿Qué es el visibility timeout?
   - *Tiempo en que el mensaje recibido queda oculto; si no se borra, reaparece.*
3. ¿Para qué sirve una DLQ?
   - *Aislar mensajes que fallan N veces para analizarlos y reprocesarlos.*
4. ¿Qué es long polling y por qué conviene?
   - *Esperar hasta 20 s por mensajes: menos llamadas vacías y menos costo.*
5. ¿Cuándo borras el mensaje?
   - *Solo cuando terminaste de procesarlo bien.*
6. ¿Qué es `MessageGroupId`?
   - *Agrupa mensajes que deben procesarse en orden (FIFO).*
7. ¿Qué haces con un mensaje de 50 MB?
   - *Claim Check: archivo en S3 y ticket en la cola.*
8. ¿SQS permite que varios consumidores distintos lean el mismo mensaje?
   - *No: cada mensaje lo toma un consumidor. Para fan-out, SNS → varias colas.*
9. ¿Qué hace `ChangeMessageVisibility`?
   - *Amplía o reduce el tiempo de ocultación (trabajos largos o backoff).*
10. ¿Por qué la retención de la DLQ debe ser mayor?
    - *Porque el tiempo de retención cuenta desde el envío original.*

## Ejercicios
1. Diseña cola + DLQ para un procesador de facturas: timeout, `maxReceiveCount`, retención.
2. Calcula el backoff para el intento 1, 2, 3, 4 con base 10 s y tope 15 min.
3. Elige entre estándar y FIFO para «cambios de estado del pedido».
4. Escribe la política de cola que acepte solo eventos de un tópico SNS.

## Autoevaluación
- [ ] Sé configurar una cola con DLQ y cifrado.
- [ ] Sé escribir un consumidor idempotente con backoff.
- [ ] Sé elegir estándar o FIFO.
- [ ] Sé diagnosticar una cola que crece.
