# Azure · Azure SQL Database · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · "Borré todos los pedidos de hoy" (restauración PITR)
- **Problema:** un `DELETE` sin `WHERE` en producción a las 14:32.
- **Solución:** se restauró la base a las 14:30 con PITR **como otra base** (`pedidos-restaurada`), se comparó y se copiaron las filas perdidas a la original; luego se retiraron permisos de borrado masivo a las personas.
- **Lección:** la restauración crea una base nueva (no pisa la actual): tienes tiempo para decidir. Practica el procedimiento **antes** del incidente.

## Caso 2 · Se cayeron las conexiones durante un escalado
- **Problema:** al subir de 2 a 4 vCores a mediodía, la API devolvió errores durante unos 20 segundos.
- **Causa:** el cambio de nivel cierra conexiones al terminar; la aplicación no reintentaba y el pool conservaba conexiones muertas.
- **Solución:** reintento de errores transitorios (40613, 40197…), validación del pool y `max-lifetime` de 25 minutos.
- **Lección:** los cortes breves son normales en la nube; tu código debe estar preparado.

## Caso 3 · "La base está lenta" y no era la base
- **Problema:** `workers_percent` al 100 % y timeouts.
- **Causa:** 30 pods × pool de 20 conexiones = 600 conexiones intentando ejecutar consultas simultáneas contra una base de 4 vCores.
- **Solución:** pool de 8 por pod, un solo pod "lento" corregido (una consulta sin índice) y alerta de `workers_percent`.
- **Lección:** más conexiones no es más velocidad; calcula `pods × pool`.

## Caso 4 · Un plan de consulta que empeoró de la noche a la mañana
- **Problema:** una consulta que tardaba 40 ms pasó a 6 segundos.
- **Causa:** el motor cambió de plan tras actualizar estadísticas (plan regresado).
- **Solución:** en Query Store se vio el plan anterior y se **forzó**; luego se creó el índice que lo hacía estable.
- **Lección:** activa y consulta Query Store; permite volver al plan bueno sin tocar código.

## Caso 5 · Contraseña SQL filtrada en un repositorio
- **Problema:** una cadena de conexión con usuario y contraseña apareció en un archivo de configuración subido a Git.
- **Solución:** servidor con **solo Entra ID**, aplicaciones con identidad administrada y usuarios contenidos; se eliminó el usuario SQL; se rotó todo lo comprometido.
- **Lección:** donde no hay contraseña no hay fuga de contraseña.

## Caso 6 · Dos usuarios editan el mismo pedido
- **Problema:** un operador cancelaba un pedido mientras otro lo marcaba como enviado; ganaba el último y se perdía un cambio.
- **Solución:** columna `version` con `@Version` (concurrencia optimista); en conflicto la API responde **409** y la pantalla recarga.
- **Lección:** sin control de concurrencia, "gana el último" silenciosamente.

## Caso 7 · Evento perdido entre base y bus
- **Problema:** a veces se guardaba el pedido pero no salía el evento `pedido.creado`.
- **Causa:** la aplicación guardaba en la base y luego publicaba en Service Bus; si fallaba entre medias, quedaba inconsistente.
- **Solución:** patrón **Outbox**: el evento se escribe en una tabla en la misma transacción; un publicador lo envía con `MessageId` fijo.
- **Lección:** no existen transacciones entre base y bus: se diseña la consistencia.

## Caso 8 · Un SaaS con 400 clientes y una base por cliente
- **Problema:** 400 bases provisionadas costaban una fortuna y casi todas estaban ociosas.
- **Solución:** **Elastic pool** con capacidad compartida y límites por base; las más grandes salieron a bases propias.
- **Lección:** el pool paga la capacidad para el pico agregado, no para el pico de cada una.

## Caso 9 · Datos de un cliente visibles para otro
- **Problema:** un `WHERE` olvidado en un informe mostró pedidos de otro inquilino.
- **Solución:** **Seguridad a nivel de fila** (RLS) con `SESSION_CONTEXT('tenant_id')` fijado al tomar la conexión; el error de aplicación ya no puede filtrar datos.
- **Lección:** la regla de aislamiento vive en la base, no solo en cada consulta.

## Caso 10 · Despliegue en caliente de una columna nueva
- **Problema:** añadir una columna obligatoria rompía a las versiones antiguas del servicio durante el despliegue progresivo.
- **Solución:** 3 pasos compatibles: añadir columna **nullable** → desplegar código que la escribe → rellenar → exigir `NOT NULL` en una migración posterior.
- **Lección:** esquema y código se despliegan en momentos distintos: cada paso debe funcionar con ambas versiones.

## Caso 11 · "Serverless" y el primer cliente de la mañana
- **Problema:** el primer pedido del día tardaba 45 segundos y fallaba por timeout.
- **Causa:** la base serverless se había pausado de noche y la reanudación tarda.
- **Solución:** en desarrollo se aceptó y se aumentaron los timeouts con reintentos; en producción se usó cómputo **provisionado** (sin pausa).
- **Lección:** serverless ahorra en uso intermitente, pero la primera conexión paga la reanudación.

## Caso 12 · Un informe pesado frena el sitio
- **Problema:** el reporte mensual lanzaba consultas de minutos y la tienda iba lenta.
- **Solución:** nivel **Business Critical**/**Hyperscale** con réplica de lectura y conexión con `ApplicationIntent=ReadOnly` para el reporte; luego, un almacén analítico para los históricos.
- **Lección:** separa lectura analítica de la transaccional.

## Caso 13 · Deadlocks en horas pico
- **Problema:** errores 1205 esporádicos al actualizar pedidos y stock.
- **Causa:** dos flujos actualizaban las mismas tablas en **orden distinto**.
- **Solución:** orden consistente de acceso (siempre `stock` y luego `pedido`), transacciones más cortas y reintento del 1205.
- **Lección:** los deadlocks se evitan con orden y brevedad; se toleran con reintentos.
