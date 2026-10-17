# AWS · Mensajería · Amazon SNS (publicar/suscribir)

**SNS (Simple Notification Service) es un servicio de publicación/suscripción: publicas un mensaje en un *tópico* y SNS lo entrega a *todos* sus suscriptores** (colas SQS, funciones Lambda, endpoints HTTP, correo, SMS, notificaciones móviles, Firehose). Es el «fan-out»: un hecho, muchos interesados.

## 1. Qué es

**Analogía:** el **altavoz del edificio**. Anuncias una vez («llegó el pedido 48213») y cada área que se suscribió lo escucha: bodega, facturación, analítica. Cada una puede tener un filtro («solo me interesan pedidos de Lima»).

```
                         ┌──► SQS  facturación  (filtro: total > 100)
 Productor ──Publish──► TÓPICO ──► SQS  logística    (filtro: envio = "domicilio")
  (orden creada)         ├──► Lambda  notificaciones
                         └──► Firehose  analítica (todo)
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Tópico estándar** | Rendimiento muy alto; entrega al menos una vez; sin orden garantizado |
| **Tópico FIFO** | Orden por `MessageGroupId` y deduplicación; solo suscriptores SQS (FIFO y estándar) |
| **Suscripción** | Protocolo + endpoint (SQS, Lambda, HTTP/S, email, SMS, aplicación móvil, Firehose) |
| **Política de filtro** | JSON por suscripción: sobre **atributos del mensaje** (por defecto) o sobre el **cuerpo** (`FilterPolicyScope`) |
| **Entrega cruda (*raw*)** | Para SQS/HTTP: el suscriptor recibe tu mensaje tal cual, **sin el sobre JSON de SNS** |
| **Reintentos y DLQ de suscripción** | Si un suscriptor falla, SNS reintenta según la política; tras agotarla, va a la DLQ **de esa suscripción** |
| **Atributos del mensaje** | Pares tipados (String, Number, Binary) usados para filtrar |
| **Tamaño** | Hasta 1 MiB *(verifica; antes 256 KiB)* → más grande: [Claim Check](../../06-storage/claim-check/README.md) |
| **Cifrado** | SSE con KMS en el tópico |
| **Política de acceso** | Quién publica y quién se suscribe (incluye otras cuentas y servicios de AWS) |
| **Archivo y reproducción (FIFO)** | Mensajes archivados para reprocesar *(verifica)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Un evento debe llegar a varios sistemas (fan-out) | **SNS → varias colas SQS** |
| Cada suscriptor necesita solo parte de los eventos | **SNS con políticas de filtro** |
| Alertas a personas (correo/SMS) o notificaciones móviles | **SNS** |
| Orden estricto por entidad con varios consumidores | **SNS FIFO → SQS FIFO** |
| Enrutamiento complejo por contenido, orígenes de SaaS, reproducción | **EventBridge** ([guía](../eventbridge/README.md)) |
| Un solo consumidor | **SQS directo** (sin SNS) |
| Histórico reproducible por varios lectores | **Kinesis / Kafka** |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Tópico** | El «canal» donde publicas |
| **Suscripción** | Quién escucha y cómo |
| **Fan-out** | Un mensaje, muchos destinos |
| **Filtro** | Reglas para recibir solo lo que importa |
| **Raw delivery** | Recibir el mensaje sin sobre de SNS |
| **DLQ de suscripción** | Dónde van los mensajes que no se pudieron entregar |
| **Sobre (envelope)** | JSON con `Type`, `MessageId`, `Message`… que SNS agrega |

## 5. Cómo se usa
1. Crea el tópico (cifrado) y las colas suscritas con **entrega cruda**, **filtro** y **DLQ**: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Autoriza al tópico en la política de **cada cola** (`SourceArn`).
3. Publica con atributos (`tipo`, `total`, `envio`) para que los filtros funcionen: [`ejemplos/cli/sns.sh`](ejemplos/cli/sns.sh).
4. Cada suscriptor es **idempotente** y tiene su propia DLQ.
5. Prueba la política de filtro con eventos reales antes de producción ([uso en Java](uso-en-java.md) trae un evaluador).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Productor** | — | `sns:Publish` al tópico |
| **Suscriptor SQS** | — | Política de **su cola** autoriza al tópico (`SourceArn`) |
| **Pipeline** | `sns:CreateTopic`, `Subscribe`, `SetSubscriptionAttributes` | — |

- **Política del tópico:** limita quién publica (por rol/cuenta/servicio) y quién puede suscribirse; evita `Principal: "*"`.
- **Cifrado:** si el tópico usa KMS, los servicios que publican (S3, CloudWatch…) necesitan permiso en la clave.
- **HTTP/S:** confirma la suscripción y **verifica la firma** de cada mensaje; con SQS/Lambda no hace falta.
- **Datos personales:** no los pongas en atributos (se ven en filtros y logs).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| SNS → SQS por suscriptor (aísla fallos) | Lambda/HTTP directo sin cola para flujos críticos |
| Entrega cruda cuando el consumidor es tuyo | Parsear el sobre en todos los consumidores sin necesidad |
| Filtros en el tópico (ahorra mensajes y costo) | Filtrar en cada consumidor |
| DLQ por suscripción + alarma | Reintentos sin destino de fallos |
| Atributos tipados (`Number` para importes) | Todo como String y comparar texto |
| Versionar el esquema (`version` en el mensaje) | Cambiar el formato sin avisar |
| FIFO solo si necesitas orden | FIFO por costumbre (menos rendimiento) |

## 8. Límites, costos y versiones
- **Costo:** por publicación y por entrega (SQS/Lambda con precio bajo; SMS/correo/móvil más caros); cada 64 KiB cuenta como una solicitud *(verifica)*.
- **Límites** *(verifica)*: suscripciones por tópico, tamaño del mensaje, filtros (complejidad de política), `PublishBatch` de 10.
- **Terraform:** `aws_sns_topic`, `aws_sns_topic_subscription` (con `raw_message_delivery`, `filter_policy`, `redrive_policy`). Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
