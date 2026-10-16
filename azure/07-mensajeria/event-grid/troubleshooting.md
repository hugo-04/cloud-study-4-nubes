# Azure · Event Grid · Troubleshooting

Sigue el evento: **¿lo recibió el tópico? → ¿coincidió con el filtro? → ¿se entregó al destino? → ¿lo procesó el consumidor?** Las métricas indican en qué tramo se pierde.

| Métrica | Significado |
|---|---|
| `PublishSuccessCount` / `PublishFailCount` | Eventos aceptados o rechazados al publicar |
| `MatchedEventCount` | Coincidieron con el filtro de la suscripción |
| `DeliverySuccessCount` | El destino los aceptó |
| `DeliveryAttemptFailCount` | Intentos de entrega fallidos (se reintenta) |
| `DeadLetteredCount` / `DroppedEventCount` | Enviados al dead-letter / descartados |

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Publicar devuelve 401/403 | Sin rol *EventGrid Data Sender* o claves desactivadas | Roles; `local_auth_enabled` | Rol al publicador; usar Entra ID |
| Publicar devuelve 400 | Esquema equivocado (CloudEvents vs Event Grid), `specversion` ausente | Esquema de entrada del tópico | Alinear esquema y cabecera `Content-Type` |
| Publicar devuelve 413 | Evento > 1 MB | Tamaño | Claim Check; solo ids en `data` |
| `PublishSuccessCount` sube pero nada llega | Filtro no coincide | `MatchedEventCount` = 0 | Revisar tipos, `subject` (mayúsculas), filtros avanzados |
| `Matched` sube pero `DeliverySuccess` no | Destino rechaza o no autoriza | Registros de fallos de entrega | Rol de la identidad **del tópico** en el destino; red del destino |
| Falla la creación de suscripción (webhook) | Handshake no respondido | Respuesta del endpoint a la validación | Responder `validationResponse` / cabeceras CloudEvents; ruta accesible |
| Webhook 401 en entrega | Token/clave inválidos | Registros del endpoint | Audiencia de Entra ID; clave de la URL |
| Eventos duplicados | Al menos una vez; timeout del destino | Mismo `id` | Idempotencia; responder rápido |
| Eventos desordenados | Sin orden garantizado | Tiempos y `id` | Diseñar para el desorden; secuencia en `data` |
| Entrega a destino con red privada falla | Falta "servicios de confianza" o identidad | Configuración de red del destino | Identidad administrada + excepción de confianza |
| Dead-letter no se escribe | Falta rol en el contenedor o contenedor inexistente | Roles; nombre | *Storage Blob Data Contributor* a la identidad del tópico |
| Eventos de Key Vault no llegan | Sin fecha de expiración en el secreto o sin suscripción | `exp` del secreto | Definir expiración; revisar la suscripción |
| Bucle de eventos | Consumidor publica eventos que el mismo recibe | Cadena de `type`/`source` | Cortar la cadena con filtros y campo `origen` |
| Costo alto | Reintentos masivos, filtros laxos | Operaciones por suscripción | Filtros estrictos; arreglar destino; limitar reintentos |
| Dominio: evento no llega a un cliente | Tópico hijo inexistente o `source` mal escrito | Tópicos del dominio | Crear el hijo; usar el nombre exacto en `source` |
| Pull: `receive` no devuelve nada | Sin eventos o suscripción equivocada | Nombre de tópico/suscripción | Verificar nombres y que haya publicaciones |
| Pull: eventos se reentregan | Bloqueo vencido o sin `acknowledge` | `DeliveryCount` | Confirmar a tiempo; `renewLocks` |

## Secuencia recomendada
1. ¿La publicación devolvió 2xx? (códigos, `PublishSuccessCount`).
2. ¿`MatchedEventCount` sube? Si no: filtro.
3. ¿`DeliveryAttemptFailCount`? Si sí: destino, roles, red (consulta KQL).
4. ¿El consumidor es idempotente y tolera el desorden?
5. ¿Hay dead-letter y alerta?

KQL en [ejemplos/kql](ejemplos/kql/kql-eventgrid.md).
