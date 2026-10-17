# AWS · DynamoDB · Troubleshooting

Orden: **¿región y nombre correctos? → ¿permisos (tabla e índices)? → ¿la consulta usa clave (Query) o recorre todo (Scan)? → ¿throttling (partición caliente, capacidad, GSI)? → ¿consistencia (eventual/GSI)? → ¿paginación y lotes incompletos?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `ResourceNotFoundException` | Región o nombre de tabla equivocados | `aws dynamodb describe-table` en esa región | Revisar configuración |
| `AccessDeniedException` al consultar un GSI | Política sin `table/<t>/index/*` | Mensaje (menciona el recurso) | Agregar el ARN del índice |
| `ProvisionedThroughputExceededException` / `ThrottlingException` | Partición caliente, capacidad baja o GSI limitante | Métricas `ReadThrottleEvents` / `WriteThrottleEvents` por tabla e índice; Contributor Insights | Mejor clave; más capacidad; bajo demanda; dimensionar GSI |
| `ValidationException: Reserved keyword` | Atributo con palabra reservada (`name`, `status`) | Expresión | `ExpressionAttributeNames` (`#n`) |
| `ValidationException` por clave | Tipo de clave distinto, cadena vacía en la clave, falta la clave de ordenación | Esquema de la tabla | Corregir tipo/valor de la clave |
| `ValidationException: Item size exceeded` | Ítem > 400 KB | Tamaño del ítem | Guardar el objeto en S3 y la referencia |
| `ConditionalCheckFailedException` | La condición no se cumple (versión distinta, ya existía) | Condición y valor actual | Es esperado: manejarlo (conflicto o duplicado), no reintentar a ciegas |
| `TransactionCanceledException` | Una condición falló o hubo conflicto con otra transacción | `CancellationReasons` por ítem | Corregir o reintentar si es `TransactionConflict` |
| Consulta lenta/cara | Es un `Scan` o el filtro descarta casi todo | `ScannedCount` ≫ `Count` | Rediseñar la clave o un GSI |
| Resultado incompleto | Falta seguir `LastEvaluatedKey` | Respuesta | Paginar |
| `BatchWriteItem` "exitoso" pero faltan ítems | `UnprocessedItems` sin reintentar | Respuesta | Reintentar solo los no procesados con espera creciente |
| Ítem no visible justo tras escribir | Lectura eventual o GSI | Tipo de lectura | `ConsistentRead` en la tabla base |
| Ítems vencidos que aún aparecen | TTL no es inmediato | Atributo `expira_en` | Filtrar vencidos al leer |
| Facturación alta | Scans, GSI con todo proyectado, bajo demanda con carga constante | Cost Explorer / métricas | Rediseño; aprovisionado con auto scaling; proyección mínima |
| Iterador de Streams vencido | Más de 24 h sin leer | Error `ExpiredIteratorException` | Leer a tiempo; reiniciar desde `TRIM_HORIZON` |
