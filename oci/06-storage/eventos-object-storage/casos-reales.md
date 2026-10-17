# Oracle OCI · Storage · Eventos de Object Storage · Casos reales

## 1. La regla que no disparaba
**Qué pasó:** las fotos se subían, pero la función de miniaturas de ModaLima nunca corría.
**Causa:** el bucket no tenía `object_events_enabled`.
**Arreglo:** activarlo en Terraform y una prueba de humo en el pipeline.
**Lección:** sin eventos en el bucket, no hay regla que valga.

## 2. Miniaturas infinitas
**Qué pasó:** la cuenta de funciones creció sin parar en minutos.
**Causa:** las miniaturas se guardaban en el mismo bucket, lo que generaba nuevos eventos.
**Arreglo:** bucket de destino distinto y filtro por prefijo en el consumidor.
**Lección:** cuidado con los ciclos de eventos.

## 3. Dos correos por factura
**Qué pasó:** los socios de Café Andino recibían el aviso de factura dos veces.
**Causa:** evento entregado dos veces; el consumidor no deduplicaba.
**Arreglo:** registro de `eventID` procesados con expiración.
**Lección:** al menos una vez significa a veces dos.

## 4. El archivo que ya no estaba
**Qué pasó:** el procesador fallaba con 404 de vez en cuando.
**Causa:** el usuario subía y borraba rápidamente; el evento llegaba tarde.
**Arreglo:** `HEAD` previo; si no existe, se descarta el evento.
**Lección:** el evento describe el pasado.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Nada se dispara | Eventos del bucket apagados | `object_events_enabled` |
| 2 | Invocaciones sin fin | Ciclo | Destino distinto |
| 3 | Duplicados | Reentrega | Deduplicar por `eventID` |
| 4 | 404 al procesar | Evento tardío | `HEAD` y descartar |
