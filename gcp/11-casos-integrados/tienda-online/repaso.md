# Google Cloud · Caso integrado · Tienda online · Repaso

## Preguntas
1. ¿Qué problema resuelve el outbox?
2. ¿Y el inbox?
3. ¿Qué hace el relay?
4. ¿Por qué `SKIP LOCKED`?
5. ¿Para qué la clave de orden?
6. ¿Qué identidad publica?
7. ¿Cómo se protege la entrada?
8. ¿Dónde viven los carritos?
9. ¿Qué no debe ir en un evento?
10. ¿Por qué no 2PC?

## Respuestas
1. Guardar y avisar de forma atómica.
2. Procesar cada evento una sola vez pese a duplicados.
3. Publica pendientes y los marca enviados.
4. Para que varias instancias no tomen las mismas filas.
5. Entregar en orden los eventos de un mismo pedido.
6. La SA de Cloud Run `run-pedidos` con `pubsub.publisher`.
7. Cloud Armor + LB y Cloud Run con ingress interno.
8. En Firestore.
9. Datos de tarjeta y personales completos.
10. No escala ni lo soportan los servicios: se usan sagas.

## Ejercicios
1. Dibuja la saga de devolución.
2. Escribe la consulta de pendientes antiguos.
3. Diseña la alerta de la DLQ.
