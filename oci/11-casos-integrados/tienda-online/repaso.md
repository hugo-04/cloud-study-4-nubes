# Oracle OCI · Caso integrado · Tienda online · Repaso

## Preguntas
1. ¿Qué problema resuelve el outbox?
2. ¿Qué hace el relay?
3. ¿Qué resuelve el inbox?
4. ¿Por qué no publicar después del commit sin outbox?
5. ¿Qué pieza filtra ataques web?
6. ¿Dónde viven los carritos y por qué?
7. ¿Qué pasa con un evento venenoso en el relay?
8. ¿Cómo versionas un evento?
9. ¿Qué identidad usan los pods?
10. ¿Cuándo no usar eventos?

## Respuestas
1. Guardar y registrar el aviso de forma atómica.
2. Publica las filas pendientes del outbox y las marca.
3. Ignorar duplicados en el consumidor.
4. Un fallo entre el commit y la publicación pierde el evento.
5. El WAF sobre el Load Balancer.
6. En NoSQL, por acceso por clave y concurrencia optimista.
7. Se marca fallido tras N intentos y se alerta.
8. Con versión en el tipo y campos nuevos opcionales.
9. Workload identity de OKE.
10. Para consultas síncronas en el camino del usuario.

## Ejercicios
1. Diseña el esquema `PedidoPagado.v1`.
2. Escribe la consulta del relay que toma un lote sin bloquear a otros relays.
3. Diseña la saga de pago con compensación si falla la reserva de stock.
