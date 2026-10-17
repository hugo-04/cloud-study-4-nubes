# NotebookLM · AWS · Amazon EventBridge

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Amazon EventBridge, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la central de despacho de un puerto: bus, reglas, destinos, DLQ y archivo.
2. El sobre del evento, buses (predeterminado, personalizado, de socio), patrones (exacto, prefix, suffix, anything-but, numeric, exists, wildcard, $or), destinos, transformador de entrada, reintentos, DLQ, archivo y reproducción, Pipes, Scheduler, esquemas, entrega al menos una vez.
3. Cuándo usarlo y cuándo no (frente a SNS, SQS, Kinesis y Kafka).
4. Seguridad: PutEvents con ARN del bus, políticas de destino con SourceArn, roles de reglas, política del bus entre cuentas, cifrado.
5. Qué hacer y qué no; costos.
6. Los seis casos reales como historias con su lección.
7. Java: publicar en lotes con reintento por entrada, escribir el detail sin dependencias, evaluar patrones en local, leer el evento recibido; Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny).
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
