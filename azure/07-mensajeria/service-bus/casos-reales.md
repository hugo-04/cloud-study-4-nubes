# Azure · Service Bus · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · El pico del Cyber Day
- **Problema:** a las 20:00 entraban 4 000 pedidos por minuto y la base de datos de facturación se caía.
- **Solución:** la API valida, **encola en `pedidos` y responde 202**; los procesadores consumen al ritmo que aguanta la BD (`maxConcurrentCalls` × réplicas); KEDA escala réplicas según la cola.
- **Resultado:** la API nunca se cae; la cola absorbe el pico y se vacía en minutos.
- **Lección:** la cola nivela la carga (*load leveling*) y desacopla velocidad de entrada de velocidad de proceso.

## Caso 2 · El mensaje venenoso
- **Problema:** un pedido con JSON inválido bloqueaba el flujo: se reintentaba una y otra vez, saturando logs y CPU.
- **Solución:** errores permanentes → `deadLetter` con motivo `NEGOCIO_INVALIDO`; `maxDeliveryCount = 8` para lo inesperado; alerta cuando la DLQ tiene mensajes.
- **Lección:** un mensaje malo no debe frenar al resto; la DLQ es parte del diseño, no un fallo.

## Caso 3 · Se cobró dos veces
- **Problema:** un cliente pagó dos veces el mismo pedido.
- **Causa:** el consumidor cobró, cayó antes de completar el mensaje, y el broker lo reentregó (entrega **al menos una vez**).
- **Solución:** tabla `procesados` con clave única y efecto + marca en **una sola transacción**; `MessageId` estable y *duplicate detection* para los reenvíos del productor; clave de idempotencia en la pasarela de pago.
- **Lección:** el broker no da exactamente-una-vez; la idempotencia es del consumidor.

## Caso 4 · Procesados dos veces a la vez
- **Problema:** archivos grandes se procesaban en dos réplicas simultáneamente.
- **Causa:** el bloqueo duraba 1 minuto, el proceso 6, y había `prefetch` alto (el reloj del bloqueo corría mientras esperaba en memoria).
- **Solución:** `maxAutoLockRenewDuration` de 15 min, `prefetch = 0` y `lockDuration` acorde.
- **Lección:** bloqueo ≥ tiempo de proceso o renovación activa; prefetch bajo con procesos lentos.

## Caso 5 · Direcciones actualizadas fuera de orden
- **Problema:** el cliente cambió dos veces su dirección y quedó la primera.
- **Causa:** varios consumidores competían y procesaron los cambios en distinto orden.
- **Solución:** cola con **sesiones** y `SessionId = clienteId`: orden FIFO por cliente y paralelismo entre clientes.
- **Lección:** el orden solo se garantiza con sesiones.

## Caso 6 · La suscripción que recibía todo
- **Problema:** Facturación recibía eventos de inventario y fallaba.
- **Causa:** al crear la suscripción quedó la regla `$Default` (todo) además de la regla de filtro; las reglas se combinan con OR.
- **Solución:** reemplazar `$Default` por la regla filtrada; revisar reglas en revisión de infraestructura.
- **Lección:** `$Default` deja pasar todo.

## Caso 7 · Outbox: base de datos + mensaje sin perder nada
- **Problema:** se guardaba el pedido en la BD pero a veces el mensaje no se publicaba (o al revés).
- **Causa:** no existe transacción entre la base de datos y Service Bus.
- **Solución:** patrón **Outbox**: en la misma transacción SQL se inserta el pedido y una fila en `salida`; un publicador lee `salida`, envía a Service Bus con `MessageId = id de la fila` y marca como enviada.
- **Lección:** la BD es la fuente de verdad; el broker se alimenta de ella.

## Caso 8 · Reintentos con espera creciente
- **Problema:** un proveedor de envíos caía 5 minutos y los reintentos inmediatos lo empeoraban.
- **Solución:** ante error transitorio, reenviar una copia **programada** (10 s, 20 s, 40 s…) con propiedad `intento`; tras 5 intentos, *dead-letter* con `REINTENTOS_AGOTADOS`.
- **Gotcha:** la copia necesita **MessageId nuevo**, o la detección de duplicados la descarta.
- **Lección:** `abandon()` reintenta ya; la espera real se logra reprogramando.

## Caso 9 · Saga de pedido, pago y envío
- **Problema:** un pedido pasa por pago, inventario y envío; si falla el envío hay que devolver el pago.
- **Solución:** comandos por cola (`pagar`, `reservar`, `enviar`) y eventos por tópico (`pago.confirmado`, `envio.fallido`); un orquestador con estado en BD emite compensaciones (`reembolsar`); cada paso es idempotente.
- **Lección:** consistencia eventual con compensaciones; sin transacciones distribuidas.

## Caso 10 · Desactivar claves SAS rompió un job heredado
- **Problema:** tras `local_auth_enabled=false`, un proceso batch antiguo dejó de enviar.
- **Causa:** usaba una cadena de conexión con `SharedAccessKey`.
- **Solución:** migrarlo a identidad administrada con *Data Sender*; mientras tanto, inventario de quién usaba claves (registros de ejecución).
- **Lección:** inventaría los consumidores de claves antes de cerrarlas.

## Caso 11 · La DLQ que nadie miraba
- **Problema:** 300 000 mensajes en la DLQ durante dos meses; clientes sin facturas.
- **Solución:** alerta `DeadletteredMessages > 0`, panel por entidad, runbook (leer motivo, corregir causa, reprocesar por motivo con el [reprocesador](uso-en-java.md#6-dlq-inspeccionar-y-reprocesar)).
- **Lección:** una DLQ sin alerta es una pérdida silenciosa de dinero.
