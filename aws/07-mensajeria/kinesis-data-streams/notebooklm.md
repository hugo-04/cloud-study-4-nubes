# NotebookLM · AWS · Amazon Kinesis Data Streams

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Amazon Kinesis Data Streams, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la cinta transportadora con carriles (shards) y marcadores de lectura.
2. Streams, shards, registros, clave de partición y hash MD5, números de secuencia, modo bajo demanda y aprovisionado, retención, consumidores compartidos y fan-out mejorado, KCL y checkpoints, Lambda como consumidor, iteradores, cifrado, entrega al menos una vez.
3. Cuándo usarlo y cuándo no (frente a SQS, SNS, EventBridge, Firehose y Kafka).
4. Seguridad: permisos de productor y de consumidor KCL (DynamoDB y CloudWatch), KMS, entre cuentas, endpoint de VPC.
5. Qué hacer y qué no; costos.
6. Los seis casos reales como historias con su lección.
7. Java: simulador de distribución de claves, productor por lotes con reintento por registro, lectura con GetRecords, comparación de números de secuencia, consumidor KCL; Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny).
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
