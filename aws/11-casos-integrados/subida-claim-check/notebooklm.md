# NotebookLM · AWS · Caso integrado · Subida de archivos con Claim Check

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre el caso integrado "subida de archivos con Claim Check" en AWS, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la lavandería con casillero y ticket, y el diagrama completo (API, URL prefirmada, S3 cuarentena, EventBridge, SQS, validador, S3 validadas, DynamoDB, reconciliador).
2. Los 8 pasos del flujo y la máquina de estados con escrituras condicionales.
3. Para qué sirve y cuándo no hace falta; qué no resuelve (antivirus).
4. Conceptos: Claim Check, URL prefirmada, cuarentena, firma del archivo, escritura condicional, reconciliador.
5. Seguridad: tabla identidad / plano de control / plano de datos, buckets privados con TLS, clave por idCarga, dueño comprobado en cada descarga.
6. Qué hacer y qué no, límites y costos.
7. Los seis casos reales; Java: reglas puras de validación, servicio de cargas, validador idempotente, reconciliador, adaptadores S3 y DynamoDB; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
