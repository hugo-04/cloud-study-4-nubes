# AWS · Ingress y API · Elastic Load Balancing (ALB y NLB)

**Elastic Load Balancing** reparte el tráfico entrante entre varias copias de tu servicio y las saca de rotación cuando fallan. Dos tipos cubren casi todo: el **ALB** (*Application Load Balancer*, capa 7: entiende HTTP) y el **NLB** (*Network Load Balancer*, capa 4: TCP/UDP/TLS, muy rápido, IP estable).

## 1. Qué es

**Analogía:** el **recepcionista de un edificio**. El ALB lee la tarjeta de cada visita («vienes por *facturas*, piso 3; vienes por *pedidos*, piso 5») y además revisa que cada oficina esté abierta. El NLB es el portero que abre la puerta correcta según el número de puerta, sin leer la tarjeta, pero a toda velocidad y con una dirección fija.

```
 Internet ──► ALB (443) ──┬─ regla host=api.modalima.com, ruta /pedidos/* ──► Target group "pedidos" ──► tarea 1, tarea 2, tarea 3
                          └─ regla ruta /facturas/*                        ──► Target group "facturas" ──► tarea 1, tarea 2
 Cliente TCP ──► NLB (IP estática) ───────────────────────────────────────► Target group "broker" ──► nodo 1, nodo 2
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Load balancer** | El punto de entrada, repartido en una subred por zona de disponibilidad. Público (*internet-facing*) o interno |
| **Listener** | Puerto + protocolo en el que escucha (ALB: HTTP/HTTPS; NLB: TCP/UDP/TLS) |
| **Regla (ALB)** | Condición (host, ruta, cabecera, método, IP origen, cadena de consulta) → acción (reenviar, redirigir, respuesta fija, autenticar) |
| **Target group** | Conjunto de destinos con su *health check*. Tipos: `instance`, `ip` (lo normal con Fargate/EKS), `lambda`, `alb` |
| **Health check** | Ruta/puerto/umbrales: un destino que falla sale de rotación |
| **Certificado** | De **ACM**; varios por listener con **SNI**; política TLS (versión mínima y cifrados) |
| **Pesos** | Reparto ponderado entre target groups (despliegues graduales, *canary*) |
| **Atributos** | Idle timeout, cross-zone, *deregistration delay*, *slow start*, *stickiness*, logs de acceso |

### ALB frente a NLB
| Aspecto | ALB | NLB |
|---|---|---|
| Capa | 7 (HTTP/HTTPS/gRPC) | 4 (TCP/UDP/TLS) |
| Enrutamiento | Host, ruta, cabeceras, métodos | Por puerto |
| IP estable | No (DNS; usar nombre) | **Sí** (IP elástica por zona) |
| Conserva IP del cliente | Vía `X-Forwarded-For` | Sí (en destinos de tipo instancia/IP, configurable) |
| Autenticación integrada | OIDC / Cognito | No |
| WAF | **Sí** | No |
| Latencia / rendimiento | Muy buena | Mínima, millones de conexiones |
| Seguridad de red | Security groups | Security groups (opcional) |
| Típico | APIs y webs | Brokers, bases por TCP, PrivateLink, IP fija para listas blancas |

### Detalles que importan
- **Cabeceras de reenvío:** el ALB añade `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Port`. Tu aplicación debe **confiar solo en el balanceador**.
- **Deregistration delay:** al retirar un destino, el balanceador espera ese tiempo para terminar las peticiones en curso.
- **Idle timeout** (ALB, 60 s por defecto): conexiones inactivas más largas se cortan; ajusta *keep-alive* de la aplicación **mayor** que el del ALB.
- **Zona cruzada** (*cross-zone*): activa por defecto en ALB; en NLB es opcional (con costo de transferencia).
- **mTLS, gRPC, WebSocket y HTTP/2** soportados en ALB.
- **Una respuesta del ALB** (503/504) puede venir del propio balanceador: mira `X-Amzn-ErrorType` y los logs.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| APIs/web HTTP con varios microservicios detrás de un solo dominio | **ALB** (reglas por host/ruta) |
| Tráfico TCP/UDP, IP fija, PrivateLink, alto rendimiento | **NLB** |
| Quieres autenticación OIDC antes de llegar a la app | **ALB** |
| Necesitas WAF delante | ALB (o [CloudFront + WAF](../cloudfront-waf/README.md)) |
| Throttling por cliente, planes de uso, claves de API | [API Gateway](../api-gateway/README.md) |
| Caché global y reducción de latencia | [CloudFront](../cloudfront-waf/README.md) delante |
| Un solo servicio sin necesidad de balanceador | [ECS Express Mode](../../04-compute/ecs-express-mode/README.md) ya lo trae |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Listener / regla** | Dónde escucha / qué hacer según la petición |
| **Target group** | La lista de destinos y cómo comprobar su salud |
| **Health check** | Prueba periódica de «¿estás vivo y listo?» |
| **SNI** | Varios certificados en un mismo puerto, según el nombre pedido |
| **Cross-zone** | Repartir entre destinos de todas las zonas |
| **Deregistration delay** | Gracia para terminar peticiones al retirar un destino |
| **Sticky sessions** | Mismo cliente al mismo destino (evítalas si puedes) |
| **Connection draining** | Lo mismo que deregistration delay |
| **PrivateLink** | Exponer un NLB a otras VPC/cuentas sin abrir red |

## 5. Cómo se usa
1. Subredes públicas (o privadas si es interno) en **al menos dos zonas** ([Red](../../01-red/vpc-subredes/README.md)).
2. *Security groups*: el del balanceador admite 80/443 desde Internet; el de las tareas admite **solo el del balanceador**.
3. Certificado en **ACM** (validación por DNS) y listener 443; el 80 redirige a 443.
4. Target groups tipo `ip` con *health check* a `/actuator/health/readiness`.
5. Reglas por host/ruta. Todo en Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf). Operación: [`ejemplos/cli/elb.sh`](ejemplos/cli/elb.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Pipeline** | `elasticloadbalancing:*` sobre sus recursos, `acm:Describe*` | — |
| **Operadores** | `Describe*` (lectura) | — |
| **Cliente final** | — | TLS hacia el listener; autenticación OIDC opcional |
| **Aplicación** | — | Solo recibe tráfico del balanceador (SG) |

- **TLS 1.2+** con política moderna (p. ej. la de TLS 1.3 recomendada vigente); HSTS en la aplicación o CloudFront.
- **Redirección 80→443**; sin tráfico en claro.
- **Logs de acceso** a S3 (cifrado, con ciclo de vida) y, si hace falta, logs de conexión.
- **WAF** asociado al ALB; protección contra *desync* en modo defensivo/estricto.
- ALB **interno** para servicios que no son públicos.
- Cuidado con confiar en `X-Forwarded-For`: toma el elemento correcto (el último salto de confianza).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Health check de *readiness* real | Health check a `/` que siempre devuelve 200 |
| `deregistration_delay` alineado con el apagado de la app | Dejar 300 s (despliegues lentísimos) o 0 (cortes) |
| Keep-alive de la app > idle timeout del ALB | Que la app cierre conexiones antes que el ALB (502) |
| Un ALB compartido con reglas por servicio | Un ALB por microservicio sin necesidad (costo) |
| Subredes en ≥ 2 zonas | Una sola zona |
| Certificados en ACM con renovación automática | Certificados manuales |
| Registrar el DNS con **alias** al ALB | IP fija del ALB (cambia) |
| Logs de acceso activados | Diagnosticar a ciegas |

## 8. Límites, costos y versiones
- **Costo:** por hora de balanceador + **LCU** (unidades de capacidad según conexiones, ancho de banda, reglas); NLB con su propia métrica (NLCU); IP públicas IPv4 también se cobran. *Verifica precios.*
- **Límites** (verifica): reglas por listener, target groups por ALB, destinos por target group, certificados por listener.
- **Terraform:** `aws_lb`, `aws_lb_listener`, `aws_lb_listener_rule`, `aws_lb_target_group`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
