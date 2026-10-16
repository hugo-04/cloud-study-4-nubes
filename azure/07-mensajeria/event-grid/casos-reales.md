# Azure · Event Grid · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Rotación automática de secretos
- **Problema:** la contraseña de la base de datos vencía y alguien la cambiaba a mano; dos veces se cayó producción por olvido.
- **Solución:** tópico del sistema de Key Vault → `SecretNearExpiry` a una cola de Service Bus → un servicio genera la nueva contraseña, la guarda como nueva versión del secreto y actualiza la base.
- **Resultado:** rotación sin intervención y con trazabilidad.
- **Lección:** los eventos del sistema convierten tareas manuales en flujos automáticos.

## Caso 2 · Fan-out de pedidos sin acoplar equipos
- **Problema:** el servicio de pedidos llamaba uno a uno a Facturación, Inventario y Marketing; añadir un cuarto consumidor exigía cambiar el emisor.
- **Solución:** el emisor publica `pedido.creado` en un tópico personalizado; cada equipo crea su suscripción con sus filtros.
- **Lección:** el publicador no conoce a los consumidores.

## Caso 3 · Event Grid + Service Bus para no perder trabajo
- **Problema:** un webhook caído durante 40 minutos perdió eventos de pago por reintentos agotados.
- **Solución:** Event Grid entrega a una **cola de Service Bus**; los consumidores leen a su ritmo con DLQ propia, y Event Grid solo debe lograr dejar el evento en la cola.
- **Lección:** Event Grid enruta y filtra; Service Bus garantiza el procesamiento.

## Caso 4 · La factura de Event Grid se triplicó
- **Problema:** miles de entregas por segundo a un destino que respondía 500.
- **Causa:** el webhook fallaba y Event Grid reintentaba durante 24 horas cada evento.
- **Solución:** arreglar el destino, acotar `max delivery attempts` y TTL a lo útil, dead-letter y alerta de `DeliveryAttemptFailCount`.
- **Lección:** reintentos sin límite sobre un destino roto cuestan dinero y ruido.

## Caso 5 · Bucle infinito entre dos servicios
- **Problema:** dos microservicios se enviaban eventos entre sí sin fin.
- **Causa:** el servicio A publicaba `inventario.actualizado` al recibir `pedido.creado`; B publicaba `pedido.actualizado` al recibir ese evento…
- **Solución:** distinguir eventos de **negocio** (hechos externos) de eventos de **efecto** y no reaccionar a eventos propios; campo `origen` y filtro.
- **Lección:** cuidado con las cadenas de eventos que se retroalimentan.

## Caso 6 · SaaS multi-cliente con dominio
- **Problema:** cada cliente de ModaLima Pro quería recibir solo sus eventos en su propio webhook, con aislamiento.
- **Solución:** un **dominio** con un tópico hijo por cliente; cada cliente tiene permisos y suscripciones solo sobre el suyo.
- **Lección:** el dominio escala a miles de tópicos con una sola infraestructura.

## Caso 7 · Duplicados al facturar
- **Problema:** una factura se emitió dos veces.
- **Causa:** entrega al menos una vez: un reintento llegó después de que el primer intento había tenido éxito pero tardó en responder.
- **Solución:** idempotencia por `id` del evento en una tabla con clave única.
- **Lección:** "al menos una vez" = consumidor idempotente.

## Caso 8 · Webhook que no se podía crear
- **Problema:** "handshake failed" al crear la suscripción.
- **Causa:** el endpoint exigía autenticación y bloqueaba la petición de validación.
- **Solución:** permitir la validación en esa ruta con la autenticación de Event Grid (token de Entra ID de la aplicación) y responder el código de validación.
- **Lección:** el handshake ocurre al crear la suscripción y debe contestarse rápido.

## Caso 9 · Evento enorme rechazado
- **Problema:** `413` al publicar eventos con el pedido completo (con imágenes en base64).
- **Solución:** el evento lleva solo ids y una referencia; el consumidor consulta o lee el blob ([Claim Check](../../06-storage/claim-check/README.md)).
- **Lección:** el evento avisa, no transporta.

## Caso 10 · Pull para controlar el ritmo
- **Problema:** un consumidor lento no aguantaba el *push* de miles de eventos por minuto.
- **Solución:** tópico de namespace con entrega **pull**: el consumidor recibe lotes, confirma y devuelve los que no puede procesar.
- **Lección:** pull da control de ritmo; push da inmediatez.

## Caso 11 · Eventos de Container Registry para desplegar
- **Problema:** el equipo de plataforma quería desplegar automáticamente cuando se publicaba una imagen etiquetada `release-*`.
- **Solución:** tópico del sistema de Container Registry → `ImagePushed` con filtro de `subject` → Function que dispara el pipeline.
- **Lección:** los eventos conectan servicios de plataforma sin sondear.
