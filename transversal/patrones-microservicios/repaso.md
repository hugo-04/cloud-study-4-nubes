# Transversal · Patrones de microservicios · Repaso

## Preguntas
1. ¿Por qué base de datos por servicio?
2. ¿Qué resuelve el strangler fig?
3. ¿Diferencia entre saga orquestada y coreografiada?
4. ¿Qué debe cumplir una compensación?
5. ¿Qué problema resuelve el outbox?
6. ¿Para qué sirve una idempotency key?
7. ¿Por qué jitter en los reintentos?
8. ¿Qué hace un circuit breaker abierto?
9. ¿Qué aísla un bulkhead?
10. ¿Cuándo NO conviene event sourcing?

## Respuestas
1. Para que cada servicio evolucione su modelo sin romper a otros.
2. Migrar un monolito por partes detrás de un proxy.
3. Un coordinador dirige los pasos / cada servicio reacciona a eventos de otros.
4. Ser idempotente, reintentable y semánticamente correcta (no siempre es «borrar»).
5. Guardar el cambio y el evento de forma atómica.
6. Que un reintento del cliente no repita el efecto.
7. Para que los clientes no reintenten sincronizados y saturen al servicio.
8. Falla rápido sin llamar al servicio hasta el periodo de prueba.
9. Los recursos (hilos, conexiones) por dependencia.
10. Cuando la historia no es un requisito: añade complejidad de versiones, proyecciones y reconstrucciones.

## Ejercicios
1. Diseña la saga «devolución»: pasos y compensaciones.
2. Decide dónde reintentar en la cadena gateway → pedidos → pagos.
3. Agrega a la proyección el evento `PedidoReembolsado`.
