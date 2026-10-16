# Azure · 07 Mensajería

Cómo se hablan los microservicios **sin llamarse directamente**. Cuatro servicios, cuatro formas de pasar información, y una regla: **elige por lo que necesita el mensaje, no por moda**.

| Pieza | Qué transporta | Analogía | La eliges para |
|---|---|---|---|
| [Service Bus](service-bus/README.md) | **Mensajes** (comandos y trabajo por hacer) con garantías | Oficina de correos con acuse de recibo | Pedidos, pagos, facturación: entrega confiable, DLQ, orden por sesión, duplicados, tópicos |
| [Event Grid](event-grid/README.md) | **Eventos** ("pasó algo") enrutados y filtrados | Sistema de altavoces del edificio | Reaccionar a Azure (blob, secretos, ACR) y fan-out ligero de eventos de dominio |
| [Event Hubs (Kafka)](event-hubs-kafka/README.md) | **Flujo** masivo de registros que se puede releer | Cinta transportadora con carriles y marcadores | Telemetría, clics, CDC, logs, aplicaciones Kafka |
| [Storage Queues](storage-queues/README.md) | **Tareas** simples en una bandeja barata | Bandeja de tarjetas en la cocina | Trabajos en segundo plano, buffers, volumen alto sin funciones avanzadas |

## Árbol de decisión

```
¿Es un COMANDO que debe ejecutarse sí o sí (pagar, facturar, despachar)?
   ├─ ¿Necesitas orden por cliente, duplicados, DLQ con motivo, tópicos o transacciones?  → Service Bus
   └─ ¿Es una tarea simple, sin esas garantías, y quieres lo más barato?                 → Storage Queue

¿Es un HECHO que ya ocurrió y a varios les puede interesar?
   ├─ ¿Viene de un servicio de Azure o necesitas filtros por tipo/subject y entrega a webhook/Function? → Event Grid
   └─ ¿Necesitas que el consumidor lo lea a su ritmo y garantías de procesamiento?       → Event Grid → Service Bus

¿Es un FLUJO enorme de datos (miles a millones por segundo) que varios analizan, y quieres poder RELEER?
   └─ → Event Hubs (con cliente nativo o Kafka)
```

## Comparativa

| Característica | Service Bus | Event Grid | Event Hubs | Storage Queue |
|---|---|---|---|---|
| Modelo | Cola / tópico con bloqueo y liquidación | Enrutador de eventos (push; pull en namespaces) | Log particionado con retención | Cola simple |
| Entrega | Al menos una vez (o como mucho una vez) con DLQ | Al menos una vez | Al menos una vez | Al menos una vez |
| Orden | Sesiones (FIFO por clave) | No | Por partición | No |
| Reintentos / DLQ | Completo y nativo | Básico (reintentos + dead-letter a Blob) | Manual (tú) | Manual (`-poison`) |
| Reproducir lo pasado | No | No | **Sí** (retención) | No |
| Detección de duplicados | Sí | No | No | No |
| Tamaño del mensaje | 256 KB (Standard) / 100 MB (Premium) | 1 MB | ~1 MB | 64 KB |
| Volumen | Medio-alto | Alto | **Muy alto** | Alto |
| Consumidor | Lee con bloqueo | Recibe (push) o pide (pull) | Lee con offset por grupo | Lee con visibilidad |
| Protocolos | AMQP, HTTPS | HTTPS, MQTT | AMQP, **Kafka**, HTTPS | HTTPS |
| Costo | Medio | Bajo (por operación) | Por capacidad | **Muy bajo** |
| Típico | Comandos entre microservicios | Reaccionar y notificar | Telemetría, Kafka | Trabajos en segundo plano |

## Garantías que debes asumir siempre
- **Al menos una vez:** habrá repetidos → **consumidor idempotente** (clave única por `eventId`/`MessageId`).
- **Orden limitado:** solo donde el servicio lo garantiza (sesión, partición) → diseña sin depender de él cuando puedas.
- **Mensajes venenosos:** todo consumidor necesita plan de salida (DLQ, event hub de errores, cola de veneno) **y alerta**.
- **Mensaje pequeño:** ids y referencias; lo grande va a Blob ([Claim Check](../06-storage/claim-check/README.md)).

## Patrones que se repiten

| Patrón | Cadena | Cuándo |
|---|---|---|
| **Event Grid → Service Bus** | Evento → Event Grid filtra → cola/tópico → procesador | Reaccionar a eventos de Azure con garantías de procesamiento |
| **Outbox transaccional** | Transacción de BD escribe dato + fila "outbox" → publicador envía a Service Bus | Evitar dobles escrituras entre base y bus |
| **Claim Check** | Blob + ticket (cola/bus) → consumidor lee con identidad | Archivos grandes entre servicios |
| **CDC → Event Hubs** | Base → Debezium → event hub → lago/buscador | Replicar cambios sin consultar la base |
| **Telemetría → Capture** | Dispositivos → event hub → Capture → lago | Analítica e historial barato |
| **Cola de trabajo** | API → Storage Queue → N trabajadores (KEDA) | Segundo plano escalable |
| **Reintentos con retroceso** | Fallo → reprogramar con espera creciente → veneno tras N intentos | Servicios externos inestables |
| **Saga** | Pasos con compensaciones coordinados por mensajes | Transacciones distribuidas (ver patrones de microservicios) |

## Reglas transversales de seguridad
- **Entra ID antes que claves:** `local_auth_enabled = false` en Service Bus, Event Grid y Event Hubs; `shared_access_key_enabled = false` en Storage.
- **Roles por entidad** (cola, tópico, event hub), con productor y consumidor separados.
- **Private Endpoint** con su zona DNS: `privatelink.servicebus.windows.net` (Service Bus y Event Hubs), `privatelink.eventgrid.azure.net`, `privatelink.queue.core.windows.net`.
- **Entrega con identidad administrada** entre servicios (Event Grid → Service Bus).
- **Alertas** en DLQ, event hub de errores y cola de veneno.

## Cómo se relacionan con otros capítulos
- [Storage · Claim Check](../06-storage/claim-check/README.md) y [Eventos de Blob](../06-storage/eventos-blob/README.md).
- [IAM · Managed Identity](../02-iam/managed-identity/README.md): acceso sin claves.
- [Red · Private Endpoint y DNS](../01-red/private-endpoint-dns/README.md).
- [Compute · Function Apps](../04-compute/function-apps/README.md): disparadores de Service Bus, Event Hubs, Event Grid y colas.
- [Compute · AKS](../04-compute/aks/README.md): KEDA para escalar consumidores.
- Gobierno *(por escribir)*: políticas que fuerzan red privada y desactivan claves.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus), ejemplos (CLI, Terraform, KQL y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
