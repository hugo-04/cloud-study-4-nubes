# Azure · Mensajería · Event Grid (enrutador de eventos)

## 1. Qué es

**Event Grid es el servicio de Azure para publicar "algo pasó" y entregarlo a quien se suscribió, sin que el emisor sepa quién escucha.** Es un enrutador de eventos sin servidores: no administras nada, escala solo y se paga por operación. Recibe eventos de servicios de Azure (Storage, Key Vault, Container Registry…), de tus aplicaciones (temas personalizados) o de socios, los filtra y los empuja (*push*) a destinos como colas, Functions o webhooks. En su variante de **espacios de nombres** también ofrece entrega por **extracción (*pull*)** y un **broker MQTT** para dispositivos.

Analogía: **el sistema de altavoces y avisos de un edificio**. Alguien anuncia "llegó el camión de carga" (evento); cada área (suscripción) pidió que le avisen solo de lo que le interesa (filtro) y por su canal preferido (cola, correo, teléfono). El que anuncia no sabe quién escucha ni qué hará con el aviso.

```
  FUENTES (publicadores)                    EVENT GRID                              DESTINOS (handlers)
  ──────────────────────                    ──────────                              ───────────────────
  Servicios de Azure ──► Tópico del sistema ─┐
   (Storage, Key Vault, ACR, Resource        │      ┌ filtro: tipo + subject + avanzado ─► Service Bus (cola/tópico)
    Groups, App Configuration…)              ├──────┤
  Tu aplicación ───────► Tópico personalizado┤      ├ filtro ...                         ─► Azure Function
  Tu SaaS (multi-cliente) ► Dominio ─────────┤      ├ filtro ...                         ─► Webhook (tu API)
  Socios (Auth0, SAP…) ──► Tópico de socio ──┘      ├ filtro ...                         ─► Storage Queue / Event Hubs
                                                    └ si no se pudo entregar              ─► Dead-letter (contenedor de Blob)

  Variante "Namespaces": Tópico de namespace ──► suscripciones con entrega PULL (receive/ack) o PUSH   |  Broker MQTT para IoT
```

---

## 2. Cómo funciona por dentro

### 2.1 Familias y piezas

| Elemento | Qué es | Para qué |
|---|---|---|
| **Tópico del sistema** (*system topic*) | Publicador = un servicio de Azure | Reaccionar a lo que pasa en Azure (blob creado, secreto por vencer, imagen publicada) |
| **Tópico personalizado** (*custom topic*) | Un punto de publicación tuyo (`https://<topic>.<region>-1.eventgrid.azure.net/api/events`) | Eventos de dominio de tus microservicios |
| **Dominio** (*domain*) | Un tópico "padre" con miles de tópicos hijos | SaaS multi-cliente: un tópico por cliente con permisos propios |
| **Tópico de socio** (*partner topic*) | Eventos de un SaaS externo hacia tu suscripción | Integraciones con terceros |
| **Suscripción de eventos** | Regla: filtro + destino + reintentos + dead-letter | Quién recibe qué |
| **Espacio de nombres** (*namespace*) | Contenedor con **tópicos de namespace** (CloudEvents, pull o push) y **broker MQTT** | Control de consumo tipo broker; IoT |

### 2.2 Evento, esquema y sobre
Un evento es un **hecho ya ocurrido** (no una orden): `pedido.creado`, `secreto.por.vencer`. Esquemas:

| Esquema | Notas |
|---|---|
| **Event Grid schema** | Propio de Azure: `id, topic, subject, eventType, eventTime, data, dataVersion` |
| **CloudEvents v1.0** | Estándar abierto: `id, source, type, subject, time, specversion, data`. **Recomendado**; obligatorio en tópicos de namespace |
| **Esquema de entrada personalizado** | Mapeas tus campos a los de Event Grid (tópicos personalizados) |

CloudEvents mínimo de un microservicio:
```json
{
  "specversion": "1.0",
  "id": "evt-8f1c2d",
  "source": "/servicios/pedidos",
  "type": "pe.modalima.pedido.creado",
  "subject": "pedidos/1001",
  "time": "2026-10-16T16:02:11Z",
  "datacontenttype": "application/json",
  "data": { "pedidoId": "1001", "clienteId": "u-42", "region": "PE", "total": 150.0 }
}
```
Ejemplos en [ejemplos/eventos](ejemplos/eventos/).

### 2.3 Entrega, reintentos y dead-letter

| Tema | Comportamiento (verifica límites vigentes) |
|---|---|
| Garantía | **Al menos una vez**; sin orden garantizado |
| Éxito | Webhook: respuesta 2xx; Service Bus/Queue/Event Hubs: mensaje aceptado |
| Reintentos | Retroceso exponencial hasta ~30 intentos o 24 h (configurables: intentos y tiempo de vida) |
| Errores "definitivos" | Algunos códigos (p. ej. 400, 413 en webhook) van directo a dead-letter |
| Dead-letter | **Opcional**: contenedor de Blob; sin él, el evento se descarta al agotar reintentos |
| Lotes | Puede agrupar varios eventos en una llamada (`max events per batch`) |
| Latencia | Normalmente segundos |
| Tamaño | Hasta 1 MB por evento (se factura por tramos de 64 KB) |
| Handshake | Los webhooks se **validan** al crear la suscripción (ver [Eventos de Blob](../../06-storage/eventos-blob/README.md#25-webhooks-el-apretón-de-manos-handshake)) |

### 2.4 Destinos (handlers)

| Destino | Autenticación de entrega | Cuándo |
|---|---|---|
| **Service Bus** (cola/tópico) | Identidad administrada (*Data Sender*) | Procesamiento confiable con DLQ y reintentos de negocio |
| **Storage Queue** | Identidad (*Queue Data Message Sender*) | Cola simple y barata |
| **Event Hubs** | Identidad (*Event Hubs Data Sender*) | Pasar eventos a un flujo/stream |
| **Azure Functions** | Integrado (disparador Event Grid) | Código corto y sin servidor |
| **Webhook** | Handshake + Entra ID o clave en la URL | Tu API, Logic Apps, terceros |
| **Hybrid Connections** | Relay | Destino local sin abrir puertos |

### 2.5 Filtros
| Filtro | Ejemplo |
|---|---|
| **Tipos de evento** | `pe.modalima.pedido.creado`, `Microsoft.KeyVault.SecretNearExpiry` |
| **Subject empieza/termina por** | `pedidos/PE/`, `.csv` |
| **Avanzados** | `data.region` StringIn [`PE`, `CL`]; `data.total` NumberGreaterThan 100; `data.items` IsNotNull; operadores de cadena, número, booleano y nulos |

Hay límites (cantidad de filtros y de valores por suscripción) y el *subject* distingue mayúsculas por defecto: *verifica los vigentes*.

### 2.6 Autenticación de publicadores
- **Microsoft Entra ID** con el rol *EventGrid Data Sender* (recomendado).
- Claves de acceso o firma SAS del tópico (desactívalas con `local_auth_enabled = false`).

### 2.7 Event Grid frente a Service Bus y Event Hubs

| Pregunta | Event Grid | Service Bus | Event Hubs |
|---|---|---|---|
| ¿Qué transporta? | **Eventos** discretos ("pasó X") | **Mensajes** con contrato y trabajo por hacer | **Flujo** de registros (telemetría, logs) |
| Modelo | Push (y pull en namespaces) | Pull con bloqueo | Pull de un log por partición |
| Reintentos/DLQ | Sí (básico) | Sí (completo, por mensaje) | No (tú manejas offsets) |
| Orden | No | Sesiones | Por partición |
| Reproducir el pasado | No | No | Sí (retención) |
| Volumen | Alto | Medio | Muy alto |
| Típico | Reaccionar a Azure, fan-out ligero | Comandos entre microservicios | Streaming, Kafka |

Patrón común: **Event Grid → Service Bus**: Event Grid enruta y filtra, Service Bus garantiza el procesamiento.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Reaccionar a Azure**: blob creado → procesar; secreto por vencer → rotar; imagen publicada → desplegar; recurso creado → etiquetar/auditar; cambio de configuración → recargar.
- **Eventos de dominio** de tus microservicios con fan-out a varios interesados.
- **SaaS multi-cliente** con dominios (un tópico por cliente).
- **Automatización sin servidores** (Functions, Logic Apps).
- **IoT** con el broker MQTT.

| NO lo uses si | Alternativa |
|---|---|
| Necesitas colas con orden, sesiones, transacciones y DLQ por mensaje | **Service Bus** |
| Necesitas reproducir el histórico o procesar millones/segundo | **Event Hubs** / Kafka |
| Necesitas un comando con respuesta (RPC) | Llamada directa o cola con `ReplyTo` |
| Necesitas orden estricto | Service Bus con sesiones o Event Hubs por partición |
| Los eventos llevan megabytes | Claim Check |
| Exactamente una vez | Idempotencia en el consumidor |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Evento** | Un hecho ya ocurrido | `pedido.creado` |
| **Tópico** | Punto donde se publica | `evgt-pedidos` |
| **Suscripción** | Regla de entrega | filtro + cola |
| **Handler** | Destino del evento | Service Bus |
| **CloudEvents** | Estándar de sobre de eventos | `specversion: 1.0` |
| **Dominio** | Tópico con miles de tópicos hijos | Un hijo por cliente |
| **Pull / Push** | El consumidor pide / el servicio entrega | `receive` / webhook |
| **Dead-letter** | Almacén de eventos no entregados | Contenedor de Blob |
| **Handshake** | Validación de un webhook | `validationCode` |
| **MQTT** | Protocolo ligero para dispositivos | Sensores |
| **Identidad de entrega** | Identidad con la que Event Grid entrega | *System-assigned* del tópico |

---

## 5. Cómo se usa

1. **Elige la fuente:** tópico del sistema (Azure), personalizado (tu código) o dominio (multi-cliente).
2. **Define el contrato del evento:** CloudEvents, `type` con prefijo de dominio (`pe.modalima.pedido.creado`), `subject` jerárquico, `data` pequeño con ids (no la entidad completa).
3. **Crea la suscripción** con filtros, destino, identidad de entrega, reintentos y dead-letter.
4. **Da permisos** a la identidad (del tópico) en el destino.
5. **Publica** con identidad (*EventGrid Data Sender*) usando el SDK.
6. **Consume** con un consumidor idempotente (`id` del evento).
7. **Observa:** métricas (publicados, coincidentes, entregados, fallidos, dead-letter) y registros de diagnóstico.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/event-grid.sh) · [KQL](ejemplos/kql/kql-eventgrid.md) · [eventos de ejemplo](ejemplos/eventos/) · [filtros](ejemplos/eventos/filtros-avanzados.md).

---

## 6. Seguridad
- **Publicar y suscribirse con Entra ID**; desactiva claves del tópico (`local_auth_enabled = false`).
- **Entrega con identidad administrada** a los destinos; sin cadenas de conexión.
- **Mínimo privilegio:** el publicador solo *Data Sender* del tópico; la identidad de entrega solo *enviar* al destino.
- **Webhooks:** HTTPS, validación, autenticación con Entra ID (audiencia de tu app).
- **Red:** Private Endpoint para tópicos y dominios, reglas de IP, y "servicios de confianza" para entregas con identidad a destinos protegidos.
- **Datos:** los eventos no deben llevar datos personales; ids y metadatos.
- **Control de suscripciones:** crear una suscripción puede desviar eventos: restringe *EventGrid EventSubscription Contributor*.
- **Dead-letter** en un contenedor privado con retención.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Servicio que publica (tópico/dominio) | Enviar eventos | *EventGrid Data Sender* (en el tópico) |
| Consumidor de namespace (pull) | Recibir y confirmar | *EventGrid Data Receiver* (en el tópico del namespace) |
| Quien crea suscripciones | Escribir suscripciones | *EventGrid EventSubscription Contributor* |
| Quien administra tópicos/dominios | Plano de control | *EventGrid Contributor* |
| Identidad del tópico → Service Bus | Entregar | *Azure Service Bus Data Sender* |
| Identidad del tópico → Storage Queue | Entregar | *Storage Queue Data Message Sender* |
| Identidad del tópico → Event Hubs | Entregar | *Azure Event Hubs Data Sender* |
| Identidad del tópico → dead-letter | Escribir blobs | *Storage Blob Data Contributor* |
| Dispositivos MQTT | Publicar/suscribirse a espacios de tópicos | *EventGrid TopicSpaces Publisher/Subscriber* o autenticación por certificado |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- CloudEvents con `type` versionado y `data` mínimo.
- Filtros estrictos (tipo + subject) para pagar y procesar solo lo necesario.
- Identidad administrada en entrega y publicación.
- Dead-letter siempre en producción; reintentos acordes al negocio.
- Consumidores **idempotentes** y tolerantes al desorden.
- **Event Grid → Service Bus** cuando el procesamiento necesita garantías de negocio.
- Pruebas con eventos de ejemplo contra tu webhook/consumidor.

**Qué NO hacer**
- Usarlo como cola de trabajo con orden y transacciones.
- Meter la entidad completa o datos personales en `data`.
- Asumir una sola entrega o un orden.
- Dejar webhooks sin autenticación.
- Suscribirse a todo "por si acaso".
- Crear un bucle: el consumidor publica eventos que él mismo recibe.
- Compartir claves del tópico entre equipos.

---

## 8. Límites, costos y versiones
- Costo por **operaciones** (publicar, entregar, filtros avanzados, reintentos, MQTT) con cuota gratuita mensual; los espacios de nombres tienen su propia estructura de precios. *Verifica precios vigentes.*
- Límites: tamaño de evento, rendimiento por tópico, número de suscripciones, filtros, retención en pull. *Verifica en la doc.*
- Funciones en evolución (tópicos de namespace, MQTT, pull): confirma disponibilidad y SDK en tu región y versión.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
