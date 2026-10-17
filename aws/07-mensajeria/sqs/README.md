# AWS · Mensajería · Amazon SQS (colas)

**SQS (Simple Queue Service) es una cola de mensajes administrada: un productor deja mensajes, un consumidor los toma cuando puede, y el servicio los guarda de forma duradera mientras tanto.** Desacopla quien pide un trabajo de quien lo hace: si el consumidor es lento o se cae, los mensajes esperan; si hay un pico, la cola lo absorbe.

## 1. Qué es

**Analogía:** el **buzón de pedidos de una cocina**. El mesero (productor) deja la comanda y sigue atendiendo; el cocinero (consumidor) toma la siguiente cuando termina. Si el cocinero deja una comanda a medias, vuelve al buzón y otro la toma.

```
 Productor ──SendMessage──► [ COLA ] ──ReceiveMessage──► Consumidor
                               ▲  │  (el mensaje queda "invisible" mientras se procesa)
                               │  └─ si no se borra a tiempo, reaparece
                               │
          tras N intentos ──► [ DLQ ]  (cola de mensajes fallidos)
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Estándar** | Rendimiento casi ilimitado; entrega **al menos una vez**; orden **no** garantizado; puede haber duplicados |
| **FIFO** | Orden por **grupo de mensajes** (`MessageGroupId`) y **deduplicación** (ventana de 5 min); menor rendimiento por API (se amplía con lotes y alto rendimiento; verifica) |
| **Visibility timeout** | Al recibir un mensaje queda oculto N segundos; si no lo borras, reaparece |
| **Long polling** | `WaitTimeSeconds` hasta 20 s: menos llamadas vacías y menos costo |
| **DLQ + redrive** | Tras `maxReceiveCount` recepciones, el mensaje pasa a otra cola; luego se puede devolver a la original |
| **Retraso** | `DelaySeconds` (cola o mensaje) hasta 15 min |
| **Retención** | 1 minuto a 14 días (por defecto 4 días) |
| **Tamaño** | Hasta 1 MiB por mensaje *(verifica; antes 256 KiB)*; más grande → [Claim Check](../../06-storage/claim-check/README.md) |
| **Lotes** | Enviar/recibir/borrar hasta 10 mensajes por llamada |
| **Atributos** | Metadatos tipados del mensaje (sin tocar el cuerpo) |
| **Cifrado** | SSE-SQS por defecto o SSE-KMS con tu clave |
| **Política de cola** | Quién puede enviar/recibir (SNS, S3, EventBridge, otras cuentas) |
| **Colas justas (*fair queues*)** | En colas estándar, reparten el consumo entre grupos (inquilinos) para que uno ruidoso no ahogue a los demás *(verifica disponibilidad)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Trabajo en segundo plano (correos, PDF, imágenes) | **SQS estándar** |
| Absorber picos delante de una base o API frágil | **SQS** |
| Orden estricto por cliente/pedido | **SQS FIFO** con `MessageGroupId` = pedido |
| Un evento para muchos consumidores | **SNS → SQS** o EventBridge (no una cola compartida) |
| Streaming con repetición y varios lectores del mismo historial | **Kinesis / Kafka** (SQS borra al consumir) |
| Respuesta inmediata al usuario | **No** (SQS es asíncrono) |
| Mensajes enormes | **Claim Check** |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Receipt handle** | Recibo de ese intento de recepción; se usa para borrar |
| **ApproximateReceiveCount** | Cuántas veces se entregó el mensaje |
| **At-least-once** | Puede llegar más de una vez |
| **MessageGroupId** | Dentro de un grupo, orden estricto (FIFO) |
| **DeduplicationId** | Mismo valor en 5 min = un solo mensaje (FIFO) |
| **Poison message** | Mensaje que siempre falla |
| **Backoff** | Esperar cada vez más entre reintentos |

## 5. Cómo se usa
1. Crea cola + DLQ + política + cifrado: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Productor: lotes de 10, reintento de los que fallaron, atributos con el tipo y la correlación.
3. Consumidor: long polling, procesar, **borrar solo al terminar**, idempotente.
4. Visibility timeout ≥ 6× el tiempo de procesamiento típico (o `ChangeMessageVisibility`).
5. DLQ con alarma y procedimiento de *redrive*: [`ejemplos/cli/sqs.sh`](ejemplos/cli/sqs.sh).
6. Lambda como consumidor: mapeo de eventos con lotes y fallos parciales ([Lambda](../../04-compute/lambda/README.md)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Productor** | — | `sqs:SendMessage` a la cola |
| **Consumidor** | — | `sqs:ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility`, `GetQueueAttributes` |
| **Servicios que publican (SNS, S3, EventBridge)** | — | Política de cola con `aws:SourceArn` |
| **Pipeline** | `sqs:CreateQueue`, `SetQueueAttributes`, `TagQueue` | — |

- **Cifra** (SSE-SQS o KMS); con KMS, los productores y servicios necesitan `kms:GenerateDataKey`.
- **TLS obligatorio** con condición `aws:SecureTransport` en la política.
- **Sin `Principal: "*"`**; usa `SourceArn`/`SourceAccount`.
- **Datos personales:** no pongas secretos en el cuerpo; usa referencias.
- Los mensajes de la DLQ contienen datos reales: misma protección que la cola principal.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Consumidores idempotentes | Asumir entrega exactamente una vez |
| DLQ con `maxReceiveCount` 3–5 y alarma | Sin DLQ: el mensaje venenoso gira para siempre |
| Long polling (20 s) | Short polling en bucle |
| Lotes de 10 para enviar y borrar | Un mensaje por llamada |
| Visibility timeout mayor que el procesamiento | Dejarlo en 30 s con trabajos de minutos |
| Backoff con `ChangeMessageVisibility` | Reintentar inmediatamente |
| FIFO solo si necesitas orden | FIFO «por si acaso» (limita rendimiento) |
| Retención de la DLQ mayor que la principal | DLQ que expira antes de analizar |

## 8. Límites, costos y versiones
- **Costo:** por solicitud (cada 64 KiB cuenta como una); lotes y long polling lo reducen; primer millón mensual gratis *(verifica)*.
- **Límites** *(verifica)*: 1 MiB por mensaje, 14 días de retención, 120 000 mensajes en vuelo (estándar), 20 000 (FIFO).
- **Terraform:** `aws_sqs_queue` con `redrive_policy`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
