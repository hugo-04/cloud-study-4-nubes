# NotebookLM · Azure · Patrón Claim Check

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre el patrón Claim Check implementado en Azure con Blob Storage y Service Bus (y menciones a Event Hubs con Kafka y a Event Grid), para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía del guardarropa de un teatro; qué problema resuelve y los límites de tamaño de mensaje de cada servicio.
2. Diagrama del flujo completo: subida directa con SAS, evento o confirmación, ticket en la cola, consumidor con identidad.
3. Las variantes: dirigida por el backend, por eventos y servicio a servicio.
4. El ticket: campos, por qué sin SAS, versión del blob, hash, tamaño, correlación; contrato versionado.
5. Las reglas donde se rompe en la vida real: orden de escritura, atomicidad, idempotencia, duplicados, bloqueo del mensaje, mensajes venenosos, DLQ, blob inexistente, archivos enormes, privacidad y limpieza.
6. Elegir el transporte: Service Bus, Event Hubs, Event Grid, Storage Queue.
7. Seguridad e IAM: roles de productor y consumidor, identidades administradas, redes privadas.
8. Los 11 casos reales como historias con su lección.
9. Código Java: productor con hash en streaming y Service Bus, consumidor con liquidación manual del mensaje, verificación de hash, dead-letter con motivo, idempotencia con base de datos, renovación del bloqueo, versión reactiva y Quarkus con Mutiny.
10. Ejemplos de Terraform (Blob, Event Grid, Service Bus, roles), CLI y esquemas JSON del mensaje.
11. Cuándo NO usar Claim Check, qué hacer, qué NO hacer, costos.
12. La tabla de troubleshooting y cómo reprocesar una DLQ.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
