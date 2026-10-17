# AWS · Caso integrado · Clickstream · Troubleshooting

## Lista ordenada
1. **¿Llegan datos al stream?** `IncomingRecords` e `IncomingBytes`.
2. **¿Hay estrangulamiento de escritura?** `WriteProvisionedThroughputExceeded` por shard: ¿uno solo? → clave caliente.
3. **¿El consumidor va atrasado?** `GetRecords.IteratorAgeMilliseconds`; si crece, mira el procesamiento y los errores.
4. **¿Hay un lote que se repite?** Registros inválidos mal tratados.
5. **¿Se escriben las métricas?** Permisos `dynamodb:PutItem`; filas con la clave `(pagina, ventana#tipo#shard)`.
6. **¿Llega al lago?** Métricas de Firehose y prefijo `clics/anio=…` en S3; carpeta `errores/`.
7. **¿Athena no ve datos?** Partition projection y ruta exacta.

## Síntoma → causa
| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `ProvisionedThroughputExceededException` al escribir | Pocos shards o clave caliente | Reparto de claves; más shards o modo bajo demanda |
| Fallos parciales en `PutRecords` | Estrangulamiento puntual | Reintentar solo los fallidos con espera |
| `IteratorAge` crece | Consumidor lento o caído | Escalar consumidores (un worker por shard), revisar errores |
| `ExpiredIteratorException` | Iterador sin usar > 5 min | Pedir un iterador nuevo desde el checkpoint |
| Métricas dobles | Salida no idempotente | `PutItem` por clave, dedupe |
| Faltan clics del último minuto tras reiniciar | Checkpoint no seguro | Checkpoint hasta la ventana abierta más vieja |
| Athena devuelve 0 filas | Partición o ruta incorrectas | Revisar `storage.location.template` y fecha |
| Lago con basura | Datos sin validar en la puerta | Validación y seudonimización en la API |
