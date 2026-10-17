# AWS · Kinesis Data Streams · Troubleshooting

Orden: **¿escribe bien (`FailedRecordCount`, throttling)? → ¿el reparto de claves es sano (shard caliente)? → ¿el lector avanza (atraso, checkpoints)? → ¿permisos (stream, KMS, DynamoDB de KCL)? → ¿duplicados o saltos (idempotencia)? → ¿retención suficiente?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `ProvisionedThroughputExceededException` al escribir | Un shard recibe más de 1 MiB/s o 1 000 reg/s | `WriteProvisionedThroughputExceeded` por shard | Mejor clave; más shards o modo bajo demanda; reintento con *jitter* |
| Solo un shard con tráfico | Clave de partición con pocos valores | `IncomingBytes` por shard | Clave de alta cardinalidad |
| `PutRecords` OK pero faltan datos | Registros fallidos no reintentados | `FailedRecordCount` y `ErrorCode` por registro | Reintentar solo los fallidos |
| `ReadProvisionedThroughputExceeded` | Varios consumidores compartidos o muchas llamadas `GetRecords` | Métrica por shard | Fan-out mejorado; KCL en vez de bucles propios |
| `IteratorAgeMilliseconds` creciente | Procesamiento lento o consumidor caído | Métrica + registros del consumidor | Paralelismo, lotes, aislar llamadas lentas; ampliar retención temporalmente |
| Lambda reprocesa el mismo lote sin parar | Un registro «venenoso» | Registros de la función | Bisección de lote, reintentos máximos y destino de fallos |
| KCL no arranca o no obtiene shards | Faltan permisos de DynamoDB/CloudWatch o nombre de aplicación distinto | Excepciones de `Scheduler`; tabla de *leases* | Permisos mínimos; mismo `applicationName` en todas las instancias |
| Registros duplicados | Reintentos del productor o reproceso del lector | Mismo identificador de negocio repetido | Idempotencia por clave |
| `AccessDenied` / `KMSAccessDeniedException` | Falta permiso en la clave | CloudTrail | `kms:Decrypt` / `GenerateDataKey` |
| Datos «desaparecidos» al releer | Superada la retención | `RetentionPeriodHours` | Ampliar retención antes de necesitar releer |
| Orden roto entre registros | Distintas claves, o varios productores sin secuencia | Claves usadas | Misma clave para lo que debe ir en orden; `SequenceNumberForOrdering` si hay un solo productor en serie |
| Un `shardEnded` sin checkpoint final | Procesador no llamó a `checkpoint()` al cerrar | Registros de KCL | Hacer `checkpoint()` en `shardEnded` |
