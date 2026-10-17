# Google Cloud · Compute · Cloud Run functions · Casos reales

## 1. Miniaturas dobles
**Qué pasó:** cada foto de producto de ModaLima generaba dos miniaturas.
**Causa:** reentrega del evento y función no idempotente.
**Arreglo:** nombre determinista y comprobación por id del evento.
**Lección:** al menos una vez significa a veces dos.

## 2. El evento perdido
**Qué pasó:** algunas facturas de Café Andino nunca se procesaban.
**Causa:** la función fallaba y los reintentos estaban desactivados.
**Arreglo:** reintentos activados y DLQ en la suscripción.
**Lección:** sin reintentos, un error es una pérdida.

## 3. El bucle infinito
**Qué pasó:** la función escribía en el mismo bucket que la disparaba.
**Causa:** ciclo de eventos.
**Arreglo:** bucket de salida distinto.
**Lección:** separa entrada y salida.

## 4. Webhook sin verificar
**Qué pasó:** un tercero envió pagos falsos al webhook público.
**Causa:** no se verificaba la firma del proveedor.
**Arreglo:** verificación HMAC del cuerpo con el secreto del proveedor.
**Lección:** público no significa confiable.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Duplicados | No idempotente | Id del evento |
| 2 | Pérdidas | Sin reintentos | Reintentos + DLQ |
| 3 | Bucle | Ciclo | Bucket distinto |
| 4 | Fraude | Sin firma | HMAC |
