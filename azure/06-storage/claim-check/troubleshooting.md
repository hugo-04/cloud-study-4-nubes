# Azure · Claim Check · Troubleshooting

Un problema de Claim Check casi siempre es de uno de estos cinco lugares: **subida**, **evento/publicación**, **cola**, **lectura del blob** o **procesamiento**. Sigue el ticket por todos.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| El blob se subió pero no hay mensaje | Evento no entregado / filtro mal / el cliente no confirmó | Suscripción de Event Grid y su filtro; métricas de entrega; endpoint de confirmación | [Eventos de blob](../eventos-blob/troubleshooting.md); reintentos del cliente; reconciliación |
| Hay mensaje pero el blob no existe | Borrado por ciclo de vida o por el productor; nombre incorrecto | `az storage blob exists`; soft delete | Alinear retenciones; restaurar; DLQ con motivo |
| Mensaje en la **DLQ** | `maxDeliveryCount` agotado, TTL vencido, error explícito | Motivo (`DeadLetterReason`) del mensaje | Corregir causa y **reprocesar** desde la DLQ; ver motivos |
| Consumidor recibe **403** al leer el blob | Falta *Storage Blob Data Reader*; firewall/Private Endpoint; SAS vencida | Roles; red; `AuthenticationType` en `StorageBlobLogs` | Rol correcto; red/DNS; ticket sin SAS |
| **404** al leer con `versionId` | Versión borrada (política de versiones) | Lista de versiones | Retener versiones ≥ vida del ticket |
| Hash distinto al del ticket | Blob modificado o subida incompleta | Comparar `sha256`, `etag`, `versionId` | Leer por versión; rechazar y *dead-letter* con `HASH_INVALIDO` |
| Mensajes procesados **dos veces** | Bloqueo vencido, duplicados del broker, reintentos | `DeliveryCount`, tiempos de proceso | Idempotencia; renovar bloqueo; duplicate detection |
| Mensajes que **nunca** se completan | Excepción sin manejar, `autoComplete` mal usado | Logs del consumidor | Completar/abandonar explícitamente en cada ruta |
| `MessageLockLost` | Proceso más largo que el bloqueo | Duración vs `lockDuration` | `maxAutoLockRenewDuration`; procesar en trozos |
| `ServiceBusException: MessageSizeExceeded` | Ticket demasiado grande (cuerpo con datos) | Tamaño del mensaje | Quitar datos del ticket; solo referencias |
| `QuotaExceeded` / cola llena | Consumo más lento que la producción | Métricas de la cola | Escalar consumidores (KEDA); TTL; alertas |
| Consumidor no recibe nada | Suscripción/cola equivocada, sesión requerida, `local_auth` | Nombre, sesiones, permisos | Corregir configuración; rol *Data Receiver* |
| Event Grid no entrega a Service Bus | Identidad sin *Data Sender* | Entregas fallidas en la suscripción | Dar el rol a la identidad del tópico del sistema |
| Lentitud al procesar | Descarga secuencial, BD con inserciones fila a fila | Perfil de tiempos | Lotes, hilos, descarga por rangos, índices |
| `OutOfMemoryError` | Archivo completo en memoria | Pila del error | *Streaming* |
| Costos de blob crecen | Huérfanos y procesados sin limpiar | Inventario por etiqueta | Ciclo de vida por `estado`; reconciliación |
| DLQ crece y nadie se entera | Sin alertas | Métrica *Dead-lettered messages* | Alerta y runbook de reproceso |

## Reprocesar la DLQ (idea)
1. Lee de `<cola>/$deadletterqueue` con un receptor dedicado.
2. Si la causa ya se corrigió, **reenvía** el mensaje a la cola original (nuevo `MessageId` o el mismo si quieres que aplique la detección de duplicados).
3. Si es irrecuperable, registra el caso y archiva/borra.

## Secuencia recomendada
1. Toma el `mensajeId`/`correlacionId` y búscalo en los logs del productor y del consumidor.
2. ¿Existe el blob? ¿Qué versión y hash tiene?
3. ¿Está el mensaje en la cola, en entrega o en la DLQ? ¿Con qué motivo?
4. ¿La identidad del consumidor puede leer el blob (rol y red)?
5. ¿El consumidor es idempotente y completa/abandona en todas las rutas?

KQL de Service Bus (con diagnósticos activos):
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SERVICEBUS" and Category == "OperationalLogs"
| where TimeGenerated > ago(1h) and (Status_s != "Succeeded")
| project TimeGenerated, OperationName, Status_s, EventName_s, ResourceId
```
