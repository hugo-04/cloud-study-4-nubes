# Oracle OCI · Mensajería · Streaming · Casos reales

## 1. La partición caliente del Cyber
**Qué pasó:** en el Cyber de ModaLima, el productor de clickstream recibía errores de *throttling*.
**Causa:** la clave era el id de la campaña; casi todo el tráfico caía en una partición.
**Arreglo:** clave por id de sesión y más particiones en un stream nuevo.
**Lección:** la clave reparte la carga; elige una con muchos valores.

## 2. Los eventos que se perdían en silencio
**Qué pasó:** faltaba el 2 % de los eventos en los tableros.
**Causa:** `PutMessages` devolvía `failures > 0` y el productor no lo miraba.
**Arreglo:** reintentar solo las entradas fallidas con *backoff*.
**Lección:** una respuesta 200 puede traer fallos parciales.

## 3. El reproceso imposible
**Qué pasó:** tras corregir un bug, Café Andino quiso reprocesar 10 días y solo había 7.
**Causa:** retención máxima del stream.
**Arreglo:** exportar continuamente a Object Storage con Connector Hub.
**Lección:** el stream no es un archivo histórico.

## 4. El grupo atrasado
**Qué pasó:** las recomendaciones mostraban productos de ayer.
**Causa:** el grupo de consumo tenía horas de lag por un consumidor lento.
**Arreglo:** más instancias en el grupo (hasta el número de particiones) y alarma de lag.
**Lección:** mide el lag, no solo los errores.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Throttling | Partición caliente | Clave de alta cardinalidad |
| 2 | Datos faltantes | Fallos parciales ignorados | Reintentar fallidos |
| 3 | Sin historial | Retención | Exportar a Object Storage |
| 4 | Datos viejos | Lag | Escalar consumidores + alarma |
