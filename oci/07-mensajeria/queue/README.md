# Oracle OCI · Mensajería · Queue

Cola de mensajes administrada y sin servidores: los productores dejan mensajes, los consumidores los toman, los procesan y los borran. Si un consumidor falla, el mensaje vuelve a ser visible y otro lo reintenta; tras N intentos va a la cola de mensajes muertos (DLQ).

## 1. Qué es

**Analogía:** la ventanilla de pedidos de una cocina con tickets colgados. El mesero cuelga el ticket (mensaje); un cocinero lo toma y lo «esconde» mientras cocina (visibilidad); si se le quema el plato y no lo entrega, el ticket vuelve a colgarse; si un ticket se quema cinco veces, va a la caja de «revisar con el jefe» (DLQ).

```
 Productores ──PutMessages──► Queue "pedidos" (endpoint de mensajes propio)
                                 │ GetMessages (long polling 20 s, visibilidad 120 s)
                                 ▼
                         Consumidores ──► procesan ──► DeleteMessage(receipt)
                                 │ falla → vuelve visible → reintento (deliveryCount++)
                                 └─ deliveryCount > 5 → DLQ
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Cola** | Recurso regional con endpoint de mensajes (`messages_endpoint`) |
| **Mensaje** | Contenido de texto (tamaño máximo pequeño *(verifica)*) + metadatos opcionales (canal) |
| **Visibilidad** | Tiempo en que un mensaje tomado queda oculto para otros |
| **Long polling** | `timeoutInSeconds`: la llamada espera hasta que haya mensajes |
| **Receipt** | Comprobante de la entrega; se usa para borrar o extender visibilidad |
| **`deliveryCount`** | Cuántas veces se entregó |
| **DLQ** | Destino tras `dead_letter_queue_delivery_count` intentos |
| **Retención** | Tiempo máximo que vive un mensaje sin consumir |
| **Canales** | Subdivisión lógica dentro de una cola (por cliente, por tipo) |
| **Cifrado** | Llave de Oracle o propia (CMK) |

### Garantías
- Entrega **al menos una vez**; sin orden estricto global.
- Un mensaje no borrado antes de que venza la visibilidad **se reentrega**.
- Un consumidor lento debe **extender** la visibilidad (`UpdateMessage`).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Desacoplar el checkout del envío de correos y la facturación | **Queue** |
| Trabajo que puede reintentarse y repartirse entre réplicas | **Queue** |
| Varios sistemas deben recibir **el mismo** evento | [Notifications](../notifications/README.md) o [Streaming](../streaming/README.md) |
| Releer el historial o reprocesar desde un punto | [Streaming](../streaming/README.md) |
| Reaccionar a cambios de recursos de OCI | [Events](../events/README.md) |
| Mensajes de varios MB | Claim check con Object Storage |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Al menos una vez** | Puede llegar repetido: consumidor idempotente |
| **Visibilidad** | «Reservado» mientras lo procesas |
| **Backoff** | Esperar más en cada reintento (extendiendo la visibilidad) |
| **DLQ** | Donde terminan los mensajes venenosos |
| **Mensaje venenoso** | Uno que siempre falla |

## 5. Cómo se usa
1. Cola con DLQ y CMK: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Consumidor con long polling, borrado al terminar y *backoff* por visibilidad: [uso en Java](uso-en-java.md).
3. Operación y DLQ: [`ejemplos/cli/queue.sh`](ejemplos/cli/queue.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage queues` | — |
| Productor | — | `use queues` (o permisos finos `QUEUE_PRODUCE`) |
| Consumidor | — | `use queues` (`QUEUE_CONSUME`) |

- Acceso por endpoint privado o puerta de servicios desde subredes privadas.
- Políticas por cola (`target.queue.id`).
- No pongas datos personales completos en el mensaje si basta un identificador.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Borrar **después** de procesar | Borrar al recibir |
| Visibilidad > tiempo típico de proceso | Visibilidad corta que provoca duplicados |
| Long polling (20 s) | Bucle de `GetMessages` sin espera |
| DLQ con alarma | Mensajes venenosos reintentando para siempre |
| Clave de idempotencia en el mensaje | Suponer entrega única |

## 8. Límites, costos y versiones
- **Costo:** por solicitudes (cada 64 KB cuenta como una) con cuota gratuita mensual *(verifica)*.
- **Límites** (verifica): tamaño de mensaje, retención máxima (días), mensajes en vuelo, tasa por cola.
- **Terraform:** `oci_queue_queue`.
- **SDK:** `QueueAdminClient` (gestión), `QueueClient` (mensajes, con `endpoint` de la cola).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
