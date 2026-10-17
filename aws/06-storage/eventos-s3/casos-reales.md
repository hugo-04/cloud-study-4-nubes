# AWS · Eventos de S3 · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El bucle de las miniaturas
**Qué pasó:** una Lambda generaba miniaturas y las guardaba en el mismo bucket y prefijo que disparaba el evento. En minutos hubo millones de invocaciones y una factura inesperada. **Solución:** prefijos separados (`originales/` → `miniaturas/`), el evento solo en `originales/`, y límite de concurrencia reservada. **Lección:** entrada y salida nunca comparten disparador.

## 2. «El archivo con ñ no existe»
**Qué pasó:** `NoSuchKey` al leer `ventas+octubre+ñ.csv`: la clave del evento venía codificada. **Solución:** decodificar con `URLDecoder` (UTF-8) antes de llamar a S3. **Lección:** la clave de las notificaciones llega codificada como URL.

## 3. Dos facturas por un mismo archivo
**Qué pasó:** S3 entregó el evento dos veces; el consumidor generó dos facturas. **Solución:** clave de idempotencia (`bucket|clave|versionId|sequencer`) con escritura condicional. **Lección:** «al menos una vez».

## 4. La actualización que llegó antes que la creación
**Qué pasó:** un `PUT` sobreescribió el mismo archivo dos veces seguidas; los eventos llegaron invertidos y el sistema se quedó con la versión vieja. **Solución:** comparar `sequencer` por clave y descartar el más antiguo; o procesar siempre «la última versión» consultando S3. **Lección:** no hay orden global.

## 5. El filtro que ahorró el 90 % de invocaciones
**Qué pasó:** cada subida de 0 bytes (marcadores de carpeta) y cada borrado disparaban el procesamiento. **Solución:** EventBridge con patrón `size > 0`, prefijo `exportes/` y motivo `PutObject`/`CompleteMultipartUpload`. **Lección:** filtra en el origen, no en el consumidor.

## 6. El destino mudo
**Qué pasó:** se configuró la notificación a SQS pero no llegaban mensajes: faltaba la política de la cola que autoriza a S3. **Solución:** política con `SourceArn` del bucket y `SourceAccount`; probar con `s3:TestEvent`. **Lección:** el destino debe permitir expresamente a S3.

| Problema | Solución |
|---|---|
| Bucle infinito | Prefijos separados + concurrencia limitada |
| `NoSuchKey` con espacios/ñ | Decodificar la clave |
| Duplicados | Idempotencia |
| Orden invertido | `sequencer` por clave |
| Invocaciones inútiles | Filtros finos (EventBridge) |
| No llega nada | Política del destino con `SourceArn` |
