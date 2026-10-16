# Azure · Service Bus · Troubleshooting

Un problema de mensajería casi siempre está en uno de cinco sitios: **conexión** (red/DNS/identidad), **productor**, **configuración de la entidad**, **consumidor** o **capacidad**. Sigue el mensaje por su `MessageId`.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `UnauthorizedAccess` / 401 al enviar o recibir | Falta *Data Sender/Receiver* en la entidad; identidad equivocada | Roles de la identidad en esa entidad (no solo en el grupo de recursos) | Asignar el rol correcto en el alcance de la entidad |
| `Unauthorized` con cadena de conexión | `local_auth_enabled=false` | Propiedad del namespace | Usar identidad; o habilitar claves temporalmente |
| Timeout / `ServiceCommunicationProblem` | Red: firewall, Private Endpoint, DNS, puerto 5671 bloqueado | `nslookup`; prueba por WebSockets (443) | DNS privado correcto; permitir 5671 o usar AMQP sobre WebSockets |
| `MessagingEntityNotFound` | Nombre de cola/tópico/suscripción incorrecto | Entidades del namespace | Corregir; crear con IaC |
| `MessageSizeExceeded` | Cuerpo mayor al límite del nivel | Tamaño del mensaje | Claim Check; Premium para mensajes grandes |
| `QuotaExceeded` | Entidad llena (tamaño máximo) | Métrica *Size* de la entidad | Escalar consumidores; subir el tamaño; TTL; revisar productores |
| `ServerBusy` / `ThrottledRequests` | Límite de operaciones del nivel | Métrica `ThrottledRequests` | Lotes, reintentos con espera, Premium |
| Mensajes enviados pero **no aparecen** | *Duplicate detection* con el mismo `MessageId` | `MessageId` del productor | Id único por hecho distinto; ids nuevos en reintentos programados |
| Suscripción **no recibe** nada | Filtro mira otra propiedad/tipo; regla eliminada sin sustituir | Reglas de la suscripción; propiedades del mensaje | Corregir regla; probar con `TrueFilter` |
| Suscripción recibe **todo** | Quedó `$Default` | Lista de reglas | Eliminar o reemplazar `$Default` |
| `MessageLockLost` al completar | Bloqueo vencido (proceso largo, prefetch alto) | Duración del proceso vs `lockDuration` | `maxAutoLockRenewDuration`; prefetch bajo; trocear |
| Mensajes duplicados en el consumidor | Entrega al menos una vez, bloqueo perdido | `DeliveryCount` > 1 | Idempotencia |
| Mensajes que no se consumen y la cola crece | Consumidor caído, sin concurrencia, o bloqueados | `ActiveMessages`, logs del consumidor | Reiniciar/escalar; revisar excepciones sin liquidar |
| Mensajes "desaparecen" tras errores | `receive-and-delete` o `autoComplete` con fallo | Modo de recepción | Peek-lock + liquidación explícita |
| Mensajes en DLQ | `MaxDeliveryCountExceeded`, TTL, dead-letter explícito, error de filtro | `DeadLetterReason` y descripción | Corregir causa y reprocesar |
| `SessionCannotBeLocked` | Otra instancia tiene la sesión | Consumidores de sesión | Esperar/limitar `maxConcurrentSessions`; revisar cierres |
| Sesión con mensajes que nadie procesa | Cola sin sesiones y mensajes con `SessionId` (o al revés) | `requires_session` | Alinear productor y entidad |
| Orden roto | Varios consumidores sin sesiones | Configuración | Sesiones por clave |
| Programados no llegan | Hora en el pasado o cancelados; zona horaria | `ScheduledEnqueueTime` en UTC | Usar UTC; cancelar por número de secuencia |
| Event Grid no entrega a Service Bus | Falta rol *Data Sender* para su identidad, o red cerrada sin "servicios de confianza" | Fallos de entrega en la suscripción de eventos | Rol y excepción de confianza |
| Costo/latencia altos con muchos envíos pequeños | Un envío por mensaje | Operaciones por minuto | `ServiceBusMessageBatch` |
| Premium sin acceso desde Internet | Red privada por diseño | Reglas de red | Private Endpoint y DNS |

## Reprocesar la DLQ (procedimiento)
1. Mira motivos: `DeadLetterReason` agrupados (`MaxDeliveryCountExceeded` suele ser un error de consumidor; `NEGOCIO_INVALIDO` es un dato malo).
2. Corrige la **causa** antes de reenviar (si no, vuelve a fallar).
3. Reenvía a la cola original (con **MessageId nuevo** si hay duplicate detection) y completa el de la DLQ: [código](uso-en-java.md#6-dlq-inspeccionar-y-reprocesar).
4. Lo irrecuperable: registrar y archivar (a Blob) y completar.

## Secuencia recomendada
1. ¿Conecta? (DNS, red, identidad con rol **en la entidad**).
2. ¿El mensaje salió? (`MessageId` en el log del productor; duplicate detection).
3. ¿Dónde está: activo, bloqueado, programado, diferido, DLQ?
4. ¿Por qué falla el consumidor? (excepción, bloqueo perdido, idempotencia).
5. ¿Capacidad? (`ActiveMessages`, `ThrottledRequests`, CPU en Premium).

KQL en [ejemplos/kql](ejemplos/kql/kql-servicebus.md).
