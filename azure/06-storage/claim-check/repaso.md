# Azure · Claim Check · Repaso

## Preguntas de repaso
1. ¿Qué es Claim Check y qué problema resuelve?
   - *Guardar el dato grande en storage y enviar por la cola solo una referencia, porque los brokers tienen límites de tamaño y mover MB por ellos es caro.*
2. ¿Qué lleva el ticket?
   - *Id, URL del blob (sin SAS), versión/etag, tamaño, tipo, hash, propietario, correlación, fecha.*
3. ¿Por qué es mejor un ticket sin SAS?
   - *No viajan credenciales; el consumidor usa su identidad. Si lleva SAS, debe vivir más que los reintentos.*
4. ¿Qué va primero: el blob o el mensaje?
   - *El blob; si no, el consumidor puede recibir un ticket de algo que no existe.*
5. ¿Qué dos variantes producen el ticket?
   - *Dirigida por el backend (valida y publica) y dirigida por eventos (BlobCreated → cola).*
6. ¿Cómo garantizas idempotencia?
   - *`mensajeId` único, detección de duplicados del broker y tabla de procesados con clave única; operaciones repetibles.*
7. ¿Qué haces si el blob no existe al consumir?
   - *Dead-letter con motivo (`BLOB_AUSENTE`), sin reintentos infinitos.*
8. ¿Cómo te proteges de que el blob cambie después del ticket?
   - *`blobVersionId`/`etag` y verificación de `sha256`.*
9. ¿Qué es el `lockDuration` y qué pasa si lo superas?
   - *Tiempo de bloqueo del mensaje; si lo superas, otro consumidor lo recibe: renueva el bloqueo.*
10. ¿Por qué procesar en streaming?
    - *Evita `OutOfMemoryError` y permite archivos de GB con memoria constante.*
11. ¿Cómo evitas huérfanos?
    - *Etiquetas de estado, regla de ciclo de vida, conciliación periódica.*
12. ¿Cuándo no usarías Claim Check?
    - *Mensajes pequeños, atomicidad estricta (outbox) o flujos continuos de registros pequeños.*
13. ¿Qué roles necesita cada lado?
    - *Productor: Blob Data Contributor + Service Bus Data Sender. Consumidor: Blob Data Reader + Service Bus Data Receiver.*

## Entrevista
- Diseña el procesamiento de 10 000 archivos de 500 MB al día, con antivirus, validación y reproceso.
- ¿Cómo reprocesas una DLQ con 5 000 mensajes?
- ¿Cómo mantienes consistencia entre un blob y su mensaje sin transacción?
- Explica cómo harías el mismo patrón con Event Hubs/Kafka.

## Ejercicio práctico
1. Despliega el Terraform de [ejemplos](ejemplos/terraform/main.tf).
2. Sube un blob y comprueba que llega el ticket a la cola.
3. Implementa el consumidor de [uso en Java](uso-en-java.md) con verificación de hash y *dead-letter*.
4. Borra el blob antes de consumir y comprueba la DLQ con `BLOB_AUSENTE`.
5. Envía el mismo ticket dos veces y comprueba que se procesa una sola.
