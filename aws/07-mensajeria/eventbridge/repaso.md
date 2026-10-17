# AWS · EventBridge · Repaso

## Preguntas
1. ¿Qué es un bus de eventos y qué es una regla?
   - *El canal que recibe los eventos / un patrón + destinos que enruta lo que coincide.*
2. ¿Qué campos tiene el sobre de un evento?
   - *`version`, `id`, `detail-type`, `source`, `account`, `time`, `region`, `resources`, `detail`.*
3. ¿Qué diferencia hay entre el bus predeterminado y uno personalizado?
   - *El primero recibe eventos de servicios de AWS; el segundo, los de tus aplicaciones (con su propia política).*
4. ¿Para qué sirven la DLQ y la política de reintentos de un destino?
   - *Para acotar cuánto se reintenta y guardar lo que no se pudo entregar.*
5. ¿Qué garantías de entrega y orden hay?
   - *Al menos una vez y sin orden garantizado: consumidores idempotentes.*
6. ¿Qué hace el transformador de entrada?
   - *Extrae campos y arma el mensaje que recibe el destino.*
7. ¿Qué es el archivo y para qué sirve el *replay*?
   - *Guarda eventos y permite reemitirlos para reprocesar tras un error.*
8. ¿Cuándo usar Scheduler en vez de una regla programada?
   - *Casi siempre: zonas horarias, una sola vez, ventanas flexibles.*
9. ¿Por qué `PutEvents` con HTTP 200 puede haber fallado?
   - *Porque el resultado es por entrada: revisa `FailedEntryCount`.*
10. ¿Cuándo preferir SNS o Kinesis/Kafka?
    - *SNS: fan-out simple de alto volumen; Kinesis/Kafka: flujos continuos con orden por clave y varios lectores.*

## Ejercicios
1. Escribe un patrón que capture `OrdenCreada` de `modalima.ordenes` con `total > 100` y `envio` que empiece por `dom`; pruébalo con `test-event-pattern`.
2. Agrega un destino SQS con DLQ, reintentos de 1 hora/10 intentos y la política de la cola.
3. Crea un transformador que envíe solo `idOrden` y `direccion` a logística.
4. Publica 25 eventos con `PutEvents`; simula 2 fallos parciales y reintenta solo esos.

## Autoevaluación
- [ ] Explico el sobre del evento y dónde va mi contenido.
- [ ] Sé por qué un destino sin política falla en silencio.
- [ ] Reintento solo las entradas fallidas de `PutEvents`.
- [ ] Sé cuándo usar archivo/replay y qué exige de los consumidores.
- [ ] Elijo entre EventBridge, SNS, SQS y Kinesis/Kafka con criterios.
