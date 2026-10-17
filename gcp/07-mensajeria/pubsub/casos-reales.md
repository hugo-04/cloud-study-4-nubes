# Google Cloud · Mensajería · Pub/Sub · Casos reales

## 1. El suscriptor que se ahogó
**Qué pasó:** el servicio de facturación de ModaLima se quedó sin memoria tras una caída de 2 horas.
**Causa:** al volver, recibió todos los mensajes acumulados sin control de flujo.
**Arreglo:** flow control (100 mensajes / 50 MB en vuelo) y escalado horizontal.
**Lección:** limita lo que entra a lo que puedes procesar.

## 2. Pedidos fuera de orden
**Qué pasó:** «pedido cancelado» se procesaba antes que «pedido creado».
**Causa:** sin clave de orden.
**Arreglo:** `orderingKey = idPedido` y orden habilitado en la suscripción.
**Lección:** el orden se pide explícitamente y por clave.

## 3. El mensaje venenoso
**Qué pasó:** un mensaje con un campo inválido se reentregaba miles de veces.
**Causa:** el consumidor hacía nack ante un error permanente.
**Arreglo:** clasificar fallas: transitoria → nack; permanente → registrar y ack (o DLQ).
**Lección:** no todos los errores merecen reintento.

## 4. La DLQ que no recibía
**Qué pasó:** Café Andino configuró DLQ pero los mensajes seguían reintentándose.
**Causa:** el agente de Pub/Sub no tenía permisos sobre el tema DLQ y la suscripción.
**Arreglo:** bindings del agente de servicio en Terraform.
**Lección:** la DLQ usa la identidad del servicio.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin memoria | Sin flow control | Limitar en vuelo |
| 2 | Desorden | Sin clave | `orderingKey` |
| 3 | Reintentos eternos | Nack de permanentes | Clasificar fallas |
| 4 | DLQ vacía | Permisos del agente | Bindings |
