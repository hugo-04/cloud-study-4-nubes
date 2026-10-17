# Oracle OCI · Datos · NoSQL · Casos reales

## 1. El carrito que perdía productos
**Qué pasó:** clientes de ModaLima agregaban dos productos desde dos pestañas y quedaba uno.
**Causa:** cada pestaña leía, modificaba y escribía; la última ganaba.
**Arreglo:** escritura condicional con la versión leída; si cambió, releer y reintentar.
**Lección:** concurrencia optimista para documentos editados por varios.

## 2. La consulta que se comió la capacidad
**Qué pasó:** las lecturas por clave empezaron a fallar por *throttling*.
**Causa:** un reporte hacía `SELECT * WHERE estado = 'ABANDONADO'` cada minuto, recorriendo la tabla.
**Arreglo:** índice secundario y reporte cada hora; mejor aún, exportar a analítica.
**Lección:** las consultas sin clave comparten la misma capacidad.

## 3. Carritos eternos
**Qué pasó:** la tabla de Café Andino creció a millones de carritos abandonados.
**Causa:** sin TTL.
**Arreglo:** TTL de 7 días, renovado al tocar el carrito.
**Lección:** lo temporal debe expirar solo.

## 4. La clave de shard equivocada
**Qué pasó:** la tabla de eventos tenía una partición saturada.
**Causa:** clave de shard = fecha; todo el tráfico del día iba a la misma.
**Arreglo:** clave de shard = dispositivo, fecha en la parte ordenada.
**Lección:** reparte por la dimensión de alta cardinalidad.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambios perdidos | Sin versión | Escritura condicional |
| 2 | Throttling | Consulta sin clave | Índice / exportar |
| 3 | Tabla gigante | Sin TTL | TTL |
| 4 | Partición caliente | Shard por fecha | Shard por entidad |
