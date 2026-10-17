# Oracle OCI · 05 Ingress y API

¿Cómo llega el tráfico de afuera a mis servicios, y qué lo filtra en el camino? Cinco piezas que se combinan en capas.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Load Balancer](load-balancer/README.md) | ¿Cómo reparto HTTP entre réplicas sanas? | La recepcionista de una clínica | Web/API HTTP, TLS, rutas |
| [Network Load Balancer](network-load-balancer/README.md) | ¿Y si es TCP/UDP o necesito la IP del cliente? | El guardia del estacionamiento | Kafka, gRPC, UDP, *appliances* |
| [API Gateway](api-gateway/README.md) | ¿Quién puede llamar a mi API y cuántas veces? | El mostrador de seguridad del edificio | JWT, cuotas, funciones como HTTP |
| [WAF](waf/README.md) | ¿Cómo freno ataques web conocidos? | El detector de metales del concierto | OWASP, fuerza bruta, rutas por IP |
| [Ingress en OKE](ingress-oke/README.md) | ¿Cómo entra el tráfico a mis pods? | La portería del condominio | Muchos servicios HTTP en Kubernetes |

## Árbol de decisión: «quiero…»

```
¿El tráfico es HTTP/HTTPS?
   ├─ ¿Necesito JWT, scopes, cuotas por cliente o exponer funciones?  → API Gateway
   ├─ ¿Son pods de OKE con rutas por host/ruta?                        → Ingress (crea un Load Balancer)
   └─ ¿Solo repartir entre réplicas con TLS y rutas?                    → Load Balancer
       └─ ¿Está expuesto a Internet?                                    → + WAF sobre el Load Balancer

¿Es TCP/UDP, necesito la IP real del cliente o latencia mínima?        → Network Load Balancer

¿Es tráfico solo interno entre microservicios?                          → Nada de esto: ClusterIP / DNS privado
```

## Comparativa

| Característica | Load Balancer | NLB | API Gateway | WAF | Ingress OKE |
|---|---|---|---|---|---|
| **Capa** | 7 (y TCP) | 4 | 7 | 7 | 7 (o 4 con NLB) |
| **TLS** | Termina | No (pasa) | Termina | — (en el LB) | En el LB creado |
| **Autenticación** | No | No | JWT / autorizador | No | No (anotaciones limitadas) |
| **IP del cliente** | `X-Forwarded-For` | Preservada | Cabecera | Ve la real | Según el modo |
| **Cobro** | Hora + Mbps | Tráfico | Por llamadas | Instancia + peticiones | El LB que crea |
| **Error típico** | Chequeo pesado | NSG sin IPs de clientes | Sin audiencia | Bloquear el día 1 | Un LB por servicio |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Tienda web y API pública | WAF → Load Balancer → Ingress nativo → pods | Filtra, reparte y enruta por ruta |
| API de socios con llaves | API Gateway + autorizador propio → Ingress interno | Cuotas y llaves por socio |
| Brokers de mensajería internos | NLB privado | TCP, sin abrir paquetes |
| Panel de administración | Solo por VPN/Bastion; regla de WAF como red de seguridad | No exponerlo es mejor que filtrarlo |

## Orden recomendado de adopción
1. Load Balancer con TLS y chequeos de *readiness*.
2. WAF en modo detección; luego bloqueo.
3. Ingress compartido en OKE con IP reservada.
4. API Gateway para APIs de terceros o funciones.
5. NLB para protocolos no HTTP.
6. Todo como código; registros de acceso activos.

## Reglas transversales
- Backends en subredes privadas; NSG solo desde la pieza anterior.
- La IP del cliente se lee de cabeceras **solo** si vienen de un proxy confiable.
- Drenado y apagado ordenado en cada despliegue.
- TLS 1.2+; certificados renovados automáticamente.
- Un LB compartido mejor que muchos sueltos.

## Java en ingress: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Load Balancer | Drenado seguro que respeta el mínimo de réplicas sanas | Núcleo puro + adaptador del SDK |
| NLB | Semáforo de salud de los backend sets | Lectura → veredicto puro |
| API Gateway | Autorizador de llaves de socios + inventario de APIs | Respuesta con la forma del gateway |
| WAF | Auditor de políticas contra el mínimo de la empresa | Resumen del SDK → reglas puras |
| Ingress OKE | Resolutor de IP del cliente + búsqueda del LB creado | Proxies confiables |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): subredes públicas/privadas, NSG, DNS.
- [IAM](../02-iam/README.md): quién crea balanceadores; identidad de controladores.
- [Compute](../04-compute/README.md): los backends (VM, OKE, Functions, Container Instances).
- [Gobierno](../09-gobierno/README.md): cuotas de LB y etiquetas de costo.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
