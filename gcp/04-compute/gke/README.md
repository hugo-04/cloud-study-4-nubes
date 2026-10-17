# Google Cloud · Compute · GKE (Google Kubernetes Engine)

Kubernetes administrado por Google. En modo **Autopilot**, Google administra también los nodos y cobras por lo que piden tus pods; en modo **Standard**, administras node pools. Es la plataforma para muchos microservicios con réplicas, despliegues graduales, malla de servicios y políticas comunes.

## 1. Qué es

**Analogía:** un edificio de oficinas con administración. Autopilot es el edificio con todo incluido (limpieza, mantenimiento, seguridad); Standard te da los pisos y tú contratas a quién los mantiene.

```
 Clúster regional "tienda" (canal REGULAR, nodos privados, Workload Identity, Dataplane V2)
   ├─ plano de control (Google) ── endpoint privado / redes autorizadas
   ├─ Autopilot: pods con requests → Google pone los nodos
   └─ Standard: node pools (general e2-standard-4, spot para lotes) con autoscaler
 Namespaces: tienda, pagos, plataforma · Gateway API / Ingress · NetworkPolicy · PodDisruptionBudget
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Autopilot / Standard** | Quién administra los nodos y cómo se cobra |
| **Regional / zonal** | Plano de control y nodos en 3 zonas o en una |
| **Canal de lanzamiento** | `RAPID`, `REGULAR`, `STABLE` (o extendido): actualizaciones automáticas |
| **Ventanas y exclusiones de mantenimiento** | Cuándo puede actualizar Google |
| **Clúster privado** | Nodos sin IP externa; endpoint del plano de control privado o con redes autorizadas |
| **VPC nativo** | Pods y servicios con IPs de rangos secundarios |
| **Workload Identity** | Pods con identidad de IAM sin llaves ([detalle](../../02-iam/workload-identity-gke/README.md)) |
| **Dataplane V2** | Red basada en eBPF con NetworkPolicy integrada |
| **Autoscaling** | HPA/VPA en pods, cluster autoscaler / node auto-provisioning en nodos |
| **Binary Authorization** | Solo imágenes firmadas/permitidas |
| **Backup for GKE** | Respaldos de recursos y volúmenes |

### Actualizaciones
Google actualiza el plano de control y (en Autopilot o con autoactualización) los nodos según el canal. Tus aplicaciones deben tolerarlo: **PodDisruptionBudget**, réplicas ≥ 2, `readinessProbe` y apagado ordenado.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| 10+ microservicios con plataforma común | **GKE Autopilot** |
| Necesitas DaemonSets privilegiados, GPU especiales o control fino de nodos | **GKE Standard** |
| Un par de APIs HTTP sin estado | [Cloud Run](../cloud-run/README.md) |
| Lotes simples | Cloud Run jobs o Batch |
| Equipo sin experiencia en Kubernetes | Empieza con Cloud Run |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Request/limit** | Recursos que el pod pide y su tope |
| **PDB** | Cuántas réplicas pueden faltar a la vez |
| **HPA** | Escalado horizontal por métricas |
| **Canal** | Qué tan rápido llegan las versiones nuevas |
| **Autopilot** | Pagas por pods, no por nodos |

## 5. Cómo se usa
1. Clúster Autopilot privado con canal y ventana de mantenimiento: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Deployment con probes, PDB y HPA: [`ejemplos/k8s/app.yaml`](ejemplos/k8s/app.yaml).
3. Audita los clústeres (versión, canal, privados, Workload Identity) desde [Java](uso-en-java.md).
4. CLI: [`ejemplos/cli/gke.sh`](ejemplos/cli/gke.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/container.admin` | RBAC `cluster-admin` |
| Equipos | `roles/container.developer` (o RBAC por namespace) | Su namespace |
| Pods | Workload Identity | Roles mínimos por KSA |

- Endpoint del plano de control privado o redes autorizadas.
- Nodos privados y cuenta de servicio de nodo mínima.
- NetworkPolicy por namespace; Binary Authorization en producción.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Autopilot por defecto | Standard sin una razón |
| Canal `REGULAR` + ventanas de mantenimiento | Versiones fijas que caducan |
| PDB y ≥ 2 réplicas | Un pod por servicio |
| Requests realistas | Pods sin requests (en Standard) |
| Workload Identity | Llaves JSON en secretos |

## 8. Límites, costos y versiones
- **Costo:** tarifa de administración del clúster (con un crédito gratuito) + Autopilot por vCPU/memoria/disco pedidos, o Standard por nodos *(verifica)*.
- **Límites** (verifica): nodos por clúster, pods por nodo, versiones soportadas y fin de soporte.
- **Terraform:** `google_container_cluster`, `google_container_node_pool`.
- **Java:** `ClusterManagerClient` (`google-cloud-container`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
