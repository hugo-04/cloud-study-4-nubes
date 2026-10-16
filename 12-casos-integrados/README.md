# 12 · Casos integrados: todo junto, en las 4 nubes

Aquí juntas las piezas de los módulos 00–11 en **arquitecturas completas**. Es el módulo para "ver el bosque": cómo viaja una petición, cómo se protege cada salto y qué revisar cuando algo falla.

> Empresa ficticia para los ejemplos: **ModaLima**, una tienda online de ropa.

---

## Caso A · Tienda online (web + API + datos)

### Requisitos
- Web y app móvil con tráfico público.
- API de pedidos, catálogo y pagos.
- Datos de clientes: **nada de bases de datos públicas**.
- Imágenes de productos y comprobantes en almacenamiento de objetos.
- Eventos de pedido hacia facturación y logística.

### Arquitectura en Azure

```
Internet
   │
[Front Door + WAF]            ← borde global, TLS, protección web (módulo 06)
   │
[Application Gateway / APIM]  ← entrada regional; APIM aplica auth, cuotas, versiones
   │   (VNet: snet-apim)
[AKS privado]                 ← microservicios: catalogo, pedidos, pagos (módulo 05)
   │   (VNet: snet-aks)
   ├── Azure SQL / PostgreSQL ──► por Private Endpoint (módulo 09)
   ├── Key Vault ───────────────► por Private Endpoint, acceso con Workload Identity (módulo 04)
   ├── Blob Storage ────────────► por Private Endpoint; SAS de usuario delegado (módulo 07)
   └── Service Bus (topics) ────► por Private Endpoint (módulo 08)
                                      │
                         [Function App] procesa pedido → facturación / logística
```

**Reglas de red (módulo 02):** cada servicio PaaS con `public network access = disabled`, Private Endpoint en `snet-pe`, zona DNS privada vinculada a la VNet, NSG con permisos mínimos entre subnets.

**Identidad (módulo 03):** ningún secreto en el código. Pods con **Workload Identity**; la Function con **Managed Identity**; roles con el menor privilegio (por ejemplo `Key Vault Secrets User`, `Storage Blob Data Contributor` acotado al contenedor).

### El mismo diseño en las otras nubes

| Capa | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Borde + WAF | Front Door + WAF | CloudFront + AWS WAF | OCI WAF (sobre LB / CDN de terceros) | Cloud Armor + Global External LB |
| Entrada regional | Application Gateway | Application Load Balancer | Load Balancer | Regional External LB |
| API gateway | API Management | API Gateway | API Gateway | API Gateway / Apigee |
| Contenedores | AKS | EKS | OKE | GKE |
| Base relacional | Azure SQL / PG Flexible | RDS / Aurora | Autonomous DB / MySQL HeatWave | Cloud SQL / AlloyDB |
| Base NoSQL | Cosmos DB | DynamoDB | NoSQL Database | Firestore / Bigtable |
| Secretos | Key Vault | Secrets Manager + KMS | OCI Vault | Secret Manager + Cloud KMS |
| Objetos | Blob Storage | S3 | Object Storage | Cloud Storage |
| Mensajería | Service Bus / Event Grid | SQS + SNS / EventBridge | Queue / Notifications / Events | Pub/Sub |
| Funciones | Functions | Lambda | OCI Functions | Cloud Functions / Cloud Run |
| Acceso privado a PaaS | Private Endpoint | PrivateLink / Gateway Endpoint | Service Gateway / Private Endpoint | Private Service Connect / Private Google Access |
| Identidad de carga | Managed Identity / Workload Identity | IAM Role (IRSA / Pod Identity) | Instance/Resource Principal | Service Account + Workload Identity |
| IaC | Terraform / Bicep | Terraform / CloudFormation | Terraform / Resource Manager | Terraform / Infrastructure Manager |

---

## Caso B · Subida de archivos con Claim Check (SAS / Presigned / PAR / Signed URL)

**Problema:** los clientes suben comprobantes de hasta 50 MB. Pasarlos por la API y por la cola es lento y caro.

**Flujo:**

```
1. Cliente  → API:   "quiero subir comprobante.pdf"
2. API      → valida identidad y límites; genera URL temporal de ESCRITURA
3. API      → Cliente: devuelve la URL (vence en 10 min, solo ese blob, solo escribir)
4. Cliente  → Storage: PUT directo con la URL (no pasa por tu API)
5. Storage  → evento "blob creado" (Event Grid / S3 Event / OCI Events / Pub/Sub)
6. Evento   → Cola/tópico con SOLO la referencia (la URL o el nombre del blob)
7. Worker   → lee el mensaje, genera URL de LECTURA corta, descarga y procesa
8. Worker   → marca el pedido como procesado (idempotente)
```

| Paso | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| URL de escritura | SAS de usuario delegado (`cw`) | Presigned PUT | PAR de escritura al objeto | Signed URL `PUT` |
| Evento de creación | Event Grid `BlobCreated` | S3 Event Notification | Events `createobject` | Notificación de GCS a Pub/Sub |
| Cola del mensaje | Service Bus queue | SQS | OCI Queue | Pub/Sub |
| URL de lectura | SAS `r` corta | Presigned GET | PAR de lectura | Signed URL `GET` |

**Qué NO mandar por la cola:** el archivo (límite de tamaño y costo) ni una URL con **permisos de larga duración** (el mensaje se puede ver en logs o en la cola de mensajes fallidos). Manda la **referencia** y genera el acceso de lectura **al procesar**.

Código y comandos completos: [módulo 07](../07-storage/README.md) y [módulo 08](../08-mensajeria-y-streaming/README.md).

---

## Caso C · Clickstream en tiempo real (Kafka y equivalentes)

**Problema:** la web envía 20 000 eventos/seg (clics, vistas). Se necesita analítica casi en tiempo real y reprocesar el histórico.

```
Web / App ─► [Streaming: Event Hubs / MSK / OCI Streaming / Managed Kafka]
                     │                     (particiones por clave de sesión)
                     ├─► Consumidor 1 (grupo "recomendaciones")
                     ├─► Consumidor 2 (grupo "analitica")  ← lee todo, a su ritmo
                     └─► Archivo en objetos (Capture / S3 sink / bucket) para histórico
```

| Concepto | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Log distribuido | Event Hubs (con endpoint Kafka) | Kinesis / **MSK** (Kafka) | OCI Streaming (API Kafka) | Pub/Sub / **Managed Kafka** |
| Particiones | Partitions | Shards / partitions | Partitions | Partitions (Kafka) |
| Grupo de consumidores | Consumer group | Consumer group | Consumer group | Subscription / consumer group |
| Archivo automático | Capture | Firehose | Connector Hub | Dataflow / subscription a BigQuery o GCS |

**Decisiones clave:** la **clave de partición** (preserva el orden por esa clave), el número de particiones (tope de paralelismo), la retención, y consumidores **idempotentes**.

Detalles: [módulo 08](../08-mensajeria-y-streaming/README.md).

---

## Caso D · Landing zone y gobierno

**Objetivo:** que cada equipo cree recursos **solo dentro de límites seguros**, sin depender de la memoria de las personas.

```
Raíz (Management Group / AWS Organization / OCI Tenancy / GCP Organization)
├── Plataforma   (red central, DNS, identidad, logging)
├── Producción   (políticas estrictas)
├── No-prod      (políticas más flexibles, presupuestos bajos)
└── Sandbox      (aislado, con tope de gasto)
```

Controles mínimos:
1. **Región permitida** y **etiquetas obligatorias** (política / SCP / Org Policy).
2. **Sin IP pública** en recursos de datos; **sin acceso público** en almacenamiento.
3. **Red hub-and-spoke** con DNS privado centralizado.
4. **Logs** de auditoría centralizados e inmutables.
5. **Presupuestos y alertas** de costo por suscripción/cuenta/proyecto.
6. **Locks / protección** para lo crítico.
7. Todo creado por **Terraform en pipeline** con OIDC.

Detalle: [módulo 10](../10-politicas-y-gobierno/README.md) y [módulo 11](../11-terraform-iac/README.md).

---

## Runbook de incidente: "El servicio A no llega al servicio B"

Usa la regla **RPDSI** del [módulo 02](../02-comunicacion-privada-y-diagnostico/README.md) y avanza **de abajo hacia arriba** sin saltarte pasos.

| # | Pregunta | Cómo comprobarlo | Si falla |
|---|---|---|---|
| 1 | **DNS:** ¿el nombre resuelve a la IP **privada** esperada? | `nslookup`/`dig` **desde dentro** (pod, VM) | Zona privada `privatelink.*` sin vincular a la VNet, reenviador DNS, `CoreDNS` |
| 2 | **Ruta:** ¿hay camino hasta esa IP? | Tablas de rutas / UDR, peering, NVA/firewall | Falta peering, ruta forzada a un firewall que bloquea |
| 3 | **Puerto:** ¿abre el puerto? | `nc -zv host puerto` / `curl -v` / `ConnCheck.java` | NSG / SG / NACL / Security List / firewall |
| 4 | **TLS:** ¿el certificado y el nombre coinciden? | `openssl s_client -connect host:443 -servername host` | Certificado vencido, nombre incorrecto, CA no confiable |
| 5 | **Servicio:** ¿el destino acepta redes privadas? | Firewall del servicio, `public access`, PE aprobado | PE en estado *Pending*, firewall del PaaS cerrado |
| 6 | **Identidad:** ¿el que llama tiene permiso? | Respuesta `401/403`, logs de auditoría | Falta rol (plano de datos), federación mal configurada |
| 7 | **Aplicación:** ¿responde bien? | Logs, métricas, `5xx` | Es un fallo de la app, no de la red |

**Interpretar el síntoma**

| Síntoma | Capa probable |
|---|---|
| `Name or service not known` | DNS |
| Resuelve a IP **pública** cuando esperabas privada | DNS privado mal vinculado |
| `timeout` | Ruta o filtro (se descarta en silencio) |
| `connection refused` | Llegas al host, pero nadie escucha en el puerto |
| Error de certificado | TLS |
| `401` | Autenticación |
| `403` | Autorización (o firewall del servicio) |
| `502/503/504` desde gateway | Backend caído, sondas (*health probes*) fallando o timeouts |

**Específico de AKS**
- ¿Los pods resuelven DNS? Prueba con un pod temporal: `kubectl run t --rm -it --image=busybox -- nslookup <nombre>`.
- ¿El **rango de servicios** (service CIDR) se solapa con la VNet o redes peered?
- ¿Faltan **IPs libres** en la subnet de los nodos (modelo CNI clásico)?
- ¿La **salida** pasa por un firewall que bloquea lo necesario (registro de imágenes, API de la nube)?
- ¿El clúster es **privado** y tú ejecutas `kubectl` desde fuera de la red? Usa un host dentro de la VNet o `az aks command invoke`.

**Específico de APIM**
- ¿En qué **modo de red** está (External / Internal / PE)?
- ¿La subnet y el NSG permiten los puertos requeridos de gestión y salud?
- ¿El backend resuelve **desde la VNet de APIM** (DNS)?
- ¿La política `set-backend-service` apunta al nombre correcto y con TLS válido?

---

## Checklist de producción (antes de abrir al público)

**Red**
- [ ] Rangos CIDR planificados sin solapes entre VNets/redes conectadas
- [ ] PaaS de datos sin acceso público y con endpoint privado + DNS privado
- [ ] NSG/SG con denegación por defecto y reglas mínimas
- [ ] Salida controlada (NAT / firewall) y registrada

**Identidad y secretos**
- [ ] Identidades administradas / de carga en lugar de claves
- [ ] Secretos solo en el vault, con rotación y acceso mínimo
- [ ] CI/CD con OIDC (sin secretos guardados)
- [ ] Revisión de roles amplios (Owner/Admin)

**Datos**
- [ ] Copias de seguridad probadas con una **restauración real**
- [ ] Cifrado en reposo (y con clave propia donde aplique)
- [ ] Plan de recuperación (RPO/RTO) acordado y probado

**Operación**
- [ ] Logs, métricas y alertas por servicio
- [ ] Sondas de salud y *autoscaling* configurados
- [ ] Mensajes fallidos (DLQ) con alerta
- [ ] Presupuestos y alertas de costo

**Gobierno**
- [ ] Políticas de región, etiquetas y acceso público
- [ ] Locks en recursos críticos
- [ ] Infraestructura como código revisada por pull request

---

## Plan de estudio de 8 semanas

| Semana | Módulos | Práctica |
|---|---|---|
| 1 | 00 Fundamentos · 01 Networking | Crea una VNet con 2 subnets y un NSG con CLI y luego con Terraform |
| 2 | 02 Comunicación privada y diagnóstico | Storage con Private Endpoint; rompe el DNS a propósito y diagnostícalo con RPDSI |
| 3 | 03 IAM · 04 Secretos | Managed Identity que lee un secreto de Key Vault sin claves |
| 4 | 05 Compute | App Service + Function; luego una app en AKS |
| 5 | 06 Ingress y API | Ingress + APIM con una política de límite de llamadas |
| 6 | 07 Storage · 08 Mensajería | SAS de escritura/lectura + Claim Check con una cola |
| 7 | 09 Bases de datos · 10 Políticas | SQL por Private Endpoint; una política que niegue acceso público |
| 8 | 11 Terraform · 12 Casos | Un entorno completo en Terraform, destruirlo y reconstruirlo |

> **Tip de costos:** haz cada laboratorio, **estudia, y destruye** (`terraform destroy`). Configura una alerta de presupuesto el primer día.

---

## Preguntas de entrevista (integradoras)

1. Diseña una API pública que accede a una base de datos privada. ¿Qué componentes y qué reglas de red?
2. Un pod en AKS no puede alcanzar el Key Vault. Recorre tu diagnóstico paso a paso.
3. ¿Cuándo usarías Service Bus y cuándo Event Hubs? ¿Y su equivalente en AWS y GCP?
4. Explica el patrón Claim Check y por qué evitas poner un SAS de larga duración en un mensaje.
5. ¿Cómo evitas que un equipo cree una base de datos con IP pública?
6. ¿Cómo autenticas un pipeline de Terraform en las tres nubes sin secretos guardados?
7. Un `terraform plan` muestra `-/+` en un servidor SQL. ¿Qué haces?
8. ¿En qué se diferencia un Security Group de AWS de un NSG de Azure? (con estado, nivel de asociación, reglas de denegación)
