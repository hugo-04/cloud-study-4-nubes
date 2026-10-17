# AWS · Compute · Amazon EKS

**Amazon EKS** (Elastic Kubernetes Service) es **Kubernetes administrado**: AWS opera el plano de control (la API de Kubernetes y su base de datos) y tú decides cómo se ejecutan tus *pods*: en nodos EC2 que administras con grupos gestionados, en capacidad que aprovisiona Karpenter, en Fargate o con **EKS Auto Mode**, donde AWS también administra los nodos.

## 1. Qué es

**Analogía:** un aeropuerto. AWS opera la **torre de control** (control plane, siempre disponible en varias zonas). Tú decides qué **aviones** (pods) salen y qué **puertas** (nodos) usas; con Auto Mode, AWS también opera las puertas.

```
            ┌────────── Plano de control (lo opera AWS, multi-AZ) ──────────┐
 kubectl ──►│ API server · etcd · scheduler · controllers                   │
            └───────────────────────────┬───────────────────────────────────┘
                                        │
   ┌──────────── Plano de datos (tu VPC) ──────────────────────────────────┐
   │ Nodo (EC2)             Nodo (EC2)              Fargate (1 pod = 1 VM) │
   │ ├ pod pedidos          ├ pod pedidos           └ pod batch            │
   │ └ pod pagos            └ pod facturas                                  │
   └───────────────────────────────────────────────────────────────────────┘
```

## 2. Cómo funciona por dentro

### Plano de control
Gestionado por AWS: API server y etcd en varias zonas de disponibilidad, parches y escalado automáticos. Tienes un **endpoint** (público, privado o ambos) y puedes activar los **logs del plano de control** (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) hacia CloudWatch.

### Plano de datos: cuatro formas
| Opción | Qué administras tú | Cuándo |
|---|---|---|
| **Grupos de nodos gestionados** | Tipo de instancia, tamaño, versión de AMI (AWS orquesta el ciclo de vida) | Lo más común y predecible |
| **Karpenter** | Reglas (`NodePool`); crea nodos a medida según los pods pendientes | Ahorro y variedad de instancias, Spot |
| **Fargate** | Solo el perfil; cada pod corre aislado | Cargas esporádicas sin nodos (sin DaemonSets, sin GPU; verifica límites) |
| **EKS Auto Mode** | Casi nada: AWS gestiona nodos, red, balanceadores y discos *(verifica funciones y costo)* | Equipos pequeños que quieren menos operación |

### Add-ons esenciales
| Add-on | Para qué |
|---|---|
| **VPC CNI** | Da a cada pod una **IP real de tu VPC** |
| **CoreDNS** | DNS dentro del clúster |
| **kube-proxy** | Reglas de red de los Services |
| **EBS CSI driver** | Discos EBS como volúmenes persistentes |
| **EKS Pod Identity Agent** | Credenciales AWS para pods ([IRSA y Pod Identity](../../02-iam/irsa-pod-identity/README.md)) |
| **metrics-server** | Métricas para el HPA |
| **AWS Load Balancer Controller** | Crea ALB/NLB desde `Ingress`/`Service` ([Ingress y API](../../05-ingress-api/README.md)) |

### Acceso al clúster: *access entries*
El modo moderno es `authentication_mode = "API"`: asocias un rol/usuario de IAM a una **política de acceso** de EKS (`AmazonEKSClusterAdminPolicy`, `AmazonEKSAdminPolicy`, `AmazonEKSEditPolicy`, `AmazonEKSViewPolicy`) con alcance de clúster o de *namespace*. El antiguo `ConfigMap aws-auth` queda como legado.

### Red
Los pods usan IP de las subredes (VPC CNI): un clúster grande **consume muchas IPs** (mitigar con *prefix delegation* o subredes secundarias). Los *security groups* se pueden aplicar a pods; las *NetworkPolicy* limitan el tráfico entre pods (verifica soporte del CNI).

### Escalado
- **Pods:** HPA (por CPU/memoria/métricas propias), VPA.
- **Nodos:** Karpenter o Cluster Autoscaler; Auto Mode lo hace solo.

### Versiones y actualización
Kubernetes publica una versión menor varias veces al año. EKS da un periodo de **soporte estándar** y otro de **soporte extendido con costo adicional** *(verifica fechas)*. Orden de actualización: **plano de control → add-ons → nodos**, de una versión menor cada vez, probando en un clúster de preproducción.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Muchos microservicios, equipos con experiencia en Kubernetes, Helm/operadores/malla | **EKS** |
| Portabilidad de manifiestos y herramientas del ecosistema | **EKS** |
| Pocos servicios y quieres menos operación | [ECS Fargate](../ecs-fargate/README.md) o [Express Mode](../ecs-express-mode/README.md) |
| Eventos cortos | [Lambda](../lambda/README.md) |
| Equipo sin experiencia en Kubernetes y sin tiempo para aprenderlo | **No**: la complejidad se paga todos los días |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Pod** | La unidad mínima: uno o más contenedores juntos |
| **Deployment** | «Quiero N pods de esta versión» |
| **Service** | Nombre y balanceo interno estables para un grupo de pods |
| **Ingress** | Regla HTTP de entrada desde fuera |
| **Namespace** | Carpeta lógica para aislar equipos/entornos |
| **Node group** | Conjunto de nodos EC2 gestionados |
| **HPA / PDB** | Escalar pods / mínimo de pods disponibles durante interrupciones |
| **Access entry** | Quién de IAM puede entrar al clúster y con qué rol |
| **Add-on** | Componente del sistema que EKS instala y actualiza |
| **Probes** | Comprobaciones de vida y de disponibilidad de un pod |

## 5. Cómo se usa
1. Crea el clúster y el grupo de nodos con Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Da acceso con *access entries*; configura `kubectl`: [`ejemplos/cli/eks.sh`](ejemplos/cli/eks.sh).
3. Instala el controlador de balanceadores y el *autoscaler* (Karpenter o el de Auto Mode).
4. Despliega con manifiestos: [`ejemplos/k8s/pedidos.yaml`](ejemplos/k8s/pedidos.yaml) (Deployment, Service, HPA, PDB, ServiceAccount).
5. Da permisos AWS a los pods con **Pod Identity** (o IRSA).
6. Observa: logs del plano de control, Container Insights, métricas de Prometheus.

## 6. Seguridad

| Identidad | Plano de control (API de AWS) | Plano de datos (API de Kubernetes y AWS desde los pods) |
|---|---|---|
| **Pipeline** | `eks:DescribeCluster` + access entry con rol de edición | `kubectl apply` en sus *namespaces* |
| **Administradores** | `eks:*` limitado a operaciones | Access entry de administrador (temporal) |
| **Pods** | — | Pod Identity / IRSA con rol por *ServiceAccount* |
| **Nodos** | Rol de nodo (ECR, CNI) | — |

- Endpoint del API **privado** (o público restringido por CIDR) y acceso por VPN/bastión/SSM.
- **Cifrado de secretos de Kubernetes** con clave KMS; recuerda que un `Secret` es solo base64: mejor leer de Secrets Manager.
- *Pod Security Standards* (`restricted`), usuario no-root, `readOnlyRootFilesystem`, sin `privileged`.
- Imágenes de ECR con escaneo; políticas de admisión.
- Un rol de IAM **por servicio**, no uno compartido por el nodo.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| `requests` y `limits` en cada contenedor | Pods sin recursos declarados |
| Probes de *readiness* y *liveness* distintas | Una sola probe que mata pods lentos al arrancar |
| `PodDisruptionBudget` y `topologySpreadConstraints` | Todos los pods en un nodo/zona |
| Pod Identity/IRSA por servicio | Permisos AWS en el rol del nodo |
| Actualizar una versión menor cada vez, con preproducción | Saltar versiones o dejar vencer el soporte |
| `preStop` + `terminationGracePeriodSeconds` | Cortar peticiones al desplegar |
| Subredes amplias o prefix delegation | Subredes `/24` para un clúster grande |
| Todo por GitOps/pipeline | `kubectl edit` en producción |

## 8. Límites, costos y versiones
- **Costo:** cargo por hora por clúster + nodos (EC2/Fargate) + balanceadores + NAT + datos; el soporte extendido suma un cargo por clúster. *Verifica precios y calendario.*
- **Límites:** pods por nodo dependen del tipo de instancia (o de *prefix delegation*), cuotas de ENI/IP.
- **Terraform:** `aws_eks_cluster`, `aws_eks_node_group`, `aws_eks_addon`, `aws_eks_access_entry`, `aws_eks_pod_identity_association`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
