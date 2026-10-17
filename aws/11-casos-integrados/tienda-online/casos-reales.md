# AWS · Caso integrado · Tienda online · Casos reales

Seis historias de ModaLima. Cada una termina con la lección.

## 1. El pedido que nadie facturó
**Qué pasó:** `pedidos` hacía `INSERT` y luego `PutEvents`. Un despliegue mató el contenedor entre ambos: 14 pedidos sin factura.
**Causa:** dos escrituras en sistemas distintos sin transacción común.
**Arreglo:** bandeja de salida + publicador.
**Lección:** si "guardar" y "avisar" no están en la misma transacción, alguno se perderá.

## 2. El `200` que mentía
**Qué pasó:** `PutEvents` devolvió HTTP 200 y el publicador marcó 10 eventos como enviados; 3 habían fallado por `ThrottlingException`.
**Causa:** no se revisó `FailedEntryCount` ni cada entrada.
**Arreglo:** marcar publicadas solo las entradas con `EventId`; las fallidas vuelven a la bandeja.
**Lección:** en lotes, el resultado es **por elemento**.

## 3. La factura doble
**Qué pasó:** una cola sin tiempo de visibilidad suficiente entregó dos veces el mismo mensaje; el cliente recibió dos facturas.
**Causa:** el consumidor no era idempotente y la visibilidad (30 s) era menor que el procesamiento (45 s).
**Arreglo:** bandeja de entrada en DynamoDB con escritura condicional; visibilidad 120 s.
**Lección:** *al menos una vez* se compensa con idempotencia, no con esperanza.

## 4. La cola de otro equipo
**Qué pasó:** una sola cola para facturación y logística; un mensaje venenoso de logística bloqueó ambos.
**Causa:** consumidores distintos compartiendo cola y DLQ.
**Arreglo:** una cola + DLQ por consumidor (Terraform con `for_each`).
**Lección:** aislar el fallo es parte del diseño.

## 5. El evento que no llegó (permiso)
**Qué pasó:** se añadió el consumidor `antifraude`; la regla existía pero no llegaba nada.
**Causa:** faltaba la política de la cola para `events.amazonaws.com`; EventBridge no podía escribir.
**Arreglo:** política con `aws:SourceArn` de la regla, y revisar `FailedInvocations`.
**Lección:** un destino sin permiso falla en silencio si no hay alarma.

## 6. Reproducir tras un error
**Qué pasó:** facturación tuvo un bug 40 minutos; 230 eventos terminaron en DLQ o con efecto incorrecto.
**Arreglo:** corregir, mover la DLQ de vuelta (`start-message-move-task`) y reproducir la ventana del archivo.
**Lección:** el consumidor idempotente es lo que permite reproducir sin miedo.

## Resumen

| # | Síntoma | Causa | Pieza que lo evita |
|---|---|---|---|
| 1 | Pedido sin factura | Doble escritura | Bandeja de salida |
| 2 | Eventos perdidos con 200 | Resultado por lote ignorado | Revisar cada entrada |
| 3 | Factura doble | Sin idempotencia | Bandeja de entrada |
| 4 | Bloqueo cruzado | Cola compartida | Cola + DLQ por consumidor |
| 5 | No llega el evento | Falta política de la cola | `aws:SourceArn` + alarma |
| 6 | Corrección masiva | Sin reproducción | Archivo + mover DLQ |
