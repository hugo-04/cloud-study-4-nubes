# Google Cloud · Mensajería · Pub/Sub

Mensajería **publicar/suscribir** global y sin servidores: publicas en un **tema**, y cada **suscripción** recibe su copia (pull, push o exportación a BigQuery/Cloud Storage). Escala sola a millones de mensajes por segundo, con reintentos, DLQ, filtros, orden por clave y entrega exactamente una vez opcional.

## 1. Qué es

**Analogía:** el correo interno de una empresa con buzones por área. Envías un sobre al tema «pedidos-pagados»; facturación, despacho y analítica tienen cada uno su buzón (suscripción) y reciben su copia; si alguien no confirma que la leyó, el sobre vuelve a su buzón.

```
 Productores ─► Tema "pedidos-pagados" (retención 7 días, esquema Avro/Protobuf opcional)
                 ├─ Suscripción "facturacion" (pull, ack 60 s, orden por clave=idCliente, DLQ tras 5)
                 ├─ Suscripción "despacho"    (push OIDC → Cloud Run, filtro attributes.tipo = "fisico")
                 └─ Suscripción "analitica"   (exportación directa a BigQuery)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Tema** | Destino de publicación; retención opcional; esquema opcional |
| **Mensaje** | Datos (hasta 10 MB *(verifica)*) + atributos + `messageId` + `publishTime` + clave de orden opcional |
| **Suscripción** | Pull (tu app pide), push (Pub/Sub llama a tu HTTPS), BigQuery, Cloud Storage |
| **Ack deadline** | Tiempo para confirmar; si no, se reentrega (se puede extender) |
| **Retención** | Mensajes no confirmados (y confirmados, si se activa) hasta 7 días; *seek* para releer |
| **Orden** | Por clave de orden (`orderingKey`) con la opción habilitada en la suscripción |
| **Exactly-once** | Opción por suscripción (pull) que evita reentregas tras un ack exitoso *(verifica alcance)* |
| **Filtros** | Por atributos, al crear la suscripción |
| **DLQ** | Tema de mensajes muertos tras N intentos |
| **Política de reintentos** | Backoff exponencial entre reentregas |

### Garantías
Al menos una vez (por defecto); el orden solo existe por clave; los consumidores deben ser idempotentes.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Eventos de negocio a varios sistemas | **Pub/Sub** |
| Ingestar eventos a BigQuery sin código | Suscripción BigQuery |
| Tareas a un endpoint con tasa controlada y agenda | [Cloud Tasks](../cloud-tasks/README.md) |
| Eventos de servicios de Google (auditoría, Storage) enrutados | [Eventarc](../eventarc/README.md) |
| Ecosistema Kafka existente | [Managed Kafka](../managed-kafka/README.md) |
| Mensajes de varios MB | Claim check con Cloud Storage |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Ack / nack** | «Listo» / «devuélvelo» |
| **Clave de orden** | Mensajes con la misma clave llegan en orden |
| **Seek** | Rebobinar una suscripción a un momento o snapshot |
| **Flow control** | Límite de mensajes/bytes en vuelo en el suscriptor |
| **Idempotencia** | Procesar dos veces = una vez |

## 5. Cómo se usa
1. Tema con esquema opcional, suscripciones pull con orden y DLQ, y push con OIDC: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Publicador con clave de orden y suscriptor que confirma solo al terminar y clasifica fallas: [uso en Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/pubsub.sh`](ejemplos/cli/pubsub.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/pubsub.admin` | — |
| Productor | — | `roles/pubsub.publisher` en el tema |
| Consumidor | — | `roles/pubsub.subscriber` en la suscripción |
| Agente de Pub/Sub (DLQ) | — | `publisher` en el tema DLQ y `subscriber` en la suscripción origen |

- Permisos por tema/suscripción, no por proyecto.
- Push con OIDC hacia servicios privados.
- CMEK si los datos lo exigen; mensajes con identificadores, no datos personales completos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Ack después de procesar | Ack al recibir |
| Flow control en el suscriptor | Recibir más de lo que puedes procesar |
| DLQ con alarma | Mensajes venenosos eternos |
| Clave de orden solo donde haga falta | Ordenar todo (limita el paralelismo) |
| Un `Publisher` por tema y aplicación | Uno por mensaje |

## 8. Límites, costos y versiones
- **Costo:** por volumen (TiB) publicado y entregado, almacenamiento de mensajes retenidos *(verifica)*.
- **Límites** (verifica): tamaño de mensaje, ack deadline máximo (600 s), retención (7 días o 31 en temas).
- **Terraform:** `google_pubsub_topic`, `google_pubsub_subscription`, `google_pubsub_schema`, `*_iam_member`.
- **Java:** `Publisher`, `Subscriber` (`google-cloud-pubsub`); Spring Cloud GCP opcional.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
