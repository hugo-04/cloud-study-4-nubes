# Azure · Storage · Eventos de Blob (Event Grid)

## 1. Qué es

**Los eventos de Blob son avisos automáticos ("se creó este archivo", "se borró aquel") que Azure Storage publica a Event Grid cada vez que ocurre algo en una cuenta de almacenamiento.** Tú decides quién se entera (una cola, una Function, tu API) y de qué cosas, sin escribir código de sondeo.

Analogía: **el timbre de la puerta**. Antes tenías que asomarte cada minuto a ver si había llegado alguien (sondeo); ahora el portero (Event Grid) toca el timbre y avisa solo a las personas que pediste (las suscripciones), con una nota que dice quién llegó y a qué puerta, pero **sin entregar el paquete** (el contenido sigue en el blob).

```
 Cliente / servicio                      Azure Storage                Event Grid                      Destinos (handlers)
 ──────────────────                      ─────────────                ──────────                      ───────────────────
 PUT blob (PutBlockList)  ────────────►  Cuenta stmodalima01  ──►  TÓPICO DEL SISTEMA  ──┬─ filtro A ─►  Service Bus (cola)
                                         (publicador de eventos)    (uno por cuenta)     ├─ filtro B ─►  Storage Queue
                                                                                         ├─ filtro C ─►  Azure Function
                                                                                         ├─ filtro D ─►  Webhook (tu API)
                                                                                         └─ filtro E ─►  Event Hubs
                                                                                              │
                                                                                              └─ si falla mucho ─► contenedor "deadletter"
```

---

## 2. Cómo funciona por dentro

### 2.1 Las piezas

| Pieza | Qué es | Detalle práctico |
|---|---|---|
| **Fuente (publicador)** | La cuenta de almacenamiento | Publica sola; no instalas nada |
| **Tópico del sistema** (*system topic*) | Representa a la fuente dentro de Event Grid | **Uno por cuenta** para el tipo de tópico de Storage. Se crea explícitamente en IaC |
| **Suscripción de eventos** (*event subscription*) | "Quiero estos eventos, con este filtro, entregados allí" | Puedes tener varias por tópico, cada una con su destino, filtro y reintentos |
| **Destino** (*handler*) | Quien recibe | Service Bus (cola/tópico), Storage Queue, Event Hubs, Azure Functions, Webhook, Hybrid Connections |
| **Filtros** | Reducen el ruido | Tipo de evento, prefijo/sufijo del *subject*, filtros avanzados sobre `data.*` |
| **Identidad de entrega** | Con quién se presenta Event Grid al destino | Identidad administrada del tópico (sin secretos) |
| **Dead-letter** | Dónde caen los eventos que no se pudieron entregar | Contenedor de blobs (hay que configurarlo) |

### 2.2 Tipos de evento de Blob (verifica la lista vigente en la doc)

| Evento | Cuándo se emite | Nota |
|---|---|---|
| `Microsoft.Storage.BlobCreated` | Se crea o reemplaza un blob | Se emite **al completar** la subida (`PutBlob`, `PutBlockList`, `CopyBlob`); un archivo subido en 200 bloques da **un** evento al confirmar la lista de bloques, no 200 |
| `Microsoft.Storage.BlobDeleted` | Se borra un blob | Con *soft delete* el evento sale al borrar, aunque el contenido siga recuperable |
| `Microsoft.Storage.BlobRenamed` | Se renombra (solo con espacio de nombres jerárquico) | Data Lake Gen2 |
| `Microsoft.Storage.DirectoryCreated / Renamed / Deleted` | Operaciones sobre directorios (solo con jerárquico) | Data Lake Gen2 |
| `Microsoft.Storage.BlobTierChanged` | Cambia el nivel (Hot, Cool, Cold, Archive) | Útil para auditar la política de ciclo de vida |
| `Microsoft.Storage.AsyncOperationInitiated` | Empieza una operación diferida (p. ej. rehidratar desde Archive o copiar) | Aviso de inicio, no de fin |
| `Microsoft.Storage.BlobInventoryPolicyCompleted` | Terminó un inventario | Para disparar análisis |
| `Microsoft.Storage.LifecyclePolicyCompleted` | Terminó una pasada de la política de ciclo de vida | Para auditoría |

El campo `data.api` indica qué operación lo causó: `PutBlob`, `PutBlockList`, `CopyBlob`, `FlushWithClose` (Data Lake Gen2), `SftpCreate`/`SftpCommit` (SFTP)…

### 2.3 Forma de un evento (esquema de Event Grid)

```json
{
  "topic": "/subscriptions/<sub>/resourceGroups/rg-estudio-storage/providers/Microsoft.Storage/storageAccounts/stmodalima01",
  "subject": "/blobServices/default/containers/subidas/blobs/usuarios/u-42/7f2a2e2e",
  "eventType": "Microsoft.Storage.BlobCreated",
  "id": "831e1650-001e-001b-66ab-eeb76e069631",
  "eventTime": "2026-10-16T16:02:11.1234567Z",
  "data": {
    "api": "PutBlockList",
    "eTag": "0x8D4BCC2E4835CD0",
    "contentType": "application/pdf",
    "contentLength": 4382211,
    "blobType": "BlockBlob",
    "url": "https://stmodalima01.blob.core.windows.net/subidas/usuarios/u-42/7f2a2e2e",
    "sequencer": "00000000000004420000000000028963"
  }
}
```
Ejemplos completos (Event Grid, CloudEvents y el evento de validación) en [ejemplos/eventos](ejemplos/eventos/).

| Campo | Para qué sirve |
|---|---|
| `id` | Identifica el evento. **Un duplicado trae el mismo `id`**: úsalo para la idempotencia |
| `subject` | Ruta del blob (`/blobServices/default/containers/<contenedor>/blobs/<ruta>`): base de los filtros |
| `data.url` | Dónde está el blob (sin SAS) |
| `data.eTag` | Versión del contenido anunciado: léelo con `If-Match` para recibir **exactamente** eso |
| `data.contentLength` | Tamaño; filtra archivos vacíos o enormes |
| `data.sequencer` | Cadena que **ordena** eventos del mismo blob: el mayor es el más reciente |

**Esquemas de entrega:** *Event Grid schema* (propio) o **CloudEvents v1.0** (estándar abierto; recomendado si hay varios productores/consumidores). El esquema se elige en la suscripción.

### 2.4 Garantías y reintentos

| Tema | Comportamiento |
|---|---|
| Entrega | **Al menos una vez** (puede haber duplicados) |
| Orden | **No garantizado**; usa `sequencer` por blob |
| Éxito | El destino responde 2xx (webhook) o acepta el mensaje (cola) |
| Reintentos | Retroceso exponencial hasta agotar el número de intentos o el tiempo de vida del evento (por defecto del orden de 30 intentos / 24 h, configurable) |
| Dead-letter | Por defecto **no hay**: pasado el límite el evento se descarta. Configura un contenedor de dead-letter |
| Latencia | Normalmente segundos; sin SLA de latencia estricto |
| Tamaño | Hasta 1 MB por evento (se factura por tramos de 64 KB) |

### 2.5 Webhooks: el apretón de manos (*handshake*)
Para evitar que alguien te mande eventos sin permiso, Event Grid **valida** el endpoint al crear la suscripción:
- *Event Grid schema*: envía un evento `SubscriptionValidationEvent` con un `validationCode`; tu endpoint debe responder `{"validationResponse": "<validationCode>"}`.
- *CloudEvents v1.0*: envía un `OPTIONS` con `WebHook-Request-Origin`; respondes con `WebHook-Allowed-Origin` y `WebHook-Allowed-Rate`.

Con destinos nativos (Service Bus, Storage Queue, Event Hubs, Functions) **no hay handshake**: se autoriza por identidad y roles.

### 2.6 Filtros
| Filtro | Ejemplo | Para qué |
|---|---|---|
| Tipos de evento | Solo `BlobCreated` | Ignorar borrados |
| `subject` empieza por | `/blobServices/default/containers/subidas/blobs/usuarios/` | Un contenedor y un prefijo |
| `subject` termina en | `.csv` | Solo ciertas extensiones |
| Avanzado | `data.contentLength` > 0; `data.api` en (`PutBlob`, `PutBlockList`); `data.blobType` = `BlockBlob` | Descartar vacíos, copias, etc. |

El *subject* distingue mayúsculas de minúsculas por defecto. Hay un máximo de filtros avanzados por suscripción (*verifica el límite vigente*).

### 2.7 Eventos vs otras formas de "enterarse" de cambios

| Mecanismo | Modelo | Úsalo cuando |
|---|---|---|
| **Event Grid (este capítulo)** | *Push*, casi en tiempo real, al menos una vez | Reaccionar a blobs: procesar, indexar, escanear, notificar |
| **Change feed** | *Pull*, registro **ordenado y durable** de todos los cambios | Auditoría, replicar a otro sistema, reconstruir estado, nada puede perderse |
| **Disparador Blob de Functions (sondeo)** | La Function escanea el contenedor | Cuentas pequeñas; en contenedores grandes puede tardar minutos. Mejor la variante con Event Grid |
| **Productor publica el mensaje** | Tú publicas tras escribir | Quieres validar antes y controlar el contenido del ticket ([Claim Check](../claim-check/README.md) variantes A y C) |
| **Inventario de blobs** | Informe periódico | Conciliar, no reaccionar |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Procesar archivos al llegar (CSV, imágenes, PDF, video) sin sondear ([Claim Check](../claim-check/README.md), variante B).
- Escanear con antivirus, extraer metadatos, generar miniaturas.
- Indexar en un buscador cuando cambia el catálogo.
- Auditar borrados y cambios de nivel.
- Encadenar procesos entre equipos sin acoplarlos.

| NO lo uses si | Alternativa |
|---|---|
| Necesitas **orden total** y **cero pérdidas** demostrables | Change feed |
| Quieres decidir **qué** se anuncia (validar antes) | Publica tú el ticket |
| El evento debe llevar datos de negocio (usuario, pedido) | El productor publica; el evento solo trae la ruta |
| Procesas el resultado en el **mismo** contenedor/prefijo | Contenedores o prefijos separados, o creas un bucle infinito |
| Necesitas exactamente una vez | Idempotencia en el consumidor (no hay exactamente-una-vez) |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Evento** | Un hecho que ya ocurrió | `BlobCreated` |
| **Tópico del sistema** | Punto de publicación de una cuenta | `evgt-storage-cc` |
| **Suscripción de eventos** | Regla de entrega: filtro + destino | `blobcreated-a-cola` |
| **Handler / destino** | Quien recibe el evento | Cola de Service Bus |
| **Subject** | Ruta del blob dentro del evento | `/blobServices/default/containers/subidas/blobs/…` |
| **Sequencer** | Marca para ordenar eventos del mismo blob | `0000…28963` |
| **Dead-letter** | Almacén de eventos no entregados | Contenedor `deadletter` |
| **Handshake** | Validación del endpoint del webhook | `validationCode` |
| **CloudEvents** | Estándar de envoltorio de eventos | `specversion: 1.0` |
| **Identidad de entrega** | Identidad con la que Event Grid entrega | *System-assigned* del tópico |

---

## 5. Cómo se usa

1. **Decide el destino** según lo que haga el consumidor: cola de Service Bus (lo normal para procesar), Function (código corto), webhook (tu API), Storage Queue (barato y simple).
2. **Crea el tópico del sistema** de la cuenta con identidad administrada.
3. **Dale permiso** a esa identidad en el destino (*Azure Service Bus Data Sender*, *Storage Queue Data Message Sender*…).
4. **Crea la suscripción** con tipo de evento, filtro por contenedor y prefijo, esquema CloudEvents, reintentos y dead-letter.
5. **Escribe un consumidor idempotente** que verifique el blob (ETag), procese y complete.
6. **Observa**: métricas (*Matched Events*, *Delivery Failed Events*, *Dead Lettered Events*) y registros de diagnóstico.
7. **Prueba**: sube un archivo y mira que llega; borra y revisa; fuerza un fallo y comprueba el dead-letter.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/eventos-blob.sh) · [KQL](ejemplos/kql/kql-eventgrid.md) · [eventos de ejemplo](ejemplos/eventos/).

---

## 6. Seguridad

- **Entrega con identidad administrada** al destino; sin llaves de acceso ni cadenas de conexión en la suscripción.
- **Mínimo privilegio** en el destino: solo *enviar* al recurso concreto.
- **Webhooks**: autentica con **Microsoft Entra ID** (la suscripción presenta un token con la audiencia de tu aplicación) o, como mínimo, una clave en la URL; valida el handshake; HTTPS obligatorio.
- **No pongas datos sensibles en el *subject*** (nombres de archivo con DNI): viaja en el evento y en los registros.
- **Redes privadas**: los eventos los publica la propia cuenta (el firewall de la cuenta no los bloquea); el **destino** protegido por red (p. ej. Service Bus Premium con Private Endpoint) debe permitir "servicios de confianza de Microsoft" con identidad administrada. *Verifica el soporte vigente por destino.*
- **Dead-letter** en una cuenta con acceso restringido y con retención; los eventos contienen rutas de archivos.
- **Control de quién crea suscripciones**: es un permiso poderoso (puede desviar eventos).

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Quien crea la suscripción | Escribir `Microsoft.EventGrid/eventSubscriptions/write` en la fuente | *EventGrid EventSubscription Contributor* en la cuenta o el grupo de recursos |
| Quien solo mira suscripciones | Lectura | *EventGrid EventSubscription Reader* |
| Identidad del tópico → Service Bus | Entregar a la cola | *Azure Service Bus Data Sender* en la cola |
| Identidad del tópico → Storage Queue | Entregar a la cola | *Storage Queue Data Message Sender* |
| Identidad del tópico → Event Hubs | Entregar al hub | *Azure Event Hubs Data Sender* |
| Identidad del tópico → dead-letter | Escribir el blob | *Storage Blob Data Contributor* en el contenedor de dead-letter |
| Consumidor de la cola | Recibir y leer el blob | *Azure Service Bus Data Receiver* + *Storage Blob Data Reader* |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Filtrar por **tipo de evento + contenedor + prefijo** (y extensión si aplica).
- Usar **CloudEvents** si habrá más de un consumidor o sistema.
- Configurar **dead-letter** y reintentos acordes al negocio.
- Hacer el consumidor **idempotente** (`id` del evento) y tolerante al desorden (`sequencer`).
- Leer el blob con **`If-Match: eTag`** del evento para procesar justo lo anunciado.
- Separar contenedores de **entrada** y de **resultado** (evita bucles).
- Responder 2xx rápido en los webhooks y procesar de forma asíncrona.
- Alertar sobre *Dead Lettered Events* y *Delivery Failed Events*.

**Qué NO hacer**
- Suscribirse a todo el tópico "por si acaso".
- Asumir orden o una sola entrega.
- Procesar dentro del webhook trabajos de minutos (se reintenta y se duplica).
- Escribir los resultados en el mismo prefijo que dispara el evento.
- Dar permisos amplios (*Contributor*) al tópico en el destino.
- Meter datos personales en nombres de blob.
- Depender de los eventos para **auditoría legal** (usa change feed y registros de diagnóstico).

---

## 8. Límites, costos y versiones
- Costo por **operaciones** de Event Grid (publicar, entregar, filtrar avanzado, reintentos), con una cuota gratuita mensual; normalmente despreciable frente al almacenamiento. *Verifica precios vigentes.*
- Límites: tamaño de evento (1 MB), número de suscripciones por tópico, filtros avanzados por suscripción, intentos y tiempo de vida del evento. *Verifica en la doc.*
- Un solo tópico del sistema por cuenta y tipo; varias suscripciones sobre él.
- Los tipos de evento y los campos de `data` evolucionan: usa el SDK (`StorageBlobCreatedEventData`) en lugar de parsear a mano.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
