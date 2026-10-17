# AWS · Ingress en EKS · Troubleshooting

Orden: **`kubectl describe ingress` (eventos) → logs del controlador → ¿IAM del controlador? → ¿subredes etiquetadas? → ¿target group sano? → ¿SG? → ¿pods Ready? (readiness gate)**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Ingress sin `ADDRESS` | Controlador caído o sin permisos, subredes sin etiquetas | `kubectl -n kube-system logs deploy/aws-load-balancer-controller` | Reparar rol/etiquetas |
| `AccessDenied` en eventos | Política de IAM incompleta o rol no asociado (Pod Identity) | Asociación del ServiceAccount | Política oficial de la versión; asociación correcta |
| `couldn't auto-discover subnets` | Falta `kubernetes.io/role/elb` o `internal-elb` | Etiquetas de las subredes | Etiquetar; o `alb.ingress.kubernetes.io/subnets` |
| Destinos `unhealthy` | Health check mal, SG del pod no admite al ALB | Target group en la consola/CLI | `healthcheck-path`, `healthcheck-port`; SG |
| 502/504 durante despliegues | Sin preStop/gracia/readiness gate | Eventos; logs del ALB | Apagado coordinado; readiness gate |
| Pod en `Running` pero no `Ready` | Readiness gate espera al ALB | `kubectl describe pod` → condiciones | Revisar salud en el target group |
| `certificate not found` | El dominio no coincide con un certificado de ACM | ACM | `certificate-arn` explícito |
| Redirección infinita | App redirige a HTTPS sin leer `X-Forwarded-Proto` | Cabeceras | Estrategia de cabeceras ([ALB](../alb-nlb/uso-en-java.md)) |
| Dos Ingress se pisan | Misma `group.order`/regla en el mismo grupo | Eventos | Órdenes únicos; hosts distintos |
| ALB no se borra | `deletion_protection` activado | Atributos | Desactivar antes de borrar |
| NLB no registra pods | `nlb-target-type: ip` ausente o SG | Anotaciones del Service | Corregir anotaciones |
| WAF no se aplica | ARN en otra región o de otro alcance | ARN | WAF `REGIONAL` en la misma región |
