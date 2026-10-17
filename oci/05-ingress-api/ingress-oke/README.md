# Oracle OCI · Ingress y API · Ingress en OKE

Cómo entra el tráfico a los pods de un clúster OKE. Tres caminos: un `Service` de tipo `LoadBalancer` (OKE crea un LB o NLB de OCI por ti), el **OCI Native Ingress Controller** (un LB de OCI enruta por host/ruta directo a los pods) o un controlador dentro del clúster (como NGINX) detrás de un LB.

## 1. Qué es

**Analogía:** la portería de un condominio. El `Service LoadBalancer` es abrir una puerta propia para cada casa; el Ingress es una sola portería que mira la dirección del sobre (host y ruta) y lo lleva a la casa correcta.

```
 Internet ──► LB de OCI (lo crea OKE a partir de YAML)
                ├─ host tienda.modalima.example /catalogo ──► pods catalogo (8080)
                └─ host tienda.modalima.example /pedidos  ──► pods pedidos  (8080)
 Opciones:  Service type=LoadBalancer  |  Ingress (OCI Native Ingress Controller)  |  Ingress NGINX detrás de un NLB
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Cloud controller manager** | Componente de OKE que convierte un `Service LoadBalancer` en un LB/NLB de OCI |
| **Anotaciones** | Configuran ese LB: forma, NSG, subred, interno/público, tipo `nlb`, políticas de salud |
| **OCI Native Ingress Controller** | Complemento que traduce objetos `Ingress` a un LB de OCI con backends = IPs de pods |
| **IngressClass + IngressClassParameters** | Qué controlador atiende y con qué LB (compartimento, subred, forma) |
| **Controlador en el clúster** | NGINX u otro, expuesto con un `Service LoadBalancer` (normalmente NLB) |
| **Readiness gates** | El LB marca sano al pod antes de que Kubernetes le mande tráfico (controlador nativo) |
| **IP pública reservada** | Para que el IP no cambie si el Service se recrea |

### Recorrido
1. Aplicas el YAML; el controlador crea o actualiza el LB de OCI (tarda minutos).
2. Con `Service LoadBalancer`, el LB apunta a los **nodos** (NodePort) y kube-proxy reenvía a los pods.
3. Con el controlador nativo, el LB apunta **directo a las IPs de los pods** (requiere red VCN-native de pods).
4. Al borrar el Service o el Ingress, OKE borra el LB: cuidado con los IP no reservados.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Un solo servicio TCP expuesto (por ejemplo, gRPC interno) | `Service LoadBalancer` con anotación de NLB |
| Muchos servicios HTTP bajo un dominio | **Ingress** (nativo de OCI) |
| Reglas avanzadas (reescrituras complejas, autenticación externa) | Controlador NGINX detrás de NLB |
| API pública con JWT y cuotas | [API Gateway](../api-gateway/README.md) delante del Ingress interno |
| Protección OWASP | [WAF](../waf/README.md) sobre el LB creado |
| Tráfico solo entre pods | **No**: `Service ClusterIP` |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **NodePort** | Puerto en cada nodo que reenvía al Service |
| **`externalTrafficPolicy: Local`** | Preserva la IP del cliente y evita un salto extra |
| **Pods VCN-native** | Cada pod tiene IP de la VCN; el LB puede apuntarle directo |
| **TLS en el Ingress** | Certificado como secreto de Kubernetes o del servicio Certificates |
| **Ruta `Prefix` vs `Exact`** | Cómo se compara la ruta |

## 5. Cómo se usa
1. Red y NSG del LB y una IP pública reservada: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Manifiestos: [`ejemplos/k8s/ingress.yaml`](ejemplos/k8s/ingress.yaml) (Ingress nativo) y [`ejemplos/k8s/service-lb.yaml`](ejemplos/k8s/service-lb.yaml) (Service con NLB).
3. La app debe resolver bien la IP del cliente y apagarse ordenadamente: [uso en Java](uso-en-java.md).
4. Diagnóstico: [`ejemplos/cli/ingress-oke.sh`](ejemplos/cli/ingress-oke.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| OKE (cloud controller) | Política para gestionar LB y NSG en el compartimento de red | — |
| Controlador nativo | Workload identity o instance principal con `manage load-balancers` | — |
| Equipos de app | RBAC de Kubernetes sobre `Ingress`/`Service` en su namespace | — |

- Limita quién puede crear `Service LoadBalancer` (cada uno crea un LB público y cuesta).
- NSG del LB por anotación; nodos/pods aceptan solo desde ese NSG.
- Anotación de LB **interno** cuando el tráfico viene de API Gateway o de la VCN.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Un Ingress compartido para muchos servicios HTTP | Un LB público por microservicio |
| IP pública reservada | Depender del IP efímero en el DNS |
| `readinessProbe` y `preStop` en los pods | Pods que reciben tráfico antes de estar listos |
| Anotar forma flexible y NSG | Dejar valores por defecto |
| Política de admisión que restrinja `LoadBalancer` | Que cualquiera cree LB públicos |

## 8. Límites, costos y versiones
- **Costo:** cada LB/NLB creado se cobra como uno normal *(verifica)*; el controlador no tiene cargo propio.
- **Límites** (verifica): LB por región (cuota), versiones de Kubernetes compatibles con el complemento nativo.
- **Anotaciones:** `service.beta.kubernetes.io/oci-load-balancer-*`, `oci.oraclecloud.com/load-balancer-type`, `oci-network-load-balancer.oraclecloud.com/*` *(verifica nombres en la documentación vigente)*.
- **SDK (para inspeccionar el LB creado):** `LoadBalancerClient`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
