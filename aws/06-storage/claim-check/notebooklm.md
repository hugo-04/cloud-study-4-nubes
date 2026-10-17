# NotebookLM · AWS · Patrón Claim Check

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre el patrón Claim Check implementado en AWS con S3 y SQS, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del guardarropa y el flujo completo del diagrama.
2. Por qué existe: tamaños máximos de SQS, SNS, EventBridge, Kinesis y Kafka en MSK.
3. Las piezas: S3 versionado, productor, ticket, cola y DLQ, consumidor, idempotencia, limpieza; variante por evento de S3 frente a ticket explícito; el orden «subir y luego publicar».
4. Cuándo usarlo y cuándo no.
5. Seguridad: confused deputy, roles mínimos por prefijo, sin URLs prefirmadas en el ticket, cifrado.
6. Los seis casos reales como historias con su lección.
7. Java: ticket JSON, validación, hash SHA-256 en streaming, idempotencia con DynamoDB condicional, productor, consumidor, poller de SQS; Spring (MVC y WebFlux con @SqsListener) y Quarkus (imperativo con scheduler y reactivo con Mutiny).
8. Troubleshooting en orden; retenciones y visibility timeout.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
