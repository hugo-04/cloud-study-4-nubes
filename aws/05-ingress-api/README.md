# AWS · 05 Ingress y API

Cómo entran las peticiones a tus microservicios: **balancear, publicar una API, acelerar y proteger en el borde, y exponer lo que corre en EKS**. Cuatro servicios que suelen ir en cadena.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [ALB y NLB](alb-nlb/README.md) | ¿Cómo reparto el tráfico entre mis instancias o contenedores? | El recepcionista que dirige a cada visita a la oficina correcta | HTTP/HTTPS con reglas por host y ruta (ALB); TCP/UDP, IP fija o PrivateLink (NLB) |
| [API Gateway](api-gateway/README.md) | ¿Cómo publico y controlo una API (autenticación, cuotas, versiones)? | La ventanilla única con ficheros de reglas | APIs HTTP/REST/WebSocket con Lambda o backends privados, autorizadores JWT y límites |
| [CloudFront + WAF](cloudfront-waf/README.md) | ¿Cómo acerco el contenido al usuario y filtro el tráfico malo? | La red de sucursales con un guardia en la puerta | Caché global, TLS en el borde, URLs firmadas, reglas administradas y límites por IP |
| [Ingress en EKS](ingress-eks/README.md) | ¿Cómo expongo lo que corre en Kubernetes? | El conserje que actualiza las señales cuando cambian los inquilinos | Que un `Ingress`/`Service` cree y mantenga el ALB/NLB y registre los pods |

> Se encadenan así: **usuario → CloudFront (+WAF) → ALB / API Gateway → servicios (ECS, EKS, Lambda)**. No siempre usas los cuatro: empieza por el ALB y añade el resto cuando haga falta.

## Árbol de decisión: «quiero…»

```
¿Exponer un servicio HTTP en contenedores o instancias con reglas por ruta?
   └─ ALB (en EKS lo crea el Ingress con el AWS Load Balancer Controller)

¿Exponer TCP/UDP (brokers, bases, protocolos propios), IP fija o PrivateLink?
   └─ NLB

¿Publicar una API con autenticación JWT, cuotas y planes de uso, sobre todo si el backend es Lambda?
   └─ API Gateway (HTTP API primero; REST API si necesitas claves/planes de uso, validación o caché integrada)

¿Mandar eventos en tiempo real al navegador (chat, notificaciones)?
   └─ API Gateway WebSocket

¿Servir un sitio estático o acelerar una API a usuarios lejanos?
   └─ CloudFront delante (S3 con OAC o ALB como origen)

¿Bloquear inyecciones, bots o abuso de login?
   └─ WAF asociado a CloudFront (global) o al ALB/API (regional)

¿Entregar archivos privados con enlace que caduca?
   └─ CloudFront con URLs o cookies firmadas

¿Que los equipos publiquen sus servicios en EKS sin tocar la consola?
   └─ Ingress con group.name + política que controle qué namespace puede ser público

¿Un ALB creado con Terraform que reciba pods de EKS?
   └─ TargetGroupBinding
```

## Comparativa

| Característica | ALB | NLB | API Gateway | CloudFront + WAF | Ingress en EKS |
|---|---|---|---|---|---|
| **Capa** | 7 (HTTP/HTTPS/gRPC) | 4 (TCP/UDP/TLS) | 7 (API administrada) | 7 (CDN) + filtros | Orquesta ALB/NLB |
| **Qué hace bien** | Reglas por host/ruta/cabecera, ponderación, OIDC | Baja latencia, IP estática, PrivateLink | Autorizadores, cuotas, transformación, dominios | Caché, TLS y protección en el borde | Mantener balanceadores desde YAML |
| **Autenticación integrada** | OIDC/Cognito | No | JWT, IAM, Lambda authorizer, Cognito | URLs firmadas; WAF no autentica | Delegada al ALB |
| **Modelo de cobro** | Hora + LCU | Hora + NLCU | Por petición (+ datos) | Por petición y transferencia; WAF por regla y petición | Los balanceadores que cree |
| **Estado/timeouts a vigilar** | Idle timeout, deregistration | Sin idle de aplicación; ojo con health checks | Límite de integración (~29 s en REST; verifica) | TTL de caché, tiempo de origen | Apagado de pods vs deregistration |
| **Error típico** | 502/504 por keep-alive menor que el idle | Preservación de IP mal entendida | Autorizador que no pasa el scope | Origen público sin cabecera secreta | Un ALB por Ingress |

## La receta ModaLima (cómo se ve junto)

| Capa | Qué se configura |
|---|---|
| **Borde** | CloudFront con dominio propio y certificado de ACM (us-east-1), WAF con reglas administradas (primero `Count`) y límite por IP en `/api/login`; sitio estático desde S3 con OAC |
| **Entrada de la API** | CloudFront → ALB con cabecera secreta; HTTPS solo, redirección 80→443, política TLS moderna |
| **Microservicios en EKS** | Ingress de clase `alb` agrupado (`group.name: tienda`), `target-type: ip`, readiness gate, `preStop` + gracia coherentes |
| **APIs de integración con socios** | API Gateway HTTP API con autorizador JWT y enlace a la VPC |
| **Servicios internos de datos/mensajería** | NLB interno (por ejemplo, brokers) |
| **Gobierno** | Webhook de admisión que impide publicar a Internet fuera del *namespace* de borde |

## Orden recomendado de adopción
1. **ALB** con HTTPS y redirección; health checks de *readiness*.
2. **Timeouts coherentes** (keep-alive > idle del ALB, deregistration, apagado ordenado).
3. **CloudFront** delante, con el origen protegido por cabecera secreta.
4. **WAF** en `Count` → ajustar → `Block`.
5. **API Gateway** para las APIs que necesiten autorizadores y cuotas.
6. **Ingress agrupado** y webhook que controle la publicación.
7. **Todo como código** (capítulo 10, Terraform en AWS).

## Reglas transversales
- **TLS en todas partes**; certificados de ACM con renovación automática.
- **Confía solo en el balanceador** para `X-Forwarded-*` (lista de proxies).
- **El origen no debe ser accesible saltándose el borde**: cabecera secreta, listas de prefijos o SG.
- **Un `Deny`/`Block` sin ensayo en `Count` rompe tráfico legítimo.**
- **Timeouts en cadena**: cada capa tiene el suyo; el de abajo debe ser mayor que el de arriba para no cortar conexiones.
- **Publicar es una decisión de seguridad**, también cuando solo es una anotación en YAML.
- **Observabilidad:** logs de acceso de ALB, de API Gateway y de CloudFront en almacenamiento con retención.

## Java en este capítulo: qué hace cada `uso-en-java.md`

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| ALB y NLB | IP real del cliente detrás del balanceador, validador de timeouts, lector de salud de destinos | Núcleo puro + SDK de ELB v2 |
| API Gateway | Enrutador y manejador de eventos para Lambda, firma SigV4 para llamar APIs con IAM, seguridad JWT/scopes | Núcleo puro + `AwsV4HttpSigner` |
| CloudFront + WAF | URLs firmadas, verificación de la cabecera secreta, invalidaciones por lotes, `Cache-Control` por tipo | Núcleo puro + SDK de CloudFront |
| Ingress en EKS | Apagado coordinado (`Connection: close`), webhook de admisión con las reglas de publicación | Núcleo puro sobre `Map` (sin Jackson) |

Reglas comunes: **funciones puras** para las decisiones (se prueban sin red), SDK con `close()` gestionado por el contenedor, y en reactivo lo bloqueante va a `boundedElastic` / pool de trabajadores de Mutiny.

## Cómo se relacionan con otros capítulos
- [Red](../01-red/README.md): subredes públicas/privadas, grupos de seguridad y endpoints donde viven los balanceadores.
- [IAM](../02-iam/README.md): roles del controlador (Pod Identity), autorización IAM de API Gateway.
- [Secretos](../03-secretos/README.md): claves de URLs firmadas y cabecera secreta del origen.
- [Compute](../04-compute/README.md): ECS, EKS y Lambda, los destinos de estos servicios.
- [Storage](../06-storage/README.md): S3 como origen de CloudFront con OAC.
- [Terraform en AWS](../10-terraform/README.md): todo lo anterior como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON/YAML), troubleshooting, repaso y prompt de NotebookLM.
