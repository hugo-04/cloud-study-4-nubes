# Google Cloud · Storage · Eventos de Cloud Storage · Casos reales

## 1. La notificación que no publicaba
**Qué pasó:** se configuró la notificación del bucket de ModaLima, pero el tema nunca recibió nada.
**Causa:** el agente de servicio de Cloud Storage no tenía `pubsub.publisher` en el tema.
**Arreglo:** binding en Terraform junto a la notificación.
**Lección:** la notificación publica con una identidad que no es la tuya.

## 2. Procesar la versión equivocada
**Qué pasó:** se generó la miniatura de la foto vieja tras un reemplazo rápido.
**Causa:** el consumidor leía «el objeto actual», no la generación del evento.
**Arreglo:** leer por generación; si ya no existe, descartar.
**Lección:** la generación es la identidad del evento.

## 3. Miniaturas infinitas
**Qué pasó:** cada miniatura disparaba otra.
**Causa:** salida en el mismo bucket sin filtro de prefijo.
**Arreglo:** notificación con prefijo `fotos/` y salida en otro bucket.
**Lección:** filtra y separa.

## 4. El mensaje venenoso
**Qué pasó:** un archivo corrupto se reintentaba sin fin y retrasaba al resto en Café Andino.
**Causa:** sin DLQ.
**Arreglo:** DLQ tras 5 intentos y alerta.
**Lección:** lo que siempre falla debe salir del camino.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Nada llega | Agente sin publisher | Binding |
| 2 | Versión vieja | Sin generación | Leer por generación |
| 3 | Bucle | Mismo bucket | Prefijo + otro bucket |
| 4 | Atasco | Sin DLQ | DLQ |
