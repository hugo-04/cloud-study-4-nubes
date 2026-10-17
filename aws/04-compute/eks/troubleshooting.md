# AWS · EKS · Troubleshooting

Orden: **¿entro al clúster? (`kubectl auth whoami`) → ¿los nodos están Ready? → ¿el pod está Pending / CrashLoop / ImagePull? → `kubectl describe pod` y `logs --previous` → ¿probes? → ¿permisos AWS del pod? → ¿red / DNS?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `error: You must be logged in` / `Unauthorized` | Tu rol de IAM no tiene access entry | `aws eks list-access-entries` | Crear access entry + política |
| `kubectl` se cuelga | Endpoint privado y estás fuera de la VPC | `describe-cluster` → `endpointPublicAccess` | VPN/bastión o permitir tu CIDR |
| Nodo `NotReady` | CNI/kubelet caído, sin IPs, rol de nodo incompleto | `kubectl describe node`; add-ons | Reparar add-on VPC CNI; revisar rol y subred |
| Pod `Pending` — `Insufficient cpu/memory` | Sin capacidad | `describe pod` → eventos | Más nodos / Karpenter; ajustar requests |
| Pod `Pending` — `too many pods` / sin IP | Límite de pods por nodo o IPs de subred agotadas | IPs libres; `max-pods` | Prefix delegation; subredes mayores |
| `ImagePullBackOff` | Sin ruta a ECR, imagen inexistente o sin permiso | `describe pod` | Endpoints ECR/S3 o NAT; rol de nodo con ECR |
| `CrashLoopBackOff` | Error de arranque (config, secreto, puerto) | `kubectl logs --previous` | Corregir; revisar variables |
| `OOMKilled` (137) | Límite de memoria bajo | `describe pod` → Last State | Subir límite; `MaxRAMPercentage` |
| Readiness falla en el arranque | Spring tarda más que la probe | Eventos de probe | `startupProbe` / `initialDelaySeconds` |
| `AccessDenied` desde el pod | Sin Pod Identity/IRSA o ServiceAccount equivocada | `kubectl describe sa`; variables `AWS_*` en el pod | Asociación correcta; SDK actualizado |
| ALB no se crea | Controlador sin permisos o subredes sin etiquetas | Logs del controlador | Permisos y etiquetas `kubernetes.io/role/elb` |
| Resolución DNS falla | CoreDNS caído o sin recursos | `kubectl -n kube-system get pods` | Reparar/escalar CoreDNS |
| Add-on en `DEGRADED` | Versión incompatible o permisos | `describe-addon` → `health` | Actualizar versión del add-on |
| Despliegue corta peticiones | Sin `preStop`/graceful | Logs de 502 | `preStop: sleep`, `terminationGracePeriodSeconds` |
