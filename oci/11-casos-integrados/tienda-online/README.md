# Oracle OCI · Caso integrado · Tienda online de ModaLima

Crear un pedido, cobrarlo y avisar a facturación, despacho y correos **sin perder eventos ni duplicar facturas**, con todo en subredes privadas y sin llaves en el código.

## 1. Qué es

**Analogía:** la caja de una tienda con libreta. La cajera anota la venta y, en la misma línea de la libreta, «avisar a bodega» (outbox). Un ayudante recorre la libreta y lleva los avisos; si se cae en el camino, vuelve a la libreta y reintenta. La bodega tacha cada aviso recibido para no despachar dos veces (inbox).

```
 Cliente ─► WAF ─► Load Balancer ─► Ingress OKE ─► pods "pedidos" (workload identity)
                                                    │ 1 transacción: INSERT pedido + INSERT outbox
                                                    ▼
                                              ATP (servicio tp)
                                                    │ relay del outbox (cada 1 s)
                                                    ▼
                                              OCI Queue "pedidos-pagados" ─► facturación (inbox idempotente)
                                              Notifications "pedido-pagado" ─► despacho (webhook) · correos
 Secretos: Vault · Caché de catálogo: OCI Cache · Carritos: NoSQL · Comprobantes: Object Storage + PAR
```

## 2. Cómo funciona por dentro

### El viaje de una compra
1. El navegador llama a `POST /v1/pedidos` (WAF → LB → Ingress → pod).
2. El servicio valida el carrito (NoSQL) y los precios (caché → base).
3. **Una sola transacción** en ATP: inserta el pedido y una fila `outbox` con el evento `PedidoPagado`.
4. El **relay** lee filas pendientes del outbox, publica en Queue/Notifications y las marca enviadas.
5. Facturación consume la cola, registra el `id_evento` en su **inbox** (clave única) y factura; si el evento llega dos veces, la segunda inserción falla y no factura.
6. Despacho recibe el webhook de Notifications y también deduplica.

### Qué servicio resuelve cada necesidad
| Necesidad | Servicio | Capítulo |
|---|---|---|
| Filtrar ataques y repartir tráfico | WAF + Load Balancer + Ingress nativo | [05](../../05-ingress-api/README.md) |
| Correr los microservicios | OKE con workload identity | [04](../../04-compute/README.md) |
| Pedidos y outbox | Autonomous (ATP) | [08](../../08-datos/README.md) |
| Carritos | NoSQL con versión | [08](../../08-datos/nosql/README.md) |
| Tareas de facturación | Queue con DLQ | [07](../../07-mensajeria/queue/README.md) |
| Avisos a varios sistemas | Notifications | [07](../../07-mensajeria/notifications/README.md) |
| Comprobantes | Object Storage + PAR | [06](../../06-storage/README.md) |
| Contraseñas | Vault | [03](../../03-secretos/README.md) |

### La pieza difícil: «guardar y avisar» sin perder ni duplicar
- **Sin outbox**: si guardas y luego publicas, un fallo entre ambos pierde el evento; si publicas y luego guardas, puedes avisar algo que no existe.
- **Con outbox**: guardar y «anotar el aviso» es atómico; publicar es reintentable.
- **Con inbox**: el consumidor tolera duplicados (al menos una vez).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Hechos de negocio que otros deben conocer sí o sí | Outbox + cola/tema |
| Consultas entre servicios en el camino del usuario | Llamada directa con *timeout* (no eventos) |
| Un monolito pequeño sin consumidores externos | Transacción local basta |
| Transacciones distribuidas con 2PC | **No**: sagas con eventos y compensaciones |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Outbox** | Tabla de avisos pendientes escrita en la misma transacción |
| **Relay** | Proceso que publica el outbox |
| **Inbox** | Registro de eventos ya procesados (clave única) |
| **Saga** | Secuencia de pasos con compensaciones si algo falla |
| **Contrato de evento** | Esquema versionado del mensaje |

## 5. Cómo se usa
1. Infraestructura del flujo de eventos (cola con DLQ, tema, permisos): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Tablas de outbox e inbox: [`ejemplos/sql/outbox.sql`](ejemplos/sql/outbox.sql).
3. Relay e inbox en Java: [uso en Java](uso-en-java.md).
4. Prueba de punta a punta: [`ejemplos/cli/prueba.sh`](ejemplos/cli/prueba.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pods de pedidos (workload identity) | — | `use queues`, `use ons-topics`, `read secret-bundles` acotados |
| Facturación | — | `use queues` sobre su cola |
| Plataforma | `manage` de la infraestructura vía pipeline | — |

- Todo en subredes privadas; solo el LB es público y con WAF.
- Eventos con identificadores, no con datos de tarjeta ni personales completos.
- Usuarios de base por servicio.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Outbox en la misma transacción | Publicar «después» y rezar |
| Inbox con clave única por `id_evento` | Confiar en entrega única |
| Contratos de evento versionados | Cambiar el JSON sin avisar |
| DLQ con alarma | Reintentos infinitos |
| Relay idempotente y con lotes | Un relay que publica fila por fila sin marcar |

## 8. Límites, costos y versiones
- **Costo:** dominado por OKE, ATP y LB; Queue/Notifications son baratos *(verifica)*.
- **Límites** (verifica): tamaño de mensaje de Queue y Notifications; sesiones del servicio `tp`.
- **Terraform:** `oci_queue_queue`, `oci_ons_notification_topic`, `oci_identity_policy`.
- **SDK:** `QueueClient`, `NotificationDataPlaneClient`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
