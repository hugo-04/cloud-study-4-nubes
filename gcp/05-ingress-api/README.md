# Google Cloud · 05 Ingress y API

¿Cómo llega el tráfico de afuera a mis servicios y qué lo filtra? En Google Cloud casi todo pasa por el **balanceador de aplicación**, con **Cloud Armor** encima y, si hace falta, **API Gateway** para JWT y cuotas.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Cloud Load Balancing](cloud-load-balancing/README.md) | ¿Cómo reparto y enruto HTTP(S) global? | La central con un número internacional | Web/API, TLS, rutas, CDN |
| [API Gateway](api-gateway/README.md) | ¿Quién puede llamar y cuántas veces? | Recepción con lista de invitados | JWT, llaves y cuotas sobre Cloud Run |
| [Cloud Armor](cloud-armor/README.md) | ¿Cómo freno ataques web? | Control de seguridad del aeropuerto | WAF, tasa, DDoS L7 |
| [Entrada a GKE](ingress-gke/README.md) | ¿Cómo entra el tráfico a mis pods? | La portería del condominio | Gateway API, rutas por equipo |

## Árbol de decisión: «quiero…»

```
¿HTTP(S) público?
   ├─ ¿Pods de GKE de varios equipos?            → Gateway API (crea el balanceador de aplicación)
   ├─ ¿Cloud Run con dominio propio y WAF?       → Balanceador global + NEG sin servidor + Cloud Armor
   ├─ ¿JWT, llaves y cuotas por consumidor?      → API Gateway (backends privados)
   └─ Siempre que sea público                     → Cloud Armor en el backend service

¿TCP/UDP o IP del cliente intacta?               → Balanceador de red de paso (Service LoadBalancer en GKE)
¿Microservicios internos con TLS y rutas?         → Balanceador de aplicación interno
```

## Comparativa

| Característica | Load Balancing | API Gateway | Cloud Armor | Gateway API (GKE) |
|---|---|---|---|---|
| **Capa** | 7 (y 4) | 7 | 7 (en el balanceador) | 7 (crea el balanceador) |
| **Autenticación** | No (IAP opcional) | JWT / llave | No | No (IAP vía política) |
| **Cuotas por cliente** | No | Sí | Tasa por IP/clave | No |
| **Configuración** | URL map | OpenAPI 2.0 | Reglas CEL/WAF | Gateway + HTTPRoute |
| **Error típico** | Chequeos bloqueados | Backend público | Bloquear sin vista previa | Tomar el primer XFF |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Tienda web y API | Gateway API en GKE → balanceador global + Cloud Armor | Rutas por equipo y WAF |
| API de socios | API Gateway → Cloud Run privado | JWT, llaves y cuotas |
| Estáticos | Backend bucket + CDN | Rendimiento y costo |
| Login | Regla de rate-based ban | Fuerza bruta |

## Orden recomendado de adopción
1. Balanceador global con certificados administrados.
2. Cloud Armor en vista previa; luego bloqueo.
3. Gateway API para GKE con rutas por equipo.
4. API Gateway para APIs de terceros.
5. Pruebas de enrutamiento en el pipeline.

## Reglas transversales
- Una sola puerta: backends privados (ingress interno, firewall de rangos de Google).
- La IP del cliente es el penúltimo valor de `X-Forwarded-For`.
- TLS 1.2+ y certificados administrados.
- Cambios de rutas y reglas en código con pruebas.
- El gateway autentica; el dominio autoriza.

## Java en ingress: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Load Balancing | Simulador del URL map para pruebas | Modelo puro del recurso |
| API Gateway | Lectura de claims reenviadas + regla de dueño | Confianza condicionada |
| Cloud Armor | Auditor de políticas | Mínimo de la empresa |
| Entrada a GKE | IP real del cliente + inventario de reglas | Cabeceras confiables |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): rangos de chequeos y firewall.
- [Compute](../04-compute/README.md): backends en GKE, Cloud Run y MIG.
- [IAM](../02-iam/README.md): `run.invoker` para el gateway.
- [Gobierno](../09-gobierno/README.md): registros y costos.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
