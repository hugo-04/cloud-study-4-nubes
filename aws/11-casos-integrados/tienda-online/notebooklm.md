# NotebookLM · AWS · Caso integrado · Tienda online

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre el caso integrado "tienda online" en AWS, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la tienda con vitrina, mostrador, trastienda y buzón interno, y el diagrama completo (CloudFront+WAF, API Gateway, ALB, ECS Fargate, Aurora, ElastiCache, EventBridge, SQS, DynamoDB, S3).
2. El viaje de una compra en 10 pasos y la tabla de qué servicio resuelve cada necesidad.
3. La pieza difícil: guardar y avisar. Bandeja de salida, publicador por lotes, resultado por elemento, bandeja de entrada en DynamoDB, entrega al menos una vez más idempotencia.
4. Cuándo usar este diseño y cuándo no.
5. Seguridad: tabla identidad / plano de control / plano de datos, políticas de cola con aws:SourceArn, sin datos personales en atributos.
6. Qué hacer y qué no, límites y costos.
7. Los seis casos reales como historias con su lección; Java: núcleo común, Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en el orden de la lista.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
