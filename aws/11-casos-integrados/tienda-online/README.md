# AWS · Caso integrado · Tienda online de ModaLima

Una tienda de ropa en línea **de punta a punta**: desde que el cliente toca «Comprar» hasta que se factura, se guarda el comprobante y se avisa por correo, usando solo servicios de AWS y **sin ninguna clave en el código**. Este caso no explica cada servicio (para eso están los capítulos 00–10): enseña **cómo se conectan** y dónde se rompen.

## 1. Qué es

**Analogía:** una tienda física con almacén. La *vitrina* (CloudFront) recibe al público y el guardia (WAF) revisa quién entra; el *mostrador* (API Gateway) atiende solo pedidos con formato correcto; la *trastienda* (ECS Fargate) tiene a los empleados (microservicios); el *libro de caja* (Aurora) guarda lo que no puede perderse; el *buzón interno* (EventBridge + SQS) reparte avisos entre áreas sin que nadie espere a nadie.

```
 Cliente ─► CloudFront + WAF ─► API Gateway (HTTP API) ─► VPC Link ─► ALB interno ─► ECS Fargate
 (web/app)    (borde, TLS)       (JWT, cuotas)            (solo VPC)                ┌──────────────┐
                                                                                    │ catalogo     │──► ElastiCache (caché)
                                                                                    │ pedidos      │──► Aurora ──┐ misma transacción
                                                                                    │ publicador   │◄── bandeja_salida ◄┘
                                                                                    │ facturacion  │◄── SQS ◄─┐
                                                                                    │ comprobantes │──► S3 (PDF) + URL prefirmada corta
                                                                                    │ notificacion │◄── SQS ◄─┤  reglas por contenido
                                                                                    └──────────────┘          │
                                                           publicador ─► EventBridge bus "prod-ordenes" ──────┘
      Todo lo de la derecha, por VPC endpoints / subredes privadas · rol IAM por servicio (task role) · secretos en Secrets Manager
      Logs y métricas en CloudWatch · Terraform lo crea · Organizations/Config/Budgets lo gobiernan
```

## 2. Cómo funciona por dentro

### El viaje de una compra

| # | Qué pasa | Quién | Detalle que importa |
|---|---|---|---|
| 1 | El cliente consulta el catálogo | CloudFront → API Gateway → `catalogo` | WAF filtra ataques; API Gateway valida el JWT; el catálogo sale de ElastiCache y, si falta, de Aurora |
| 2 | Agrega al carrito | `pedidos` → ElastiCache | El carrito vive con vencimiento; **no** es un dato crítico |
| 3 | Pulsa «Comprar» con `Idempotency-Key` | `pedidos` | Si reintenta por mala señal, no se duplica el pedido |
| 4 | Se guarda el pedido **y** el evento | `pedidos` → Aurora | **Una sola transacción**: `pedidos` + `bandeja_salida` |
| 5 | Se responde `201 Created` | `pedidos` | El cliente no espera a facturación |
| 6 | El publicador lee la bandeja y publica `PedidoCreado` | `publicador` → EventBridge | `FOR UPDATE SKIP LOCKED`; `PutEvents` por lotes de hasta 10; se revisa **cada entrada** |
| 7 | Las reglas reparten el evento | Bus `prod-ordenes` → SQS por consumidor | Facturación y notificaciones reciben todo; logística solo `envio` que empieza por «dom» |
| 8 | Facturación procesa **una vez** | `facturacion` + DynamoDB (bandeja de entrada) | Escritura condicional `attribute_not_exists`: el duplicado se descarta |
| 9 | El PDF se guarda en S3 | `comprobantes` → S3 | El evento lleva la **referencia** (Claim Check), no el archivo |
| 10 | Si algo falla repetidamente | DLQ del consumidor | Alarma + procedimiento de reproceso |

### Qué servicio resuelve cada necesidad

| Necesidad | Servicio | Capítulo |
|---|---|---|
| Borde, TLS, ataques | CloudFront + WAF | [05](../../05-ingress-api/cloudfront-waf/README.md) |
| Puerta de la API (JWT, cuotas) | API Gateway | [05](../../05-ingress-api/api-gateway/README.md) |
| Balanceo interno | ALB | [05](../../05-ingress-api/alb-nlb/README.md) |
| Ejecutar los microservicios | ECS Fargate | [04](../../04-compute/ecs-fargate/README.md) |
| Pedidos (transaccional) | Aurora PostgreSQL | [08](../../08-datos/rds-aurora/README.md) |
| Bandeja de entrada (idempotencia) | DynamoDB | [08](../../08-datos/dynamodb/README.md) |
| Caché de catálogo y carrito | ElastiCache | [08](../../08-datos/elasticache-redis/README.md) |
| Evento «PedidoCreado» y enrutamiento | EventBridge | [07](../../07-mensajeria/eventbridge/README.md) |
| Cola y DLQ por consumidor | SQS | [07](../../07-mensajeria/sqs/README.md) |
| Comprobantes | S3 + Claim Check | [06](../../06-storage/claim-check/README.md) |
| Descarga controlada | URLs prefirmadas | [06](../../06-storage/urls-prefirmadas/README.md) |
| Cadenas y claves | Secrets Manager + KMS | [03](../../03-secretos/secrets-manager/README.md) |
| Identidad de cada servicio | Roles de tarea (IAM) | [02](../../02-iam/iam-roles-politicas/README.md) |
| Red privada | VPC, SG, endpoints | [01](../../01-red/vpc-endpoints-privatelink/README.md) |
| Reglas y presupuesto | SCP, Config, Budgets | [09](../../09-gobierno/README.md) |
| Todo como código | Terraform | [10](../../10-terraform/README.md) |

### La pieza difícil: «guardar y avisar» sin perder ni duplicar

| Estrategia | Qué pasa si el proceso muere entre medio | Veredicto |
|---|---|---|
| Guardar en Aurora y luego `PutEvents` | Pedido sin evento (nadie factura) | ❌ pierde |
| `PutEvents` y luego guardar | Evento de un pedido que no existe | ❌ inventa |
| **Bandeja de salida** (pedido + evento en una transacción) y un publicador aparte | Se publica más tarde; si se publica dos veces, el consumidor lo descarta | ✅ al menos una vez + idempotencia |
| Capturar cambios de Aurora (CDC) | Igual de seguro, más piezas | ✅ si ya operas CDC |

La regla de oro: **entrega al menos una vez + consumidor idempotente = efecto exactamente una vez**. El `idEvento` se crea al guardar el pedido y es la clave de la bandeja de entrada.

## 3. Para qué sirve y cuándo NO

- **Sirve** para: cualquier flujo «guardar y avisar» con varios consumidores (pedidos, reservas, pagos, altas).
- **No** uses este diseño para: una sola app con un solo consumidor y sin crecimiento previsto (una cola SQS directa basta), ni para cargas donde el orden estricto por clave y la relectura son centrales (mira el caso [clickstream](../clickstream/README.md)).

## 4. Conceptos clave (en palabras simples)

- **Bandeja de salida (outbox):** tabla donde el servicio anota «debo avisar esto» en la misma transacción que el dato.
- **Bandeja de entrada (inbox):** tabla del consumidor con los `idMensaje` ya procesados; evita procesar dos veces.
- **Idempotencia:** hacer algo dos veces deja el mismo resultado que hacerlo una.
- **Entrega al menos una vez:** el sistema prefiere repetir antes que perder.
- **Regla por contenido:** EventBridge decide el destino mirando campos del evento.
- **DLQ:** cola de mensajes que no se pudieron procesar tras N intentos.
- **Contrato versionado:** el evento lleva `version` y solo cambia de forma compatible.

## 5. Cómo se usa

1. Crea la capa de eventos con [`ejemplos/terraform`](ejemplos/terraform/main.tf) (bus, archivo, reglas, colas, DLQ, bandeja de entrada, alarmas, políticas mínimas).
2. Crea las tablas con [`ejemplos/sql/bandeja-salida.sql`](ejemplos/sql/bandeja-salida.sql).
3. El servicio `pedidos` escribe pedido + bandeja en una transacción (`@Transactional`).
4. El `publicador` publica por lotes, marca los publicados y reintenta solo los fallidos.
5. Cada consumidor lee su cola, registra el `idMensaje` en DynamoDB con escritura condicional y recién entonces ejecuta el efecto.
6. Prueba un evento con [`ejemplos/cli/operacion.sh`](ejemplos/cli/operacion.sh).

## 6. Seguridad

| Identidad | Plano de control (crear/cambiar) | Plano de datos (usar) |
|---|---|---|
| Pipeline de Terraform (rol de aplicar) | Crea bus, reglas, colas, tablas | — |
| `publicador` (rol de tarea) | — | `events:PutEvents` solo sobre el bus `prod-ordenes` |
| `facturacion` (rol de tarea) | — | `sqs:ReceiveMessage/DeleteMessage` en **su** cola; `dynamodb:PutItem` en la bandeja de entrada |
| `comprobantes` (rol de tarea) | — | `s3:PutObject` en el prefijo de comprobantes |
| Persona de soporte | Solo lectura de colas | Sin acceso a cuerpos con datos personales |

- La cola solo acepta mensajes de **su regla** (`aws:SourceArn`).
- Sin datos personales en atributos, claves ni nombres de cola.
- Cifrado en reposo (SSE de SQS, KMS en Aurora/S3) y en tránsito (TLS).

## 7. Qué hacer / qué NO hacer

| Haz | No hagas |
|---|---|
| Pedido y evento en **una** transacción | `PutEvents` dentro del `@Transactional` «a ver si funciona» |
| `Idempotency-Key` desde el cliente | Confiar en que «no habrá reintentos» |
| Una cola y una DLQ **por consumidor** | Una cola compartida por todos |
| Revisar `FailedEntryCount` y cada entrada | Dar por bueno el HTTP 200 de `PutEvents` |
| Alarma por antigüedad del mensaje más viejo y por DLQ | Descubrir el atraso por un cliente enojado |
| Versionar el evento (`version`) | Cambiar un campo sin avisar |
| Archivo de EventBridge para reproducir | Reenviar a mano desde la base |

## 8. Límites, costos y versiones

- `PutEvents`: hasta 10 entradas y 256 KB por llamada *(verifica)*.
- SQS estándar: entrega al menos una vez, sin orden garantizado; visibilidad ≥ tiempo de procesamiento.
- Costos que suben primero: Aurora (instancias), NAT (si no usas endpoints), CloudFront/WAF por solicitud *(verifica precios)*.
- Versiones del código del caso: Java 21, Spring Boot 4.1.x, Quarkus 3.40.x, AWS SDK v2.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
