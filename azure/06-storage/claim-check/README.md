# Azure · Storage · Patrón Claim Check (enviar la referencia, no el archivo)

## 1. Qué es

**Claim Check ("ticket de guardarropa") es un patrón de integración: el dato grande se guarda en un almacén (Blob Storage) y por la cola/tópico/stream viaja solo un mensaje pequeño con la referencia (el "ticket")**. Quien procesa lee el mensaje, usa la referencia para recuperar el dato y lo procesa.

Analogía: **el guardarropa de un teatro**. Dejas el abrigo (archivo de 2 GB) y recibes un número (mensaje de 1 KB). Por el pasillo circula el número, no el abrigo.

```
┌──────────┐ 1. pide permiso de subida ┌─────────┐
│ Cliente  │ ─────────────────────────►│ Backend │
│ (web/app)│ ◄──────────────────────── │  (API)  │
└────┬─────┘ 2. URL temporal (SAS)     └────┬────┘
     │ 3. sube el archivo DIRECTO           │
     ▼                                      │
┌──────────────────┐                        │
│ Blob Storage     │                        │
└────────┬─────────┘                        │
         │ 4a. evento BlobCreated           │ 4b. el cliente avisa y la API valida
         ▼                                  ▼
┌───────────────────────────────────────────────────┐
│ COLA / TÓPICO:  { id, blobUrl, versión, tamaño,   │  ← el "ticket" (KB)
│                   hash, tipo, creadoEn }          │
└────────────────────────┬──────────────────────────┘
                         │ 5. el consumidor recibe el ticket
                         ▼
                 ┌──────────────┐  6. descarga el blob con su identidad
                 │ Procesador   │ ─── (streaming), verifica el hash,
                 └──────────────┘     procesa y completa el mensaje
```

---

## 2. Cómo funciona por dentro

### 2.1 Por qué existe: límites de mensaje (verifica los vigentes)

| Servicio | Tamaño máximo de mensaje (orientativo) |
|---|---|
| Storage Queues | 64 KB |
| Service Bus **Standard** | 256 KB |
| Service Bus **Premium** | hasta ~100 MB |
| Event Hubs | ~1 MB por evento (según tier) |
| Event Grid | ~1 MB por evento |
| Kafka (propio o Event Hubs-Kafka) | 1 MB por defecto (`max.message.bytes`) |

Un PDF de 40 MB, un video o un catálogo de 2 GB **no caben**, y aunque cupieran (Premium), mover MB por el broker es caro y lento.

### 2.2 Las piezas

| Pieza | Papel |
|---|---|
| **Almacén** (Blob) | Guarda el dato grande, con su ciclo de vida y su cifrado |
| **Productor** | Sube (o autoriza subir) y publica el ticket |
| **Mensaje-ticket** | Metadatos + referencia + garantías (hash, versión) |
| **Cola/tópico** | Entrega confiable: reintentos, *dead-letter*, duplicados |
| **Consumidor** | Recupera el blob con **su** identidad, verifica, procesa, confirma |
| **Idempotencia** | El mismo ticket puede llegar dos veces; el resultado debe ser el mismo |
| **Limpieza** | Borrado/archivo del blob y de huérfanos |

### 2.3 Dos variantes para producir el ticket

| Variante | Cómo | Cuándo |
|---|---|---|
| **A. Dirigida por el backend** | El cliente sube con SAS y avisa a la API; la API valida y **publica** el ticket | Quieres validar antes de encolar (tamaño, tipo, propietario) |
| **B. Dirigida por eventos** | El storage emite `BlobCreated` (Event Grid) y se enruta a la cola | Quieres desacople total y subidas desde cualquier origen |
| **C. Servicio a servicio** | El productor (otro microservicio) escribe el blob con su identidad y publica el ticket | No hay navegador: es tu propio backend |

Variante B se detalla en [Eventos de blob](../eventos-blob/README.md); la subida con SAS en [SAS tokens](../sas-tokens/README.md).

### 2.4 El mensaje (el "ticket")
Un contrato versionado y **pequeño**. Recomendado: formato **CloudEvents** o un JSON propio estable.

```json
{
  "mensajeId": "7f2a2e2e-6a47-4c2b-9d8e-0a7f8a1c1e11",
  "tipo": "archivo.recibido",
  "version": 1,
  "blobUrl": "https://stmodalima01.blob.core.windows.net/subidas/usuarios/u-42/7f2a2e2e",
  "blobVersionId": "2026-10-16T16:02:11.1234567Z",
  "etag": "0x8DBD0A1B2C3D4E5",
  "tamanoBytes": 4382211,
  "contentType": "application/pdf",
  "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "propietario": "u-42",
  "correlacionId": "c1e0b3a2-…",
  "creadoEn": "2026-10-16T16:02:11Z"
}
```
Esquema y ejemplo en [ejemplos/mensajes](ejemplos/mensajes/).

### 2.5 Detalles que importan (donde se rompe en la vida real)

| Tema | Regla |
|---|---|
| **Sin credenciales en el mensaje** | Lleva la **URL sin SAS**; el consumidor usa su **identidad administrada** con *Storage Blob Data Reader*. Así no viajan secretos por la cola |
| **Si incluyes una SAS** | Trata el mensaje como secreto; su vencimiento debe superar **TTL de la cola + reintentos**, o el reintento fallará con 403 |
| **Integridad** | `sha256` y `tamanoBytes`: el consumidor los verifica **después** de leer |
| **Inmutabilidad de lo referenciado** | Incluye `blobVersionId` (versionado activado) o `etag` para leer **exactamente** lo que se anunció, aunque alguien sobrescriba el blob |
| **Orden de escritura** | **Primero el blob, después el mensaje.** Si el blob falla, no hay ticket. Si el mensaje falla, queda un huérfano que limpia el ciclo de vida |
| **Atomicidad blob+mensaje** | No hay transacción entre ambos: diseña para *al menos una vez* + idempotencia + limpieza de huérfanos |
| **Idempotencia** | `mensajeId` único; Service Bus **detección de duplicados** (ventana) y/o tabla de procesados con clave única |
| **Blob inexistente** | 404 → *dead-letter* con motivo (`BLOB_AUSENTE`), no reintentar infinito |
| **Mensaje venenoso** | `maxDeliveryCount` finito → DLQ; alerta por tamaño de la DLQ |
| **Bloqueo de mensaje** | Si procesar dura más que el `lockDuration`, renueva el bloqueo (o la entrega se duplica) |
| **Archivos enormes** | *Streaming* (nunca en memoria), por trozos o por rangos; paraleliza por bloques si el formato lo permite |
| **Privacidad** | Los datos personales viven en el blob (cifrado, retención controlada), no en el mensaje ni en logs |
| **Limpieza** | Borrar o archivar el blob al terminar; etiqueta de estado + regla de ciclo de vida |
| **Observabilidad** | Propaga `correlacionId`; mide edad del mensaje más antiguo, DLQ, tamaño de blobs, duración de proceso |

### 2.6 Elección del transporte del ticket

| Necesidad | Servicio |
|---|---|
| Comandos/trabajos con reintentos, DLQ, sesiones, duplicados | **Service Bus** (cola) |
| Un ticket a varios consumidores | **Service Bus** (tópico + suscripciones) |
| Volumen altísimo, streaming, reprocesar el histórico | **Event Hubs** / Kafka ([Event Hubs-Kafka](../../07-mensajeria/event-hubs-kafka/README.md)) |
| Reaccionar a "algo pasó" (notificación) | **Event Grid** |
| Cola muy simple y barata | Storage Queue (64 KB) |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Archivos grandes (PDF, imágenes, video, CSV de millones de filas, catálogos, respaldos) que deben procesarse de forma asíncrona.
- Mensajes con cargas variables que a veces superan el límite del broker.
- Desacoplar la **subida** (rápida, directa) del **procesamiento** (lento, escalable).
- Fan-out: varios consumidores procesan el mismo archivo sin copiarlo por el broker.
- Reducir costo y latencia del broker.

| NO lo uses si | Alternativa |
|---|---|
| El mensaje cabe cómodamente (< decenas de KB) | Envía el dato en el mensaje |
| Necesitas atomicidad estricta entre dato y evento | Patrón *Transactional Outbox* con el dato en la misma BD |
| El dato es un flujo continuo en tiempo real | Event Hubs / Kafka con registros pequeños |
| El procesamiento es síncrono y el usuario espera | Llamada directa (con límites) |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Claim Check** | Guardar el dato y enviar una referencia | Ticket de guardarropa |
| **Ticket** | El mensaje con la referencia | JSON de 1 KB |
| **Dead-letter queue (DLQ)** | Cola de mensajes que no se pudieron procesar | `BLOB_AUSENTE` |
| **Idempotencia** | Procesar dos veces = procesar una | Clave única de proceso |
| **Duplicate detection** | El broker descarta mensajes con el mismo `MessageId` en una ventana | 10 min |
| **At-least-once** | Se entrega una o más veces | Reintentos |
| **Lock duration** | Tiempo que el mensaje está "bloqueado" para un consumidor | 5 min |
| **Huérfano** | Blob sin ticket (o ticket sin blob) | Falló el envío |
| **Versión de blob** | Identifica una versión inmutable | `versionId` |
| **Outbox** | Patrón para publicar eventos con atomicidad desde la BD | Tabla de salida |

---

## 5. Cómo se usa

1. **Almacén:** cuenta de Blob con versionado, soft delete y ciclo de vida ([Blob](../blob-storage/README.md)).
2. **Canal:** cola de Service Bus con duplicados, `maxDeliveryCount` y DLQ ([Service Bus](../../07-mensajeria/service-bus/README.md)).
3. **Subida:** SAS de escritura emitida por la API ([SAS](../sas-tokens/README.md)).
4. **Ticket:** variante A (API) o B (evento).
5. **Consumidor:** recibe, descarga **en streaming** con su identidad, verifica hash, procesa, etiqueta el blob (`estado=procesado`), completa el mensaje.
6. **Errores:** abandona (reintento), *dead-letter* (irrecuperable) y alertas.
7. **Limpieza:** regla de ciclo de vida sobre `estado=procesado`.

Archivos: [Terraform completo (Blob + Event Grid + Service Bus + roles)](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/claim-check.sh) · [mensajes](ejemplos/mensajes/).

---

## 6. Seguridad
- **Identidades administradas** en productor y consumidor (sin claves de storage ni cadenas de conexión de Service Bus: `local_auth_enabled=false`).
- **Mínimo privilegio:** productor = *Storage Blob Data Contributor* (solo su contenedor) + *Azure Service Bus Data Sender*; consumidor = *Storage Blob Data Reader* (+ *Contributor* si etiqueta/borra) + *Azure Service Bus Data Receiver*.
- **Nada sensible en el mensaje**; si hay SAS, mensaje = secreto.
- **Verifica integridad** (hash) y **propiedad** (el `propietario` del ticket coincide con la ruta del blob).
- **Analiza** el archivo (antivirus, tipo real) antes de procesar.
- **Redes privadas:** Private Endpoint de Blob y de Service Bus; consumidores dentro de la VNet.
- **Cifrado** en reposo (CMK si aplica) y TLS.
- **Retención** mínima del blob y del mensaje; borra al terminar.

### IAM de este patrón

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| API / productor | Escribir el blob (si lo hace él) y publicar | *Storage Blob Data Contributor* (contenedor) + *Azure Service Bus Data Sender* (cola) |
| API que emite SAS | Delegación | *Storage Blob Delegator* (cuenta) + rol de datos |
| Event Grid (variante B) | Entregar a la cola con su identidad | *Azure Service Bus Data Sender* para la identidad del tópico del sistema |
| Consumidor | Recibir y leer el blob | *Azure Service Bus Data Receiver* + *Storage Blob Data Reader* |
| Consumidor que marca estado | Escribir etiquetas | *Storage Blob Data Contributor* (o *Tag Owner* personalizado) |
| Operaciones | Ver DLQ | *Azure Service Bus Data Receiver* (solo DLQ) o lectura de métricas |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Subir el blob **antes** de publicar el ticket.
- Mensaje con `mensajeId` estable, `blobVersionId`/`etag`, `sha256` y `tamanoBytes`.
- Consumidor **idempotente** (clave única + estado en el blob).
- Streaming y verificación de hash.
- `maxDeliveryCount` razonable (5–10), DLQ monitorizada y reprocesable.
- Renovar el bloqueo en procesos largos.
- Etiquetar el blob (`estado`) y limpiar con ciclo de vida.
- Medir edad del mensaje más antiguo y tamaño de la DLQ.

**Qué NO hacer**
- Mandar el archivo (o su base64) dentro del mensaje.
- Incluir SAS de vencimiento corto en un mensaje con reintentos largos.
- Asumir que el blob sigue igual que cuando se envió el ticket (usa versión o hash).
- Reintentar para siempre un blob inexistente.
- Leer todo el archivo en memoria.
- Poner datos personales en el ticket o en los logs.
- Dejar blobs huérfanos para siempre.
- Procesar un archivo sin analizar solo porque "la subida salió bien".

---

## 8. Límites, costos y versiones
- Costos: almacenamiento del blob, operaciones de lectura/escritura, **mensajes** del broker, salida de datos.
- Límites del broker (tamaño de mensaje, entregas, retención, bloqueo): *verifica según tier*.
- Service Bus Premium aumenta el tamaño de mensaje pero no sustituye al patrón para archivos de cientos de MB.
- Event Grid ofrece entrega **al menos una vez** y reintentos limitados: diseña el consumidor idempotente.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
