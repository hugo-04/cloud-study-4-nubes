# Oracle OCI · Caso integrado · Clickstream · Casos reales

## 1. El minuto que nunca cerraba
**Qué pasó:** el tablero mostraba el minuto actual vacío y los anteriores incompletos.
**Causa:** las ventanas se cerraban por hora de proceso; los móviles enviaban con 20 s de retraso.
**Arreglo:** ventanas por hora del evento y marca de agua con 30 s de retraso permitido.
**Lección:** el tiempo que importa es el del evento.

## 2. El SKU estrella que saturó una partición
**Qué pasó:** en el lanzamiento de una colección, el stream devolvía *throttling*.
**Causa:** clave por SKU.
**Arreglo:** clave por sesión.
**Lección:** la clave reparte la carga.

## 3. Conteos dobles tras un reinicio
**Qué pasó:** después de cada despliegue el tablero mostraba picos falsos.
**Causa:** commit automático al leer; al reiniciar se reprocesaba desde antes del último agregado escrito… o se perdían datos según el caso.
**Arreglo:** commit manual después de escribir el agregado, y agregado idempotente por ventana.
**Lección:** el commit marca lo procesado, no lo leído.

## 4. El reproceso de la semana pasada
**Qué pasó:** se quiso recalcular el Cyber de hace 10 días.
**Causa:** el stream solo retenía 72 horas.
**Arreglo:** reprocesar desde el historial en Object Storage.
**Lección:** el historial vive fuera del stream.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Ventanas incompletas | Hora de proceso | Hora del evento + marca de agua |
| 2 | Throttling | Clave por SKU | Clave por sesión |
| 3 | Picos falsos | Commit temprano | Commit tras escribir |
| 4 | Sin datos viejos | Retención | Historial en Object Storage |
