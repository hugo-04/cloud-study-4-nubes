# AWS · Storage · Eventos de S3

**S3 puede avisar cuando pasa algo con un objeto (se creó, se borró, se restauró, se replicó…) y enviar ese aviso a SQS, SNS, Lambda o Amazon EventBridge.** Es el «disparador» de casi todo flujo de archivos: subir un CSV → procesarlo; subir una foto → generar miniaturas; llegar un PDF → escanearlo.

## 1. Qué es

**Analogía:** el **timbre de la puerta de la bodega**. Cada vez que alguien deja o retira una caja, suena el timbre y llega una nota con *qué caja* y *cuándo*. La nota puede ir a un buzón (SQS), a un tablón de avisos (SNS), directo a quien trabaja (Lambda) o a una central que reparte avisos a muchos (EventBridge).

```
 Cliente ──PUT──► S3 bucket ──evento ObjectCreated──┬─► SQS ──► consumidor (Spring/Quarkus/Lambda)
                                                    ├─► SNS ──► varios suscriptores
                                                    ├─► Lambda (directo)
                                                    └─► EventBridge ──► reglas ──► SQS / Lambda / Step Functions / API…
```

## 2. Cómo funciona por dentro

### 2.1 Dos mecanismos distintos

| | **Notificaciones de eventos** | **Amazon EventBridge** |
|---|---|---|
| Destinos | SQS, SNS, Lambda | Más de 20 servicios, varios por regla, otras cuentas/regiones |
| Filtros | Prefijo y sufijo de la clave | Patrones ricos: prefijo, sufijo, **tamaño numérico**, motivo (`PutObject`, `CopyObject`…), etiquetas del evento |
| Eventos | Un conjunto elegido | Prácticamente todos |
| Extras | — | Archivar y **reproducir** eventos, reglas por equipo |
| Latencia | Típicamente segundos | Típicamente segundos (algo mayor) |
| Cuándo | Un destino, filtro simple | Muchos consumidores, filtros finos, desacoplar equipos |

Se pueden usar **a la vez** en el mismo bucket.

### 2.2 Tipos de evento frecuentes
`ObjectCreated:*` (Put, Post, Copy, CompleteMultipartUpload) · `ObjectRemoved:*` (Delete, DeleteMarkerCreated) · `ObjectRestore:*` · `LifecycleExpiration:*` · `Replication:*` · `ObjectTagging:*` · `IntelligentTiering` *(verifica la lista)*.

### 2.3 Qué recibes
Un JSON con bucket, clave, tamaño, `eTag`, `versionId`, **`sequencer`**, hora y región. En las **notificaciones**, la **clave viene codificada como URL** (los espacios llegan como `+`, la `ñ` como `%C3%B1`); en EventBridge llega sin codificar. Ejemplos: [`ejemplos/json/`](ejemplos/json/).

### 2.4 Garantías (lo que NO te prometen)
- **Al menos una vez:** puede llegar **duplicado**.
- **Sin orden garantizado:** dos eventos de la misma clave pueden llegar invertidos. El `sequencer` (hexadecimal) permite decidir cuál es más nuevo *para la misma clave*.
- **No es transaccional:** el evento puede llegar antes de que *otro* proceso vea el objeto (casi nunca; lectura fuerte tras escritura) y **no** hay evento si falla la configuración del destino (permisos).
- **Recursión:** si tu consumidor escribe en el mismo bucket y prefijo que dispara el evento, **creas un bucle infinito**.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Procesar archivos al llegar (CSV, imágenes, PDF) | **Evento → SQS** (con DLQ) |
| Un solo paso corto y sin picos | **Evento → Lambda** directa |
| Varios sistemas necesitan enterarse | **EventBridge** o **SNS → SQS** (fan-out) |
| Filtrar por tamaño o por motivo | **EventBridge** |
| Orden estricto de procesamiento por clave | **No confíes en el orden**: usa `sequencer` o una cola FIFO propia |
| Necesitas el contenido en el mensaje | **No**: el evento solo dice *qué* pasó; descarga el objeto (patrón [Claim Check](../claim-check/README.md)) |
| Auditar «quién leyó» | **No** (eso son eventos de datos de CloudTrail) |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Notificación de evento** | Aviso de S3 a SQS/SNS/Lambda |
| **EventBridge** | Bus de eventos con reglas y destinos |
| **Sequencer** | Número que ordena eventos de una misma clave |
| **Prefijo/sufijo** | Filtro por el principio/final de la clave |
| **Fan-out** | Un aviso, muchos consumidores |
| **Recursión** | El consumidor provoca el mismo evento que lo dispara |
| **DLQ** | Cola de avisos que fallaron |

## 5. Cómo se usa
1. Define el bucket y el destino con permisos para S3/EventBridge: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Filtra (prefijo `entrada/`, sufijo `.csv`) y separa **entrada** de **salida**.
3. El consumidor parsea el evento, **decodifica la clave**, ignora `s3:TestEvent`, deduplica y procesa ([uso en Java](uso-en-java.md)).
4. Configuración por CLI: [`ejemplos/cli/eventos.sh`](ejemplos/cli/eventos.sh).
5. Para archivos grandes, el evento es el «ticket»: [Claim Check](../claim-check/README.md).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **S3 (servicio)** | — | Publica en SQS/SNS/Lambda con una **política del destino** que exige `aws:SourceArn` (el bucket) y `aws:SourceAccount` |
| **EventBridge** | — | Entrega a destinos con la política/rol de la regla |
| **Consumidor** | — | `sqs:ReceiveMessage/DeleteMessage`; `s3:GetObject` del prefijo |
| **Pipeline** | `s3:PutBucketNotification`, reglas | — |

- **Política del destino sin `SourceArn`** = cualquier bucket de cualquier cuenta podría enviar mensajes a tu cola (*confused deputy*).
- **Valida el evento**: bucket esperado, prefijo, tamaño; no ejecutes nada con la clave sin sanearla.
- **Cifrado:** si la cola usa KMS propia, S3 necesita permiso en la clave (`kms:GenerateDataKey`, `kms:Decrypt`).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Evento → SQS con DLQ y consumidor idempotente | Lambda directa sin control de concurrencia ni DLQ |
| Separar prefijos `entrada/` y `salida/` | Escribir el resultado en el prefijo que dispara el evento |
| Decodificar la clave (`+` y `%XX`) | Usar la clave tal cual llega |
| Ignorar `s3:TestEvent` y claves terminadas en `/` | Procesar «carpetas» y pruebas |
| Comparar `sequencer` si el orden importa | Asumir orden de llegada |
| Condición `SourceArn` + `SourceAccount` en el destino | Política abierta a `s3.amazonaws.com` |
| Verificar el objeto (`HeadObject` con `versionId`) | Fiarse del tamaño del evento sin comprobar |
| Alarmas en la DLQ | Fallos silenciosos |

## 8. Límites, costos y versiones
- **Costo:** las notificaciones no cobran extra (pagas SQS/SNS/Lambda y las solicitudes). EventBridge: los eventos de servicios de AWS en el bus predeterminado no se cobran, sí lo que invoque la regla *(verifica)*.
- **Configuración:** las reglas de notificación no pueden tener **prefijos solapados** para el mismo tipo de evento hacia el mismo destino.
- **Terraform:** un solo `aws_s3_bucket_notification` por bucket reúne SQS/SNS/Lambda y `eventbridge = true`. Validado con `init` + `validate`.
- **Detalle de formato:** la versión del esquema de eventos (`eventVersion` 2.x) puede cambiar; parsea solo los campos que necesitas.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
