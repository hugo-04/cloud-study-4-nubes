# Azure · Caso integrado · Tienda online · Troubleshooting

Orden general: **¿llegó la petición? → ¿se guardó el pedido? → ¿salió el evento de la bandeja? → ¿llegó al bus? → ¿lo procesó el consumidor? → ¿el archivo está en Blob?** Cada pregunta tiene una consulta en [`kql-tienda.md`](ejemplos/kql/kql-tienda.md).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Pedido creado, sin factura | La bandeja no se publica | `select count(*) from bandeja_salida where publicado_en is null` crece | Revisar el publicador: permisos *Data Sender*, DNS del bus, errores en logs |
| La bandeja crece y el publicador «funciona» | Un evento con error bloquea el lote (orden estricto) | El mismo `id` falla en cada vuelta | Corregir la causa; sacar el evento a una tabla de fallidos con alerta |
| Dos facturas del mismo pedido | Consumidor no idempotente o `MessageId` aleatorio | Dos filas con distinto `MessageId` para el mismo pedido | `MessageId` determinista + bandeja de entrada |
| Duplicados con `MessageId` igual | Fuera de la ventana de detección | Diferencia de tiempo entre ambos | Confiar en la bandeja de entrada; ampliar la ventana si procede |
| Tiempo agotado hacia SQL/Key Vault/Blob/Bus | DNS apunta a la IP pública o NSG bloquea | `verificar-privado.sh` desde un pod | Enlazar la zona privada a la VNet; revisar NSG de `snet-pe` |
| `403` al enviar/recibir en el bus | Falta el rol *Data Sender/Receiver* o la identidad no es la esperada | Asignaciones de roles en el tópico; el `azp`/`oid` del token | Asignar el rol en el alcance mínimo; esperar propagación (minutos) |
| `ServiceBusException … MessagingEntityNotFound` | Tópico o suscripción mal escritos o en otro espacio de nombres | Nombre en la configuración | Corregir la configuración por entorno |
| Mensajes en la DLQ | Excepción en el consumidor o `MaxDeliveryCount` agotado | Motivo en la propiedad `DeadLetterReason` | Corregir, reprocesar con procedimiento y alerta |
| Pedidos duplicados por reintento del cliente | Sin `Idempotency-Key` | Misma clave, dos pedidos | Tabla de claves con restricción única y respuesta repetida |
| `deadlock` / esperas en la bandeja | Varias réplicas sin `SKIP LOCKED` o lotes enormes | Esperas en la base | `FOR UPDATE SKIP LOCKED` y lotes de ~50 |
| Pedidos lentos en campaña | Catálogo leído de SQL en cada visita | Duración por dependencia en Application Insights | Redis con vencimiento + límites en APIM |
| El comprobante «no existe» | Se generó, pero el evento llegó antes que el archivo, o se firmó otra ruta | Blob por nombre y fecha | Guardar el archivo antes de publicar la referencia |
| SAS vencida o `AuthorizationFailure` | Reloj, vencimiento corto o falta de *Blob Delegator* | Hora del servidor y rol de quien firma | Sincronizar reloj; rol correcto; vencimiento razonable |
| `terraform apply` falla en el Private Endpoint | Subred con políticas de red o zona DNS equivocada | Mensaje de error y `privatelink` de cada servicio | Usar el nombre de zona correcto por servicio ([01](../../01-red/private-endpoint-dns/README.md)) |
| Sin trazas entre servicios | No se propaga el contexto en los mensajes | Falta de `traceparent` en las propiedades | Copiarlo a las propiedades del mensaje al publicar y restaurarlo al consumir |
