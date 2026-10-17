# Azure · Caso integrado · Tienda online de ModaLima

Una tienda de ropa en línea **de punta a punta**: desde que el cliente toca «Comprar» hasta que se factura, se guarda el comprobante y se avisa por correo, usando solo servicios de Azure y **sin ninguna contraseña en el código**. Este caso no explica cada servicio desde cero (para eso están sus capítulos); explica **cómo encajan** y qué se rompe cuando no se piensan juntos.

## 1. Qué es

**Analogía:** una tienda física con almacén. La *vitrina* (Front Door) recibe al público y el guardia (WAF) revisa quién entra; el *mostrador* (API Management) atiende solo pedidos con formato correcto; la *trastienda* (AKS) tiene los empleados (microservicios) que hablan entre sí por **buzones** (Service Bus) en vez de gritarse; el *archivo* (SQL, Blob) guarda lo importante bajo llave (Key Vault, Private Endpoint). Nadie lleva llaves en el bolsillo: cada empleado tiene un **carnet** (identidad administrada) que la puerta reconoce.

```
 Cliente ──► Front Door + WAF ──► API Management ──► Ingress interno ──► AKS
 (web/app)     (borde, TLS)        (cuotas, JWT)       (solo VNet)     ┌──────────────┐
                                                                       │ catalogo     │──► Redis (caché)
                                                                       │ pedidos      │──► Azure SQL ──┐ misma transacción
                                                                       │ publicador   │◄── bandeja_salida ◄┘
                                                                       │ facturacion  │◄── Service Bus (tópico eventos-pedido)
                                                                       │ comprobantes │──► Blob (PDF) + SAS corto
                                                                       └──────────────┘
          Todo lo de la derecha entra por Private Endpoint · identidades por pod (Workload Identity) · secretos en Key Vault
          Todo emite logs y métricas a Log Analytics / Application Insights · Terraform lo crea · Policy/Locks/Budget lo gobiernan
```

## 2. Cómo funciona por dentro

### El viaje de una compra (paso a paso)

| # | Qué pasa | Quién | Detalle que importa |
|---|---|---|---|
| 1 | El cliente abre la tienda y consulta el catálogo | Front Door → APIM → `catalogo` | El WAF filtra ataques; APIM valida el token y aplica cuotas; el catálogo sale de **Redis** (caché) y, si falta, de la base |
| 2 | Agrega al carrito | `pedidos` → Redis | El carrito vive en Redis con vencimiento; **no** es un dato crítico |
| 3 | Pulsa «Comprar» con una clave de idempotencia | `pedidos` | El cliente envía `Idempotency-Key`: si reintenta por mala señal, no se duplica el pedido |
| 4 | Se guarda el pedido **y** el evento | `pedidos` → Azure SQL | **Una sola transacción**: tabla `pedidos` + tabla `bandeja_salida` (patrón de bandeja de salida) |
| 5 | Se responde `201 Created` al cliente | `pedidos` | El cliente ya no espera a facturación: la compra es asíncrona |
| 6 | El publicador lee la bandeja y publica `pedido.creado` | `publicador` → Service Bus | `FOR UPDATE SKIP LOCKED` para que varias réplicas no se pisen; `MessageId` determinista |
| 7 | Facturación recibe el mensaje | Suscripción `facturacion` → `facturacion` | Procesa **una vez** aunque llegue dos (bandeja de entrada) |
| 8 | Se genera el comprobante y se guarda | `comprobantes` → Blob | El PDF no viaja por el bus (**Claim Check**); el cliente lo descarga con una SAS corta o un enlace propio |
| 9 | Se avisa por correo/WhatsApp | `notificaciones` (suscripción propia) | Otra suscripción al mismo tópico: se agrega sin tocar a `pedidos` |
| 10 | Si algo falla repetidamente | Cola de mensajes fallidos (DLQ) | Alerta + procedimiento de reproceso |

### Las capas y qué servicio resuelve cada necesidad

| Necesidad | Servicio | Capítulo | Por qué ese |
|---|---|---|---|
| Entrada global, TLS, filtrado de ataques | Front Door + WAF | [05](../../05-ingress-api/front-door-waf/README.md) | Borde y firewall de aplicaciones |
| Puerta única de la API (JWT, cuotas, versiones) | API Management | [05](../../05-ingress-api/apim/README.md) | Políticas sin tocar el código |
| Enrutar dentro del clúster | Ingress de AKS | [05](../../05-ingress-api/ingress-aks/README.md) | Rutas por servicio, solo desde la VNet |
| Ejecutar los microservicios | AKS | [04](../../04-compute/aks/README.md) | Muchos servicios con escalado y red propios |
| Pedidos y facturación (transaccional) | Azure SQL | [08](../../08-datos/azure-sql/README.md) | Integridad, transacciones, bandeja de salida |
| Carrito y catálogo en caché | Redis | [08](../../08-datos/redis/README.md) | Lecturas rápidas, datos que se pueden perder |
| Eventos entre servicios con garantías | Service Bus | [07](../../07-mensajeria/service-bus/README.md) | Colas/tópicos, reintentos, DLQ, duplicados |
| Archivos grandes (PDF, imágenes) | Blob Storage + Claim Check | [06](../../06-storage/blob-storage/README.md) · [claim check](../../06-storage/claim-check/README.md) | El bus lleva la referencia, no el archivo |
| Descarga controlada del comprobante | SAS tokens | [06](../../06-storage/sas-tokens/README.md) | Enlace con vencimiento corto |
| Cadenas, certificados, claves | Key Vault | [03](../../03-secretos/key-vault/README.md) | Secretos fuera del código, con rotación |
| Identidad de cada pod | Workload Identity + RBAC | [02](../../02-iam/workload-identity/README.md) · [RBAC](../../02-iam/rbac/README.md) | Sin claves; permisos mínimos por servicio |
| Red privada | VNet, NSG, Private Endpoint + DNS | [01](../../01-red/private-endpoint-dns/README.md) | Los datos no tienen IP pública |
| Reglas y presupuesto | Policy, bloqueos, Cost Management | [09](../../09-gobierno/README.md) | Nadie crea una base pública un viernes |
| Todo como código | Terraform | [10](../../10-terraform/README.md) | Repetible y revisable |

### La pieza difícil: «guardar y avisar» sin perder ni duplicar

Es el corazón del caso y la fuente de la mayoría de los incidentes reales. Está explicado con tabla de estrategias, diagrama y código en [`uso-en-java.md`](uso-en-java.md). En una frase: **el evento se escribe en la misma transacción que el pedido; se publica después; se puede publicar dos veces; por eso el que consume es idempotente.** El esquema está en [`ejemplos/sql/esquema.sql`](ejemplos/sql/esquema.sql) y el evento de ejemplo en [`ejemplos/json/evento-pedido-creado.json`](ejemplos/json/evento-pedido-creado.json).

### La red privada, en una mirada

| Recurso | Dónde vive | Cómo se llega |
|---|---|---|
| APIM, Ingress interno | Subred `snet-apim` / ruta interna | Desde Front Door según el nivel de APIM (verifica en la doc oficial) |
| Pods de AKS | Subred `snet-aks` | Salen hacia los datos por la VNet |
| SQL, Key Vault, Blob, Service Bus | **Private Endpoint** en `snet-pe` | Nombre público → DNS privado → IP privada de la VNet |
| NSG de `snet-pe` | — | Permite solo desde `snet-aks` a los puertos 443/1433/5671 y niega el resto |

Terraform de esta red: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf). Comprobación desde un pod: [`ejemplos/cli/verificar-privado.sh`](ejemplos/cli/verificar-privado.sh). Service Bus con Private Endpoint requiere el nivel **Premium**.

## 3. Para qué sirve y cuándo NO

**Sirve como plano de referencia** para cualquier venta en línea, reservas o pedidos: transacciones propias + eventos entre servicios + archivos + red privada.

| Situación | ¿Esta arquitectura? | Alternativa |
|---|---|---|
| 5 000 pedidos/día, 3 equipos, varios servicios que reaccionan a pedidos | ✅ | — |
| Un solo equipo y una tienda sencilla | ⚠️ Demasiado | Un App Service + Azure SQL y un solo módulo; añade mensajería cuando duela |
| Campañas con picos de 50× | ✅ con colas y escalado | Más réplicas, límites en APIM, caché del catálogo |
| Necesidad de procesar millones de eventos/seg (clics) | ❌ para eso | Ver el caso [clickstream](../clickstream/README.md) |
| Reglas que exigen todo en una sola transacción entre dominios | ❌ | Mantén esos datos en el mismo servicio |

## 4. Conceptos clave (en palabras simples)

| Término | En simple |
|---|---|
| **Bandeja de salida (outbox)** | Una tabla donde dejas el evento *junto con* el pedido; otro proceso lo publica después. Garantiza no perder eventos |
| **Bandeja de entrada (inbox)** | Una tabla de «mensajes ya vistos» para no procesar dos veces el mismo |
| **Idempotente** | Hacerlo una o diez veces deja el mismo resultado |
| **Al menos una vez** | La mensajería promete entregar, no entregar una sola vez: por eso la idempotencia |
| **Detección de duplicados** | Service Bus descarta mensajes con el mismo `MessageId` dentro de una ventana |
| **Claim Check** | Guardar el archivo aparte y enviar solo su referencia |
| **Cola de mensajes fallidos (DLQ)** | Donde van los mensajes que no se pudieron procesar tras varios intentos |
| **Idempotency-Key** | Cabecera que manda el cliente para que un reintento no cree otro pedido |
| **Private Endpoint** | Una IP privada para un servicio de Azure, dentro de tu red |
| **Workload Identity** | Cada pod se presenta ante Azure con su propio carnet, sin contraseña |
| **Plano de control / de datos** | Administrar el recurso frente a usar su contenido; tienen permisos distintos |

## 5. Cómo se usa (orden de construcción)

1. **Gobierno mínimo**: grupo de administración, política de etiquetas en `Audit`, presupuesto con alertas ([09](../../09-gobierno/README.md)).
2. **Red**: VNet, subredes, NSG, zonas DNS privadas ([01](../../01-red/README.md)) → [`terraform/main.tf`](ejemplos/terraform/main.tf).
3. **Identidad**: una identidad por servicio con Workload Identity y sus roles ([02](../../02-iam/README.md)).
4. **Datos y mensajería**: SQL, Key Vault, Blob y Service Bus Premium con Private Endpoint; deshabilitar acceso público.
5. **Cómputo**: AKS con Ingress interno; APIM y Front Door al final.
6. **Observabilidad** desde el primer día: consultas en [`kql-tienda.md`](ejemplos/kql/kql-tienda.md).
7. **Verifica** desde un pod con [`verificar-privado.sh`](ejemplos/cli/verificar-privado.sh) antes de publicar.

## 6. Seguridad

### Permisos por plano (quién necesita qué)

| Identidad | Plano de control (administrar) | Plano de datos (usar) |
|---|---|---|
| Pipeline de Terraform | Contributor en el grupo de recursos + RBAC Administrator acotado ([10](../../10-terraform/autenticacion-y-pipelines/README.md)) | — |
| Pod `pedidos` | — | *Azure Service Bus Data Sender* (tópico) · acceso SQL por Entra ID · Redis |
| Pod `publicador` | — | *Azure Service Bus Data Sender* · SQL (lee/marca la bandeja) |
| Pod `facturacion` | — | *Azure Service Bus Data Receiver* (su suscripción) · SQL · *Storage Blob Data Contributor* en el contenedor de comprobantes |
| Pod `comprobantes` | — | *Storage Blob Data Reader* + *Storage Blob Delegator* (para firmar SAS de delegación de usuario) |
| Equipo de operaciones | Reader + *Monitoring Reader* | Ninguno por defecto |
| Seguridad/auditoría | Reader + *Security Reader* | Ninguno |

### Amenazas y defensa

| Amenaza | Defensa |
|---|---|
| Inyección, bots, DDoS de capa 7 | WAF en modo prevención; límites de tasa en APIM |
| Robo de credenciales de código | No existen: identidades por pod; secretos en Key Vault |
| Datos expuestos por IP pública | Acceso público deshabilitado + Private Endpoint + política `Deny` |
| Un pod comprometido lee todo | Permisos por servicio y por recurso, no por suscripción |
| Enlace de comprobante compartido | SAS de delegación de usuario, vencimiento corto, un solo blob |
| Evento falsificado | Solo los emisores con rol *Sender* publican; valida el esquema al consumir |
| Borrado accidental | Bloqueo `CanNotDelete` en SQL, Key Vault, red y Service Bus de producción |
| Gasto descontrolado | Presupuesto con alerta pronosticada y etiquetas por servicio |

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Guardar pedido y evento en la misma transacción | Publicar al bus *dentro* de la transacción de base de datos y confiar en que «saldrá bien» |
| Consumidores idempotentes y `MessageId` determinista | Suponer que un mensaje llega una sola vez |
| Responder `201` y procesar en segundo plano | Hacer esperar al cliente por facturación y correo |
| Un tópico con suscripciones por interesado | Un servicio que llama a otros cuatro por HTTP en cadena |
| Archivos en Blob y referencia en el mensaje | Mensajes de varios MB con el PDF dentro |
| Probar la red desde un pod, no desde tu laptop | Dar por buena la red porque «el portal dice Aprobado» |
| Alertar por tamaño de la bandeja y de la DLQ | Descubrir los pedidos atascados por una queja del cliente |
| Todo con Terraform y políticas | Crear recursos a mano y «luego lo escribimos» |

## 8. Límites, costos y versiones

- **Lo que más cuesta** (verifica precios y regiones): AKS (nodos), Service Bus Premium (unidades de mensajería, necesarias para Private Endpoint), APIM según nivel, Front Door Premium, Azure SQL y los Private Endpoints (cada uno cobra por hora y por datos).
- **Ahorro:** en desarrollo, usar niveles básicos sin Private Endpoint en una suscripción aparte con presupuesto bajo; en producción, reservas para lo estable.
- **Versiones del ejemplo:** Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3. Verifica la vigencia de niveles y cuotas en la doc oficial.
- **Garantías reales:** Service Bus detecta duplicados dentro de una ventana configurable; fuera de ella solo te protege tu bandeja de entrada.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
