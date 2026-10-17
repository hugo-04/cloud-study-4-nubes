# NotebookLM · AWS · Capítulo 07 Mensajería

**Fuentes a subir:** este `README.md` y los `README.md`, `casos-reales.md` y `uso-en-java.md` de `sqs`, `sns`, `eventbridge`, `kinesis-data-streams` y `msk-kafka`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre la mensajería y los flujos de eventos en AWS: Amazon SQS, Amazon SNS, Amazon EventBridge, Amazon Kinesis Data Streams y Amazon MSK (Kafka). Habla solo de AWS; no compares con otras nubes.

Estructura obligatoria:
1. La pregunta que responde cada servicio con su analogía (bandeja de pendientes, altavoz, central de despacho, cinta con carriles, central de correos) y cómo se encadenan.
2. SQS: colas estándar y FIFO, visibilidad, reintentos, DLQ, long polling, lotes con fallos parciales.
3. SNS: tópicos, suscripciones, filtros por atributos y por cuerpo, entrega cruda, fan-out hacia colas.
4. EventBridge: buses, patrones, destinos, transformador de entrada, reintentos y DLQ por destino, archivo y reproducción, Pipes y Scheduler.
5. Kinesis Data Streams: shards, clave de partición, bajo demanda y aprovisionado, retención, consumidores compartidos y fan-out mejorado, KCL.
6. MSK: aprovisionado, Express y Serverless, autenticación IAM, red privada, permisos de clúster, tópico y grupo, tópicos por código, MSK Connect.
7. La tabla comparativa y el árbol de decisión; cuándo NO usar cada uno.
8. La receta de ModaLima y el orden de adopción; reglas transversales (idempotencia, DLQ, alarmas, contratos, resultado por elemento en lotes).
9. Java: el patrón de núcleo puro más envoltorio del SDK en Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny); ejemplos de cada servicio.
10. Los casos reales de cada servicio como historias con su lección.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 7 puntos de resumen y 5 preguntas de repaso.
```
