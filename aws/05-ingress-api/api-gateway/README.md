# AWS · Ingress y API · Amazon API Gateway

**Amazon API Gateway** es la «puerta de entrada de APIs» administrada: recibe peticiones HTTP/WebSocket, **autentica**, **limita** el ritmo, **valida**, opcionalmente **transforma** y las entrega a Lambda, a tus servicios en una red privada o a otros servicios de AWS. Pagas por petición y no administras servidores.

## 1. Qué es

**Analogía:** la **ventanilla de atención** de un banco. Antes de que alguien llegue al gerente (tu servicio), la ventanilla pide identificación (autorizador), controla cuántas personas entran por minuto (throttling), revisa que el formulario esté completo (validación) y anota quién vino (logs).

```
 Cliente ──► API Gateway ──► [ autorizador JWT/IAM/Lambda ] ──► [ throttling · validación · CORS ]
                                                                        │
                    ┌───────────────────────┬───────────────────────────┘
                    ▼                       ▼                           ▼
              Lambda (proxy)       VPC Link ► ALB/NLB (privado)    Servicio de AWS (SQS, Step Functions…)
```

## 2. Cómo funciona por dentro

### Tres tipos de API
| Tipo | Para qué | Características |
|---|---|---|
| **HTTP API** (v2) | APIs modernas, más baratas y rápidas | Autorizador **JWT** nativo, Lambda y proxy HTTP, VPC Link, CORS, dominio propio, mTLS; **sin** claves de API/planes de uso ni caché ni WAF directo *(verifica)* |
| **REST API** (v1) | APIs que necesitan todas las funciones | Planes de uso y claves de API, caché, transformación de peticiones/respuestas (VTL), validación de modelos, WAF, *canary*, política de recurso, endpoints privados |
| **WebSocket API** | Comunicación bidireccional | Rutas por mensaje, `$connect`/`$disconnect`, envío a clientes desde el backend |

### Piezas
| Pieza | Qué es |
|---|---|
| **Ruta** | `METHOD /ruta` (p. ej. `GET /pedidos/{id}`) o `$default` / `ANY /{proxy+}` |
| **Integración** | A dónde va la petición: Lambda (proxy), HTTP, **VPC Link** (red privada), servicio de AWS, mock |
| **Etapa (stage)** | Versión desplegada (`prod`, `dev`), con variables, límites y logs propios |
| **Autorizador** | **JWT** (OIDC/Cognito), **IAM** (SigV4), **Lambda** (lógica propia), Cognito (REST) |
| **Throttling** | Límite de peticiones por segundo y ráfaga (cuenta, etapa, ruta; plan de uso en REST) |
| **Dominio propio** | Nombre + certificado ACM + mapeo a una etapa |
| **CORS** | Cabeceras para navegadores, configuradas en la API |
| **Logs y trazas** | Access logs a CloudWatch, métricas, X-Ray |

### Límites que condicionan el diseño (verifica los vigentes)
- **Tiempo de integración:** ~30 s en HTTP API (y 29 s por defecto en REST, ampliable en ciertos casos): lo largo va **asíncrono**.
- **Tamaño de carga:** ~10 MB: archivos grandes van directo a S3 con URL prefirmada ([Storage](../../06-storage/README.md)).
- **Autorizador Lambda:** su respuesta puede cachearse (TTL) para no invocarlo en cada petición.

### Formato de evento para Lambda
Con HTTP API, el *payload format 2.0* entrega a la función un evento con `routeKey`, `rawPath`, `headers`, `queryStringParameters`, `body` y, si hubo autorizador JWT, los **claims** en `requestContext.authorizer.jwt.claims`.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| API pública con autenticación JWT/IAM, límites y dominio, detrás Lambda | **HTTP API** |
| Necesitas claves de API, planes de uso, caché o transformación | **REST API** |
| Exponer servicios privados (ALB/NLB) sin abrir la red | HTTP API + **VPC Link** |
| WebSocket / notificaciones push a clientes | **WebSocket API** |
| Solo balancear tráfico a tus servicios, sin gestión de APIs | [ALB](../alb-nlb/README.md) (más barato a gran volumen) |
| Caché global y estáticos | [CloudFront](../cloudfront-waf/README.md) |
| Cargas de >30 s o archivos de cientos de MB | **No** por aquí: asíncrono / S3 |
| Tráfico enorme y constante donde el costo por petición pesa | Evaluar ALB directo |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Stage** | Una versión publicada de la API |
| **Integración proxy** | Se pasa la petición completa y la función responde con el formato final |
| **VPC Link** | Túnel privado hacia un balanceador dentro de tu VPC |
| **Autorizador** | Quien decide si la petición pasa |
| **JWT** | Token firmado con identidad y permisos (claims) |
| **Throttling** | Freno de peticiones por segundo |
| **Usage plan / API key** | Cuotas por cliente (REST) |
| **CORS** | Permiso para que un navegador de otro origen llame a la API |
| **Payload format 2.0** | Estructura del evento de HTTP API hacia Lambda |

## 5. Cómo se usa
1. Elige tipo (por defecto **HTTP API**).
2. Define rutas, integraciones (Lambda / VPC Link) y el **autorizador JWT** con tu proveedor de identidad.
3. Etapa con **access logs** y límites por ruta.
4. Dominio propio con ACM.
5. Todo en Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf). Operación: [`ejemplos/cli/apigw.sh`](ejemplos/cli/apigw.sh). Eventos de ejemplo: [`ejemplos/json/`](ejemplos/json/evento-http-api.json).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Pipeline** | `apigateway:*` sobre sus APIs | — |
| **Cliente de la API** | — | Token JWT válido / firma SigV4 con `execute-api:Invoke` |
| **Integración (rol)** | — | Permiso para invocar Lambda (`lambda:InvokeFunction` vía política de recurso) |
| **Backend** | — | **Vuelve a validar** (no confíes ciegamente en que «ya pasó por API Gateway») |

- **Defensa en profundidad:** el backend también valida el JWT o verifica que el tráfico viene del API Gateway (VPC Link + SG).
- JWT: `issuer` y `audience` correctos; scopes por ruta.
- **Throttling** por ruta sensible (login, búsquedas costosas).
- **WAF** (REST API) o CloudFront+WAF delante de HTTP API.
- **CORS** con orígenes explícitos, no `*` con credenciales.
- **Logs de acceso** sin cabeceras `Authorization` ni cuerpos con datos personales.
- Endpoint por defecto (`execute-api`) deshabilitado si usas dominio propio y WAF delante.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| HTTP API salvo que necesites funciones de REST | REST API «por costumbre» (más cara) |
| Autorizador JWT + validación en el backend | Dejar rutas abiertas «temporalmente» |
| Respuestas del autorizador Lambda con caché | Invocar el autorizador en cada petición |
| Trabajo largo → 202 + proceso asíncrono | Esperar 25 s en la petición |
| Subidas grandes → URL prefirmada de S3 | Pasar archivos por la API |
| Throttling por ruta y alarmas de 4XX/5XX | Sin límites |
| Access logs con ID de petición | Logs con tokens |
| CORS mínimo | `Access-Control-Allow-Origin: *` con cookies |

## 8. Límites, costos y versiones
- **Costo:** por millón de peticiones (HTTP API bastante más barata que REST) + transferencia; caché (REST) por hora. *Verifica precios.*
- **Límites** (verifica): tiempo, tamaño de carga, rutas por API, peticiones por segundo de la cuenta.
- **Terraform:** `aws_apigatewayv2_*` (HTTP/WebSocket), `aws_api_gateway_*` (REST). Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
