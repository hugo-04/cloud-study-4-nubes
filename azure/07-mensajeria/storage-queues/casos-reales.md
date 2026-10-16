# Azure · Storage Queues · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Miniaturas de productos
- **Problema:** subir una foto de producto tardaba 8 segundos porque la API generaba 5 tamaños antes de responder.
- **Solución:** la API guarda la foto original en Blob, deja una tarea `{v, productoId, blobUrl}` en la cola `tareas` y responde en 200 ms; un trabajador genera las miniaturas.
- **Resultado:** la API se volvió rápida y las miniaturas se procesan a ritmo sostenible.
- **Lección:** la cola convierte "hacerlo ya" en "hacerlo pronto" sin perder trabajo.

## Caso 2 · Correos de confirmación en picos
- **Problema:** durante una promoción, el proveedor de correo respondía con errores y se perdían confirmaciones.
- **Solución:** cada pedido encola un mensaje de correo; los trabajadores envían, y si falla usan `updateMessage` para reintentar con retroceso; tras 5 intentos va a `correos-poison` y se avisa al equipo.
- **Lección:** cola + retroceso + veneno = tolerancia a servicios externos inestables.

## Caso 3 · Eventos de Blob baratos
- **Problema:** subían facturas escaneadas a un contenedor y se quería procesar cada archivo, sin gastar en un bus completo.
- **Solución:** Event Grid entrega los eventos `BlobCreated` a una Storage Queue; los trabajadores leen el evento, descargan el blob y lo procesan ([Eventos de Blob](../../06-storage/eventos-blob/README.md)).
- **Lección:** para flujos simples, Event Grid → Storage Queue es la combinación más barata.

## Caso 4 · Trabajo programado "en 2 horas"
- **Problema:** recordar a los clientes un carrito abandonado 2 horas después.
- **Solución:** `sendMessage` con **retraso inicial** de 2 horas (visibilidad diferida); al hacerse visible, un trabajador revisa si el carrito sigue abierto y envía el recordatorio.
- **Lección:** el diferido es el temporizador más barato; recuerda que el máximo es 7 días.

## Caso 5 · Mensaje que se procesa dos veces
- **Problema:** algunos clientes recibían dos correos.
- **Causa:** el procesamiento tardaba 70 s pero el *visibility timeout* era 30 s: el mensaje reaparecía y lo tomaba otro trabajador.
- **Solución:** visibilidad de 120 s, renovación con `updateMessage` en trabajos largos e idempotencia con clave `pedidoId+tipo` en la base.
- **Lección:** "al menos una vez" no es un defecto, es el contrato: se diseña para ello.

## Caso 6 · La cola de veneno que nadie miraba
- **Problema:** 3.000 mensajes en `-poison` sin que nadie lo supiera durante un mes.
- **Causa:** se creó la cola de veneno pero no la alarma.
- **Solución:** alerta cuando `approximateMessageCount` > 0, panel y proceso de revisión semanal (corregir y reencolar, o descartar).
- **Lección:** una cola de veneno sin alerta es un cementerio.

## Caso 7 · Escalado por largo de cola
- **Problema:** los trabajadores eran 2 fijos; en picos la cola crecía a 80.000 mensajes.
- **Solución:** KEDA con escalador `azure-queue` (50 mensajes por réplica, máximo 20) y Workload Identity.
- **Lección:** el largo de la cola es la mejor señal para escalar trabajadores.

## Caso 8 · Cuando conviene pasar a Service Bus
- **Problema:** el equipo de pagos necesitaba orden por cliente, detección de duplicados y DLQ con motivo.
- **Decisión:** esos requisitos no existen en Storage Queues; migraron **solo** el flujo de pagos a Service Bus y dejaron en Storage Queues los trabajos simples (miniaturas, correos).
- **Lección:** usa la herramienta más simple que cumpla el requisito; no obligues a una cola a ser un bus.

## Caso 9 · Mensaje demasiado grande
- **Problema:** `RequestBodyTooLarge` al encolar el JSON completo de un pedido con detalle.
- **Solución:** guardar el JSON en Blob y encolar solo la referencia ([Claim Check](../../06-storage/claim-check/README.md)).
- **Lección:** 64 KB obligan a diseñar bien el mensaje.

## Caso 10 · Función de Azure con cola: mensajes "perdidos"
- **Problema:** una Function no procesaba mensajes enviados por una aplicación Java.
- **Causa:** la Function esperaba Base64 y la aplicación enviaba texto plano (o al revés): fallaba la decodificación y el mensaje terminaba en `-poison`.
- **Solución:** alinear la codificación (`QueueMessageEncoding.BASE64` y `messageEncoding` de la Function).
- **Lección:** acuerda la codificación del cuerpo entre productor y consumidor desde el día uno.
