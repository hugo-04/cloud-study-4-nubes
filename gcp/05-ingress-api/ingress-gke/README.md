# Google Cloud · Ingress y API · Entrada a GKE (Gateway API e Ingress)

Cómo llega el tráfico a los pods de GKE. Lo recomendado es la **Gateway API** (`Gateway` + `HTTPRoute`): el controlador de GKE crea un **balanceador de aplicación** de Google (externo global, regional o interno) con NEG que apuntan **directo a los pods**. También existe el `Ingress` clásico y el `Service type: LoadBalancer` (balanceador de red).

## 1. Qué es

**Analogía:** la portería de un condominio. El `Gateway` es la portería (quién la administra, en qué puerta); cada `HTTPRoute` es la indicación «paquetes para la casa 12 por aquí» que escribe cada vecino, sin pedirle permiso al portero para cada cambio.

```
 Equipo de plataforma: Gateway "tienda" (gatewayClassName: gke-l7-global-external-managed, IP reservada, certificado)
 Equipos de app:       HTTPRoute "pedidos" (ns tienda): host tienda.modalima.example, /api/pedidos → Service pedidos:8080
                       HTTPRoute "catalogo" (ns catalogo): /api/catalogo → Service catalogo:8080
 GKE crea: forwarding rule + proxy + URL map + backend services + NEG (IPs de pods) + chequeos de salud
 Políticas: HealthCheckPolicy, GCPBackendPolicy (Cloud Armor, timeouts, IAP), GCPGatewayPolicy (política SSL)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **GatewayClass** | Tipo de balanceador: `gke-l7-global-external-managed`, `gke-l7-regional-external-managed`, `gke-l7-rilb` (interno)… *(verifica nombres)* |
| **Gateway** | Instancia: listeners (puerto, protocolo, TLS), IP, namespaces que pueden adjuntar rutas |
| **HTTPRoute** | Reglas de host/ruta/cabecera → `Service` (con pesos para canarios) |
| **NEG** | Endpoints de pods: el balanceador habla directo con los pods |
| **HealthCheckPolicy** | Chequeo propio por servicio |
| **GCPBackendPolicy** | Cloud Armor, timeout, afinidad, IAP, logging por servicio |
| **Ingress clásico** | Un objeto por balanceador; menos flexible para varios equipos |
| **Service LoadBalancer** | Balanceador de red (capa 4) para TCP/UDP |

### Separación de roles
- Plataforma crea `Gateway` y decide qué namespaces pueden adjuntar rutas (`allowedRoutes`).
- Cada equipo publica su `HTTPRoute` en su namespace.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Varios servicios HTTP de varios equipos bajo un dominio | **Gateway API** |
| Canario por pesos entre dos versiones | `HTTPRoute` con `backendRefs` ponderados |
| TCP/UDP (por ejemplo, gRPC sin HTTP/2 en el borde o un juego) | `Service type: LoadBalancer` |
| Tráfico solo dentro del clúster | **No**: `ClusterIP` |
| API con JWT y cuotas | [API Gateway](../api-gateway/README.md) delante |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Container-native load balancing** | El balanceador apunta a IPs de pods (NEG) |
| **allowedRoutes** | Qué namespaces pueden colgar rutas del Gateway |
| **ReferenceGrant** | Permiso para referenciar recursos de otro namespace |
| **IP reservada** | Para que la IP no cambie al recrear el Gateway |
| **X-Forwarded-For** | Cabecera con la IP del cliente que agrega el balanceador |

## 5. Cómo se usa
1. IP global reservada y regla de firewall para chequeos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Gateway, HTTPRoute con canario y políticas: [`ejemplos/k8s/gateway.yaml`](ejemplos/k8s/gateway.yaml).
3. En la app, la IP real del cliente detrás del balanceador de Google y la búsqueda de la IP del Gateway: [uso en Java](uso-en-java.md).
4. Diagnóstico: [`ejemplos/cli/gateway.sh`](ejemplos/cli/gateway.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | RBAC para `Gateway` y `GatewayClass` | — |
| Equipos | RBAC para `HTTPRoute` en su namespace | — |
| Clientes | — | Cloud Armor vía `GCPBackendPolicy` |

- `allowedRoutes` restringido a namespaces etiquetados.
- Certificados administrados (Certificate Manager) y política SSL moderna.
- NetworkPolicy: pods aceptan solo desde los rangos del balanceador.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Un Gateway compartido + rutas por equipo | Un balanceador por servicio |
| IP reservada | IP efímera en el DNS |
| `HealthCheckPolicy` a *readiness* | Chequeo por defecto a `/` |
| Canarios por peso | Cambios del 100 % de golpe |
| Apagado ordenado y `preStop` | Pods que mueren con conexiones vivas |

## 8. Límites, costos y versiones
- **Costo:** el balanceador que se crea (reglas, procesamiento) *(verifica)*.
- **Versiones** (verifica): versión de GKE con Gateway API habilitada; recursos `gateway.networking.k8s.io/v1`.
- **Terraform:** `google_compute_global_address`, `google_compute_firewall`; los objetos de Kubernetes con manifiestos o el proveedor de Kubernetes.
- **Java:** la app solo necesita leer bien la IP del cliente; para inventario, `GlobalForwardingRulesClient`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
