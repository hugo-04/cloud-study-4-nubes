# AWS · Caso integrado · Clickstream · Casos reales

## 1. El shard que ardía
**Qué pasó:** en una campaña, `WriteProvisionedThroughputExceeded` subió con el stream casi vacío.
**Causa:** la clave de partición era `pagina`; la página de la oferta recibía el 70 % del tráfico.
**Arreglo:** clave = sesión seudonimizada.
**Lección:** el total no importa si un solo carril recibe todo.

## 2. Un registro envenenó el consumidor
**Qué pasó:** el consumidor se quedó repitiendo el mismo lote durante horas (`IteratorAge` creciente).
**Causa:** un JSON mal formado lanzaba excepción y el lote se reintentaba para siempre.
**Arreglo:** registros inválidos se cuentan y se saltan; se guardan muestras para diagnóstico.
**Lección:** en un stream un mensaje malo no puede detener a los demás.

## 3. Las métricas se duplicaron tras un reinicio
**Qué pasó:** tras desplegar, los contadores subieron el doble durante unos minutos.
**Causa:** `ADD` en DynamoDB sobre datos reprocesados desde el checkpoint.
**Arreglo:** `PutItem` por clave de ventana (idempotente) y *dedupe* por `idEvento`.
**Lección:** si puedes reprocesar, la salida debe ser idempotente.

## 4. Checkpoint demasiado optimista
**Qué pasó:** al caerse el pod, se perdieron los clics del minuto en curso.
**Causa:** se hacía checkpoint del último registro leído; la ventana abierta vivía solo en memoria.
**Arreglo:** checkpoint hasta el registro más viejo de una ventana abierta (punto seguro).
**Lección:** el estado en memoria necesita reprocesamiento asegurado.

## 5. Datos personales en el lago
**Qué pasó:** auditoría encontró correos dentro de `idSesion`.
**Causa:** el front enviaba el correo como identificador.
**Arreglo:** seudonimización en la API (HMAC con secreto) y validación de formato; rotación planificada de la clave.
**Lección:** lo que entra al stream queda en el lago; filtra en la puerta.

## 6. Las tarjetas de la gerencia no coincidían
**Qué pasó:** el panel en vivo mostraba 3 % menos clics que el reporte del día siguiente.
**Causa:** eventos tardíos (móviles sin señal) llegaban después de cerrar la ventana.
**Arreglo:** tolerancia de 2 minutos y corrección nocturna con Athena; se documentó la diferencia esperada.
**Lección:** tiempo real y exactitud se negocian; explícalo.

## Resumen
| # | Síntoma | Pieza que lo evita |
|---|---|---|
| 1 | Shard caliente | Clave = sesión |
| 2 | Lector atascado | Saltar y contar inválidos |
| 3 | Métricas duplicadas | Salida idempotente + dedupe |
| 4 | Pérdida al reiniciar | Checkpoint seguro |
| 5 | Datos personales | Seudonimización en la puerta |
| 6 | Diferencias de totales | Marca de agua + corrección nocturna |
