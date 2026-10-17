# NotebookLM · AWS · Caso integrado · Clickstream

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre el caso integrado "clickstream" en AWS, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la cinta transportadora con carriles y dos mesas (rápida y bodega), y el diagrama (API de ingesta, Kinesis Data Streams, consumidor, DynamoDB, Firehose, S3, Athena).
2. Los 9 pasos del flujo y las tres decisiones: clave de partición por sesión, ventanas por hora del evento con marca de agua, salida idempotente con checkpoint seguro.
3. Para qué sirve y cuándo no usar Kinesis.
4. Conceptos: shard, clave de partición, clave caliente, ventana tumbling, marca de agua, checkpoint, seudonimización.
5. Seguridad y privacidad: tabla identidad / plano de control / plano de datos, HMAC de sesión, cifrado, lago privado.
6. Qué hacer y qué no, límites, dimensionamiento y costos.
7. Los seis casos reales; Java: dimensionador, simulador de reparto, productor por lotes con reintento parcial, agregador de ventanas, lector de shards con checkpoint seguro; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
