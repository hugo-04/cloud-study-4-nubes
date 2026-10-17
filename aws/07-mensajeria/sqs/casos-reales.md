# AWS · SQS · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El Black Friday que no tumbó la base
**Qué pasó:** las órdenes llegaban a 3 000/s y la base soportaba 400/s. **Solución:** la API publica en SQS y 20 consumidores escriben a ritmo constante; la cola absorbió el pico en 12 minutos. **Lección:** una cola convierte un pico en una pendiente.

## 2. El mensaje que giraba para siempre
**Qué pasó:** un JSON mal formado hacía fallar al consumidor; el mensaje reaparecía miles de veces. **Solución:** DLQ con `maxReceiveCount = 5`, alarma y *redrive* tras corregir. **Lección:** sin DLQ, un solo mensaje puede consumir la cola.

## 3. Procesar dos veces
**Qué pasó:** un trabajo de 90 s con visibility timeout de 30 s se entregó a dos consumidores. **Solución:** timeout de 6 minutos, `ChangeMessageVisibility` en trabajos largos e idempotencia por `MessageId` de negocio. **Lección:** el timeout debe superar el trabajo.

## 4. El pedido fuera de orden
**Qué pasó:** «pedido pagado» se procesaba antes que «pedido creado». **Solución:** cola FIFO con `MessageGroupId = idPedido`; el resto de pedidos sigue en paralelo. **Lección:** orden por grupo, no global.

## 5. La factura de las llamadas vacías
**Qué pasó:** consumidores con short polling hacían millones de `ReceiveMessage` vacíos. **Solución:** `WaitTimeSeconds = 20` y lotes de 10. **Lección:** long polling es dinero.

## 6. El cliente ruidoso
**Qué pasó:** un inquilino enviaba 200 000 mensajes y los demás esperaban horas. **Solución:** colas por plan, `MessageGroupId` por inquilino con colas justas y límite de concurrencia por consumidor. **Lección:** aislar a los inquilinos.

| Problema | Solución |
|---|---|
| Pico que ahoga la base | Cola entre API y escritura |
| Mensaje venenoso | DLQ + alarma + redrive |
| Doble procesamiento | Timeout mayor + idempotencia |
| Orden necesario | FIFO + MessageGroupId |
| Costo de llamadas | Long polling + lotes |
| Inquilino ruidoso | Aislar / colas justas |
