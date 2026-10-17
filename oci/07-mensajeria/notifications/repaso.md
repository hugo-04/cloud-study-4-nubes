# Oracle OCI · Mensajería · Notifications · Repaso

## Preguntas
1. ¿Qué es un tema?
2. ¿Qué protocolos de suscripción hay?
3. ¿Por qué una suscripción queda `PENDING`?
4. ¿Qué garantía de entrega hay?
5. ¿Qué pasa si el webhook falla?
6. ¿Qué es una tormenta de alertas?
7. ¿Qué permiso necesita la app para publicar?
8. ¿Cuándo usar Queue en vez de Notifications?
9. ¿Qué no debe ir en una alerta?
10. ¿Cómo conectas una alarma de Monitoring?

## Respuestas
1. Un canal de publicación con suscripciones.
2. Correo, HTTPS, SMS, Slack, PagerDuty, funciones, entre otros *(verifica)*.
3. Falta que el dueño del endpoint la confirme.
4. Al menos una vez.
5. OCI reintenta un tiempo y luego descarta.
6. Muchísimos avisos iguales en poco tiempo.
7. `use ons-topics`.
8. Cuando el trabajo debe procesarse con reintentos largos y un consumidor.
9. Datos personales y secretos.
10. Poniendo el tema como destino de la alarma.

## Ejercicios
1. Diseña los temas de ModaLima por severidad y audiencia.
2. Implementa la clave de agrupación de alertas de errores HTTP.
3. Escribe el webhook idempotente del despacho de Café Andino.
