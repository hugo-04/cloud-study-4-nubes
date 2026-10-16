# Azure · Mensajería · Service Bus (colas y tópicos empresariales)

## 1. Qué es

**Service Bus es el servicio de mensajería empresarial de Azure: un intermediario (*broker*) confiable que recibe mensajes de un servicio y los entrega a otro, aunque el segundo esté caído, lento o saturado.** Garantiza que el mensaje no se pierde, controla los reintentos, aparta los mensajes "venenosos", evita duplicados, respeta el orden cuando lo necesitas y permite repartir un mismo hecho a varios interesados.

Analogía: **la oficina de correos con casilleros y buzón de devoluciones**. Dejas una carta certificada (mensaje); el cartero (consumidor) la recoge y **firma el acuse solo cuando la entregó bien**; si no puede entregarla tras varios intentos, no la tira: la pone en el **buzón de devoluciones** (*dead-letter*) con una nota del motivo. Un tablón de anuncios con suscriptores (tópico) copia la carta a quien la pidió.

```
                       ┌──────────────── NAMESPACE (sb-modalima.servicebus.windows.net) ────────────────┐
  Productor ──send──►  │  COLA "pedidos"                                         ┌─ consumidor A       │
  (API de pedidos)     │  [m5][m4][m3][m2][m1] ──peek-lock──────────────────────►├─ consumidor B  (competidores: cada
                       │        │ (falla N veces / expira)                       └─ consumidor C   mensaje lo trata UNO)
                       │        └──► $deadletterqueue  (con motivo)                                      │
                       │                                                                                 │
  Productor ──send──►  │  TÓPICO "eventos-pedido"                                                        │
                       │    ├─ suscripción "facturacion" (filtro: tipo = pedido.pagado) ──► Facturación │
                       │    ├─ suscripción "inventario"  (filtro SQL: region = 'PE')    ──► Inventario  │
                       │    └─ suscripción "auditoria"   (sin filtro: todo)             ──► Auditoría   │
                       └─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Cómo funciona por dentro

### 2.1 Jerarquía y niveles

| Elemento | Qué es |
|---|---|
| **Namespace** | Contenedor y dirección (`<nombre>.servicebus.windows.net`): red, identidad, nivel y límites se definen aquí |
| **Cola** (*queue*) | Un destino, **un consumidor por mensaje** (consumidores competidores) |
| **Tópico** (*topic*) | Un destino de publicación; copia cada mensaje a cada suscripción |
| **Suscripción** | "Cola virtual" de un tópico con sus **reglas** (filtros) |
| **Regla** (*rule*) | Filtro (booleano, SQL o correlación) y, opcionalmente, acción que modifica propiedades |
| **Subcola de mensajes fallidos** (*DLQ*) | Cada cola y suscripción tiene la suya: `$deadletterqueue` |

| Nivel | Cuándo | Rasgos (verifica límites vigentes) |
|---|---|---|
| **Basic** | Solo colas simples | Sin tópicos |
| **Standard** | Uso general | Colas y tópicos; recursos compartidos; mensajes de hasta ~256 KB; se paga por operaciones |
| **Premium** | Producción exigente | Recursos **dedicados** (unidades de mensajería), rendimiento predecible, mensajes de hasta ~100 MB, **Private Endpoint**, zonas de disponibilidad, CMK, replicación/Geo-DR, JMS 2.0 |

### 2.2 Anatomía de un mensaje

| Parte | Ejemplos | Uso |
|---|---|---|
| **Cuerpo** | JSON de 2 KB | Datos del negocio (para archivos grandes: [Claim Check](../../06-storage/claim-check/README.md)) |
| **Propiedades del sistema** | `MessageId`, `CorrelationId`, `SessionId`, `Subject`, `ContentType`, `To`, `ReplyTo`, `TimeToLive`, `ScheduledEnqueueTime`, `PartitionKey` | Control del broker |
| **Propiedades de aplicación** | `tipo`, `region`, `version`, `intento` | Filtros de suscripciones y enrutamiento propio |
| **Propiedades puestas por el broker** | `SequenceNumber`, `EnqueuedTime`, `DeliveryCount`, `LockToken`, `LockedUntil` | Diagnóstico y liquidación |

### 2.3 El ciclo de vida de un mensaje (peek-lock)

```
  ENVIADO ──► ACTIVO ──recibir (bloqueo 1–5 min)──► BLOQUEADO ──┬─ complete()    ──► BORRADO (éxito)
                │                                                ├─ abandon()     ──► ACTIVO otra vez (DeliveryCount+1)
                │                                                ├─ defer()       ──► DIFERIDO (se pide por SequenceNumber)
                │                                                ├─ deadLetter()  ──► DLQ (motivo explícito)
                │                                                └─ (bloqueo vence)──► ACTIVO otra vez (DeliveryCount+1)
                ├─ TTL vence ──► (descartado o DLQ si está activada la opción)
                └─ DeliveryCount > MaxDeliveryCount ──► DLQ ("MaxDeliveryCountExceeded")
```

| Modo de recepción | Qué hace | Cuándo |
|---|---|---|
| **Peek-lock** (por defecto, el correcto) | El mensaje se **bloquea**; tú lo "liquidas" (*settle*) al terminar | Casi siempre: al menos una vez, sin pérdida |
| **Receive-and-delete** | Se borra al entregarlo | Solo si perder un mensaje es aceptable |

| Liquidación | Efecto | Úsala cuando |
|---|---|---|
| `complete` | Borra el mensaje | Procesado con éxito |
| `abandon` | Libera el bloqueo; vuelve a la cola | Fallo **transitorio** (BD caída, 503) |
| `deadLetter` | Lo manda a la DLQ con motivo y descripción | Fallo **irrecuperable** (mensaje inválido, regla de negocio) |
| `defer` | Lo aparta; solo se recupera con su `SequenceNumber` | Llegó fuera de orden y debes esperar a otro mensaje |

### 2.4 Funciones que justifican elegir Service Bus

| Función | Qué resuelve | Detalle |
|---|---|---|
| **DLQ** | Mensajes venenosos sin bloquear la cola | Motivos del sistema: `MaxDeliveryCountExceeded`, `TTLExpiredException`; y los tuyos |
| **`MaxDeliveryCount`** | Corta reintentos infinitos | Por defecto 10 |
| **Duplicate detection** | Descarta el mismo `MessageId` dentro de una ventana (20 s a 7 días) | El productor debe fijar `MessageId` estable |
| **Sesiones** | Orden **FIFO por clave** (`SessionId`) y un solo consumidor por sesión | Pedidos del mismo cliente en orden; estado de sesión |
| **Mensajes programados** | Entrega diferida a una hora exacta | Recordatorios, reintentos con espera |
| **TTL** | El mensaje caduca si no se consume | Evita procesar algo obsoleto |
| **Transacciones** | Enviar + completar de forma atómica dentro del namespace | Consumir de A y publicar en B sin duplicar ni perder |
| **Auto-forward** | Encadena entidades (cola/suscripción → cola/tópico) | Consolidar o enrutar |
| **Filtros y acciones** | Cada suscripción recibe solo lo suyo | SQL (`region = 'PE' AND total > 100`) o correlación (igualdad rápida) |
| **Particionamiento** | Mayor rendimiento/disponibilidad por entidad | Se decide al crear en algunos niveles |
| **Request/Reply** | `ReplyTo` + `CorrelationId` o sesión de respuesta | RPC asíncrono |

### 2.5 Reglas para consumir bien (donde se rompe en la vida real)

| Tema | Regla |
|---|---|
| **Idempotencia** | La entrega es **al menos una vez**: el consumidor debe tolerar duplicados (tabla de procesados con clave única) |
| **Bloqueo** | `lockDuration` ≥ tiempo de proceso, o renueva (`maxAutoLockRenewDuration`); si no, otro consumidor lo recibe |
| **Liquidar siempre** | Cada ruta de código termina en `complete`, `abandon` o `deadLetter`; si no, queda bloqueado hasta expirar |
| **Clasificar errores** | Transitorio → `abandon`/reintento con espera; permanente → `deadLetter` con motivo |
| **Prefetch** | Mejora el caudal pero **empieza a contar el bloqueo al traer** el mensaje: con procesos lentos, prefetch bajo |
| **Concurrencia** | `maxConcurrentCalls` por réplica × réplicas = consumo total; respeta lo que aguanta tu BD |
| **Orden** | Solo con sesiones; sin sesiones no hay orden garantizado con varios consumidores |
| **Reutiliza clientes** | Un `ServiceBusClient`/sender por aplicación, no uno por mensaje |
| **Lotes** | Envía por lotes (`ServiceBusMessageBatch`) para caudal |
| **Reintentos de reenvío** | Con espera: reenviar programado (`ScheduledEnqueueTime`) y completar el original |
| **DLQ** | Se monitoriza y se reprocesa; **no se vacía sola** |

### 2.6 Conexión
Protocolo **AMQP 1.0** sobre TCP 5671 o sobre WebSockets (443, útil tras firewalls). Autenticación con **Microsoft Entra ID** (recomendado) o claves SAS. Con `local_auth_enabled = false` solo Entra ID.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Comandos y trabajos** entre microservicios con reintentos y DLQ (cobrar, generar factura, enviar correo).
- **Publicar eventos de dominio** a varios consumidores con filtros (tópicos).
- **Orden por cliente/entidad** (sesiones).
- **Desacoplar picos**: la API acepta y el procesador consume a su ritmo (*load leveling*).
- **Sagas** y flujos de varios pasos con compensación.
- **Reintentos con espera** y recordatorios (mensajes programados).
- Integración con sistemas **JMS/AMQP** existentes (Premium).

| NO lo uses si | Alternativa |
|---|---|
| Telemetría o flujos de millones de eventos/segundo con reproceso del histórico | **Event Hubs** (o Kafka) |
| Solo necesitas reaccionar a "algo pasó" en Azure con enrutamiento ligero | **Event Grid** |
| Cola simple, barata, sin DLQ ni tópicos | **Storage Queue** |
| Mensajes de decenas de MB o archivos | **Claim Check** (Blob + ticket) |
| Necesitas leer el mensaje varias veces o reproducir el pasado | Event Hubs/Kafka (log) |
| Transacciones entre la base de datos y el broker | **Outbox** (la BD es la fuente de verdad) |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Broker** | Intermediario que guarda y entrega mensajes | Service Bus |
| **Cola** | Un mensaje → un consumidor | `pedidos` |
| **Tópico/Suscripción** | Un mensaje → una copia por suscripción | `eventos-pedido` |
| **Peek-lock** | Bloquear al recibir y liquidar después | Modo por defecto |
| **Liquidar** (*settle*) | Decidir el destino del mensaje | `complete()` |
| **DLQ** | Cola de mensajes fallidos | `$deadletterqueue` |
| **Mensaje venenoso** | Uno que siempre falla | JSON inválido |
| **Idempotencia** | Repetir no cambia el resultado | `INSERT ... ON CONFLICT DO NOTHING` |
| **Sesión** | Grupo ordenado por clave | `SessionId = clienteId` |
| **Duplicate detection** | Descarte por `MessageId` repetido | Ventana 10 min |
| **Prefetch** | Traer mensajes por adelantado | 20 |
| **Lock duration** | Tiempo del bloqueo | 1–5 min |
| **Saga** | Proceso distribuido con compensaciones | Pedido → pago → envío |
| **Outbox** | Guardar el mensaje en la BD y publicarlo después | Tabla `salida` |

---

## 5. Cómo se usa

1. **Elige nivel** (Standard para empezar; Premium si necesitas red privada, mensajes grandes o rendimiento predecible).
2. **Diseña entidades:** cola para comandos (un destinatario), tópico para eventos (varios).
3. **Configura:** `lockDuration`, `maxDeliveryCount` (5–10), TTL, duplicate detection, DLQ por expiración, sesiones si hay orden.
4. **Seguridad:** Entra ID, `local_auth_enabled=false`, roles *Data Sender/Receiver* por entidad, Private Endpoint (Premium).
5. **Productor:** `MessageId` estable, `CorrelationId`, `Subject`, propiedades de filtro, envío por lotes.
6. **Consumidor:** peek-lock, idempotencia, clasificación de errores, renovación del bloqueo, liquidación explícita.
7. **Operación:** alertas de DLQ y de mensajes activos antiguos, runbook de reproceso.
8. **Local y pruebas:** emulador de Service Bus en contenedor (solo cadena de conexión; sin Entra ID).

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/service-bus.sh) · [KQL](ejemplos/kql/kql-servicebus.md) · [Emulador local](ejemplos/emulator/) · [Reglas de suscripción](ejemplos/reglas/reglas-suscripcion.md).

---

## 6. Seguridad

- **Entra ID + roles**; `local_auth_enabled = false` para eliminar las claves SAS.
- **Mínimo privilegio por entidad**: el productor solo *Data Sender* de su cola/tópico; el consumidor solo *Data Receiver* de su cola/suscripción.
- **Red privada (Premium):** Private Endpoint + zona DNS `privatelink.servicebus.windows.net`; reglas de IP/VNet; "servicios de confianza" para Event Grid y otros.
- **TLS 1.2** como mínimo; AMQP cifrado siempre.
- **CMK** (Premium) para cifrar con tu clave de Key Vault.
- **Nada sensible en propiedades** (se ven en filtros, logs y herramientas); el cuerpo con datos personales, lo mínimo.
- **Diagnóstico** hacia Log Analytics (operaciones, rechazos de red, auditoría).
- **Protección contra borrado:** bloqueo del recurso; la DLQ y las entidades no tienen papelera.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Servicio que publica | Enviar a una cola/tópico | *Azure Service Bus Data Sender* (en la entidad) |
| Servicio que consume | Recibir y liquidar | *Azure Service Bus Data Receiver* (en la entidad o suscripción) |
| Operaciones | Leer/reprocesar la DLQ | *Data Receiver* (sobre la entidad) y proceso con control de cambios |
| Quien administra reglas/entidades con SDK | Crear suscripciones y reglas | *Azure Service Bus Data Owner* (o la plantilla de infraestructura) |
| Quien crea el namespace | Plano de control | *Contributor* acotado al grupo de recursos |
| Event Grid → Service Bus | Entregar eventos | *Data Sender* para la identidad del tópico |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- **Peek-lock**, liquidación explícita y consumidor **idempotente**.
- `MessageId` estable + duplicate detection para productores que reintentan.
- `maxDeliveryCount` finito y DLQ con alerta y runbook.
- Clasificar errores: reintentar lo transitorio, dead-letter lo permanente.
- TTL acorde al valor del mensaje.
- Un tópico por **familia de eventos**, una cola por **comando**; filtros en el servidor.
- Sesiones solo donde el orden importa.
- Outbox cuando la BD y el mensaje deben ser consistentes.
- Límites de concurrencia ajustados a la BD aguas abajo.

**Qué NO hacer**
- Receive-and-delete en procesos que importan.
- Capturar excepciones y no liquidar (mensaje bloqueado hasta expirar).
- Reintentar para siempre un mensaje inválido.
- Una cola gigante con todo mezclado y `if` por tipo en el consumidor.
- Usar Service Bus para streaming masivo o para mover archivos.
- Claves SAS en repositorios o imágenes.
- Prefetch alto con procesos largos.
- Asumir orden sin sesiones, o exactamente-una-vez.
- Crear un cliente por mensaje.

---

## 8. Límites, costos y versiones
- Costos: Standard = cargo base + operaciones (mensajes, lotes, administración); Premium = unidades de mensajería por hora (predecible). Más entidades/operaciones = más costo.
- Límites (tamaño de mensaje, tamaño de entidad, número de entidades, suscripciones por tópico, reglas, duplicate window, lock máximo 5 min): *verifica los vigentes por nivel*.
- Los SDK de Azure para Java implementan reintentos y renovación de bloqueo; las versiones y ajustes cambian: confirma en la doc.
- Spring Cloud Azure ofrece integración propia; comprueba su compatibilidad con tu versión de Spring Boot antes de usarla (aquí se usa el SDK directamente).

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
