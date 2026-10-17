# AWS · Ingress y API · Ingress en EKS (AWS Load Balancer Controller)

En Kubernetes, un **Ingress** es la regla que dice «las peticiones a este host/ruta van a este Service». En EKS, el encargado de convertir esa regla en infraestructura real es el **AWS Load Balancer Controller**: crea y mantiene **ALB** (para `Ingress`) y **NLB** (para `Service` tipo `LoadBalancer`) y registra **directamente las IP de los pods** como destinos.

## 1. Qué es

**Analogía:** el **conserje inteligente** del edificio. Tú pegas una nota en el tablón («las visitas por *pedidos* van al piso 3»; Ingress) y el conserje (controlador) cambia solo las señales, las puertas y la lista de oficinas abiertas (ALB, listeners, target groups) cada vez que un piso cambia de inquilino (los pods se crean y mueren).

```
 kubectl apply -f ingress.yaml
          │
          ▼
 Ingress "tienda" (annotations) ──► AWS Load Balancer Controller (pod en kube-system, con rol de IAM)
                                          │ crea / actualiza
                                          ▼
                     ALB ── listeners ── reglas ── Target group (tipo ip) ──► IP de cada pod (ENI de la VPC)
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Controlador** | Se instala (Helm o complemento) en `kube-system`; observa `Ingress`, `Service` y `TargetGroupBinding`; llama a las APIs de ELB, EC2, ACM y WAF |
| **Ingress (`ingressClassName: alb`)** | Un ALB; cada regla del Ingress es una regla del listener |
| **Service `LoadBalancer` (NLB)** | Un NLB para TCP/UDP/TLS |
| **Modo de destino `ip`** | El balanceador envía el tráfico **directo al pod** (recomendado con el CNI de VPC); el modo `instance` pasa por los NodePort |
| **Agrupar Ingress (`group.name`)** | Varios Ingress de distintos equipos comparten **un** ALB |
| **Anotaciones** | `scheme`, `target-type`, `certificate-arn`, `listen-ports`, `ssl-redirect`, `healthcheck-path`, `wafv2-acl-arn`, atributos de LB y de target group… |
| **TargetGroupBinding** | Enlaza un Service a un target group que ya existe (creado con Terraform) |
| **Pod readiness gate** | El pod no se considera *Ready* hasta que el ALB lo ve sano (despliegues sin cortes) |
| **Etiquetas de subred** | `kubernetes.io/role/elb=1` (públicas), `kubernetes.io/role/internal-elb=1` (privadas) para que el controlador las descubra |
| **Identidad** | El controlador usa **Pod Identity** (o IRSA) con una política de IAM específica |

### Alternativas y evolución
- **EKS Auto Mode** incluye esta capacidad ya integrada (con su propia clase de Ingress; verifica los detalles).
- **Gateway API** es la API sucesora de Ingress; el controlador de AWS la soporta en versiones recientes *(verifica versión y madurez)*.
- **ingress-nginx** (controlador comunitario): el proyecto anunció su **retiro** en 2026 *(verifica el estado)*; para nuevos clústeres prefiere el controlador de AWS o Gateway API.
- **DNS automático:** `external-dns` crea los registros de Route 53 a partir del Ingress.
- **Certificados:** ACM (el controlador los descubre por dominio o por ARN); no hace falta `cert-manager` para el borde.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Exponer microservicios HTTP de EKS por un dominio con reglas por host/ruta | **Ingress (ALB)** con `group.name` |
| TCP/UDP, IP fija o PrivateLink | **Service LoadBalancer (NLB)** |
| Ya tienes el balanceador en Terraform | **TargetGroupBinding** |
| Tráfico interno entre servicios del clúster | **No**: `Service` ClusterIP y DNS interno |
| Quieres una malla de servicios (mTLS interno, reintentos) | Una malla, además del Ingress |
| Todo detrás de CloudFront y WAF | Ingress interno/público restringido + [CloudFront](../cloudfront-waf/README.md) delante |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Ingress** | Regla de entrada HTTP por host/ruta |
| **IngressClass** | Qué controlador atiende ese Ingress |
| **Service** | Nombre y balanceo estable dentro del clúster |
| **target-type: ip** | El ALB habla directo con la IP del pod |
| **group.name** | Compartir un ALB entre Ingress |
| **TargetGroupBinding** | Enganchar un Service a un target group existente |
| **Readiness gate** | El pod espera la bendición del ALB para recibir tráfico |
| **Pod Identity** | Rol de IAM para el pod del controlador |
| **external-dns** | Crea los registros DNS desde el Ingress |

## 5. Cómo se usa
1. Etiqueta las subredes (`elb` / `internal-elb`) y crea el rol del controlador con **Pod Identity**: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Instala el controlador con Helm: [`ejemplos/cli/lbc.sh`](ejemplos/cli/lbc.sh).
3. Etiqueta el *namespace* para el **readiness gate**.
4. Aplica el Ingress y el Service: [`ejemplos/k8s/ingress.yaml`](ejemplos/k8s/ingress.yaml). NLB y TargetGroupBinding: [`ejemplos/k8s/nlb-y-binding.yaml`](ejemplos/k8s/nlb-y-binding.yaml).
5. Verifica con `kubectl describe ingress` (muestra el DNS del ALB y eventos).
6. Alinea el apagado de los pods con el *deregistration delay* ([ALB](../alb-nlb/README.md)).

## 6. Seguridad

| Identidad | Plano de control (API de AWS) | Plano de datos (Kubernetes) |
|---|---|---|
| **Controlador (pod)** | Política de IAM específica: ELB, EC2 (SG, subredes), ACM, WAF, Shield | Permisos RBAC para observar Ingress/Service |
| **Equipos de aplicación** | — | RBAC en su *namespace* para crear Ingress |
| **Pipeline** | `helm upgrade`, `kubectl apply` | — |

- **Quién puede crear Ingress** decide quién puede **publicar a Internet**: restringe con RBAC y políticas de admisión (p. ej. exigir `scheme: internal` salvo en un *namespace* autorizado).
- El *security group* de los pods admite solo al del ALB (el controlador puede gestionarlo).
- **TLS** con ACM y `ssl-policy` moderna; redirección 80→443.
- WAF con `wafv2-acl-arn`; ALB interno para servicios no públicos.
- Cuidado con anotaciones que otros equipos puedan sobrescribir en un `group.name` compartido.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| `target-type: ip` con el CNI de VPC | `instance` y NodePort sin motivo |
| `group.name` para compartir un ALB | Un ALB por Ingress (costo) |
| Readiness gate en el *namespace* | Despliegues sin sincronizar con el balanceador |
| `healthcheck-path` de *readiness* | Health check a `/` genérico |
| `preStop` + `terminationGracePeriodSeconds` coherentes | SIGTERM sin dar tiempo al ALB |
| Política de IAM oficial del controlador, versionada | Dar `elasticloadbalancing:*` sobre `*` al nodo |
| Subredes etiquetadas | Que el controlador adivine subredes |
| Todo el Ingress en Git (GitOps) | `kubectl edit ingress` en producción |

## 8. Límites, costos y versiones
- **Costo:** los balanceadores que el controlador crea (por hora + LCU); compartir ALB reduce el costo fijo. El controlador en sí no cobra.
- **Límites** (verifica): reglas por listener, target groups por ALB, pods por target group.
- **Versiones:** el controlador publica versiones menores con frecuencia; actualízalo con `helm upgrade` y revisa los CRD.
- **Terraform:** rol + `aws_eks_pod_identity_association` + etiquetas de subred. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
