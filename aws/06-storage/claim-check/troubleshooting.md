# AWS · Claim Check · Troubleshooting

Orden: **¿el ticket es válido y está permitido? → ¿existe el objeto (clave + versionId)? → ¿permisos S3/KMS del consumidor? → ¿hash/tamaño coinciden? → ¿visibility timeout suficiente? → ¿DLQ y redrive?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `NoSuchKey` / `NoSuchVersion` | Ticket antes que el objeto, objeto expirado o `versionId` incorrecto | `head-object --version-id` | Subir antes de publicar; retención mayor |
| `AccessDenied` al descargar | Rol del consumidor sin `GetObject`/`GetObjectVersion` o sin KMS | CloudTrail | Permisos del prefijo y de la clave |
| Mensajes duplicados | Entrega «al menos una vez» o timeout corto | Mismo `MessageId` o mismo ticket repetido | Idempotencia; visibility timeout mayor |
| El mensaje reaparece sin parar | El consumidor falla antes de borrar | Logs; `ApproximateReceiveCount` | Corregir el error; DLQ con `maxReceiveCount` |
| Hash no coincide | Objeto modificado, descarga parcial o ticket erróneo | Comparar SHA-256 | Reintentar; revisar al productor |
| `BadDigest` al subir | El archivo cambió mientras se subía | Error de S3 | Calcular el hash del archivo estable |
| Procesa dos veces en paralelo | Sin reserva atómica | Registros de procesamiento | Reserva condicional (`attribute_not_exists`) |
| Ticket rechazado por validación | Bucket/prefijo/tamaño fuera de lo permitido | Mensaje de validación | Corregir el productor; ver DLQ |
| Latencia alta | Descargas grandes con poca banda | Tiempos | Endpoint de VPC, más réplicas, partes en paralelo |
| DLQ llena | Error permanente (ticket inválido) | Cuerpo de la DLQ | Corregir y *redrive*; alarma |
| Cola crece | Consumidores lentos | `ApproximateNumberOfMessagesVisible` | Escalar consumidores |
