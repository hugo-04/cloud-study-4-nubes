# NotebookLM · Azure · Event Hubs (con Kafka)

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI, KQL, propiedades Kafka, emulador).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Event Hubs y su compatibilidad con Apache Kafka, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es Event Hubs, con la analogía de la cinta transportadora con carriles y marcadores, y por qué un log no es una cola.
2. Jerarquía: namespace, event hub, particiones, grupos de consumidores, offsets, retención y reproducción. Diagrama.
3. Particiones y clave de partición: orden, paralelismo, dimensionamiento, partición caliente y qué se puede o no cambiar.
4. Niveles y capacidad: Basic, Standard, Premium y Dedicated; TU, PU y CU; auto-inflate; limitación.
5. Protocolos y puertos: AMQP, Kafka (9093) y HTTPS.
6. Capture hacia Blob y Data Lake en Avro, y el Registro de esquemas con reglas de compatibilidad.
7. Kafka en Event Hubs: mapa de conceptos, qué cambia al migrar, límites por nivel y autenticación con OAUTHBEARER o PLAIN.
8. Checkpoints en el SDK nativo frente a commits en Kafka; garantía al menos una vez e idempotencia.
9. Seguridad e IAM: Entra ID sin claves, roles por event hub, red privada, cifrado, almacén de checkpoints.
10. Los 14 casos reales como historias con su lección: sensores de cadena de frío, clics, migración de Kafka, CDC con Debezium, partición caliente, lag, reproceso, rebalances, evento venenoso, limitación, SIEM, event sourcing, duplicados y costos.
11. Código Java: productor por lotes, productor reactivo, EventProcessorClient con idempotencia y errores, replay por fecha, callback handler de Entra ID para Kafka, cliente Kafka puro, Spring Kafka con manejo de errores y DLQ, lag con AdminClient, WebFlux con Sinks, el estado descontinuado de Reactor Kafka, Quarkus con SmallRye en versión reactiva e imperativa, Schema Registry con Avro y lectura de archivos Capture.
12. Ejemplos de Terraform, CLI, KQL y emulador; qué hacer y qué NO hacer; costos y límites.
13. Tabla de troubleshooting y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
