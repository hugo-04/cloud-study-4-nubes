# AWS · SNS · Troubleshooting

Orden: **¿publicó bien? → ¿suscripción confirmada? → ¿política de la cola autoriza al tópico? → ¿filtro coincide (tipo de atributo, ámbito)? → ¿KMS? → ¿DLQ de la suscripción?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| No llega nada a la cola | Política de la cola sin `SourceArn` del tópico | Política de la cola | Autorizar al tópico |
| Suscripción `PendingConfirmation` | HTTP/email sin confirmar | `list-subscriptions-by-topic` | Confirmar |
| Llegan algunos mensajes | Filtro demasiado estricto | `FilterPolicy` de la suscripción | Corregir y probar con ejemplos |
| Filtro numérico no coincide | Atributo publicado como String | `DataType` del atributo | `Number` |
| Filtro sobre el cuerpo no funciona | Ámbito `MessageAttributes` (por defecto) | `FilterPolicyScope` | `MessageBody` si filtras el JSON |
| `KMSAccessDenied` al publicar | Tópico con KMS y el rol/servicio sin permiso | CloudTrail | Permisos en la clave |
| Mensaje con sobre JSON | Entrega cruda desactivada | Atributo `RawMessageDelivery` | Activarla o desempaquetar |
| Duplicados | Entrega al menos una vez | `MessageId` repetido | Idempotencia |
| Mensajes en la DLQ de la suscripción | Endpoint caído o sin permiso | Cuerpo y atributos | Corregir y reenviar |
| `InvalidParameter` en FIFO | Falta `MessageGroupId`/`DeduplicationId` | Error | Enviar ambos (o dedup por contenido) |
| `AuthorizationError` al publicar | Falta `sns:Publish` | IAM | Permiso al rol |
| Mensajes retrasados | Reintentos a un endpoint lento | Métricas de entrega | Cola intermedia; ajustar política |
