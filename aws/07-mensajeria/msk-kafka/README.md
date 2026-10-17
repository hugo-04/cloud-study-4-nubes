# AWS · Mensajería · Amazon MSK (Kafka administrado)

**Amazon MSK (Managed Streaming for Apache Kafka) te da clústeres de Apache Kafka reales, administrados por AWS: tú usas Kafka con sus clientes de siempre y AWS se encarga de aprovisionar brokers, repartirlos en zonas de disponibilidad, parchear, reemplazar nodos con falla, cifrar y monitorear.** Es la opción cuando necesitas el ecosistema y los protocolos de Kafka (Kafka Connect, Kafka Streams, tooling, compatibilidad con clientes existentes).

> Los conceptos generales de Kafka (tópicos, particiones, grupos de consumidores, *offsets*, garantías de entrega) están en el módulo transversal [Kafka](../../../transversal/kafka/README.md). Aquí está **lo propio de MSK**: tipos de clúster, red, autenticación con IAM, permisos, operación y cómo se conectan Spring Boot y Quarkus.

## 1. Qué es

**Analogía:** una **central de correos con buzones numerados (particiones)** que alquilas con el servicio de mantenimiento incluido. El reglamento de la central (protocolo Kafka) es el estándar de siempre; lo que cambia es que tú no construyes el edificio ni lo reparas: eliges tamaño, quién puede entrar (IAM) y por qué puertas.

```
   VPC de ModaLima (subredes privadas en 3 zonas)
 ┌──────────────────────────────────────────────────────────────┐
 │  Servicios (EKS/ECS)  ──9098 (IAM)──►  Clúster MSK            │
 │   productor/consumidor                  broker-1 (AZ-a)       │
 │                                         broker-2 (AZ-b)       │
 │   MSK Connect (S3 sink) ◄────────────── broker-3 (AZ-c)       │
 └──────────────────────────────────────────────────────────────┘
        Los brokers NO tienen IP pública por defecto: solo se llega desde dentro de la VPC
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Clúster aprovisionado (estándar)** | Eliges tipo y número de brokers (múltiplo del número de zonas), almacenamiento EBS por broker y configuración; control fino |
| **Brokers Express** | Variante aprovisionada con escalado y recuperación más rápidos y sin administrar almacenamiento *(verifica tipos y límites)* |
| **MSK Serverless** | Sin brokers que dimensionar: pagas por uso; autenticación solo con IAM; límites por partición *(verifica)* |
| **Zonas de disponibilidad** | Brokers repartidos en 2 o 3 zonas; con 3 zonas y factor de replicación 3 sobrevives a la caída de una |
| **Modos de autenticación** | **IAM** (puerto 9098), **SASL/SCRAM** con secreto en Secrets Manager (9096), **TLS mutuo** (9094), o sin autenticación (9092, solo pruebas) |
| **Autorización** | IAM (políticas `kafka-cluster:*` sobre clúster, tópico y grupo) o ACL de Kafka |
| **Configuración del clúster** | Archivo de propiedades de broker (`default.replication.factor`, `min.insync.replicas`, `auto.create.topics.enable`…) con revisiones |
| **Almacenamiento** | EBS por broker con autoescalado opcional; **almacenamiento por niveles** para retención larga *(verifica)* |
| **Cifrado** | En tránsito (TLS cliente-broker y entre brokers) y en reposo (KMS) |
| **Monitoreo** | CloudWatch en niveles (por clúster, broker, tópico, partición) y Prometheus (monitoreo abierto) |
| **MSK Connect** | Kafka Connect administrado: conectores *source/sink* (S3, bases de datos, etc.) sobre trabajadores autoescalables |
| **MSK Replicator** | Replica tópicos y offsets entre clústeres (otra región o clúster) |
| **Tópicos y datos** | Se administran con la API de Kafka (AdminClient, scripts), **no** con la API de AWS: el cliente debe poder llegar a los brokers |
| **Versiones** | Versiones de Kafka soportadas por AWS (3.x; KRaft en las recientes) *(verifica la matriz vigente)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Ya usas Kafka o necesitas Kafka Connect/Streams/ksqlDB y clientes estándar | **MSK** |
| Flujo de eventos con relectura, varios grupos de consumidores y orden por clave, con ecosistema Kafka | **MSK** |
| Piloto o carga muy variable sin ganas de dimensionar | **MSK Serverless** |
| Producción estable con control de brokers, almacenamiento y configuración | **MSK aprovisionado** (o Express si priorizas rapidez de escalado) |
| Flujo continuo sin necesitar Kafka, con integración nativa a Lambda/Firehose | [Kinesis Data Streams](../kinesis-data-streams/README.md) |
| Cola de trabajo con reintentos por mensaje y DLQ | [SQS](../sqs/README.md) |
| Fan-out a pocas colas con filtros | [SNS](../sns/README.md) |
| Enrutar por contenido a destinos distintos | [EventBridge](../eventbridge/README.md) |
| Pocos mensajes sueltos o equipo sin experiencia en Kafka | No: es una pieza grande; SQS/SNS son más simples |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Broker** | Un servidor Kafka del clúster |
| **Tópico / partición** | Canal de mensajes / su subdivisión en «carriles» ordenados |
| **Factor de replicación** | Cuántas copias de cada partición (3 en producción) |
| **`min.insync.replicas`** | Cuántas copias deben confirmar para aceptar una escritura con `acks=all` (2 con RF=3) |
| **Grupo de consumidores** | Instancias que se reparten las particiones de un tópico |
| **Offset / *lag*** | Posición de lectura / cuánto se retrasa el grupo |
| **Bootstrap servers** | Direcciones iniciales para descubrir el clúster (`get-bootstrap-brokers`) |
| **Puerto 9098** | Entrada con autenticación IAM (TLS) |
| **MSK Connect** | Conectores Kafka Connect sin administrar servidores |
| **Idempotente** | Procesar dos veces el mismo mensaje da el mismo resultado |

## 5. Cómo se usa
1. Decide el tipo: **Serverless** para empezar o **aprovisionado** (3 zonas, RF=3, `min.insync.replicas=2`): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Coloca el clúster en **subredes privadas** y abre el puerto del modo de autenticación **solo** al grupo de seguridad de los clientes.
3. Autentica con **IAM**: el rol del servicio (identidad de pod o de tarea) con las políticas de [`ejemplos/json`](ejemplos/json).
4. Obtén los *bootstrap brokers* (`aws kafka get-bootstrap-brokers`) y crea los **tópicos por código** (AdminClient o IaC), con la configuración correcta; deja `auto.create.topics.enable=false`.
5. Productores con `acks=all` e idempotencia; consumidores con *commit* manual tras procesar: [uso en Java](uso-en-java.md) y [`ejemplos/properties`](ejemplos/properties).
6. Alarmas: disco por broker, *lag* de los grupos, CPU, particiones sub-replicadas ([`ejemplos/cli/msk.sh`](ejemplos/cli/msk.sh)).

## 6. Seguridad

| Identidad | Plano de control (API de AWS) | Plano de datos (Kafka) |
|---|---|---|
| **Productor** | — | `kafka-cluster:Connect`, `DescribeTopic`, `WriteData` (+ `WriteDataIdempotently` si usa idempotencia) |
| **Consumidor** | — | `Connect`, `DescribeTopic`, `ReadData`, `DescribeGroup`, `AlterGroup` |
| **Administración de tópicos** | — | `CreateTopic`, `AlterTopic`, `DeleteTopic`, `DescribeTopicDynamicConfiguration`… |
| **Pipeline (Terraform)** | `kafka:CreateCluster`, `UpdateBrokerStorage`, `UpdateClusterConfiguration`, `GetBootstrapBrokers` | — |

- **Tres tipos de recurso en IAM:** *clúster*, *tópico* y *grupo*; olvidar el grupo es el `AccessDenied` más común del consumidor.
- **Red:** brokers privados; el grupo de seguridad permite el puerto 9098 (o 9096/9094) **solo** desde los clientes. El acceso público existe pero no es recomendable.
- **SCRAM:** el secreto debe llamarse con prefijo `AmazonMSK_` y usar una clave KMS administrada por el cliente.
- **Cifrado:** TLS obligatorio (`client_broker = "TLS"`) y KMS en reposo.
- **Datos personales:** el tópico retiene lo que escribes durante toda la retención; minimiza y cifra a nivel de campo si hace falta.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| 3 zonas, RF=3, `min.insync.replicas=2`, `acks=all` | RF=1 o `min.insync.replicas=1` en producción |
| `auto.create.topics.enable=false` y tópicos por código | Tópicos que aparecen por un error de tipeo |
| Autenticación IAM con el rol del servicio | Usuarios SCRAM compartidos sin rotación |
| Nombres de tópico con convención y versión (`pedidos.orden.creada.v1`) | Nombres libres, mezclando `.` y `_` |
| Calcular particiones con el rendimiento objetivo | «10 por si acaso» (más particiones = más sobrecarga) |
| Commit manual tras procesar; idempotencia | Autocommit y perder mensajes al fallar |
| Alarmas de disco, *lag* y réplicas sub-sincronizadas | Descubrir el disco lleno a las 3 a.m. |
| Almacenamiento autoescalable o por niveles | Retención larga sin plan de capacidad |
| Esquemas versionados y compatibles | Cambiar el formato sin avisar |
| MSK Connect para mover datos a S3/BD | Escribir y operar tus propios conectores |

## 8. Límites, costos y versiones
- **Costo:** aprovisionado = horas de broker + almacenamiento + transferencia entre zonas/salida; Serverless = horas de clúster + partición-hora + almacenamiento + GB de entrada/salida; MSK Connect y Replicator se cobran aparte *(verifica)*.
- **Límites** *(verifica)*: brokers por clúster, particiones por broker (según tipo), máximo de conexiones, límites de Serverless por partición y por clúster.
- **Terraform:** `aws_msk_cluster`, `aws_msk_serverless_cluster`, `aws_msk_configuration`, `aws_cloudwatch_metric_alarm`. Validado con `init` + `validate`.
- **Java:** `kafka-clients`, `software.amazon.msk:aws-msk-iam-auth` 2.x, Spring for Apache Kafka, reactor-kafka, Quarkus `smallrye-reactive-messaging-kafka`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
