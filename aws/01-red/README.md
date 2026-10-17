# AWS · 01 Red

La red decide **quién puede hablar con quién, por dónde y cuánto cuesta**. Cinco servicios, cada uno responde una pregunta distinta.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [VPC y subredes](vpc-subredes/README.md) | ¿**Dónde viven** mis recursos y cómo se dividen? | El conjunto residencial y sus torres | El terreno: bloques de direcciones, zonas de disponibilidad, pública/privada |
| [SG, NACL, rutas y NAT](sg-nacl-rutas-nat/README.md) | ¿Quién **puede pasar** y por dónde sale el tráfico? | Portero, control del piso, letreros y mensajero | Segmentar con grupos de seguridad, controlar rutas y dar salida a los privados |
| [VPC Endpoints, PrivateLink y Route 53](vpc-endpoints-privatelink/README.md) | ¿Cómo llego a servicios **sin salir a internet**? | El pasillo interno al banco | S3/DynamoDB gratis, servicios de AWS por interfaz, publicar servicios propios, DNS privado |
| [Peering y Transit Gateway](peering-transit-gateway/README.md) | ¿Cómo **conecto varias redes**? | Puerta directa frente al lobby central | Unir VPC y la red local, segmentar prod/dev |
| [Diagnóstico de conectividad](diagnostico-conectividad/README.md) | ¿**Dónde se pierde** el tráfico? | El plano, las cámaras y caminar el pasillo | Reachability Analyzer, Flow Logs, pruebas desde dentro |

> Se apoyan entre sí: la **VPC** es el terreno; los **grupos de seguridad y rutas** deciden el tráfico; los **endpoints** evitan el NAT y la exposición; **peering/TGW** unen terrenos; el **diagnóstico** te dice dónde falla cuando algo no conecta.

## Árbol de decisión: «quiero que…»

```
¿Quiero que una base de datos solo hable con mi aplicación?
   └─ SG de datos con origen = SG de la app (referencia), subred de datos sin ruta a internet

¿Quiero que contenedores privados bajen imágenes y escriban a S3 sin pagar NAT?
   └─ Endpoint de puerta de enlace de S3 (+ interfaces de ecr.api, ecr.dkr y logs)

¿Quiero que mis privados salgan a internet?
   └─ Ruta 0.0.0.0/0 → NAT Gateway (uno por AZ) en subredes públicas

¿Quiero bloquear una IP maliciosa puntual?
   └─ NACL (o AWS WAF en el borde)

¿Quiero conectar 2–3 VPC con tráfico simple?
   └─ VPC Peering (rutas en ambos lados)

¿Quiero conectar 4+ VPC, la red local o separar prod de dev?
   └─ Transit Gateway con tablas de rutas por segmento

¿Quiero exponer UN servicio a otras cuentas (incluso con CIDR solapados)?
   └─ PrivateLink: NLB + endpoint service

¿Quiero nombres internos (pedidos.modalima.internal)?
   └─ Zona alojada privada de Route 53 asociada a las VPC

¿Algo no conecta?
   └─ Escalera: nombre → Reachability Analyzer → Flow Logs → ¿escucha el servicio? → métricas (NAT, balanceador)
```

## Comparativa

| Característica | VPC / subredes | Grupo de seguridad | NACL | Endpoint de interfaz | Peering | Transit Gateway |
|---|---|---|---|---|---|---|
| **Qué hace** | Define el terreno | Permite tráfico por recurso | Permite/niega por subred | Acceso privado a un servicio | Une 2 VPC | Une muchas redes |
| **Con estado** | — | Sí | **No** | — | — | — |
| **Reglas de denegación** | — | No | Sí | — | — | `blackhole` en rutas |
| **Alcance** | Región | VPC (ENI) | Subred | Una subred por AZ | 2 VPC | Región (y entre regiones por peering) |
| **Transitivo** | — | — | — | — | **No** | Sí |
| **Costo típico** | Gratis | Gratis | Gratis | Hora por AZ + GB | Gratis (transferencia entre AZ/regiones) | Hora por adjunto + GB |
| **Error típico** | CIDR solapados | `0.0.0.0/0` en un puerto de datos | Olvidar puertos efímeros | DNS privado apagado | Ruta en un solo lado | Una sola tabla «todos con todos» |

## La receta ModaLima (cómo se ve junto)

| Pieza | Decisión |
|---|---|
| VPC | `/16` por entorno y región, bloque tomado del registro central |
| Subredes | Públicas `/24` (ALB, NAT), app `/22`, datos `/24`, en tres AZ |
| Salida | Un NAT por AZ en prod; uno solo en dev |
| Seguridad | SG por rol (`alb`, `app`, `datos`, `endpoints`) con referencias entre ellos |
| Servicios de AWS | Gateway de S3 y DynamoDB + interfaces para ECR, logs, STS, Secrets Manager, SQS, KMS |
| Entre redes | Transit Gateway con tablas `prod`, `dev` y `compartida` |
| Visibilidad | Flow Logs en todas las VPC hacia la cuenta de registros; análisis guardados de las rutas críticas |

## Orden recomendado de adopción
1. **Plan de CIDR** central y sin solapes.
2. **VPC con tres niveles** y tres AZ (Terraform).
3. **Endpoints de puerta de enlace** (gratis) y luego los de interfaz que realmente uses.
4. **SG por rol** con referencias; NACL por defecto.
5. **Flow Logs** y alarmas de `REJECT` y de NAT.
6. **Transit Gateway** cuando pases de tres VPC o necesites segmentar.
7. **Análisis guardados** de las rutas críticas y runbook de diagnóstico.

## Reglas transversales
- **Planifica las direcciones primero**: es lo único realmente difícil de cambiar.
- **Referencia grupos de seguridad, no CIDR.**
- **Tres AZ, un NAT por AZ, endpoints en cada AZ** para producción.
- **Menos IP públicas**: solo balanceadores y NAT.
- **Mide antes de abrir puertos**: Reachability y Flow Logs.
- **Todo como código**: la consola solo para mirar.
- **Los cambios de red en producción pasan por revisión y por un pipeline.**

## Java en red: qué hace cada `uso-en-java.md`

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| VPC y subredes | Clientes del SDK con timeouts, caché DNS, idle del NAT/ALB, monitor de IP libres | Funciones puras + lector del SDK + Micrometer |
| SG, NACL, rutas, NAT | Pool de conexiones para no agotar el NAT; auditoría de reglas de SG | Reglas puras (hallazgos por gravedad) |
| Endpoints y PrivateLink | Comprobación de DNS privado, checklist de endpoints faltantes, `endpointOverride` solo si hace falta | Verificación + checklist |
| Peering y TGW | Validar el plan de CIDR y de segmentos; leer adjuntos del TGW | Validación previa al `apply` |
| Diagnóstico | `ConnCheck` y cliente de Reachability Analyzer | Escalera de diagnóstico automatizada |

Reglas comunes: **rol de tarea / IRSA / Pod Identity** (nunca claves fijas), llamadas `Describe*` **fuera del camino caliente** y con caché, reglas como **funciones puras**, y en reactivo todo lo bloqueante a `boundedElastic` / worker pool / hilos virtuales.

## Cómo se relacionan con otros capítulos
- [Fundamentos](../00-fundamentos/README.md): regiones, AZ y cuentas.
- Compute (ECS, EKS, Lambda): dónde se colocan las ENI y las subredes de las tareas y pods.
- Ingress y API: balanceadores en subredes públicas hacia aplicaciones privadas.
- Storage y Mensajería: endpoints y políticas `aws:SourceVpce`.
- Datos: subredes y SG de datos; Aurora y ElastiCache.
- Gobierno: reglas de Config para SG y VPC; SCP que impiden crear IP públicas.
- Terraform en AWS: toda la red como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, consultas y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
