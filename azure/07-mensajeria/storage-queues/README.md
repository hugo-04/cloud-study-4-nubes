# Azure · Mensajería · Storage Queues (cola simple y barata)

## 1. Qué es

**Azure Queue Storage (Storage Queues) es una cola de mensajes simple, muy barata y casi ilimitada que viene dentro de tu cuenta de Storage.** Sirve para dejar "tareas por hacer" en una bandeja y que uno o varios trabajadores las tomen, las procesen y las borren. No tiene tópicos, sesiones, transacciones ni detección de duplicados: a cambio es sencilla, escala muchísimo (cientos de TB en la cuenta) y se paga por operaciones minúsculas.

Analogía: **una bandeja de tareas con tarjetas en una cocina**. Quien toma una tarjeta no la rompe: la **pone boca abajo con un temporizador** ("la estoy haciendo yo"). Si termina, la tira (borra). Si se cae el cocinero y el temporizador vence, la tarjeta vuelve a quedar boca arriba para otro.

```
  PRODUCTORES                       STORAGE ACCOUNT  →  QUEUE "tareas"                      TRABAJADORES (competidores)
  ───────────                       ─────────────────────────────────────                  ──────────────────────────
  API de pedidos ──── PUT mensaje ─►  [m1][m2][m3][m4][m5] ...                 ◄─ GET (hasta 32, visibilityTimeout=60 s) ── Worker A
  Event Grid (eventos de blob) ───►   (visible)                                ◄─ GET ───────────────────────────────────── Worker B
  Function / job ─────────────────►   m2 invisible 60 s (la tiene el Worker A)       ... procesa ... DELETE (messageId + popReceipt)
                                      si el Worker A falla: pasados 60 s m2 vuelve a ser visible (dequeueCount = 2)
                                      si dequeueCount > 5 ──► se mueve a la cola "tareas-poison" (la haces tú)
```

---

## 2. Cómo funciona por dentro

### 2.1 Jerarquía
**Cuenta de Storage** → **cola** (`https://<cuenta>.queue.core.windows.net/<cola>`) → **mensajes**. Los nombres de cola son en minúsculas, 3 a 63 caracteres, con guiones.

### 2.2 El ciclo de vida de un mensaje

| Paso | Operación | Qué pasa |
|---|---|---|
| 1 | **Put** (enviar) | Se agrega con TTL (por defecto 7 días; `-1` = sin vencimiento) y retraso inicial opcional (mensaje diferido hasta 7 días) |
| 2 | **Get** (recibir) | Devuelve hasta **32** mensajes y los hace **invisibles** durante el *visibility timeout* (por defecto 30 s; hasta 7 días). Aumenta `dequeueCount` y entrega un **popReceipt** |
| 3a | **Delete** | Con `messageId` + `popReceipt` se borra definitivamente = trabajo terminado |
| 3b | **Update** | Con el `popReceipt` puedes **alargar** el tiempo de invisibilidad o cambiar el contenido (útil para trabajos largos o para reintentos con retroceso) |
| 3c | (no hacer nada) | Al vencer el *visibility timeout* el mensaje reaparece: es el **reintento automático** |
| — | **Peek** | Mira hasta 32 mensajes sin hacerlos invisibles ni contarlos |
| — | **Clear** | Vacía la cola |

Cada `Get` devuelve un `popReceipt` **nuevo**: quien intenta borrar con uno viejo (porque otro trabajador lo recibió después) falla. Es la protección contra borrar lo que ya no es tuyo.

### 2.3 Garantías y límites del modelo

| Tema | Comportamiento (verifica límites vigentes) |
|---|---|
| Entrega | **Al menos una vez** |
| Orden | **No garantizado** (suele ser aproximadamente FIFO) |
| Tamaño del mensaje | Hasta **64 KB** (con Base64 el texto útil es menor) |
| TTL | Hasta 7 días o sin vencimiento (`-1`) |
| Visibilidad | 1 segundo a 7 días |
| Recibir por llamada | Hasta 32 |
| Capacidad de la cola | Hasta la capacidad total de la cuenta |
| Rendimiento | Objetivo ≈ 2.000 mensajes por segundo por cola (mensajes de ~1 KB); la cuenta tiene sus límites |
| Cola de mensajes fallidos | **No existe**: se construye (cola `-poison`) |
| Duplicados | No se detectan: idempotencia en el consumidor |
| Sesiones / transacciones / tópicos | **No existen** |
| Codificación | El cuerpo es texto; los clientes suelen usar **Base64** (las Functions esperan una codificación concreta: verifica `messageEncoding`) |

### 2.4 El `dequeueCount` y los mensajes venenosos
Cada vez que un mensaje se recibe, su `dequeueCount` sube. Si supera un umbral (5, por ejemplo), es un **mensaje venenoso**: lo copias a una cola `<nombre>-poison` con el motivo y lo borras de la principal. Las **Azure Functions** con disparador de cola hacen esto solas (tras 5 intentos lo mueven a `<cola>-poison`).

### 2.5 Reintentos con retroceso (backoff)
Cuando el trabajo falla, en lugar de dejar que reaparezca a los 30 s, usa `Update` para fijar una invisibilidad creciente: 10 s, 20 s, 40 s… (según `dequeueCount`). Evita martillar a un servicio caído.

### 2.6 Mensajes diferidos y programados
Un `Put` con `visibilityTimeout` inicial retrasa la primera visibilidad hasta 7 días. Es el "avísame en 2 horas" más barato de Azure.

### 2.7 Quién entrega a Storage Queues
- Tu código (SDK).
- **Event Grid** (por ejemplo, eventos de Blob → cola) con identidad *Storage Queue Data Message Sender*.
- **Azure Functions** (salida a cola y disparador de cola).
- Logic Apps y otras integraciones.

### 2.8 Storage Queues frente a Service Bus

| Pregunta | Storage Queue | Service Bus |
|---|---|---|
| Complejidad | Mínima | Alta (más funciones) |
| Costo | Muy bajo | Mayor |
| Tamaño de mensaje | 64 KB | 256 KB (Standard) / 100 MB (Premium) |
| Orden | No | Sesiones (FIFO) |
| DLQ | Manual (`-poison`) | Nativa |
| Duplicados | No | Detección |
| Tópicos/suscripciones | No | Sí |
| Transacciones | No | Sí |
| Rendimiento por cola | Alto, sencillo | Alto, con límites distintos |
| Ideal | Trabajos simples, colas de tareas, buffers | Comandos de negocio entre microservicios |

Regla práctica: **empieza con Storage Queue si lo que necesitas es "una lista de tareas por hacer"; pasa a Service Bus cuando necesites DLQ nativa, orden, duplicados o tópicos.**

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Trabajos en segundo plano:** generar miniaturas, enviar correos, convertir archivos.
- **Absorber picos:** el sitio recibe 5.000 pedidos en un minuto; la cola los reparte a un ritmo sostenible.
- **Competir por trabajo:** N trabajadores toman tareas de la misma cola (escalado horizontal).
- **Disparar Functions** con el disparador de cola.
- **Recibir eventos de Blob** baratos (Event Grid → cola).
- **Claim Check:** el mensaje lleva la URL o clave del blob con la carga real ([Claim Check](../../06-storage/claim-check/README.md)).

| NO lo uses si | Alternativa |
|---|---|
| Necesitas DLQ nativa, orden, duplicados, tópicos, transacciones | **Service Bus** |
| Necesitas flujo masivo reproducible | **Event Hubs** |
| Necesitas reaccionar a eventos de Azure con filtros ricos | **Event Grid** |
| Mensajes mayores de 64 KB | Claim Check o Service Bus |
| Necesitas prioridad entre mensajes | Varias colas (alta/normal) |
| Necesitas latencia garantizada muy baja | Servicio con *push* (Service Bus con procesador) |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Cola** | Lista de mensajes dentro de una cuenta de Storage | `tareas` |
| **Mensaje** | Texto de hasta 64 KB con TTL | `{"pedidoId":"1001"}` |
| **Visibility timeout** | Tiempo en que un mensaje recibido queda invisible | 60 s |
| **popReceipt** | "Recibo" que prueba que tú lo recibiste; permite borrar/actualizar | Cambia en cada `Get` |
| **dequeueCount** | Veces que se ha recibido | 3 |
| **TTL** | Tiempo de vida del mensaje | 7 días |
| **Cola de veneno** | Cola `-poison` con los mensajes que siempre fallan | `tareas-poison` |
| **Competing consumers** | Varios trabajadores que toman de la misma cola | 5 réplicas |
| **Base64** | Codificación habitual del cuerpo | Evita problemas con caracteres |
| **Idempotencia** | Procesar dos veces = efecto de una | Clave `pedidoId` |

---

## 5. Cómo se usa

1. **Crea la cuenta de Storage** (sin claves, solo Entra ID) y la cola `tareas` y `tareas-poison`.
2. **Define el mensaje:** pequeño, con ids y una versión (`{"v":1,"pedidoId":"1001"}`); cargas grandes en Blob.
3. **Productor:** `sendMessage` con TTL adecuado (no infinito sin motivo).
4. **Trabajador:** `receiveMessages(32, visibilidad)` → procesa → `deleteMessage`.
5. **Fallos:** `updateMessage` con retroceso; si `dequeueCount` > umbral → `-poison`.
6. **Trabajos largos:** renovar la invisibilidad con `updateMessage` antes de que venza.
7. **Idempotencia:** clave única por tarea en la base de datos.
8. **Escalado:** más réplicas del trabajador según el largo de la cola (KEDA `azure-queue` scaler).
9. **Observa:** `QueueMessageCount`, latencia, errores; alerta en la cola de veneno.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/storage-queues.sh) · [KQL](ejemplos/kql/kql-storage-queues.md).

---

## 6. Seguridad

- **Entra ID, sin claves:** `shared_access_key_enabled = false` en la cuenta; roles de datos de cola.
- **Mínimo privilegio:** el productor solo *enviar*; el trabajador solo *procesar mensajes* (recibir/borrar/actualizar).
- **Red:** Private Endpoint (subrecurso `queue`, zona `privatelink.queue.core.windows.net`) y reglas de red de la cuenta.
- **Cifrado:** en reposo (claves de Microsoft o gestionadas por ti) y TLS 1.2 en tránsito.
- **Datos:** no pongas datos personales ni secretos en el mensaje; ids y referencias.
- **SAS de cola** (si alguna vez hace falta delegación): de corta vida y con permisos mínimos, mejor con delegación de usuario.
- **Auditoría:** diagnóstico de la cola a Log Analytics (`StorageQueueLogs`).

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Productor | Enviar mensajes | *Storage Queue Data Message Sender* (en la cola) |
| Trabajador | Recibir, borrar y actualizar mensajes | *Storage Queue Data Message Processor* (en la cola) |
| Herramienta de soporte | Ver mensajes y metadatos | *Storage Queue Data Reader* |
| Operaciones | Crear colas, vaciar, ver todo | *Storage Queue Data Contributor* |
| Event Grid (identidad del tópico) → cola | Entregar eventos | *Storage Queue Data Message Sender* |
| Azure Functions (disparador de cola) | Leer y borrar | *Storage Queue Data Contributor* en la cuenta del trigger (según el caso) |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Mensajes **pequeños** con ids y versión; Claim Check para lo grande.
- **Idempotencia** en el trabajador.
- **Visibility timeout** mayor que el tiempo máximo de procesamiento, o renovarlo.
- **Cola de veneno** con alerta y revisión manual.
- Retroceso exponencial vía `updateMessage`.
- TTL razonable.
- Identidad administrada y roles por cola.
- Escalar los trabajadores según el largo de la cola.

**Qué NO hacer**
- Esperar orden FIFO estricto.
- Usarla como bus de eventos con múltiples suscriptores (cada mensaje lo toma **uno**).
- Borrar un mensaje antes de terminar el trabajo.
- Dejar que reintente para siempre sin límite de `dequeueCount`.
- Poner datos sensibles o cargas grandes en el cuerpo.
- Sondear con `receive` cada milisegundo sin espera (cuesta y no sirve): pausa cuando está vacía.
- Compartir la clave de la cuenta con todos.
- Mezclar tareas de prioridad distinta en la misma cola.

---

## 8. Límites, costos y versiones
- Costo: por **operaciones** (cada put/get/delete cuenta) y capacidad; suele ser la opción de mensajería más barata de Azure. *Verifica precios vigentes.*
- Límites: 64 KB por mensaje, 7 días de TTL (o infinito), 32 mensajes por `Get`, rendimiento por cola y por cuenta. *Verifica la tabla vigente.*
- SDK: `azure-storage-queue` con el BOM 1.3.x de este repositorio.
- Las **Azure Functions** y las codificaciones Base64 tienen reglas propias: confirma `messageEncoding` en tu versión.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
