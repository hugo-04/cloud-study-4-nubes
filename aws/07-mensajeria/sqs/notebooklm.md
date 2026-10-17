# NotebookLM · AWS · Amazon SQS

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Amazon SQS, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del buzón de pedidos de una cocina y el flujo con DLQ.
2. Estándar frente a FIFO, visibility timeout, long polling, DLQ y redrive, retraso, retención, tamaño, lotes, atributos, cifrado, política de cola, colas justas.
3. Cuándo usarlo y cuándo no (frente a SNS, EventBridge, Kinesis y Kafka).
4. Seguridad: política de cola, KMS, TLS, datos en la DLQ.
5. Qué hacer y qué no; costos.
6. Los seis casos reales como historias con su lección.
7. Java: envío por lotes con reintento parcial, backoff con ChangeMessageVisibility, deduplicación FIFO, consumidor idempotente; Spring (SqsTemplate y @SqsListener, MVC y WebFlux) y Quarkus (imperativo y Mutiny).
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
