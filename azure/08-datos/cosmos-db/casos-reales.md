# Azure · Cosmos DB · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · "429 aunque hay RU de sobra" (clave de partición por fecha)
- **Problema:** durante una campaña el contenedor de pedidos devolvía 429 mientras el consumo global de RU estaba al 20 %.
- **Causa:** la clave de partición era `/fecha`; **todas las escrituras del día** caían en una sola partición lógica y, por tanto, en una sola partición física (máx. 10 000 RU/s).
- **Solución:** migrar a un contenedor nuevo con `/clienteId` (alta cardinalidad, reparto parejo) usando el change feed + importación masiva; la consulta "pedidos de hoy" pasó a una proyección aparte.
- **Lección:** subir RU no arregla una partición caliente. Revisa *Normalized RU Consumption* y la tabla `CDBPartitionKeyRUConsumption`.

## Caso 2 · La consulta del almacén que costaba 900 RU
- **Problema:** la pantalla del almacén ("pedidos por preparar") tardaba 1,5 s y consumía cientos de RU.
- **Causa:** el contenedor estaba particionado por cliente; la consulta por `almacenId` recorría **todas** las particiones.
- **Solución:** una **proyección** `pedidos-por-almacen` (clave `/almacenId`) alimentada por el **change feed**; la pantalla lee de ahí (≈ 5 RU).
- **Lección:** en Cosmos se duplica el dato con una clave distinta para cada patrón de acceso; el change feed mantiene las copias sincronizadas (consistencia eventual, aceptable aquí).

## Caso 3 · Campaña "Cyber Día": subí a 50 000 RU/s y siguió fallando
- **Problema:** el contenedor tenía autoscale con máximo 50 000 RU/s, pero el catálogo seguía con 429.
- **Causa:** el contenedor tenía solo 2 particiones físicas (cada una limitada a 10 000 RU/s) y los productos más vendidos vivían en una sola partición lógica.
- **Solución:** claves jerárquicas `/categoria`, `/sku`, **caché Redis** para los 50 productos estrella y un ensayo de carga con datos realistas antes de la campaña.
- **Lección:** el máximo útil depende del **número de particiones físicas y de cómo se reparte el tráfico**, no solo del número configurado.

## Caso 4 · La factura se duplicó por indexar todo
- **Problema:** las escrituras costaban ~14 RU para documentos de 2 KB.
- **Causa:** la política por defecto indexa **todas** las propiedades, incluidas descripciones largas y notas que nadie filtra.
- **Solución:** excluir `/notas/*`, `/direccionEntrega/*` y otras rutas; mantener `/*` incluido y añadir **un índice compuesto** `(estado, creadoEn)`. Las escrituras bajaron a ~7 RU.
- **Lección:** el índice es el mayor ahorro oculto; **mide antes y después** con `getRequestCharge()`.

## Caso 5 · Eventos duplicados desde el change feed
- **Problema:** el servicio de notificaciones enviaba dos correos por pedido.
- **Causa:** el procesador del change feed entrega **al menos una vez**: un reinicio del pod hizo reprocesar el último lote.
- **Solución:** publicar en Service Bus con `messageId = id del evento` (detección de duplicados) y que el consumidor registre `eventoId` procesado (idempotencia). Ver [Service Bus](../../07-mensajeria/service-bus/README.md).
- **Lección:** *at-least-once* + idempotencia = efecto de "exactamente una vez".

## Caso 6 · El TTL que borró pedidos de verdad
- **Problema:** pedidos antiguos desaparecían misteriosamente.
- **Causa:** al copiar la configuración del contenedor `carritos` (TTL 7 días) se puso `defaultTtl = 604800` también en `pedidos`.
- **Solución:** restauración a un instante con **copia continua** hacia una cuenta nueva, copia de los documentos perdidos, y `defaultTtl = -1` en `pedidos` (TTL activo pero sin vencimiento por defecto; solo los eventos Outbox llevan `ttl` propio). Revisión de cambios de Terraform con aprobación.
- **Lección:** el TTL **borra datos sin avisar**. Protege los contenedores de datos importantes y activa copia continua.

## Caso 7 · Dos pods reservando el último stock
- **Problema:** se vendieron 12 unidades de un producto con 10 en inventario.
- **Causa:** cada pod leía el stock, restaba y reemplazaba sin control de versión.
- **Solución:** `patchItem` con `increment(-n)` y **predicado** `FROM c WHERE c.stock >= n` (si no hay stock suficiente, 412); alternativa: ETag con `If-Match` y reintento.
- **Lección:** la concurrencia optimista se resuelve en el servidor con ETag o con patch condicional, nunca con "leer y escribir" a ciegas.

## Caso 8 · Un cliente corporativo superó los 20 GB
- **Problema:** `Partition key reached maximum size of 20 GB` para un cliente mayorista (multi-inquilino con clave `/tenantId`).
- **Causa:** toda la información de un inquilino grande vivía en **una** partición lógica.
- **Solución:** nuevo contenedor con **clave jerárquica** (`/tenantId`, `/clienteId`, `/pedidoId`) y migración con importación masiva; las consultas por inquilino siguen dirigidas por prefijo.
- **Lección:** para multi-inquilino con tamaños dispares, usa claves jerárquicas desde el principio.

## Caso 9 · Cae una región… y casi nadie lo nota
- **Problema:** simulacro de falla regional.
- **Resultado:** con `preferredRegions` configuradas, conmutación automática y consistencia *Session*, la API tuvo ~40 s de errores 503 y se recuperó sola; el servicio que fijaba una sola región por configuración quedó caído hasta redeploy.
- **Lección:** configura **todas** las regiones preferidas, prueba la conmutación (en cuenta de pruebas) y haz que el cliente reintente.

## Caso 10 · Se filtró una cadena de conexión
- **Problema:** una clave de la cuenta apareció en un repositorio.
- **Solución:** regenerar claves, **desactivar la autenticación local**, asignar roles de datos a las identidades administradas y migrar herramientas (scripts de carga, Data Explorer del portal con Entra, CLI).
- **Cuidado:** herramientas antiguas que usan la clave dejan de funcionar; prepara la migración y las excepciones de emergencia (acceso temporal por rol, no clave).
- **Lección:** sin claves no hay nada que filtrar.

## Caso 11 · Se borró el contenedor equivocado
- **Problema:** `terraform destroy` en el entorno equivocado eliminó el contenedor `pedidos`.
- **Solución:** como la cuenta tenía **copia continua (30 días)**, se restauró a un instante anterior en una **cuenta nueva**, se validaron los datos y se apuntó la aplicación a la cuenta restaurada (o se copiaron los documentos).
- **Prevención:** *locks* de recurso, `prevent_destroy` en Terraform, permisos de plano de control separados por entorno.
- **Lección:** con copia periódica la restauración exige abrir un caso a soporte; la continua es autoservicio.

## Caso 12 · Paginar con OFFSET en el catálogo
- **Problema:** la página 200 del catálogo cuesta 40 veces más RU que la primera.
- **Causa:** `OFFSET ... LIMIT` vuelve a recorrer los resultados anteriores.
- **Solución:** paginación con **token de continuación** (`iterableByPage`) y un cursor opaco en la API.
- **Lección:** "ir a la página N" no es una operación natural en Cosmos; ofrece "siguiente" o búsqueda.

## Caso 13 · Migrar de seis tablas relacionales a un documento
- **Problema:** el pedido vivía en `pedido`, `linea`, `pago`, `envio`, `direccion`, `estado_historial` y cada pantalla hacía seis consultas.
- **Solución:** un documento `pedido` con líneas, pago y envío **incrustados**; el historial de estados en un contenedor aparte (documento por evento); el catálogo se **referencia** (cambia con otra frecuencia).
- **Lección:** incrusta lo que se lee y cambia **junto**; referencia lo que tiene otro ciclo de vida o puede crecer sin límite.

## Caso 14 · El documento de 2 MB
- **Problema:** `Request size is too large` (413) al actualizar pedidos de clientes frecuentes.
- **Causa:** el historial de eventos se guardaba como un **arreglo que crece sin límite** dentro del pedido.
- **Solución:** un documento por evento (mismo `clienteId`, `pedidoId` como propiedad) y consultas por partición; para históricos largos, *buckets* (un documento por día).
- **Lección:** arreglos ilimitados dentro de un documento son un antipatrón. Si crece sin tope, es otra entidad.

## Caso 15 · "Mi pedido no aparece" (consistencia de sesión)
- **Problema:** el usuario creaba un pedido y la lista "mis pedidos" no lo mostraba durante unos segundos.
- **Causa:** la escritura la atendió una instancia y la lectura otra, que consultó una réplica con retraso; sin token de sesión compartido no hay garantía de leer la propia escritura.
- **Solución:** devolver el **token de sesión** en una cabecera (`X-Cosmos-Session`) y aceptarlo en las lecturas siguientes (ver [uso en Java](uso-en-java.md) §3–4); o leer el documento creado directamente por `id`.
- **Lección:** *Session* garantiza "leer lo que escribiste" solo dentro de la misma sesión; en servicios sin estado hay que propagarla.
