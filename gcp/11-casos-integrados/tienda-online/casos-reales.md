# Google Cloud · Caso integrado · Tienda online · Casos reales

## 1. El pedido sin factura
**Qué pasó:** algunos pedidos pagados de ModaLima nunca se facturaban.
**Causa:** el servicio guardaba y luego publicaba; Cloud Run reciclaba la instancia entre ambos.
**Arreglo:** outbox en la misma transacción y relay.
**Lección:** guardar y avisar debe ser atómico.

## 2. Dos facturas por pedido
**Qué pasó:** en el Cyber aparecieron facturas duplicadas.
**Causa:** reentregas de Pub/Sub cuando facturación tardaba más que el plazo de ack.
**Arreglo:** inbox con clave única y plazo de ack acorde.
**Lección:** al menos una vez significa duplicados.

## 3. El relay que se pisaba
**Qué pasó:** con dos instancias del relay, los eventos salían repetidos.
**Causa:** `SELECT` sin bloqueo.
**Arreglo:** `FOR UPDATE SKIP LOCKED` y lotes pequeños.
**Lección:** el relay también es concurrente.

## 4. «Despachado» antes de «pagado»
**Qué pasó:** en Café Andino despacho recibía eventos de un pedido en desorden.
**Causa:** publicación sin clave de orden.
**Arreglo:** clave de orden = id de pedido y suscripción con orden activado.
**Lección:** orden por entidad, no global.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Evento perdido | Guardar y publicar separados | Outbox |
| 2 | Duplicados | Reentrega | Inbox |
| 3 | Relay duplicado | Sin bloqueo | SKIP LOCKED |
| 4 | Desorden | Sin clave | Clave de orden |
