# NotebookLM · Azure · Eventos de Blob (Event Grid)

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre los eventos de Blob Storage con Azure Event Grid, para un ingeniero Java de microservicios que quiere dominarlos de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué son los eventos de Blob, con la analogía del timbre de la puerta, y qué problema resuelven frente al sondeo.
2. Las piezas: cuenta de storage, tópico del sistema, suscripción de eventos, filtros, destinos, identidad de entrega y dead-letter. Diagrama del flujo.
3. Los tipos de evento (BlobCreated, BlobDeleted, BlobRenamed, cambios de nivel, inventario, ciclo de vida) y cuándo se emite cada uno, incluidas las subidas por bloques y por SFTP.
4. El esquema del evento campo por campo (id, subject, url, eTag, contentLength, sequencer) y los esquemas Event Grid y CloudEvents.
5. Garantías: al menos una vez, sin orden, reintentos, dead-letter, latencia y tamaño.
6. El handshake de los webhooks y la autenticación con Microsoft Entra ID.
7. Filtros por tipo, prefijo, sufijo y avanzados, con ejemplos.
8. Eventos frente a change feed, disparador de Functions por sondeo, inventario y mensajes publicados por el productor.
9. Seguridad e IAM: roles del tópico en cada destino, quién puede crear suscripciones, redes privadas y servicios de confianza.
10. Los 11 casos reales como historias con su lección: bucle infinito, duplicados, desorden, webhook sin validar, filtro con mayúsculas, dead-letter, red privada, SFTP, auditoría, lifecycle.
11. Código Java: webhook con validación en Spring Boot imperativo y reactivo y en Quarkus con Mutiny, consumidor de cola con idempotencia y lectura con If-Match, y una Azure Function.
12. Ejemplos de Terraform, CLI, KQL y eventos JSON; qué hacer y qué NO hacer; costos; tabla de troubleshooting y reproceso del dead-letter.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
