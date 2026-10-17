# Google Cloud · Storage · Claim check · Casos reales

## 1. Mensajes de 9 MB
**Qué pasó:** la cola de pedidos mayoristas de ModaLima se volvió lenta y cara.
**Causa:** los pedidos completos viajaban en Pub/Sub.
**Arreglo:** sobre híbrido con umbral de 64 KB.
**Lección:** los mensajes deben ser livianos.

## 2. La carga cambiada
**Qué pasó:** el consumidor procesó una versión distinta a la publicada.
**Causa:** se leía el objeto sin generación y otro proceso lo había reescrito.
**Arreglo:** generación en el ticket + SHA-256.
**Lección:** el ticket fija qué se envió.

## 3. Ticket sin carga
**Qué pasó:** consumidores recibían tickets cuyo objeto no existía.
**Causa:** publicación y escritura en paralelo.
**Arreglo:** escribir, confirmar, publicar.
**Lección:** el orden importa.

## 4. Reintento sin datos
**Qué pasó:** Café Andino no pudo reprocesar mensajes de la DLQ.
**Causa:** el consumidor borraba la carga al empezar.
**Arreglo:** el ciclo de vida limpia a los 7 días.
**Lección:** deja la carga para los reintentos.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Lento y caro | Mensajes grandes | Sobre híbrido |
| 2 | Versión distinta | Sin generación | Generación + hash |
| 3 | 404 | Orden invertido | Escribir antes |
| 4 | DLQ irrecuperable | Borrado temprano | Ciclo de vida |
