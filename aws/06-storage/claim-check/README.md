# AWS · Storage · Patrón Claim Check (enviar la referencia, no el archivo)

## 1. Qué es

**Claim Check («ticket de guardarropa») es un patrón de integración: el dato grande se guarda en un almacén (S3) y por la cola, el tópico o el stream viaja solo un mensaje pequeño con la referencia (el «ticket»).** Quien procesa lee el mensaje, usa la referencia para traer el dato y lo procesa.

**Analogía:** el **guardarropa de un teatro**. Dejas el abrigo (un PDF de 80 MB) y recibes un número (un mensaje de 1 KB). Por el pasillo circula el número, no el abrigo.

```
┌──────────┐ 1. pide permiso      ┌─────────┐
│ Cliente  │ ───────────────────► │ Backend │
│ web/móvil│ ◄─────────────────── │  (API)  │
└────┬─────┘ 2. URL prefirmada    └────┬────┘
     │ 3. sube DIRECTO                  │
     ▼                                  │
┌──────────────────┐                    │
│  S3 (versionado) │                    │
└────────┬─────────┘                    │
         │ 4a. evento ObjectCreated     │ 4b. confirmación + ticket explícito
         ▼                              ▼
┌───────────────────────────────────────────────────────┐
│ SQS / SNS / EventBridge / Kinesis / Kafka:            │
│ { bucket, clave, versionId, tamaño, sha256, tipo,     │  ← el «ticket» (KB)
│   correlación, creado }                               │
└────────────────────────┬──────────────────────────────┘
                         │ 5. el consumidor recibe el ticket
                         ▼
                 ┌──────────────┐ 6. descarga con SU rol (versionId),
                 │ Procesador   │    verifica sha256, procesa,
                 └──────────────┘    confirma (borra el mensaje)
```

## 2. Cómo funciona por dentro

### 2.1 Por qué existe: los mensajes tienen tope *(verifica los vigentes)*

| Servicio | Tamaño máximo orientativo |
|---|---|
| SQS | hasta 1 MiB (antes 256 KiB) |
| SNS | hasta 1 MiB (antes 256 KiB) |
| EventBridge | hasta 1 MiB (antes 256 KiB) |
| Kinesis Data Streams | ~1 MiB por registro (ampliable según modo; verifica) |
| Kafka en MSK | 1 MB por defecto (`max.message.bytes`, configurable) |

Un PDF de 80 MB, un video o un catálogo de 2 GB **no caben**; y aunque quepan, mover megabytes por el broker es caro, lento y llena sus memorias. Regla práctica: **si el cuerpo puede pasar de ~100–200 KB, usa Claim Check**.

### 2.2 Las piezas

| Pieza | Papel |
|---|---|
| **Almacén (S3 con versionado)** | Guarda el dato; `versionId` identifica *exactamente* qué versión es |
| **Productor** | Sube (o autoriza subir), calcula el SHA-256, y **después** publica el ticket |
| **Ticket** | Referencia + garantías (versión, tamaño, hash, tipo, correlación) |
| **Cola/tópico** | Entrega confiable: reintentos, visibilidad, *dead-letter* |
| **Consumidor** | Valida el ticket, descarga **con su propio rol**, verifica el hash, procesa, confirma |
| **Idempotencia** | El mismo ticket puede llegar dos veces; el resultado debe ser igual |
| **Limpieza** | Ciclo de vida del objeto y de los huérfanos |

### 2.3 Dos variantes

| Variante | Quién crea el ticket | Cuándo |
|---|---|---|
| **A. Evento de S3** | S3 (notificación `ObjectCreated` a SQS/EventBridge) | Subida directa del navegador; no hay backend en medio del camino |
| **B. Ticket explícito** | Tu productor tras subir | Necesitas hash, correlación, tipo de negocio u orden; o el productor es un servicio |

La variante A es la más simple ([eventos de S3](../eventos-s3/README.md)); la B da garantías más fuertes (hash conocido de antemano, esquema propio). Se combinan: A para detectar, y el consumidor valida contra el hash que el backend registró al emitir la URL.

### 2.4 El orden importa
1. **Subir primero, publicar después.** Publicar un ticket cuyo objeto aún no existe produce errores intermitentes.
2. Si falla la publicación, queda un **objeto huérfano**: lo limpia el ciclo de vida; el productor reintenta con una clave nueva.
3. El consumidor **borra el mensaje solo al terminar**. Si falla, el mensaje reaparece tras el *visibility timeout* y, tras N intentos, va a la DLQ.
4. El objeto debe **vivir más que la retención de la DLQ**: si no, el ticket de la DLQ apunta a la nada.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| PDF, imágenes, video, lotes CSV, adjuntos | **Claim Check** |
| Varios consumidores necesitan el mismo dato grande | **Claim Check** (cada uno descarga lo que necesita) |
| Cuerpos < ~50 KB | **No**: viaja en el mensaje (menos piezas, menos fallos) |
| Necesitas atomicidad mensaje + dato | **No**: S3 y la cola no comparten transacción; diseña con idempotencia |
| El dato cambia después de publicar | Usa `versionId` + hash (si no, procesas algo distinto a lo anunciado) |
| El dato es secreto | Claim Check con S3 cifrado + roles mínimos; nunca URLs prefirmadas dentro del ticket |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Ticket** | Mensaje pequeño con la referencia al dato |
| **Productor / consumidor** | Quien sube y publica / quien recibe y procesa |
| **`versionId`** | Identifica la versión exacta del objeto |
| **SHA-256** | Huella para comprobar que el dato no cambió |
| **Idempotencia** | Procesar dos veces = mismo resultado |
| **Visibility timeout** | Tiempo en que el mensaje está «reservado» para un consumidor |
| **DLQ** | Cola de mensajes que fallaron demasiadas veces |
| **Huérfano** | Objeto sin ticket (o ticket sin objeto) |

## 5. Cómo se usa
1. Bucket versionado + cola + DLQ + permisos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Ticket de ejemplo: [`ejemplos/mensajes/ticket.json`](ejemplos/mensajes/ticket.json).
3. Productor: sube con `checksum SHA-256`, publica el ticket. Consumidor: valida, descarga con `versionId`, verifica, procesa, confirma ([uso en Java](uso-en-java.md)).
4. Prueba con la CLI: [`ejemplos/cli/claim-check.sh`](ejemplos/cli/claim-check.sh).
5. Subida desde el navegador: [URLs prefirmadas](../urls-prefirmadas/README.md).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Productor** | — | `s3:PutObject` en el prefijo; `sqs:SendMessage` a la cola |
| **Consumidor** | — | `sqs:ReceiveMessage`/`DeleteMessage`; `s3:GetObject` (y `GetObjectVersion`) **solo del prefijo esperado** |
| **Pipeline** | Crear bucket, cola, políticas | — |

- **Confused deputy:** un productor malicioso podría anunciar `bucket/otro-tenant/secreto.pdf`. El consumidor **valida bucket y prefijo permitidos** antes de descargar y su rol solo alcanza ese prefijo.
- **Nunca pongas credenciales ni URLs prefirmadas en el ticket** (caducan, se filtran por logs/DLQ).
- **Cifra** el bucket (SSE-KMS) y la cola (SSE) y exige TLS.
- **Valida el contenido** (tipo real, tamaño, antivirus) antes de usarlo.
- **No registres el contenido** del dato; registra `correlacion`, clave y tamaño.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Subir primero y publicar después | Publicar antes de que exista el objeto |
| Versionado + `versionId` + SHA-256 en el ticket | Referenciar solo por clave |
| Consumidor idempotente | Asumir entrega exactamente una vez |
| Validar bucket/prefijo/tamaño del ticket | Confiar en lo que dice el mensaje |
| DLQ con alarma y objeto con retención mayor | Dejar fallar en silencio |
| Rol del consumidor con prefijo mínimo | `s3:*` sobre todo el bucket |
| Ciclo de vida para huérfanos | Acumular objetos «por si acaso» |
| Procesar en streaming / archivo temporal | Cargar el archivo completo en memoria |

## 8. Límites, costos y versiones
- **Costo:** S3 (almacenamiento + solicitudes + transferencia) + mensajes. Descargar desde la misma región no cobra transferencia. Cada consumidor adicional descarga el dato otra vez.
- **Biblioteca oficial:** existe el *Amazon SQS Extended Client Library for Java* que aplica este patrón con S3 de forma transparente *(verifica la versión para SDK v2)*; aquí se implementa a mano para controlar hash, versión e idempotencia.
- **Tiempos:** el *visibility timeout* debe superar el tiempo máximo de procesamiento (o usar `ChangeMessageVisibility`).
- **Terraform:** validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
