# AWS · Mensajería · Amazon Kinesis Data Streams (flujos de datos)

**Kinesis Data Streams es un registro de eventos ordenado y duradero para flujos continuos de datos: los productores *anexan* registros, y varios lectores independientes los leen a su ritmo, pudiendo releer lo que ya pasó mientras dure la retención.** Piénsalo como un diario que solo se escribe al final y que cada lector recorre con su propio marcador.

## 1. Qué es

**Analogía:** una **cinta transportadora con varios carriles (shards)**. Cada paquete lleva una etiqueta (la *clave de partición*) que decide por qué carril viaja; dentro de un carril el orden es estricto. Cada equipo se para junto a la cinta con su propia libreta (su *checkpoint*) y va leyendo; los paquetes no desaparecen al leerse, se quedan hasta que pasa el tiempo de retención.

```
 Productores                  STREAM                            Lectores independientes
 (web, apps)   ──PutRecords──► shard-0 ▒▒▒▒▒▒▒▒▒▒──────────►  facturación (KCL)  ─ marcador propio
 clave=usuario  hash(clave)    shard-1 ▒▒▒▒▒▒▒▒▒▒──────────►  analítica (Lambda) ─ marcador propio
                               shard-2 ▒▒▒▒▒▒▒▒▒▒──────────►  antifraude (fan-out mejorado)
                               └── retención: 24 h … 365 días ──┘
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Stream** | El flujo; contiene uno o más *shards* |
| **Shard** | Unidad de capacidad y de **orden**. En aprovisionado: escritura 1 MiB/s o 1 000 registros/s, lectura 2 MiB/s *(verifica)* |
| **Registro** | Clave de partición + datos (blob) + número de secuencia asignado por Kinesis; hasta 1 MiB de datos *(verifica: límites mayores en configuraciones nuevas)* |
| **Clave de partición** | Se pasa por MD5; el resultado (128 bits) decide el shard. **Misma clave ⇒ mismo shard ⇒ orden relativo** |
| **Número de secuencia** | Cifra creciente por shard (hasta ~56 dígitos); se compara **como número**, no como texto |
| **Modo bajo demanda** | Kinesis ajusta shards solo; pagas por uso; sin planificar capacidad |
| **Modo aprovisionado** | Tú fijas el número de shards (y lo cambias con `UpdateShardCount`/dividir/combinar) |
| **Retención** | 24 h por defecto, ampliable hasta 365 días *(verifica costos de retención larga)* |
| **Consumidor compartido** | Varios lectores **reparten** los 2 MiB/s de lectura de cada shard (máx. 5 llamadas `GetRecords`/s por shard) |
| **Fan-out mejorado** | Cada consumidor registrado recibe sus propios 2 MiB/s por shard, por *push* HTTP/2 (`SubscribeToShard`) |
| **KCL** | Biblioteca cliente (Java) que reparte shards entre instancias, guarda *checkpoints* en DynamoDB y maneja resharding |
| **Lambda como consumidor** | Una función por lote de cada shard (tamaño de lote, paralelismo por shard, bisección ante errores, destino de fallos) |
| **Iterador** | Posición de lectura: `TRIM_HORIZON` (lo más antiguo), `LATEST`, `AT_TIMESTAMP`, `AT_SEQUENCE_NUMBER`/`AFTER_…` |
| **Cifrado** | SSE con KMS |
| **Entrega** | Al menos una vez: puede haber duplicados (reintentos del productor, reproceso del lector) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Clickstream, telemetría, logs de aplicación a gran volumen | **Kinesis Data Streams** |
| Orden estricto **por clave** (por usuario, por pedido) con alto volumen | **Kinesis** con esa clave de partición |
| Varios equipos leyendo lo mismo, cada uno a su ritmo, con relectura | **Kinesis** (consumidores independientes) |
| Reprocesar los últimos días tras corregir un error | **Kinesis** (retención + iterador por fecha) |
| Entregar a S3/Redshift/OpenSearch sin código | Firehose *(servicio hermano de entrega, sin código)* |
| Cola de trabajo con reintentos por mensaje y DLQ | [SQS](../sqs/README.md) |
| Fan-out con filtros a pocas colas | [SNS](../sns/README.md) |
| Enrutar por contenido a destinos distintos | [EventBridge](../eventbridge/README.md) |
| Ecosistema Kafka (Connect, Streams, compatibilidad) | [MSK](../msk-kafka/README.md) |
| Pocos mensajes sueltos | No: SQS/SNS son más simples y baratos |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Shard** | Un «carril» del stream: capacidad y orden |
| **Clave de partición** | Etiqueta que decide el carril |
| **Shard caliente** | Un carril saturado porque la clave se reparte mal |
| **Checkpoint** | «Hasta aquí ya leí» (lo guarda KCL en DynamoDB) |
| **Atraso (*iterator age*)** | Cuánto se retrasa el lector respecto a lo escrito |
| **Resharding** | Dividir o combinar shards |
| **Fan-out mejorado** | Carril de lectura exclusivo por consumidor |
| **KPL** | Biblioteca de productor que agrupa y agrega registros |
| **Idempotente** | Procesar dos veces lo mismo da el mismo resultado |

## 5. Cómo se usa
1. Elige la **clave de partición** pensando en el orden que necesitas y en el reparto (muchos valores distintos): [uso en Java](uso-en-java.md) trae un simulador de distribución.
2. Crea el stream (bajo demanda para empezar), con cifrado, retención y métricas: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Publica con `PutRecords` en lotes (≤ 500 registros, ≤ 5 MiB) y **reintenta solo los registros fallidos**.
4. Consume con **KCL** (o Lambda); `checkpoint` después de procesar, y consumidores idempotentes.
5. Alarmas: atraso del iterador y *throttling* de escritura ([`ejemplos/cli/kinesis.sh`](ejemplos/cli/kinesis.sh) trae los comandos de diagnóstico).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Productor** | — | `kinesis:PutRecord`, `PutRecords` (+ `kms:GenerateDataKey` si hay KMS) |
| **Consumidor KCL** | — | `GetRecords`, `GetShardIterator`, `DescribeStream(Summary)`, `ListShards`, `SubscribeToShard`; DynamoDB (tabla de *leases*); `cloudwatch:PutMetricData`; `kms:Decrypt` |
| **Pipeline** | `kinesis:CreateStream`, `UpdateShardCount`, `IncreaseStreamRetentionPeriod`, `RegisterStreamConsumer`… | — |

- **Cifrado:** KMS en el stream; permisos de la clave para productores y lectores.
- **Entre cuentas:** política de recursos del stream o un rol que se asume.
- **Datos personales:** el stream retiene lo que escribes hasta 365 días; no lo uses como almacén de PII.
- **Red:** endpoint de VPC (interface) para que el tráfico no salga a Internet ([red](../../01-red/README.md)).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Clave de alta cardinalidad (usuario, sesión, pedido) | Clave con pocos valores (país, tipo) → shard caliente |
| `PutRecords` por lotes y reintento por registro | Un `PutRecord` por evento en bucle |
| Bajo demanda al empezar; aprovisionado cuando la carga es estable | Fijar shards «a ojo» |
| KCL (o Lambda) para consumir | Reescribir a mano el reparto de shards y los checkpoints |
| Checkpoint **después** de procesar | Checkpoint antes y perder datos al fallar |
| Idempotencia y comparación numérica de secuencias | Comparar números de secuencia como texto |
| Fan-out mejorado si hay varios consumidores exigentes | Cinco consumidores compartiendo 2 MiB/s |
| Alarmas de atraso y de throttling | Descubrir el atraso por quejas |
| Referencias a objetos grandes ([Claim Check](../../06-storage/claim-check/README.md)) | Registros de varios MiB |

## 8. Límites, costos y versiones
- **Costo:** bajo demanda = por hora de stream + GB escritos/leídos; aprovisionado = por shard-hora + unidades de carga de 25 KB; extra por retención larga y fan-out mejorado *(verifica)*.
- **Límites** *(verifica)*: `PutRecords` 500 registros / 5 MiB, tamaño del registro, consumidores con fan-out mejorado por stream, shards por cuenta.
- **Terraform:** `aws_kinesis_stream` (`stream_mode_details`), `aws_kinesis_stream_consumer`, `aws_cloudwatch_metric_alarm`. Validado con `init` + `validate`.
- **Java:** KCL 3.x (Amazon Kinesis Client Library) y AWS SDK v2.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
