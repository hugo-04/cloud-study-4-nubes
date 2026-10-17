# Oracle OCI · Caso integrado · Tienda online · Casos reales

## 1. El pedido sin factura
**Qué pasó:** algunos pedidos pagados nunca se facturaban.
**Causa:** el servicio guardaba el pedido y luego publicaba; un reinicio entre ambos perdía el evento.
**Arreglo:** outbox en la misma transacción y relay.
**Lección:** guardar y avisar debe ser atómico.

## 2. Dos facturas por pedido
**Qué pasó:** en horas punta aparecían facturas duplicadas.
**Causa:** reentrega de la cola tras superar la visibilidad.
**Arreglo:** inbox con clave única por `id_evento`.
**Lección:** el consumidor es quien garantiza «una vez».

## 3. El relay que se atascó
**Qué pasó:** el outbox creció a 200.000 filas en una noche.
**Causa:** un evento malformado hacía fallar el lote completo una y otra vez.
**Arreglo:** marcar el evento como fallido tras N intentos y seguir con el resto; alarma por filas pendientes.
**Lección:** un mensaje venenoso no debe bloquear a los demás.

## 4. El cambio de contrato
**Qué pasó:** despacho dejó de funcionar tras agregar un campo obligatorio al evento.
**Causa:** consumidores con esquema rígido.
**Arreglo:** versión en el evento (`PedidoPagado.v2`), campos nuevos opcionales y convivencia de versiones.
**Lección:** los eventos son una API pública.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Evento perdido | Guardar y publicar separados | Outbox |
| 2 | Duplicados | Reentrega | Inbox |
| 3 | Outbox creciendo | Mensaje venenoso | Fallidos aparte + alarma |
| 4 | Consumidor roto | Contrato cambiado | Versionado |
