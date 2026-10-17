# Google Cloud · Compute · Cloud Run functions · Repaso

## Preguntas
1. ¿Qué tipos de función hay?
2. ¿Sobre qué corre una función?
3. ¿Qué es un CloudEvent?
4. ¿Qué rol necesita el disparador?
5. ¿Qué pasa si una función de eventos falla sin reintentos?
6. ¿Cómo logras idempotencia?
7. ¿Qué límite de tiempo tienen los eventos?
8. ¿Cuándo usar Cloud Run en lugar de una función?
9. ¿Cómo proteges un webhook público?
10. ¿Qué runtime Java usar?

## Respuestas
1. HTTP y de eventos.
2. Sobre Cloud Run.
3. Un formato estándar de evento con id, fuente, tipo y datos.
4. `roles/run.invoker` sobre la función.
5. El evento se pierde.
6. Con el id del evento y resultados deterministas.
7. Hasta 9 minutos *(verifica)*.
8. Para APIs con varias rutas o frameworks completos.
9. Verificando la firma del remitente.
10. `java21`.

## Ejercicios
1. Escribe la función de miniaturas idempotente.
2. Configura reintentos y DLQ para facturación.
3. Diseña la verificación HMAC del webhook de pagos.
