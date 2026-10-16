# Azure · Eventos de Blob · Repaso

## Preguntas de repaso
1. ¿Qué publica Azure Storage hacia Event Grid?
   - *Eventos como `BlobCreated` o `BlobDeleted` con la ruta, el tamaño, el ETag y la URL; no el contenido.*
2. ¿Qué es un tópico del sistema y cuántos puede haber por cuenta?
   - *La representación de la cuenta como fuente de eventos; uno por cuenta y tipo de tópico.*
3. ¿Qué es una suscripción de eventos?
   - *Una regla: qué eventos (filtros) y a dónde (destino), con reintentos y dead-letter.*
4. ¿Qué garantía de entrega ofrece Event Grid?
   - *Al menos una vez, sin orden garantizado.*
5. ¿Cómo manejas duplicados y desorden?
   - *Idempotencia por `id` del evento; `sequencer` por blob para descartar los más viejos.*
6. ¿Cuándo se emite `BlobCreated` en una subida por bloques?
   - *Al confirmar la lista de bloques (`PutBlockList`), no por cada bloque.*
7. ¿Qué es el handshake del webhook?
   - *Validación al crear la suscripción: respondes el `validationCode` (Event Grid schema) o los encabezados de origen (CloudEvents).*
8. ¿Por qué entregar con identidad administrada?
   - *Sin llaves ni cadenas de conexión; el rol se da a la identidad del tópico.*
9. ¿Qué pasa con los eventos que no se pueden entregar?
   - *Tras agotar intentos o tiempo se descartan, salvo que configures dead-letter en un contenedor.*
10. ¿Cómo evitas el bucle infinito?
    - *Contenedor/prefijo de salida distinto del de entrada y filtros por *subject*.*
11. ¿Cómo lees justo lo anunciado?
    - *Descargando con `If-Match: <eTag del evento>`; 412 significa que ya cambió.*
12. ¿Cuándo prefieres change feed?
    - *Cuando necesitas un registro ordenado y durable (auditoría, replicación, reconstrucción).*
13. ¿Qué rol necesita quien crea una suscripción?
    - *`Microsoft.EventGrid/eventSubscriptions/write`, p. ej. *EventGrid EventSubscription Contributor*.*

## Entrevista
- Diseña el procesamiento de archivos de 50 socios con picos de 100 000 por hora y antivirus.
- ¿Cómo garantizas que un blob sobrescrito dos veces deja el resultado de la última versión?
- ¿Eventos o change feed para sincronizar un buscador? Justifica.
- ¿Cómo depuras que "no llegan eventos"?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf).
2. Sube un archivo bajo `entrada/` y observa el mensaje en la cola.
3. Sube a otro prefijo y comprueba que *Matched Events* no cambia.
4. Quita el rol *Data Sender* y mira *Delivery Failed* y el dead-letter; restáuralo y reprocesa.
5. Procesa el evento con [Java](uso-en-java.md) leyendo con `If-Match`.
