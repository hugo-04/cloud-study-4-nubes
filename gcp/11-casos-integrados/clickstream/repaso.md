# Google Cloud · Caso integrado · Clickstream · Repaso

## Preguntas
1. ¿Por qué la clave es la sesión?
2. ¿Hora del evento o de llegada?
3. ¿Qué es la marca de agua?
4. ¿Qué pasa con los tardíos?
5. ¿Cuándo se hace commit?
6. ¿Por qué el top es idempotente?
7. ¿Qué limita el paralelismo?
8. ¿Dónde va el historial?
9. ¿Qué datos se recortan?
10. ¿Qué se vigila?

## Respuestas
1. Para mantener el orden de la navegación de cada persona.
2. Del evento.
3. El máximo visto menos el retraso permitido.
4. Se cuentan aparte (o se corrigen en el histórico).
5. Después de escribir el resultado.
6. Para que releer no duplique.
7. El número de particiones.
8. BigQuery, vía Kafka Connect.
9. IP completas y datos personales.
10. El lag por grupo y los tardíos.

## Ejercicios
1. Calcula particiones para 8 000 eventos/s.
2. Cambia a ventanas deslizantes de 5 min.
3. Diseña la alerta de lag.
