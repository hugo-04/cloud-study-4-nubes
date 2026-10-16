# Azure · Mensajería · Event Hubs (con su endpoint Kafka)

## 1. Qué es

**Event Hubs es el servicio de Azure para recibir y guardar un flujo enorme de registros (eventos, telemetría, logs, clics) y dejar que muchos lectores los procesen, cada uno a su ritmo, incluso volviendo a leer lo ya pasado.** No es una cola que entrega y borra: es un **registro (*log*) de solo agregar**, dividido en **particiones**, donde los datos se conservan durante un tiempo de retención y cada lector lleva su propio marcador (*offset*). Habla tres idiomas: **AMQP 1.0**, **HTTPS** y el **protocolo de Apache Kafka**, de modo que un cliente Kafka existente se conecta cambiando solo la configuración.

Analogía: **una cinta transportadora de varios carriles (las particiones) que nunca retira las cajas hasta que pasa el tiempo de retención**. Los productores ponen cajas en los carriles; cada equipo de lectura (grupo de consumidores) se para junto a la cinta con su propia libreta donde anota "voy por la caja número 5.230" (el *offset*). Si el equipo se equivoca, vuelve a la caja 4.000 y repite; si llega gente nueva, no le quita cajas a los demás.

```
 PRODUCTORES                         NAMESPACE (valla de capacidad: unidades de rendimiento / procesamiento)
 ───────────                         ────────────────────────────────────────────────────────────────────
 Microservicio pedidos ──┐           EVENT HUB "clics-web"  (= TOPIC de Kafka)
 App móvil (HTTPS) ──────┼─────►     ┌ Partición 0: [e0][e1][e2][e3][e4]──► offset →
 Sensores IoT ───────────┤           ├ Partición 1: [e0][e1][e2]──────────► offset →      retención: 1–90 días
 Debezium (CDC, Kafka) ──┘           ├ Partición 2: [e0][e1][e2][e3]──────► offset →      (según nivel)
   clave de partición decide         └ Partición 3: [e0][e1]──────────────► offset →
   a qué carril va                                │
                                                  ├─► GRUPO "analitica"  (lee todo; 1 consumidor por partición como máximo)
                                                  ├─► GRUPO "antifraude" (lee todo otra vez, su propio offset)
                                                  ├─► GRUPO "busqueda"   (reindexa, puede rebobinar)
                                                  └─► CAPTURE ──► Blob / Data Lake (archivos Avro) para el lago de datos
```

---

## 2. Cómo funciona por dentro

### 2.1 La jerarquía

| Nivel | Qué es | Equivalente Kafka |
|---|---|---|
| **Namespace** | Contenedor con el punto de conexión (`<ns>.servicebus.windows.net`), la capacidad, la red y la seguridad | El **clúster** |
| **Event hub** | Un flujo con nombre (`clics-web`) con N particiones y una retención | Un **topic** |
| **Partición** | Un carril ordenado e independiente dentro del event hub | Una **partition** |
| **Grupo de consumidores** | Una "vista" del flujo con sus propios offsets | Un **consumer group** |
| **Offset** | Posición de un evento dentro de su partición | El **offset** |
| **Sequence number** | Número consecutivo del evento en su partición | (offset) |
| **Evento** | Cuerpo (bytes) + propiedades + metadatos del sistema | El **record** |

### 2.2 Particiones y clave de partición (lo más importante del diseño)

- Una partición es una **cola ordenada**: el orden se garantiza **solo dentro de una partición**, nunca entre particiones.
- El productor decide el carril de dos maneras: **clave de partición** (se calcula un *hash*; misma clave → misma partición → orden para esa clave) o **sin clave** (reparto rotativo, máximo equilibrio y sin orden por entidad).
- Regla de oro: **la clave debe ser la entidad cuyo orden importa** (`pedidoId`, `clienteId`, `sensorId`), con muchos valores distintos para no crear una partición "caliente".
- **Paralelismo de lectura = número de particiones**: dentro de un grupo, cada partición la lee **un solo consumidor a la vez**. Con 8 particiones, el 9.º consumidor del grupo queda ocioso.
- El número de particiones se fija al crear el event hub. En los niveles Basic y Standard **no se cambia** después; en Premium y Dedicated se puede **aumentar** (nunca reducir). *Verifica el comportamiento vigente.*
- Cómo dimensionar: `particiones ≥ max( throughput_pico / throughput_por_partición , consumidores_en_paralelo_deseados )`, con holgura para crecer. Más particiones no cuestan más por sí mismas, pero sí complican el reparto y aumentan el tiempo de arranque de los consumidores.

### 2.3 Offsets, retención y reproducción

- Los eventos **no se borran al leerlos**: se conservan hasta que cumple la **retención** (por tiempo; Basic 1 día, Standard 1 a 7 días, Premium y Dedicated hasta 90 días; *verifica los límites vigentes*).
- Cada lector guarda su offset. **Reproducir** = reposicionar el offset (al inicio, a una fecha o a un número) y volver a procesar. Es la gran diferencia con una cola.
- **Entrega al menos una vez**: tras una caída, el consumidor retoma desde su último *checkpoint*, así que puede ver eventos repetidos. Diseña consumidores **idempotentes**.

### 2.4 Grupos de consumidores
Cada grupo recibe **todos** los eventos y lleva sus propios offsets. Un microservicio = un grupo. El grupo `$Default` existe siempre; crea grupos con nombre. Hay un máximo de grupos por event hub según el nivel (Basic 1, Standard 20, Premium 100; *verifica*). Es el equivalente del `group.id` de Kafka.

### 2.5 Niveles y capacidad

| Nivel | Capacidad | Rasgos |
|---|---|---|
| **Basic** | Unidades de rendimiento (TU) | Sin endpoint Kafka, 1 grupo, retención de 1 día; para pruebas simples |
| **Standard** | **TU** (1 TU ≈ 1 MB/s o 1.000 eventos/s de entrada y 2 MB/s de salida; *verifica*) con **auto-inflate** | Kafka, Capture, Schema Registry, hasta 20 grupos y 7 días |
| **Premium** | **Unidades de procesamiento (PU)** aisladas | Más retención (hasta 90 días), más grupos, red privada con mejor aislamiento, aumento de particiones, funciones Kafka ampliadas |
| **Dedicated** | **Unidades de capacidad (CU)** en clúster exclusivo | Volúmenes muy grandes y aislamiento total |

- **Auto-inflate**: sube TU automáticamente hasta un máximo que tú fijas; **no baja solo** (hay que reducirlas).
- Si superas la capacidad, recibes errores de **limitación** (*throttling*, `ServerBusy`, HTTP 429/códigos Kafka de cuota): hay que reintentar con retroceso y, si es estructural, ampliar capacidad.

### 2.6 Protocolos y puertos

| Protocolo | Puerto | Uso |
|---|---|---|
| **AMQP 1.0** | 5671 (y 5672) | SDK nativo de Azure (recomendado si no tienes código Kafka) |
| **Kafka** | **9093** (SASL_SSL) | Clientes y herramientas Kafka existentes |
| **HTTPS** | 443 | Publicar desde entornos restringidos (móviles, firewalls) |
| AMQP sobre WebSockets | 443 | Cuando el 5671 está bloqueado |

### 2.7 Capture: del flujo al lago de datos sin escribir código
Event Hubs puede **volcar automáticamente** el flujo a **Blob Storage o Data Lake Gen2** en archivos **Avro** con una ventana de tiempo y de tamaño (por ejemplo cada 5 minutos o 300 MB). Estructura: `{namespace}/{eventhub}/{partición}/{año}/{mes}/{día}/{hora}/{minuto}/{segundo}`. Útil para la **zona bronce** del lago (ver [Data Lake](../../06-storage/data-lake-gen2/README.md)), auditoría y reprocesos masivos. Requiere dar a la identidad del namespace permiso de escritura (*Storage Blob Data Contributor*) en el contenedor.

### 2.8 Event Hubs como "Kafka administrado"

**Mapa de conceptos**

| Kafka | Event Hubs |
|---|---|
| Clúster | Namespace |
| Topic | Event hub |
| Partition | Partición |
| Consumer group | Grupo de consumidores |
| Offset / commit | Offset / checkpoint (los commits de Kafka se guardan en el servicio) |
| `bootstrap.servers` | `<namespace>.servicebus.windows.net:9093` |
| ACL / SASL | Entra ID (OAUTHBEARER) o `$ConnectionString` (PLAIN) |
| Schema Registry | Registro de esquemas de Event Hubs (Avro/JSON/Custom) |

**Qué cambia al migrar una aplicación Kafka**: solo `bootstrap.servers`, `security.protocol=SASL_SSL` y el mecanismo SASL. **El código no cambia.**

**Diferencias y límites que debes conocer** (*verifica la lista vigente; cambia con las versiones*):
- No hay que administrar brokers, ZooKeeper/KRaft, discos ni *rebalances* de réplicas: lo hace el servicio.
- Los *topics* se crean como **event hubs** (con `AdminClient` si se permite, o con Terraform/CLI); parámetros como `replication.factor` no aplican.
- Funciones avanzadas (transacciones, *log compaction*, Kafka Streams, compresión específica) dependen del **nivel** (Standard vs Premium/Dedicated).
- La retención es la del nivel; `retention.ms` por topic tiene reglas propias.
- Kafka Connect y Debezium **funcionan** apuntando al endpoint; Kafka Connect se ejecuta en tus propios contenedores (por ejemplo en AKS).
- Los nombres de *topic* son los de los event hubs: sin `.` ni caracteres raros que el servicio no admita.

### 2.9 Registro de esquemas (Schema Registry)
Repositorio de **esquemas Avro/JSON** con versiones y reglas de compatibilidad (`Backward`, `Forward`, `None`) organizado en **grupos de esquemas**. El productor serializa con el identificador del esquema en el mensaje y el consumidor lo recupera para deserializar. Evita que un equipo rompa a los demás cambiando un campo. Disponible desde el nivel Standard; funciona también con serializadores de Kafka (Confluent compatible vía el serializador de Azure). *Verifica el SDK y la versión.*

### 2.10 Checkpoints: quién guarda el "voy por aquí"

| Cliente | Dónde se guarda el offset |
|---|---|
| **Kafka** (`KafkaConsumer`, Spring Kafka, Quarkus) | En el propio servicio (equivalente a `__consumer_offsets`) con `enable.auto.commit` o `commitSync/commitAsync` |
| **SDK nativo** (`EventProcessorClient`) | En un **Blob Storage** que tú indicas (*checkpoint store*); también reparte particiones entre instancias y balancea carga |

Un **checkpoint** es "he procesado hasta este evento". Se hace **después** de procesar (no antes) para no perder datos; se hace cada N eventos o cada T segundos (no por cada evento: sería lento y caro).

### 2.11 Continuidad y recuperación
- **Zonas de disponibilidad**: Standard (con zonas, donde existan), Premium y Dedicated resisten la caída de una zona.
- **Geo-recuperación (*Geo-DR*)**: empareja dos namespaces; ante un desastre haces *failover* y el alias DNS apunta al secundario. Replica **metadatos** (event hubs, grupos), **no los datos**.
- **Replicación geográfica** (Premium/Dedicated): replica también los datos. *Verifica disponibilidad y límites.*

### 2.12 Event Hubs frente a otros servicios de mensajería de Azure

| Pregunta | Event Hubs | Service Bus | Event Grid | Storage Queue |
|---|---|---|---|---|
| Modelo | **Log** particionado, se conserva | Cola/tópico con bloqueo y liquidación | Enrutador de eventos | Cola simple |
| Volumen | **Millones/s** | Moderado | Alto | Moderado |
| Reproducir lo pasado | **Sí** | No | No | No |
| Orden | Por partición | Sesiones | No | No |
| DLQ por mensaje | **No** (lo manejas tú) | Sí | Básico | No (cola de veneno manual) |
| Típico | Telemetría, clics, CDC, Kafka | Comandos de negocio | Reaccionar a Azure | Trabajo sencillo y barato |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Telemetría e IoT**: miles de sensores enviando lecturas continuamente.
- **Analítica de comportamiento**: clics, vistas, búsquedas de una tienda en línea.
- **Integración de datos (CDC)**: cambios de bases de datos hacia lagos y buscadores con Debezium.
- **Arquitecturas Kafka**: migrar o ejecutar aplicaciones Kafka sin administrar brokers.
- **Event sourcing y vistas materializadas** (el log es la fuente de verdad temporal).
- **Logs y auditoría centralizados** hacia SIEM.
- **Procesamiento de flujos** (Stream Analytics, Spark, Flink, Functions).

| NO lo uses si | Alternativa |
|---|---|
| Necesitas "una tarea, un trabajador" con reintentos y DLQ por mensaje | **Service Bus** |
| Quieres reaccionar a "se creó un blob" sin código | **Event Grid** |
| Tu volumen es de unos cientos de mensajes por hora | **Storage Queue** o Service Bus |
| Necesitas orden global estricto | Una sola partición (limita el rendimiento) o rediseñar por clave |
| Los mensajes pesan megabytes | **Claim Check** ([patrón](../../06-storage/claim-check/README.md)) |
| Necesitas consultar eventos por contenido | Una base de datos / búsqueda alimentada desde el flujo |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Event hub** | Un flujo con nombre y particiones | `clics-web` |
| **Partición** | Carril ordenado del flujo | 8 particiones |
| **Clave de partición** | Valor que decide el carril | `pedidoId` |
| **Offset** | Posición del evento en su partición | 5.230 |
| **Checkpoint** | "He procesado hasta aquí" guardado | Blob / servicio |
| **Grupo de consumidores** | Vista independiente del flujo | `antifraude` |
| **Retención** | Tiempo que se conservan los eventos | 7 días |
| **TU / PU / CU** | Unidades de capacidad por nivel | 4 TU |
| **Auto-inflate** | Subida automática de TU | máx. 10 TU |
| **Capture** | Volcado automático a Blob/Data Lake en Avro | cada 5 min |
| **Throttling** | Rechazo por exceder la capacidad | `ServerBusy` |
| **Rebalance** | Reparto de particiones entre consumidores del grupo | Al entrar/salir una instancia |
| **Lag** | Cuántos eventos le faltan al consumidor para alcanzar al productor | 12.000 eventos |
| **Partición caliente** | Una partición recibe mucho más que las demás | Clave sesgada |
| **Schema Registry** | Repositorio de esquemas con compatibilidad | `Backward` |
| **Idempotencia** | Procesar dos veces = efecto de una | Clave única por `eventId` |

---

## 5. Cómo se usa

1. **Decide nivel y capacidad:** Standard con auto-inflate para empezar; Premium si necesitas aislamiento, red privada estricta o más retención.
2. **Diseña el event hub:** una **partición** por unidad de paralelismo; **clave de partición** = entidad cuyo orden importa; retención según la necesidad de reproducir.
3. **Crea grupos de consumidores** con nombre por microservicio (`antifraude`, `analitica`).
4. **Elige el cliente:** SDK nativo (`azure-messaging-eventhubs`) o cliente Kafka (Spring Kafka, reactor-kafka, Quarkus).
5. **Autentica con Entra ID** (`DefaultAzureCredential` o OAUTHBEARER) y los roles *Data Sender* / *Data Receiver*.
6. **Productor:** envía **por lotes**, con clave, y confirma (`acks`) o espera el resultado; reintentos con retroceso.
7. **Consumidor:** procesa idempotente, **checkpoint después de procesar**, maneja eventos venenosos (reenviar a un event hub de errores) y mide el lag.
8. **Activa Capture** si quieres el lago de datos; **Schema Registry** si varios equipos comparten el contrato.
9. **Observa:** solicitudes entrantes/salientes, errores de servidor, limitación, lag por grupo y salud del namespace.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/event-hubs.sh) · [KQL](ejemplos/kql/kql-eventhubs.md) · [propiedades Kafka](ejemplos/kafka/) · [emulador local](ejemplos/emulator/).

---

## 6. Seguridad

- **Entra ID, sin claves:** `local_authentication_enabled = false`; sin SAS ni cadenas de conexión. Para Kafka, **OAUTHBEARER** (código en [uso en Java](uso-en-java.md)).
- **Mínimo privilegio** por event hub: el productor solo *Data Sender*; cada consumidor solo *Data Receiver*, sobre **su** event hub (no sobre el namespace entero).
- **Red:** Private Endpoint (zona `privatelink.servicebus.windows.net`), reglas de red del namespace, y "servicios de confianza" para Capture y Event Grid.
- **Cifrado:** en tránsito TLS 1.2+; en reposo con claves de Microsoft o gestionadas por ti (Key Vault; nivel que lo soporte).
- **Checkpoint store:** el contenedor de Blob con permiso *Storage Blob Data Contributor* solo para los consumidores.
- **Datos:** no envíes datos personales sin minimizar; usa Claim Check para contenido grande o sensible.
- **Auditoría:** diagnóstico del namespace a Log Analytics (operaciones, errores, conexiones).

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Microservicio productor | Enviar eventos | *Azure Event Hubs Data Sender* (en el event hub) |
| Microservicio consumidor | Leer y hacer checkpoint | *Azure Event Hubs Data Receiver* (en el event hub) + *Storage Blob Data Contributor* (en el contenedor de checkpoints, solo con SDK nativo) |
| Administrador de flujos | Crear event hubs, grupos | *Contributor* o *Azure Event Hubs Data Owner* (acotado) |
| Capture | Escribir archivos | *Storage Blob Data Contributor* (identidad del namespace en el contenedor) |
| Event Grid → Event Hubs | Entregar eventos | *Azure Event Hubs Data Sender* a la identidad del tópico |
| Schema Registry (serializador) | Leer/registrar esquemas | *Schema Registry Reader* / *Contributor* |
| Aplicaciones de monitoreo | Leer métricas | *Monitoring Reader* |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Elegir bien la **clave de partición** y revisar la distribución por partición.
- **Checkpoint después de procesar**, no por cada evento (cada N eventos o T segundos).
- Consumidores **idempotentes** con la clave `eventId`.
- Un **grupo de consumidores por microservicio**.
- **Lotes** en el productor (`linger.ms`, `batch.size`, o `createBatch()`).
- **Reintentos con retroceso** ante limitación; **alertas de lag**.
- Un event hub **de errores** (DLQ manual) para eventos venenosos.
- Entra ID + roles por event hub + red privada.
- **Capture** para el lago, no consumidores ad hoc que copian datos.
- Probar con el **emulador** y con Kafka local antes de la nube.

**Qué NO hacer**
- Usarlo como cola de comandos con garantías por mensaje (para eso, Service Bus).
- Una sola partición "para tener orden" en un flujo grande.
- Más consumidores en un grupo que particiones.
- Hacer checkpoint antes de procesar (perderás eventos si el servicio cae).
- Compartir un solo grupo de consumidores entre servicios distintos (se roban eventos).
- Ignorar el lag hasta que la retención borre los datos sin leer.
- Eventos gigantes: pásalos por Blob y envía la referencia.
- Dejar activas las claves SAS del namespace.
- Crear cientos de event hubs "por si acaso": cada uno tiene particiones y retención que cuestan gestión.

---

## 8. Límites, costos y versiones

- **Costo:** por capacidad (TU/PU/CU) por hora + eventos de entrada (en Basic/Standard) + Capture + Schema Registry y retención extendida según el nivel. *Verifica precios y regiones.*
- **Límites típicos** (cambian por nivel): eventos de hasta ~1 MB por lote/evento (Standard 1 MB), particiones por event hub, event hubs por namespace, grupos por event hub, conexiones simultáneas, retención. *Verifica la tabla vigente de cuotas.*
- **Versiones:** clientes Kafka 1.0+ soportados (usa uno reciente); `azure-messaging-eventhubs` con el BOM del SDK 1.3.x en este repositorio.
- **Funciones en evolución:** Kafka Streams, transacciones, compactación, replicación geográfica: confirma disponibilidad por nivel antes de diseñar.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
