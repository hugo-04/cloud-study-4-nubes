# Transversal · Apache Kafka · Repaso

## Preguntas
1. ¿Qué garantiza el orden en Kafka?
2. ¿Qué decide la partición de un registro?
3. ¿Qué significan `acks=all` y `min.insync.replicas`?
4. ¿Qué evita la idempotencia del productor?
5. ¿Por qué un consumidor «al menos una vez» debe ser idempotente?
6. ¿Qué pasa si hay más consumidores que particiones?
7. ¿Qué es la compactación?
8. ¿Para qué sirve una DLT?
9. ¿Qué compatibilidad de esquema conviene por defecto?
10. ¿Qué causa rebalanceos en bucle?

## Respuestas
1. El orden existe solo dentro de una partición.
2. La clave (hash) o el particionador si no hay clave.
3. El líder confirma cuando todas las ISR tienen el registro; con mínimo 2 ISR toleras perder un broker sin perder datos.
4. Duplicados por reintentos del productor.
5. Porque tras un fallo se reprocesa desde el último offset confirmado.
6. Los sobrantes quedan inactivos.
7. Conservar solo el último valor por clave.
8. Apartar mensajes que no se pueden procesar sin bloquear la partición.
9. `BACKWARD`.
10. Procesar un lote más tiempo que `max.poll.interval.ms`.

## Ejercicios
1. Diseña el tema `ventas.pedido.pagado.v1`: particiones, réplica, retención y clave.
2. Agrega una prueba de duplicado al `Facturador`.
3. Cambia el consumidor reactivo para publicar los inválidos en la DLT.
