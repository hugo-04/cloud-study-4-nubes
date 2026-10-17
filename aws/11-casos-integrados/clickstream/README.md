# AWS · Caso integrado · Clickstream de ModaLima

Cada clic de la web de ModaLima —ver un polo, abrir el carrito, pagar— es un **dato que fluye**. Este caso muestra cómo capturarlo sin frenar la tienda, medirlo casi en tiempo real (páginas más vistas, sesiones por minuto) y guardarlo barato para análisis posteriores. Une Kinesis Data Streams, Firehose, S3, Athena, DynamoDB y IAM.

## 1. Qué es

**Analogía:** una cinta transportadora con varios carriles (shards) en la puerta de la tienda. Cada visitante deja una ficha en el carril que le toca (por su sesión). Al final de la cinta hay dos mesas: una **mesa rápida** que cuenta cada minuto (métricas en vivo) y una **bodega** que guarda todas las fichas para estudiarlas luego (lago de datos).

```
 Navegador ─► API de ingesta (ECS) ─ PutRecords por lotes ─► Kinesis Data Streams "prod-clics"
 (lotes de clics)   · valida y limpia · seudonimiza sesión           │ clave de partición = sesión seudonimizada
                                                                      ├─► Consumidor de métricas (ECS) ─► DynamoDB metricas-clics (por ventana)
                                                                      │       · agrega por ventana de 1 min · checkpoint seguro
                                                                      └─► Firehose ─► S3 lago (gzip, por fecha) ─► Athena (corrección diaria, análisis)
 CloudWatch: IteratorAge (atraso) · WriteProvisionedThroughputExceeded (clave caliente) · Terraform lo crea
```

## 2. Cómo funciona por dentro

| # | Paso | Detalle que importa |
|---|---|---|
| 1 | El navegador envía **lotes** de clics | Un lote por pocos segundos, no un POST por clic |
| 2 | La API valida, recorta el reloj y **seudonimiza** la sesión | HMAC con secreto de Secrets Manager; nada de correos, nombres ni IP en el stream |
| 3 | Escribe con `PutRecords` | Hasta 500 registros y 5 MiB; el resultado es **por registro**: se reintentan solo los fallidos |
| 4 | Kinesis reparte por clave | MD5 de la clave → shard; misma sesión, mismo shard, **en orden** |
| 5 | El consumidor lee cada shard | Un agregador **por shard**; ventanas de 1 minuto por hora del evento |
| 6 | Cierra ventanas con *marca de agua* | Tolera 2 minutos de llegada tardía; lo más tardío se corrige en la noche con Athena |
| 7 | Escribe métricas de forma idempotente | `PutItem` sobrescribe la fila `(pagina, ventana#tipo#shard)`: reprocesar no duplica |
| 8 | Hace *checkpoint* en el punto **seguro** | Hasta el registro más viejo que aún alimenta una ventana abierta |
| 9 | Firehose guarda todo en S3 | Gzip, particionado `anio/mes/dia`, buffer 60 s / 64 MiB |

| Necesidad | Servicio | Capítulo |
|---|---|---|
| Flujo continuo con orden por clave y relectura | Kinesis Data Streams | [07](../../07-mensajeria/kinesis-data-streams/README.md) |
| Entregar el flujo al lago sin código | Firehose (Terraform) | [07](../../07-mensajeria/kinesis-data-streams/README.md) |
| Lago de datos | S3 | [06](../../06-storage/s3/README.md) |
| Métricas por ventana y checkpoints | DynamoDB | [08](../../08-datos/dynamodb/README.md) |
| Clave de seudonimización | Secrets Manager + KMS | [03](../../03-secretos/secrets-manager/README.md) |
| Ejecutar API y consumidor | ECS Fargate | [04](../../04-compute/ecs-fargate/README.md) |
| Permisos mínimos | IAM | [02](../../02-iam/iam-roles-politicas/README.md) |
| Presupuesto y alarmas | Budgets | [09](../../09-gobierno/budgets-costos/README.md) |
| Todo como código | Terraform | [10](../../10-terraform/README.md) |

### Las tres decisiones que definen el caso
1. **Clave de partición = sesión.** Reparte parejo (miles de sesiones) y mantiene el orden por visitante. Con clave `pagina` una página popular saturaría un shard (**clave caliente**).
2. **Agregar por ventana con la hora del evento**, no la de llegada, con tolerancia a lo tardío y corrección nocturna.
3. **Salida idempotente + checkpoint seguro.** Kinesis entrega *al menos una vez*: repetir debe dar el mismo resultado.

## 3. Para qué sirve y cuándo NO

- **Sirve** para: clics, telemetría, eventos de dispositivos, logs de aplicación con volumen continuo y varios lectores.
- **No** uses Kinesis para: unos cientos de eventos de negocio por día (EventBridge/SQS bastan y son más simples), ni como base de datos de consulta.

## 4. Conceptos clave (en palabras simples)

- **Shard:** un carril del stream (capacidad fija: ~1 MiB/s o 1000 registros/s de escritura).
- **Clave de partición:** decide el carril; misma clave, mismo carril.
- **Clave caliente:** una clave que recibe demasiado y satura su carril.
- **Ventana *tumbling*:** tramos de tiempo fijos que no se solapan (12:00–12:01, 12:01–12:02…).
- **Hora del evento vs. de llegada:** cuándo ocurrió vs. cuándo lo vimos.
- **Marca de agua (watermark):** «ya no espero nada más viejo que esto»; cierra ventanas.
- **Checkpoint:** marcador de hasta dónde se procesó; al reiniciar se continúa desde ahí.
- **Seudonimizar:** reemplazar un identificador por otro irreversible sin la clave.

## 5. Cómo se usa

1. Calcula shards con el dimensionador de [uso en Java](uso-en-java.md) o elige `ON_DEMAND` si la carga es irregular.
2. Crea todo con [`ejemplos/terraform`](ejemplos/terraform/main.tf).
3. Despliega la API de ingesta y el consumidor.
4. Crea la tabla de Athena con [`ejemplos/sql/athena-clics.sql`](ejemplos/sql/athena-clics.sql).
5. Opera con [`ejemplos/cli/operacion.sh`](ejemplos/cli/operacion.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de Terraform | Crea stream, Firehose, tablas, alarmas | — |
| API de ingesta (rol de tarea) | — | `kinesis:PutRecords` solo sobre el stream |
| Consumidor (rol de tarea) | — | Leer el stream; `dynamodb:PutItem/GetItem` en métricas y checkpoints |
| Firehose (rol de servicio) | — | Leer el stream y escribir en el bucket del lago |
| Analistas | — | Athena sobre el lago; sin acceso al stream |

- Stream cifrado con KMS; bucket privado con cifrado y ciclo de vida.
- **Privacidad:** el identificador de sesión se seudonimiza con HMAC; no se envían correo, nombre ni IP. La clave de HMAC rota con un plan (ver caso de la lección 5).

## 7. Qué hacer / qué NO hacer

| Haz | No hagas |
|---|---|
| Lotes de clics y `PutRecords` | Un `PutRecord` por clic |
| Revisar el resultado de **cada** registro | Ignorar `FailedRecordCount` |
| Clave con muchos valores parejos | Clave con pocos valores (`pagina`, `pais`) |
| Un registro malo se cuenta y se salta | Lanzar excepción y trabar el shard |
| Checkpoint después de procesar y hasta el punto seguro | Checkpoint al leer |
| Salida idempotente (`PutItem` por clave de ventana) | `ADD` ciegos que duplican al reprocesar |
| Alarma por `IteratorAge` | Enterarte del atraso por el dashboard vacío |
| Corrección nocturna con Athena | Prometer exactitud perfecta en tiempo real |

## 8. Límites, costos y versiones

- Escritura por shard: 1 MiB/s o 1000 registros/s; lectura compartida 2 MiB/s por shard (o *enhanced fan-out* por consumidor) *(verifica)*.
- Registro: hasta 1 MiB; `PutRecords`: 500 registros y 5 MiB *(verifica)*.
- Retención: 24 h por defecto, hasta 365 días con costo extra *(verifica)*.
- Costos que suben primero: horas-shard (o GB en bajo demanda), lectura extendida, Firehose por GB, Athena por datos escaneados *(verifica precios)*.
- Versiones del código: Java 21, Spring Boot 4.1.x, Quarkus 3.40.x, AWS SDK v2.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
