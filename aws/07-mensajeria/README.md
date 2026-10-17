# AWS · 07 Mensajería

Cuando dos piezas de tu sistema deben hablar **sin esperarse**, necesitas algo en medio: una cola, un tópico, un bus o un registro de eventos. Este capítulo reúne las cinco piezas de AWS para eso. La diferencia entre ellas no es «cuál es mejor», sino **qué pregunta responde cada una**.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [SQS](sqs/README.md) | ¿Quién hace **este trabajo**, y qué pasa si falla? | La bandeja de pendientes de una oficina | Una cola de trabajo con reintentos, retraso, DLQ y escalado de consumidores |
| [SNS](sns/README.md) | ¿Quién más debe **enterarse**? | El altavoz del edificio | Un hecho que debe llegar a varios sistemas (fan-out), con filtros por suscriptor |
| [EventBridge](eventbridge/README.md) | ¿A quién le **corresponde** este evento según su contenido? | La central de despacho de un puerto | Enrutar por contenido, reaccionar a eventos de servicios de AWS, archivar y reproducir |
| [Kinesis Data Streams](kinesis-data-streams/README.md) | ¿Qué **pasó, en qué orden**, y puedo releerlo? | Una cinta con carriles y marcadores de lectura | Flujos continuos (clics, telemetría) con orden por clave, varios lectores y relectura |
| [MSK (Kafka)](msk-kafka/README.md) | Lo mismo, **con el ecosistema Kafka** | Una central de correos con buzones numerados, administrada | Kafka estándar: Connect, Streams, clientes existentes, control fino |

> No compiten tanto como parece: las piezas se **encadenan**. Un patrón muy común es *EventBridge o SNS → SQS por consumidor*, y un flujo de alto volumen en *Kinesis o MSK* que alimenta analítica.

## Árbol de decisión: «quiero que…»

```
¿Quiero repartir TRABAJO entre varios workers, con reintentos y cola de fallos?
   └─ SQS (estándar; FIFO solo si el orden por grupo es obligatorio)

¿Quiero que UN hecho llegue a varios sistemas, cada uno con su cola?
   └─ SNS → una cola SQS por suscriptor (con filtros en el tópico)

¿Quiero decidir el destino según CAMPOS del evento, o reaccionar a lo que AWS ya emite?
   └─ EventBridge (bus por dominio; reglas; DLQ por destino)

¿Quiero poder REPRODUCIR lo que pasó la semana pasada tras corregir un error?
   ├─ Pocos miles de eventos de negocio → EventBridge: archivo y replay
   └─ Flujo continuo de alto volumen → Kinesis o MSK (retención + posición de lectura)

¿Quiero orden estricto POR CLAVE (por usuario, por pedido) con mucho volumen?
   └─ Kinesis (clave de partición) o MSK (clave del mensaje)

¿Ya uso Kafka, o necesito Connect / Streams / clientes Kafka existentes?
   └─ MSK (Serverless para empezar; aprovisionado para control fino)

¿Quiero avisar a PERSONAS (correo, SMS, móvil)?
   └─ SNS

¿Quiero un cron con zona horaria?
   └─ EventBridge Scheduler (no una cola)

¿El mensaje es MÁS GRANDE que el límite del servicio?
   └─ Claim Check: el archivo a S3 y el ticket por la cola/tópico (capítulo 06)
```

## Comparativa

| Característica | SQS | SNS | EventBridge | Kinesis | MSK |
|---|---|---|---|---|---|
| **Modelo** | Cola | Publicación/suscripción | Bus con reglas | Registro particionado (log) | Registro particionado (log) |
| **Quién recibe** | Un consumidor por mensaje | Todos los suscriptores (con filtro) | Los destinos cuya regla coincide | Cada consumidor lee todo | Cada grupo lee todo |
| **El mensaje, tras leerlo** | Se **borra** (tú lo confirmas) | No se guarda | No se guarda (salvo archivo) | **Se queda** hasta la retención | **Se queda** hasta la retención |
| **Releer / reproducir** | No | No | Archivo y replay | Sí (posición de lectura) | Sí (offsets) |
| **Orden** | FIFO por grupo (estándar: no) | FIFO por grupo (estándar: no) | No garantizado | Por shard (clave de partición) | Por partición (clave) |
| **Entrega** | Al menos una vez (FIFO: sin duplicados en su ventana) | Al menos una vez | Al menos una vez | Al menos una vez | Configurable (idempotencia/transacciones) |
| **Filtrado** | No (el consumidor decide) | Política por suscripción | Patrones ricos por regla | No (el consumidor filtra) | No (el consumidor filtra) |
| **Reintentos / fallos** | Visibilidad + DLQ | Reintentos + DLQ por suscripción | Reintentos + DLQ por destino | El lector reintenta (KCL/Lambda) | El lector reintenta (error handler) |
| **Tamaño del mensaje** | Hasta 1 MiB *(verifica)* | Hasta 1 MiB *(verifica)* | Hasta 1 MiB *(verifica)* | Hasta 1 MiB *(verifica)* | Configurable (por defecto ~1 MiB) |
| **Operación** | Cero | Cero | Cero | Casi cero (shards o bajo demanda) | Media (clúster, tópicos, particiones) |
| **Costo base** | Por solicitud | Por publicación y entrega | Por evento publicado | Por stream/shard-hora + datos | Por broker-hora (o uso en Serverless) |
| **Error típico** | Visibilidad menor que el procesamiento; sin DLQ | Filtro con atributo de tipo equivocado | Patrón que no coincide; destino sin permiso | Clave con pocos valores (shard caliente) | Autocreación de tópicos; rebalanceos |

## La receta ModaLima (cómo se ve junto)

| Flujo | Pieza | Por qué |
|---|---|---|
| Clics de la web | **Kinesis** `prod-clics` (clave `idSesion`) + KCL de analítica | Alto volumen, orden por sesión, relectura si analítica falla |
| «Orden creada» | **EventBridge** bus `prod-ordenes` | Contrato versionado y enrutamiento por contenido |
| Facturación y logística | **SQS** una cola por consumidor (destinos de las reglas) + DLQ | Reintentos y aislamiento de fallos |
| Alertas a operaciones | **SNS** → correo / chat | Personas, no sistemas |
| Subida de archivos grandes | **S3** + **Claim Check** sobre SQS | Evitar mensajes grandes ([capítulo 06](../06-storage/README.md)) |
| Inventario de Café Andino con muchos equipos | **MSK** + MSK Connect a S3 | Ecosistema Kafka y archivo en el lago de datos |
| Cierre de caja | **EventBridge Scheduler** a las 23:00 `America/Lima` | Horario sin sorpresas de zona horaria |

## Orden recomendado de adopción

1. **SQS con DLQ** en el primer flujo asíncrono: reintentos, alarma por antigüedad del mensaje más viejo.
2. **SNS → SQS** cuando aparece el segundo consumidor del mismo hecho.
3. **EventBridge** cuando necesitas enrutar por contenido, integrar equipos con un contrato o reaccionar a eventos de AWS.
4. **Kinesis** al aparecer un flujo continuo con orden por clave y varios lectores.
5. **MSK** solo si necesitas el ecosistema Kafka (o ya lo tienes): empieza en Serverless, pasa a aprovisionado cuando necesites control.
6. **Todo como código** (capítulo 10): colas, tópicos, buses, streams y clústeres versionados y revisados.

## Reglas transversales

- **Consumidores idempotentes.** Todas estas piezas entregan *al menos una vez*: habrá duplicados.
- **Cada consumidor, su cola y su DLQ.** Un fallo ajeno no debe frenarte.
- **Alarma sobre lo que envejece:** antigüedad del mensaje más viejo (SQS), `FailedInvocations` (EventBridge), atraso del iterador (Kinesis), *lag* (MSK), mensajes en DLQ.
- **Contratos versionados:** `version` en el mensaje; cambios compatibles.
- **Mensajes pequeños:** referencias a datos grandes (Claim Check), no los datos.
- **Sin datos personales en atributos, claves ni nombres** (se ven en filtros, métricas y registros).
- **Permisos por recurso:** quien publica no lee; quien lee no administra. Políticas de recurso con `aws:SourceArn`.
- **Cifrado** con KMS y permisos de la clave para productores y lectores.
- **Resultado por elemento:** en lotes (`SendMessageBatch`, `PublishBatch`, `PutEvents`, `PutRecords`) HTTP 200 no significa «todo entregado»; revisa cada entrada y reintenta solo las fallidas.
- **Prueba los caminos de fallo** (permiso faltante, mensaje venenoso, lector caído), no solo el feliz.

## Java en mensajería: qué construye cada `uso-en-java.md`

Todos siguen el mismo molde: **un núcleo puro** (se prueba sin red), **un envoltorio del SDK** y los mismos casos en Spring MVC, WebFlux, Quarkus imperativo y Mutiny.

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| SQS | Espera con *jitter*, claves de grupo y deduplicación FIFO, envío por lotes con fallos parciales, consumidor con visibilidad dinámica | Núcleo puro + lotes con reintento por elemento |
| SNS | Atributos tipados, evaluador de políticas de filtro, desempaquetado del sobre, `PublishBatch` | Lo mismo + validación de entrada no confiable |
| EventBridge | Escritor de `detail` sin dependencias, evaluador de patrones, lectura del evento con fuente permitida, `PutEvents` por lotes | Lotes limitados por cantidad **y** bytes |
| Kinesis | Simulador de reparto de claves, comparación de secuencias, productor por lotes, lector, consumidor KCL | Lotes + checkpoint después de procesar |
| MSK | Propiedades de cliente con IAM, validador de nombres, planificador de particiones y disco, creación idempotente de tópicos; Spring Kafka, reactor-kafka, Quarkus Messaging | Configuración centralizada + `AdminClient` idempotente |

Reglas comunes: en reactivo, todo SDK bloqueante va a `boundedElastic` / pool de trabajo; cierre ordenado (`destroyMethod`, `@Disposes`, `detener()`); credenciales por la cadena por defecto (nunca claves en archivos).

## Cómo se relaciona con otros capítulos

- [Fundamentos](../00-fundamentos/README.md): regiones, cuotas y costos que afectan a cada servicio.
- [Red](../01-red/README.md): endpoints de VPC para SQS, SNS, EventBridge y Kinesis; MSK vive en subredes privadas.
- [IAM](../02-iam/README.md): roles de servicio, identidad de pods y políticas por recurso.
- [Secretos](../03-secretos/README.md): usuarios SCRAM de MSK y credenciales de *API destinations*.
- [Compute](../04-compute/README.md): Lambda como consumidor (SQS, Kinesis, MSK), pods en EKS y tareas en ECS que producen y consumen.
- [Storage](../06-storage/README.md): eventos de S3, Claim Check y archivos grandes.
- [Datos](../08-datos/README.md): flujos de cambios de bases de datos hacia colas y streams.
- [Terraform en AWS](../10-terraform/README.md): todo lo anterior como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
