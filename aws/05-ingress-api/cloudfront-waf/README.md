# AWS · Ingress y API · Amazon CloudFront y AWS WAF

**CloudFront** es la red de entrega de contenido (CDN) de AWS: copias en cientos de puntos de presencia cerca del usuario, que sirven archivos estáticos desde caché y aceleran las llamadas a tus APIs. **AWS WAF** es el cortafuegos de aplicaciones web: inspecciona las peticiones HTTP y bloquea ataques comunes, abusos y bots. Juntos forman la **primera línea** delante de tu aplicación.

## 1. Qué es

**Analogía:** CloudFront es una **cadena de quioscos de periódicos** en cada barrio: el diario (tu contenido) se imprime una vez en la imprenta (origen) y cada quiosco guarda copias para entregarlas al instante. WAF es el **guardia de seguridad** de la entrada del quiosco: revisa a cada persona con reglas («no entres con esto», «máximo 20 veces por minuto»).

```
 Usuario ──► Punto de presencia (CloudFront)
                 │  WAF: ¿bloquear / limitar / dejar pasar?
                 │  ¿está en caché? ── sí ─► responde (milisegundos)
                 └─ no ─► Origen: S3 (estáticos, vía OAC)  |  ALB / API Gateway (dinámico)
```

## 2. Cómo funciona por dentro

### CloudFront
| Pieza | Qué es |
|---|---|
| **Distribución** | La configuración: dominios, orígenes, comportamientos, certificado, WAF |
| **Origen** | De dónde se obtiene el contenido: **S3** (con *Origin Access Control*), ALB, API Gateway u otro servidor HTTP; también *VPC origins* hacia recursos privados (verifica) |
| **Comportamiento (behavior)** | Por patrón de ruta (`/api/*`, `/static/*`): origen, métodos, caché, funciones, política de cabeceras |
| **Política de caché** | Qué entra en la **clave de caché** (cabeceras, cookies, consultas) y los TTL |
| **Política de petición al origen** | Qué se reenvía al origen **sin** entrar en la clave de caché |
| **Política de cabeceras de respuesta** | Añade HSTS, CSP, CORS… |
| **CloudFront Functions** | JavaScript ligerísimo en el borde (reescrituras, cabeceras, redirecciones) |
| **Lambda@Edge** | Funciones más pesadas en el borde (autenticación, contenido dinámico) |
| **URLs y cookies firmadas** | Acceso temporal a contenido privado con claves del grupo de confianza |
| **Respuestas de error personalizadas** | Páginas de error y *SPA fallback* (404 → `/index.html`) |
| **Origin Shield** | Capa de caché adicional para reducir carga al origen |
| **Certificado** | De **ACM en `us-east-1`** (requisito de CloudFront) |

> **La clave de caché manda:** si incluyes en ella cabeceras o cookies que varían por usuario, el caché deja de servir (cada usuario es una entrada). Incluye lo mínimo; reenvía al origen lo demás por la política de petición.

### AWS WAF
| Pieza | Qué es |
|---|---|
| **Web ACL** | La lista ordenada de reglas aplicada a CloudFront, ALB, API Gateway (REST), AppSync, Cognito… |
| **Alcance** | `CLOUDFRONT` (se crea en `us-east-1`) o `REGIONAL` |
| **Reglas gestionadas** | Conjuntos de AWS: reglas comunes (OWASP), entradas maliciosas conocidas, reputación de IP, SQLi, control de bots, prevención de toma de cuentas |
| **Regla por tasa** | Limita peticiones por IP (u otra clave) en una ventana |
| **Acciones** | `Allow`, `Block`, `Count` (probar), `CAPTCHA`, `Challenge` |
| **Etiquetas** | Las reglas ponen etiquetas que otras reglas pueden usar |
| **WCU** | Unidades de capacidad: cada regla cuesta; la ACL tiene tope |
| **Registro** | A S3, CloudWatch Logs o Firehose, con **redacción** de campos sensibles |

> **Probar antes de bloquear:** las reglas nuevas se despliegan en **Count**, se revisan los falsos positivos en los logs y luego pasan a Block.

### Protección del origen
Para que nadie salte la CDN y ataque el ALB directamente: (1) el SG del ALB admite solo la **lista de prefijos administrada de CloudFront**; (2) CloudFront añade una **cabecera secreta** que el ALB/aplicación exige; (3) en S3, **OAC** con política que solo admite esa distribución.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Sitio web/SPA con archivos estáticos globales | **CloudFront + S3 (OAC)** |
| API pública con picos y ataques | **CloudFront + WAF** delante del ALB/API |
| Descargas privadas temporales | **URLs firmadas** de CloudFront (o de S3 si no necesitas CDN) |
| Reducir latencia internacional | **CloudFront** |
| Bloquear SQLi/XSS/bots y limitar tasa | **WAF** |
| API interna entre microservicios | **No**: red privada y [ALB interno](../alb-nlb/README.md) |
| Contenido 100 % dinámico y personalizado, sin caché posible | CloudFront sigue aportando TLS, WAF y red troncal, pero no caché |
| Solo necesitas WAF en un ALB regional | WAF `REGIONAL` sin CloudFront |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Punto de presencia** | Servidor de CloudFront cercano al usuario |
| **Cache hit / miss** | Respondido desde caché / hubo que ir al origen |
| **TTL** | Cuánto tiempo vale una copia |
| **Invalidación** | Borrar copias antes de que venzan |
| **OAC** | Permiso para que CloudFront (y solo él) lea el bucket privado |
| **Cache key** | Lo que distingue una copia de otra |
| **Web ACL / regla gestionada** | Conjunto de reglas de WAF / reglas hechas por AWS |
| **Rate-based rule** | Límite de peticiones por origen |
| **Count mode** | Registrar sin bloquear (ensayo) |

## 5. Cómo se usa
1. Sitio estático: bucket S3 **privado** + OAC + distribución con política `CachingOptimized` y archivos con *hash* en el nombre.
2. API: origen ALB/API Gateway; comportamiento `/api/*` con caché desactivada (o TTL corto) y política de petición `AllViewerExceptHostHeader`.
3. Certificado de ACM en `us-east-1` y alias DNS (A/AAAA) hacia la distribución.
4. WAF en `us-east-1` con reglas gestionadas y regla por tasa, **primero en Count**.
5. Protege el origen (cabecera secreta + lista de prefijos).
6. Todo en Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf). Operación: [`ejemplos/cli/cloudfront.sh`](ejemplos/cli/cloudfront.sh). Política de ejemplo: [`ejemplos/json/politica-bucket-oac.json`](ejemplos/json/politica-bucket-oac.json).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Pipeline** | `cloudfront:UpdateDistribution/CreateInvalidation`, `wafv2:*` sobre su ACL, `s3:PutObject` en el bucket | — |
| **CloudFront (OAC)** | — | `s3:GetObject` en el bucket, solo desde esa distribución |
| **Aplicación** | `cloudfront:CreateInvalidation` (limitado) | Firma URLs con la clave privada |
| **Usuario final** | — | HTTPS; URL firmada para lo privado |

- **TLS 1.2+** (política de seguridad reciente), HTTP→HTTPS, HSTS por política de cabeceras.
- **Claves privadas de firma** en Secrets Manager; **grupo de claves de confianza** con rotación.
- WAF: reglas gestionadas + tasa; registro con redacción de `Authorization` y cookies.
- **Shield Standard** viene incluido; Shield Advanced para protección DDoS avanzada con costo propio.
- No guardes información personal en la URL ni en la clave de caché.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Bucket S3 **privado** con OAC | Bucket público «para que funcione» |
| Archivos con hash y `Cache-Control: immutable` | Invalidar todo en cada despliegue |
| Clave de caché mínima | Incluir todas las cookies/cabeceras |
| WAF en Count antes de Block | Bloquear de golpe y romper tráfico legítimo |
| Proteger el origen (cabecera secreta, prefix list) | Dejar el ALB accesible desde Internet sin más |
| Respuestas de la API privadas con `no-store` | Que la CDN cachee datos de un usuario para otro |
| Certificados en `us-east-1` | Intentar usar un certificado de otra región |
| URLs firmadas de vida corta | URLs firmadas de meses |

## 8. Límites, costos y versiones
- **Costo:** transferencia de salida y peticiones por región (clases de precio), invalidaciones (cuota gratuita mensual), WAF por ACL, regla y millón de peticiones; Lambda@Edge/Functions por invocación. *Verifica precios.*
- **Límites** (verifica): tamaño de objeto, WCU por ACL (1 500 por defecto), reglas, invalidaciones simultáneas.
- **Terraform:** `aws_cloudfront_distribution`, `aws_cloudfront_origin_access_control`, `aws_wafv2_web_acl`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
