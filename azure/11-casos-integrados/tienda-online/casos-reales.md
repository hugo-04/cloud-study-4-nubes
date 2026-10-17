# Azure · Caso integrado · Tienda online · Casos reales

Historias de ModaLima (ficticia). Cada una termina con la lección.

## 1. El pedido pagado que nunca se facturó
**Qué pasó:** la API guardaba el pedido y luego publicaba en Service Bus. Un reinicio del pod justo entre ambos pasos dejó 38 pedidos cobrados sin factura durante una campaña.
**Causa:** dos escrituras en dos sistemas sin garantía común.
**Solución:** bandeja de salida: evento y pedido en una transacción; un publicador aparte. Se recuperaron los 38 con una consulta sobre pedidos sin evento.
**Lección:** si «guardar y avisar» no es atómico, algún día se pierde el aviso.

## 2. La factura duplicada
**Qué pasó:** tras el cambio anterior, a algunos clientes les llegaron dos facturas.
**Causa:** el publicador publicó, murió antes de marcar la fila y, al reiniciar, publicó otra vez. Facturación no era idempotente.
**Solución:** `MessageId` fijo (`evt-<id>`) con detección de duplicados en el tópico, y bandeja de entrada en facturación (registro del `MessageId` en la misma transacción que la factura).
**Lección:** «al menos una vez» exige consumidores idempotentes; la detección de duplicados del bus es una red, no la garantía.

## 3. El Private Endpoint que «funcionaba» desde el portal
**Qué pasó:** tras cerrar el acceso público de SQL, los pods fallaron con tiempo agotado; desde el portal todo se veía correcto.
**Causa:** la zona DNS privada no estaba enlazada a la VNet de AKS; el nombre seguía resolviendo a la IP pública.
**Solución:** enlace de la zona, y el script `verificar-privado.sh` en el pipeline de cada entorno.
**Lección:** prueba la resolución de nombres **desde dentro**; el recurso privado no sirve si el DNS dice otra cosa.

## 4. Campaña de Black Friday: el cuello era la base
**Qué pasó:** APIM y AKS escalaron, pero la base de datos se saturó y los pedidos tardaron 20 s.
**Causa:** el catálogo se leía de SQL en cada visita; el escalado de pods solo trasladó el problema.
**Solución:** catálogo en Redis con vencimiento corto, límites por cliente en APIM, y pruebas de carga previas con 3× el pico del año anterior.
**Lección:** escalar la capa de arriba sin proteger la de abajo hace más ruido, no más ventas.

## 5. El correo que bloqueaba la compra
**Qué pasó:** el proveedor de correo cayó 40 minutos; no se podían crear pedidos.
**Causa:** `pedidos` llamaba al servicio de notificaciones de forma síncrona.
**Solución:** `notificaciones` pasó a ser una suscripción más del tópico; si cae, los mensajes esperan.
**Lección:** lo que no es indispensable para confirmar la compra va por eventos.

## 6. La SAS compartida en un grupo de WhatsApp
**Qué pasó:** un enlace de descarga de comprobante, válido 30 días, circuló fuera del cliente.
**Causa:** SAS con clave de la cuenta y vencimiento largo.
**Solución:** SAS de delegación de usuario de 10 minutos generada por `comprobantes` tras autenticar; el enlace se pide cada vez.
**Lección:** el enlace firmado es una llave: corta, estrecha y emitida bajo demanda.

## 7. La DLQ que nadie miraba
**Qué pasó:** 900 mensajes fallidos acumulados durante 3 semanas por un campo nuevo que el consumidor no entendía.
**Causa:** sin alerta sobre la cola de mensajes fallidos.
**Solución:** alerta con umbral 1, procedimiento de reproceso y versión en el evento (`version`) con tolerancia a campos desconocidos.
**Lección:** una cola de fallidos sin alarma es un cementerio.

## 8. Producción borrada en un `terraform destroy` de «desarrollo»
**Qué pasó:** un `destroy` apuntó al estado equivocado y borró recursos de producción.
**Solución:** estados y suscripciones separados, bloqueos `CanNotDelete` en producción, pipelines con entorno protegido ([10](../../10-terraform/README.md)).
**Lección:** los bloqueos son el último freno; el primero es no compartir estado.

## Resumen de patrones

| Problema | Patrón | Servicio |
|---|---|---|
| Perder o duplicar eventos | Bandeja de salida + entrada | SQL + Service Bus |
| Archivos pesados | Claim Check | Blob |
| Acoplamiento síncrono | Eventos con suscripciones | Service Bus |
| Datos expuestos | Private Endpoint + DNS | Red |
| Picos | Caché + límites + colas | Redis · APIM |
| Fallos silenciosos | Alertas en DLQ y bandeja | Monitor |
