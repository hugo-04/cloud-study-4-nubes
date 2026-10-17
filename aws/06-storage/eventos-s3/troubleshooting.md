# AWS · Eventos de S3 · Troubleshooting

Orden: **¿hay notificación configurada y validada? → ¿política del destino (SourceArn/SourceAccount, KMS)? → ¿filtros prefijo/sufijo? → ¿el consumidor decodifica y parsea bien? → ¿duplicados/orden? → ¿DLQ?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Al configurar: `Unable to validate the following destination configurations` | La política del destino no autoriza a S3 | Error de `put-bucket-notification-configuration` | Política de la cola/tópico con `s3.amazonaws.com`, `SourceArn`, `SourceAccount` |
| No llegan eventos | Filtro que no coincide; destino sin política; cola con KMS sin permiso a S3 | `get-bucket-notification-configuration`; métricas de SQS | Revisar prefijo/sufijo (distingue mayúsculas); permisos KMS |
| Llega `s3:TestEvent` | S3 prueba el destino al crear la regla | Cuerpo del mensaje | Ignorarlo en el consumidor |
| `NoSuchKey` al leer | Clave sin decodificar | Comparar con la clave real | `URLDecoder.decode(clave, UTF_8)` |
| Eventos duplicados | Entrega al menos una vez | Mismo `sequencer` | Idempotencia |
| Datos viejos procesados | Orden invertido | Comparar `sequencer` | Descartar el más antiguo o leer la última versión |
| Bucle de invocaciones | Salida en el prefijo de entrada | Gráfica de invocaciones | Separar prefijos; concurrencia reservada |
| EventBridge no dispara la regla | Bucket sin `eventbridge = true` o patrón incorrecto | Configuración del bucket; prueba de patrón | Activar EventBridge; ajustar patrón |
| Lambda con `Throttled` | Pico de subidas | Métricas de Lambda | Cola SQS delante + concurrencia máxima |
| Mensajes en la DLQ | Error permanente de parseo o permisos | Cuerpo del mensaje | Corregir y reprocesar (*redrive*) |
| Retraso de segundos o minutos | Comportamiento normal bajo carga | Marcas de tiempo | Diseñar tolerante; no depender de milisegundos |
