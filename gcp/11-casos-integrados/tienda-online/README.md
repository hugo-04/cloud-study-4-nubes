# Google Cloud · Caso integrado · Tienda online de ModaLima

Crear un pedido, cobrarlo y avisar a facturación, despacho y correos **sin perder eventos ni duplicar facturas**, todo privado y sin llaves en el código.

## 1. Qué es

**Analogía:** la caja de una tienda con libreta. La cajera anota la venta y, en la misma línea, «avisar a bodega» (outbox). Un ayudante recorre la libreta y lleva los avisos; si se cae, vuelve y reintenta. La bodega tacha cada aviso recibido para no despachar dos veces (inbox).

```
 Cliente ─► Cloud Armor ─► LB de aplicaciones externo ─► Cloud Run "pedidos" (SA run-pedidos, ingress interno+LB)
                                                          │ 1 transacción: INSERT pedido + INSERT outbox
                                                          ▼
                                                    Cloud SQL PostgreSQL (IP privada, IAM auth)
                                                          │ relay del outbox (Cloud Scheduler cada minuto o bucle)
                                                          ▼
                                                    Pub/Sub "pedido-pagado" (clave de orden = pedido)
                                                      ├─ suscripción facturacion (push OIDC, DLQ) ─► inbox idempotente
                                                      ├─ suscripción despacho
                                                      └─ suscripción correos
 Secretos: Secret Manager · Catálogo: Memorystore · Carritos: Firestore · Comprobantes: Cloud Storage + URL firmada
```

## 2. Cómo funciona por dentro

### El viaje de una compra
1. El navegador llama a `POST /v1/pedidos` (Cloud Armor → LB → Cloud Run).
2. El servicio valida el carrito (Firestore) y los precios (Memorystore → Cloud SQL).
3. **Una sola transacción** en Cloud SQL: inserta el pedido y una fila `outbox` con `PedidoPagado.v1`.
4. El **relay** toma filas pendientes (`FOR UPDATE SKIP LOCKED`), publica en Pub/Sub con atributos `id` y `tipo` y las marca enviadas.
5. Facturación recibe el push, registra el `id` en su **inbox** (clave única) y factura; un duplicado choca con la clave y se responde 2xx sin facturar.
6. Despacho y correos tienen su propia suscripción y su propio inbox.

### Qué servicio resuelve cada necesidad
| Necesidad | Servicio | Capítulo |
|---|---|---|
| Filtrar ataques y entrar | Cloud Armor + Cloud Load Balancing | [05](../../05-ingress-api/README.md) |
| Correr los microservicios | Cloud Run con SA propia | [04](../../04-compute/README.md) |
| Pedidos y outbox | Cloud SQL con IAM auth | [08](../../08-datos/cloud-sql/README.md) |
| Carritos | Firestore | [08](../../08-datos/firestore/README.md) |
| Difusión a facturación, despacho, correos | Pub/Sub con DLQ | [07](../../07-mensajeria/pubsub/README.md) |
| Comprobantes | Cloud Storage + URL firmada | [06](../../06-storage/README.md) |
| Tokens de la pasarela | Secret Manager | [03](../../03-secretos/README.md) |

### La pieza difícil: «guardar y avisar» sin perder ni duplicar
- **Sin outbox**: guardar y luego publicar pierde el evento si el proceso cae en medio; publicar y luego guardar avisa algo que no existe.
- **Con outbox**: guardar y anotar el aviso es atómico; publicar es reintentable.
- **Con inbox**: el consumidor tolera la entrega «al menos una vez» de Pub/Sub.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Hechos de negocio que otros deben conocer sí o sí | Outbox + Pub/Sub |
| Consultas entre servicios en el camino del usuario | Llamada directa con *timeout* |
| Un monolito pequeño sin consumidores | Transacción local basta |
| Transacciones distribuidas con 2PC | **No**: sagas con eventos y compensaciones |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Outbox** | Tabla de avisos pendientes en la misma transacción |
| **Relay** | Proceso que publica el outbox |
| **Inbox** | Registro de eventos ya procesados (clave única) |
| **Clave de orden** | Pub/Sub entrega en orden los mensajes de un mismo pedido |
| **Contrato de evento** | Esquema versionado (`PedidoPagado.v1`) |

## 5. Cómo se usa
1. Tema, suscripciones con DLQ y push OIDC, permisos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Tablas de outbox e inbox (PostgreSQL): [`ejemplos/sql/outbox.sql`](ejemplos/sql/outbox.sql).
3. Relay e inbox en [Java](uso-en-java.md).
4. Prueba de punta a punta: [`ejemplos/cli/prueba.sh`](ejemplos/cli/prueba.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| `run-pedidos` | — | `roles/pubsub.publisher` en el tema, `cloudsql.client` + `instanceUser`, `secretAccessor` acotado |
| `pubsub-push` | — | `roles/run.invoker` en facturación |
| Plataforma | Roles de infraestructura vía pipeline | — |

- Cloud Run con ingress interno + LB; Cloud SQL sin IP pública.
- Eventos con identificadores, no con datos de tarjeta ni personales completos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Outbox en la misma transacción | Publicar «después» y rezar |
| Inbox con clave única | Confiar en entrega única |
| Contratos versionados (atributo `tipo`) | Cambiar el JSON sin avisar |
| DLQ con alerta | Reintentos infinitos |
| Relay por lotes con `SKIP LOCKED` | Varios relays pisándose |

## 8. Límites, costos y versiones
- **Costo:** dominado por Cloud Run, Cloud SQL y el LB; Pub/Sub por volumen *(verifica)*.
- **Límites** (verifica): 10 MB por mensaje de Pub/Sub, orden por clave con endpoint regional, conexiones de Cloud SQL.
- **Terraform:** `google_pubsub_topic`, `google_pubsub_subscription`, `google_cloud_run_v2_service_iam_member`.
- **Java:** `google-cloud-pubsub` (`Publisher`), conector de Cloud SQL.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
