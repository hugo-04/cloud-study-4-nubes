# Azure · Storage Queues · Troubleshooting

Sigue el flujo: **¿llega a la cola? → ¿lo recibe el trabajador? → ¿termina y borra? → ¿qué pasa si falla?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `403 AuthorizationPermissionMismatch` | Falta rol de datos de cola o se asignó en el ámbito incorrecto | IAM de la cuenta/cola; `StorageQueueLogs` | *Message Sender* para enviar, *Message Processor* para recibir/borrar; esperar propagación |
| `403 KeyBasedAuthenticationNotPermitted` | La cuenta tiene claves desactivadas y usas cadena de conexión | Configuración de la cuenta | Usar `DefaultAzureCredential` y roles |
| `403` desde una red concreta | Firewall de la cuenta o falta Private Endpoint | Reglas de red | Permitir la red o usar el Private Endpoint + DNS `privatelink.queue.core.windows.net` |
| `RequestBodyTooLarge` / `MessageTooLarge` | Mensaje > 64 KB (con Base64, menos) | Tamaño | Claim Check |
| `404 QueueNotFound` | Cola inexistente o nombre con mayúsculas | Lista de colas | Crearla (Terraform/CLI); nombres en minúsculas |
| `MessageNotFound` / `PopReceiptMismatch` al borrar | Venció la invisibilidad y otro lo recibió, o usaste un `popReceipt` viejo tras `update` | Orden de operaciones; `popReceipt` de la última respuesta | Aumentar visibilidad; renovar; usar el último `popReceipt`; idempotencia |
| Mensajes procesados dos veces | Visibilidad menor que el tiempo de proceso; caída antes del `delete` | `dequeueCount` > 1 | Visibilidad mayor, renovación, idempotencia |
| Mensajes que nunca salen de la cola | Trabajadores caídos, error antes de borrar, visibilidad muy larga | Largo de cola; logs | Revisar trabajadores; tiempos |
| El mensaje desaparece sin procesarse | TTL vencido | TTL al enviar | TTL mayor o `-1` si procede |
| Orden "raro" | No hay garantía FIFO | — | Diseñar sin depender del orden; Service Bus con sesiones si es necesario |
| `receive` devuelve vacío pero hay mensajes | Están invisibles (otro trabajador) o diferidos | `peek`; `dequeueCount`, `nextVisibleOn` | Esperar o revisar tiempos |
| Costo alto por operaciones | Sondeo continuo sin espera con cola vacía | Operaciones/seg en métricas | Pausa de 1–5 s cuando está vacía; escalar con KEDA |
| Throttling `ServerBusy` / 503 | Superas el rendimiento de la cola/cuenta | Errores en `StorageQueueLogs` | Repartir en varias colas, retroceso, lotes de 32 |
| Function no procesa mensajes | Codificación Base64 distinta, identidad sin permisos, conexión por identidad mal nombrada | Logs de la Function; `-poison` | `messageEncoding`, `ColaStorage__queueServiceUri`, roles |
| Se llena la cola de veneno | Error sistemático (cambió el formato) | Contenido y motivo | Corregir, reencolar tras arreglar, o descartar |
| Eventos de Blob no llegan a la cola | Falta rol de entrega de Event Grid o la suscripción no coincide | Métricas de Event Grid | *Storage Queue Data Message Sender* a la identidad del tópico; filtros |

## Secuencia recomendada
1. **Acceso:** rol, red, nombre de cola, endpoint.
2. **Envío:** respuesta del `put`, tamaño, TTL.
3. **Recepción:** `peek`, `dequeueCount`, `nextVisibleOn`.
4. **Procesamiento:** tiempo real vs. visibilidad; idempotencia.
5. **Fallos:** retroceso, umbral y cola de veneno con alerta.
6. **Escalado:** largo de cola y réplicas.

KQL en [ejemplos/kql](ejemplos/kql/kql-storage-queues.md); consola en [ejemplos/cli](ejemplos/cli/storage-queues.sh).
