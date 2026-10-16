# 08 · Mensajería y streaming: colas, tópicos y el equivalente de Kafka

Cómo se comunican los sistemas **sin esperarse unos a otros**. **Azure Service Bus / Event Hubs / Event Grid**, con sus equivalentes en **AWS** (SQS, SNS, Kinesis, MSK), **OCI** (Queue, Notifications, Streaming) y **GCP** (Pub/Sub, Managed Kafka).

---

## 1. Qué es (con analogía)

| Modelo | Analogía | Idea |
|---|---|---|
| **Cola** | Ventanilla con **número de turno** | Cada mensaje lo atiende **un solo** trabajador; al atenderlo, sale de la fila |
| **Tópico (pub/sub)** | Un **boletín** al que se suscriben varias áreas | Cada suscriptor recibe **su propia copia** |
| **Stream (Kafka)** | Un **diario/bitácora** que solo se agrega al final | Los mensajes **se conservan**; cada lector lleva su **marcador** y puede **releer** |
| **Enrutador de eventos** | El **timbre** del edificio | Avisa "pasó algo" y reparte a quien le interese |

---

## 2. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Desacoplar:** quien produce no espera a quien procesa.
- **Absorber picos:** la cola aguanta lo que el procesador no alcanza.
- **Reintentar** de forma segura.
- **Repartir** un mismo evento a muchos sistemas.
- **Analizar** flujos de eventos en tiempo real.

**Cuándo NO**
- Cuando necesitas una **respuesta inmediata** (usa una llamada directa HTTP/gRPC).
- Para **transferir archivos grandes** (usa *Claim Check*, módulo 07).
- Como **base de datos** (los mensajes no son para consultarse).
- Si tu equipo no puede operar la complejidad (orden, duplicados, reintentos): empieza por lo simple.

---

## 3. Conceptos clave

| Término | Definición simple |
|---|---|
| **Productor / consumidor** | Quien envía / quien procesa |
| **Broker** | El servidor que guarda y entrega los mensajes |
| **Cola** | Lista de mensajes con un consumidor por mensaje |
| **Tópico + suscripción** | Un buzón de entrada con copias para cada suscriptor |
| **Stream / log** | Secuencia ordenada de eventos que se **retiene** |
| **Partición** | Una "vía" del stream; el orden se garantiza **dentro** de ella |
| **Offset / checkpoint** | El "marcador" de hasta dónde leyó un consumidor |
| **Consumer group** | Conjunto de consumidores que se **reparten** las particiones |
| **Retención** | Cuánto tiempo se guardan los eventos |
| **Ack / complete** | "Ya lo procesé, bórralo" |
| **Lock (peek-lock)** | El mensaje se reserva para ti mientras trabajas; si no confirmas, vuelve |
| **DLQ** (dead-letter) | Cola de mensajes que **no se pudieron procesar** |
| **Mensaje venenoso (poison)** | El que **siempre** falla y bloquea el flujo |
| **Idempotencia** | Procesar dos veces produce el mismo resultado que una |
| **TTL** | Tiempo de vida del mensaje |
| **Lag** | Cuántos mensajes lleva de retraso un consumidor |

### Garantías de entrega

| Garantía | Significa | Típico |
|---|---|---|
| **At-most-once** | Puede perderse, nunca se duplica | Telemetría tolerante |
| **At-least-once** | Nunca se pierde, **puede duplicarse** | **El estándar** |
| **Exactly-once** | Una sola vez | Muy limitado; requiere diseño y soporte específico |

> **Regla práctica:** asume **at-least-once** y diseña consumidores **idempotentes**.

---

## 4. Los tres modelos, lado a lado

| | Cola | Tópico / pub-sub | Stream (Kafka) |
|---|---|---|---|
| ¿Quién consume cada mensaje? | **Uno** | **Todos los suscriptores** (cada uno su copia) | **Todos los grupos** (cada uno por su cuenta) |
| ¿Se borra al consumir? | **Sí** | Sí (por suscripción) | **No**: se retiene por tiempo/tamaño |
| ¿Se puede releer el pasado? | No | No (normalmente) | **Sí** (re-procesar, nuevos consumidores) |
| Orden | Opcional (FIFO / sesiones) | Opcional | **Por partición** |
| Volumen típico | Medio | Medio | **Muy alto** |
| Caso típico | Procesar pedidos | Notificar a varios sistemas | Telemetría, clics, CDC, analítica |

### Árbol de decisión

```
¿Un solo trabajador debe procesar cada tarea?
   Sí → COLA
   No ↓
¿Varios sistemas distintos necesitan reaccionar al mismo evento?
   Sí → ¿necesitan además releer la historia o hay un volumen muy alto?
           Sí → STREAM
           No → TÓPICO con suscripciones
   No ↓
¿Solo quieres avisar "algo pasó en la plataforma" (blob creado, VM cambiada)?
   Sí → ENRUTADOR DE EVENTOS (Event Grid / EventBridge / Events / Eventarc)
```

---

## 5. Equivalencias en las 4 nubes

| Necesidad | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Cola simple y barata | **Storage Queue** | **SQS** (Standard) | **OCI Queue** | Pub/Sub (suscripción pull) / **Cloud Tasks** |
| Cola empresarial (sesiones, DLQ, tópicos) | **Service Bus** | SQS FIFO + SNS | OCI Queue | Pub/Sub (ordering keys, DLQ) |
| Tópico / pub-sub | Service Bus topics | **SNS** (+ SQS para fan-out) | **Notifications** | **Pub/Sub** |
| Enrutador de eventos de la plataforma | **Event Grid** | **EventBridge** | **Events** | **Eventarc** |
| **Stream / equivalente de Kafka** | **Event Hubs** (con endpoint compatible con Kafka) | **Kinesis Data Streams** o **MSK** (Kafka administrado) | **OCI Streaming** (compatible con Kafka) | **Pub/Sub** o **Managed Service for Apache Kafka** |
| Kafka "de verdad" administrado | Confluent en Azure; (verifica opciones) | **MSK** / MSK Serverless | Streaming (API Kafka) | **Google Cloud Managed Service for Apache Kafka** |
| Mensajería con protocolos clásicos (AMQP/MQTT) | Service Bus (AMQP) / Event Grid (MQTT) | Amazon MQ | — | — |
| Reintentos de tareas HTTP programadas | Service Bus (mensajes programados) / Logic Apps | SQS delay / EventBridge Scheduler | Queue + Functions | Cloud Tasks / Cloud Scheduler |

### Diferencias reales

- **Event Hubs** *no es* Kafka, pero **habla el protocolo de Kafka** (puerto 9093): tus clientes Kafka pueden conectarse **sin cambiar el código** (solo la configuración). No soporta todas las características de Kafka; revisa las limitaciones vigentes.
- **MSK** y **Google Managed Kafka** sí son **Kafka administrado** (brokers de Kafka reales).
- **Kinesis** y **Event Hubs** usan su propio modelo (fragmentos/shards, particiones) y su propio SDK.
- **Pub/Sub** no expone particiones: escala solo y ofrece **suscripciones** con reintentos y DLQ; se parece más a "tópico + cola" que a un log de Kafka.
- **Service Bus** es el más completo en **funciones de cola** (sesiones, duplicados, programados, transacciones).

---

## 6. Los conceptos de Kafka en cada servicio

| Kafka | Event Hubs | Kinesis | OCI Streaming | Pub/Sub |
|---|---|---|---|---|
| Topic | Event hub | Stream | Stream | Topic |
| Partition | Partition | Shard | Partition | (interno) |
| Consumer group | Consumer group | Aplicación KCL | Consumer group | Subscription |
| Offset | Offset / checkpoint | Sequence number / checkpoint | Offset | Ack |
| Retención | Configurable (según tier) | Configurable | Configurable (días) | Retención del mensaje / de acked |
| Releer historia | Sí | Sí | Sí | Sí (con *seek* y retención de acked) |
| Capacidad | Throughput/Processing Units | Shards (o modo on-demand) | Particiones | Automática |

---

## 7. Azure en detalle

### 7.1 Los cuatro servicios de Azure

| Servicio | Es | Úsalo para |
|---|---|---|
| **Storage Queue** | Cola muy simple | Tareas sencillas, mucho volumen y bajo costo (mensajes de poco tamaño) |
| **Service Bus** | Broker empresarial (colas y tópicos) | Procesos de negocio: pedidos, pagos, órdenes |
| **Event Grid** | Enrutador de eventos | Reaccionar a eventos de Azure o propios (blob creado, recurso cambiado) |
| **Event Hubs** | Stream de alto volumen | Telemetría, clics, logs, integración con Kafka |

### 7.2 Service Bus: lo que hay que conocer

| Característica | Detalle |
|---|---|
| **Peek-lock** | Recibes, trabajas y luego **completas**; si falla o vence el lock, el mensaje vuelve |
| **Max delivery count** | Tras N intentos fallidos, pasa a **DLQ** (por defecto 10) |
| **DLQ** | Subcola automática `$DeadLetterQueue` con motivo del fallo |
| **Sesiones** | Orden estricto **por clave** (por ejemplo, por cliente) |
| **Detección de duplicados** | Descarta repetidos por `MessageId` dentro de una ventana |
| **Mensajes programados** | Entregar a una hora futura |
| **Tópicos y suscripciones** | Filtros (SQL / correlación) por suscripción |
| **Tiers** | **Standard** y **Premium** (Premium: recursos dedicados, mensajes más grandes, **Private Endpoint**) |

### 7.3 CLI

```bash
RG=rg-estudio-msg
az group create -n $RG -l eastus2

# Service Bus: cola con reintentos y DLQ
az servicebus namespace create -g $RG -n sb-modalima-estudio -l eastus2 --sku Standard
az servicebus queue create -g $RG --namespace-name sb-modalima-estudio -n pedidos \
  --max-delivery-count 5 --lock-duration PT1M --default-message-time-to-live P1D

# Tópico con una suscripción por consumidor
az servicebus topic create -g $RG --namespace-name sb-modalima-estudio -n eventos-pedido
az servicebus topic subscription create -g $RG --namespace-name sb-modalima-estudio \
  --topic-name eventos-pedido -n facturacion
az servicebus topic subscription create -g $RG --namespace-name sb-modalima-estudio \
  --topic-name eventos-pedido -n notificaciones

# Event Hubs: stream con 4 particiones
az eventhubs namespace create -g $RG -n evh-modalima-estudio -l eastus2 --sku Standard
az eventhubs eventhub create -g $RG --namespace-name evh-modalima-estudio -n clics --partition-count 4

# Limpieza
az group delete -n $RG --yes --no-wait
```
> Los parámetros de retención y SKU cambian con el CLI y el tier. Revisa `--help`.

---

## 8. Ejemplos en Java

### 8.1 Service Bus: enviar y procesar con reintentos seguros

```java
// ---- Enviar ----
ServiceBusSenderClient emisor = new ServiceBusClientBuilder()
    .fullyQualifiedNamespace("sb-modalima-estudio.servicebus.windows.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .sender().queueName("pedidos")
    .buildClient();

ServiceBusMessage msg = new ServiceBusMessage("{\"pedidoId\":123,\"total\":89.90}");
msg.setMessageId("pedido-123");                       // permite detectar duplicados
msg.setContentType("application/json");
emisor.sendMessage(msg);

// ---- Procesar ----
ServiceBusProcessorClient procesador = new ServiceBusClientBuilder()
    .fullyQualifiedNamespace("sb-modalima-estudio.servicebus.windows.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .processor().queueName("pedidos")
    .maxConcurrentCalls(4)
    .processMessage(ctx -> {
        ServiceBusReceivedMessage m = ctx.getMessage();
        try {
            procesarPedido(m.getBody().toString());   // debe ser idempotente
            // se completa solo si no lanzas excepción
        } catch (DatoInvalidoException e) {
            ctx.deadLetter(new DeadLetterOptions()
                .setDeadLetterReason("DatoInvalido")
                .setDeadLetterErrorDescription(e.getMessage()));
        }
    })
    .processError(err -> System.err.println("Error: " + err.getException()))
    .buildProcessorClient();

procesador.start();
```
- Si `procesarPedido` lanza una excepción **no controlada**, el mensaje se **abandona** y vuelve (se cuenta un intento).
- Los datos **inválidos** (que nunca se arreglarán) van **directo a DLQ**: no tiene sentido reintentarlos.

### 8.2 Kafka (cliente estándar) hacia Event Hubs

```java
Properties p = new Properties();
p.put("bootstrap.servers", "evh-modalima-estudio.servicebus.windows.net:9093");
p.put("security.protocol", "SASL_SSL");
p.put("sasl.mechanism", "PLAIN");
p.put("sasl.jaas.config",
      "org.apache.kafka.common.security.plain.PlainLoginModule required "
    + "username=\"$ConnectionString\" password=\"" + cadenaDeConexion + "\";");
p.put("key.serializer", StringSerializer.class.getName());
p.put("value.serializer", StringSerializer.class.getName());
p.put("acks", "all");

try (KafkaProducer<String, String> productor = new KafkaProducer<>(p)) {
    // La CLAVE decide la partición: mismo cliente → misma partición → orden garantizado
    productor.send(new ProducerRecord<>("clics", "cliente-42", "{\"pagina\":\"/ofertas\"}"));
}
```

Consumidor:
```java
Properties c = new Properties();
c.putAll(configuracionDeConexion);                 // las mismas propiedades de seguridad
c.put("group.id", "analitica");
c.put("enable.auto.commit", "false");
c.put("auto.offset.reset", "earliest");
c.put("key.deserializer", StringDeserializer.class.getName());
c.put("value.deserializer", StringDeserializer.class.getName());

try (KafkaConsumer<String, String> consumidor = new KafkaConsumer<>(c)) {
    consumidor.subscribe(List.of("clics"));
    while (true) {
        for (ConsumerRecord<String, String> r : consumidor.poll(Duration.ofSeconds(1))) {
            procesar(r.key(), r.value());
        }
        consumidor.commitSync();                   // confirma DESPUÉS de procesar
    }
}
```
> La cadena de conexión es un **secreto**: guárdala en Key Vault (módulo 04). Para evitar claves existe autenticación con Entra ID vía OAuth en el cliente Kafka (requiere un *callback handler*); verifica la guía vigente.

### 8.3 AWS SQS (SDK v2)

```java
try (SqsClient sqs = SqsClient.create()) {
    String url = sqs.getQueueUrl(r -> r.queueName("pedidos")).queueUrl();

    sqs.sendMessage(r -> r.queueUrl(url).messageBody("{\"pedidoId\":123}"));

    var recibidos = sqs.receiveMessage(r -> r.queueUrl(url)
            .maxNumberOfMessages(10).waitTimeSeconds(20));   // long polling

    for (Message m : recibidos.messages()) {
        procesar(m.body());
        sqs.deleteMessage(r -> r.queueUrl(url).receiptHandle(m.receiptHandle()));
    }
}
```
> En SQS **tú borras** el mensaje tras procesarlo; si no lo haces, reaparece cuando vence el *visibility timeout*.

### 8.4 Pub/Sub (GCP), idea general

```java
Publisher publisher = Publisher.newBuilder(TopicName.of("mi-proyecto", "eventos-pedido")).build();
publisher.publish(PubsubMessage.newBuilder()
        .setData(ByteString.copyFromUtf8("{\"pedidoId\":123}")).build()).get();
```
El consumidor usa un `Subscriber` con un *MessageReceiver* y llama a `ack()` o `nack()`.

---

## 9. Particiones y consumer groups (lo que más cuesta entender)

```
Tópico "clics" con 4 particiones

 P0 ─►─┐
 P1 ─►─┤  Grupo "analitica" (2 consumidores)   →  C1 lee P0,P1  |  C2 lee P2,P3
 P2 ─►─┤
 P3 ─►─┘  Grupo "alertas"   (1 consumidor)     →  C3 lee P0,P1,P2,P3
```

Reglas:
1. **Cada grupo lee todo** el tópico, de forma independiente.
2. Dentro de un grupo, **cada partición la lee un solo consumidor**.
3. Más consumidores que particiones = **algunos quedan ociosos**. El paralelismo máximo = número de particiones.
4. El **orden** se garantiza solo **dentro de una partición**. Si necesitas orden por cliente, usa la **clave de cliente**.
5. Una clave muy popular crea una **partición caliente** (hot partition): elige claves bien repartidas.
6. Cambiar el número de particiones después puede **alterar a qué partición va cada clave**; planifica con holgura.

---

## 10. Diseño de consumidores robustos

| Problema | Técnica |
|---|---|
| Mensajes duplicados | **Idempotencia**: guardar el `mensajeId` procesado o usar operaciones "upsert" |
| Mensaje venenoso | Máximo de intentos + **DLQ** + alerta |
| Fallos temporales | Reintentos con **espera exponencial** |
| Perder un evento al guardar en BD y publicar | Patrón **Outbox**: guardar el evento en la misma transacción y publicarlo después |
| Orden por entidad | Sesiones (Service Bus) / FIFO con grupo (SQS) / clave de partición |
| Mensajes grandes | **Claim Check** (módulo 07) |
| Consumidor lento | Escalar consumidores (KEDA en AKS) hasta el límite de particiones |

---

## 11. Red e IAM

**Red**

| Servicio | Acceso privado |
|---|---|
| Service Bus | Private Endpoint (**solo tier Premium**), zona `privatelink.servicebus.windows.net` |
| Event Hubs | Private Endpoint (tiers Standard o superiores), misma zona |
| Event Grid | Private Endpoint para tópicos/dominios (verifica soporte) |
| Kafka sobre Event Hubs | Puerto **9093**: ábrelo en NSG/firewall |

Equivalentes: SQS/SNS con Interface VPC Endpoint; Pub/Sub con Private Service Connect; OCI con endpoints privados de los servicios.

**IAM**

| Quién | Qué hace | Azure | AWS | OCI | GCP |
|---|---|---|---|---|---|
| Productor | Enviar | Azure Service Bus Data Sender / Event Hubs Data Sender | `sqs:SendMessage`, `sns:Publish` | `use queues` acotado | `roles/pubsub.publisher` |
| Consumidor | Recibir | Azure Service Bus Data Receiver / Event Hubs Data Receiver | `sqs:ReceiveMessage`, `sqs:DeleteMessage` | `use queues` acotado | `roles/pubsub.subscriber` |
| Administrador | Crear y configurar | Azure Service Bus Data Owner / Contributor | `sqs:*` acotado | `manage queues` | `roles/pubsub.admin` |

---

## 12. Casos de uso de vida real

### Caso 1 · Pedidos que no se pierden (cola)
- **Problema:** en campaña, la API de pedidos escribía directo a la base de datos y se saturaba.
- **Solución:** la API publica el pedido en una **cola**; trabajadores lo procesan al ritmo que soportan; los fallos van a DLQ.
- **Resultado:** la tienda aguantó el pico y no se perdió ninguna compra.
- **Lección:** la cola es un amortiguador.

### Caso 2 · Un pedido, tres reacciones (tópico)
- **Problema:** al crearse un pedido había que facturar, notificar al cliente y actualizar inventario, y la API hacía todo en secuencia.
- **Solución:** un **tópico** `eventos-pedido` con tres suscripciones. Cada sistema procesa lo suyo.
- **Resultado:** agregar un cuarto consumidor (analítica) no tocó la API.
- **Lección:** el productor no debe conocer a sus consumidores.

### Caso 3 · Clics de la web (stream)
- **Problema:** se querían analizar 5 000 eventos por segundo y poder **reprocesar** semanas atrás.
- **Solución:** **Event Hubs** con endpoint Kafka (los clientes Kafka existentes siguen igual), con captura a Storage.
- **Resultado:** analítica en tiempo real y reprocesos a demanda.
- **Lección:** si necesitas releer el pasado, necesitas un stream.

### Caso 4 · Pedidos duplicados
- **Problema:** algunos clientes recibían dos correos de confirmación.
- **Causa:** el procesador tardaba más que el *lock* y el mensaje volvió a entregarse.
- **Solución:** aumentar la duración del lock y renovarlo, y hacer el envío de correo **idempotente** con el `mensajeId`.
- **Lección:** *at-least-once* es una promesa de **no perder**, no de **no repetir**.

### Caso 5 · Catálogo de 2 GB
- **Problema:** un proveedor enviaba catálogos enormes que no entraban en el mensaje.
- **Solución:** Claim Check con Blob + cola (módulo 07).
- **Lección:** por la cola viaja la referencia.

---

## 13. Qué hacer / qué NO hacer

**Qué hacer**
- Elegir el modelo correcto (cola, tópico, stream) antes de elegir el producto.
- Hacer los consumidores **idempotentes**.
- Configurar **DLQ, máximo de intentos y alertas**.
- Usar **identidades administradas** y roles de datos mínimos.
- Mantener los mensajes **pequeños** y versionar su esquema.
- Medir **lag**, profundidad de cola y mensajes en DLQ.
- Elegir bien la **clave de partición**.
- Probar qué pasa cuando el consumidor se cae.

**Qué NO hacer**
- Asumir **orden global** (solo existe dentro de una partición o sesión).
- Procesar **sin confirmar** o confirmar **antes** de procesar.
- Ignorar la DLQ: es una bandeja de incidentes.
- Meter datos sensibles o archivos grandes en los mensajes.
- Usar un stream cuando basta una cola (más complejidad y costo).
- Cambiar el formato de un mensaje sin compatibilidad hacia atrás.
- Compartir una cadena de conexión con permisos de dueño en las aplicaciones.

---

## 14. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Mensajes en DLQ | Excepciones repetidas o datos inválidos | Leer `DeadLetterReason` y `ErrorDescription` | Corregir la causa y **reenviar** desde la DLQ |
| `MessageLockLost` / duplicados | Procesar más tiempo que el lock | Duración del procesamiento vs lock | Subir el lock, renovarlo, acortar el trabajo |
| Duplicados | Entrega *at-least-once* | Logs con el mismo `mensajeId` | Idempotencia |
| Mensajes fuera de orden | Sin sesiones/FIFO/clave consistente | Clave y partición | Usar sesión, FIFO o clave de partición |
| El lag crece | Consumidores insuficientes o lentos | Métrica de lag | Escalar consumidores (hasta nº de particiones) |
| Una partición muy cargada | Clave desbalanceada | Métricas por partición | Mejorar la clave |
| 401/403 `Unauthorized` | Falta rol de datos | Roles de la identidad | Asignar Sender/Receiver |
| Kafka: `SaslAuthenticationException` | Usuario/clave mal formados | Cadena `$ConnectionString` | Revisar la configuración JAAS |
| Kafka: `TimeoutException` al conectar | Puerto 9093 bloqueado o DNS privado mal | `ConnCheck.java` host 9093 | Abrir puerto, enlazar zona DNS (módulo 02) |
| `ServerBusy` / limitación | Se superó la capacidad del tier | Métricas de throttling | Escalar unidades o reducir ritmo |
| Mensaje rechazado por tamaño | Excede el límite del tier | Tamaño del mensaje | Claim Check |
| Suscripción sin mensajes | Filtro mal definido | Reglas de la suscripción | Corregir el filtro |
| SQS: el mensaje reaparece | No se borró o venció el *visibility timeout* | Código de borrado y timeout | Borrar tras procesar; ajustar el timeout |

---

## 15. Costos (qué los dispara)

| Servicio | Se paga principalmente por |
|---|---|
| Storage Queue | Operaciones y almacenamiento |
| Service Bus | Operaciones (Standard) o unidades de mensajería (Premium) |
| Event Hubs | Unidades de rendimiento/procesamiento y eventos |
| Event Grid | Operaciones |
| SQS / SNS / Kinesis / MSK | Peticiones, shards u horas de broker según servicio |
| Pub/Sub | Volumen de datos |

Lo que sorprende: **Premium/dedicado encendido** sin necesidad, retención larga, y mensajes grandes que podrían ser referencias.

---

## 16. Repaso y entrevista

**Repaso**
1. ¿Qué diferencia hay entre una cola, un tópico y un stream?
2. ¿Por qué el orden solo se garantiza dentro de una partición?
3. ¿Qué significa at-least-once y cómo te proteges de los duplicados?
4. ¿Qué es un mensaje venenoso y qué haces con él?
5. ¿Qué equivale a Event Hubs en AWS, OCI y GCP? ¿Es Kafka "de verdad"?

**Entrevista**
- Diseña el flujo de pedidos de una tienda online con cola, tópico y DLQ.
- ¿Cómo garantizas procesar un pago una sola vez aunque el mensaje llegue dos veces?
- ¿Cuántos consumidores pones en un grupo con 8 particiones y por qué?
