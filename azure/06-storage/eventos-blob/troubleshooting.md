# Azure · Eventos de Blob · Troubleshooting

Sigue el camino del evento: **¿lo publicó la cuenta? → ¿coincidió con el filtro? → ¿se entregó al destino? → ¿lo procesó el consumidor?** Las métricas del tópico del sistema te dicen en cuál tramo se pierde.

| Métrica del tópico/suscripción | Qué significa |
|---|---|
| *Published Events* | La cuenta publicó el evento |
| *Matched Events* | Coincidió con el filtro de la suscripción |
| *Delivery Succeeded Events* | El destino lo aceptó |
| *Delivery Failed Events* | El destino lo rechazó (se reintenta) |
| *Dead Lettered Events* | Se envió al dead-letter |
| *Dropped Events* | Se descartó (sin dead-letter) |

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| No llega ningún evento | Filtro mal escrito, tipo de evento incorrecto | *Published* sube pero *Matched* = 0 | Revisa mayúsculas/minúsculas y el prefijo del *subject*; prueba sin filtro |
| *Published* = 0 | La acción no genera evento (p. ej. subida incompleta de bloques), tipo de cuenta sin soporte | Operación realizada; versión de cuenta | Confirma la subida (`PutBlockList`); usa cuentas StorageV2/Blob |
| Falla al **crear** la suscripción (webhook) | Handshake rechazado, endpoint inaccesible, 401/404 | Respuesta del endpoint a la validación | Responde `validationResponse`; ruta pública con HTTPS; sin autenticación que bloquee la validación |
| `Delivery Failed` con 401/403 al webhook | Token de Entra ID no aceptado o clave incorrecta | Registros del endpoint | Audiencia/app registrada; clave en la URL |
| `Delivery Failed` a Service Bus/Queue | Falta rol de envío para la identidad del tópico | Roles en el destino; registros de fallos | *Azure Service Bus Data Sender* / *Storage Queue Data Message Sender* a la identidad **del tópico** |
| Entrega a destino con red privada falla | Destino no admite servicios de confianza / sin identidad | Configuración de red del destino | Premium + excepción de confianza + entrega con identidad |
| Eventos duplicados | Reintentos por timeout o entrega al menos una vez | Mismo `id` en el consumidor | Idempotencia por `id`; responder rápido |
| Eventos desordenados | Sin garantía de orden | `sequencer` de cada evento | Descarta `sequencer` menor por blob |
| Llegan **miles** de eventos inesperados | Bucle (resultado en la misma ruta), lifecycle, otro proceso | `subject` y `api` de los eventos | Separar rutas; filtros; ignorar `api` no deseado |
| Evento llega pero el blob da **404** | Se borró (lifecycle/usuario) antes de procesar | `BlobDeleted` posterior; soft delete | Coordinar retenciones; tratar 404 como "ya no existe" |
| Evento llega pero lectura da **412** | `If-Match` con ETag antiguo: el blob cambió | ETag actual vs evento | Espera el evento más reciente; descarta el viejo |
| Evento llega pero lectura da **403** | El consumidor no tiene *Blob Data Reader* o la red lo bloquea | Roles y firewall de la cuenta | Rol y red del consumidor |
| Eventos tardan | Reintentos por destino caído, cuello de botella del consumidor | Métricas de entrega y profundidad de la cola | Escalar consumidores; revisar el destino |
| Eventos perdidos tras una caída larga | Sin dead-letter y TTL agotado | *Dropped Events* | Configura dead-letter y reintentos ampliados |
| Dead-letter no se escribe | Falta rol en el contenedor o el contenedor no existe | Roles de la identidad; nombre del contenedor | *Storage Blob Data Contributor* al tópico |
| Sube el costo de Event Grid | Muchos eventos irrelevantes y reintentos | Operaciones por suscripción | Filtros más estrictos; arreglar el destino |

## Reprocesar el dead-letter
1. Listar los blobs del contenedor `deadletter`: cada uno contiene los eventos con el motivo (`deadLetterReason`) y el último error de entrega.
2. Corregir la causa (permisos, endpoint, consumidor).
3. Reenviar los eventos al destino (o a una cola de reproceso) con un script o Function; deben ser idempotentes por `id`.
4. Archivar o borrar el blob de dead-letter.

## Secuencia recomendada
1. ¿La operación genera evento? (`api` y tipo de cuenta).
2. ¿*Published* sube? ¿*Matched* sube? Si no, filtro.
3. ¿*Delivery Failed* sube? Mira el registro de fallos de entrega (KQL) y los roles.
4. ¿El consumidor es idempotente y tolera desorden?
5. ¿Hay dead-letter y alerta?

KQL en [ejemplos/kql](ejemplos/kql/kql-eventgrid.md).
