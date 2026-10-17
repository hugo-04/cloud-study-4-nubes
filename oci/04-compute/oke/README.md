# Oracle OCI · Compute · OKE (Oracle Kubernetes Engine)

Kubernetes administrado: Oracle opera el plano de control (la «cabeza» del clúster) y tú decides los nodos donde corren tus pods. Es el hogar natural de los microservicios en contenedores.

## 1. Qué es

**Analogía:** un puerto con grúas automáticas. La torre de control (plano de control) la opera la autoridad portuaria; tú traes los contenedores (pods) y eliges cuántos muelles (nodos) alquilar.

```
        Plano de control (administrado por Oracle: API, etcd, scheduler)
                          │ endpoint de la API (privado recomendado)
   ┌──────────────┬───────┴────────┬───────────────┐
 Node pool A     Node pool B      Virtual nodes (sin servidores que gestionar)
 (VM Standard)   (VM Arm / GPU)
        │ pods ── subred de pods (CNI nativo de la VCN) ── balanceador de OCI
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Clúster** | *Basic* o *Enhanced* (este último habilita workload identity, nodos virtuales, complementos gestionados) *(verifica diferencias y costo)* |
| **Endpoint de la API** | Público o privado; con subred y NSG propios |
| **Node pool administrado** | Grupo de VM (formas flexibles) con imagen OKE; tú los actualizas |
| **Nodos virtuales** | Pods sin gestionar servidores; pagas por pod |
| **CNI** | `OCI_VCN_IP_NATIVE`: cada pod recibe IP de la VCN; `FLANNEL_OVERLAY`: red superpuesta |
| **Subredes** | API, nodos, pods, balanceadores (separadas) |
| **Complementos** (*add-ons*) | CoreDNS, kube-proxy, escalador, etc. |
| **OCIR** | Registro de contenedores de OCI |

### Cómo llega el tráfico
`Internet → Load Balancer / NLB (servicio tipo LoadBalancer o Ingress) → pods`. Las anotaciones del servicio controlan forma, ancho de banda y subred del balanceador.

### Actualizaciones
1. **Primero el plano de control**, luego los node pools (nunca un nodo más nuevo que el plano).
2. Node pools: crear uno nuevo con la versión nueva, *cordon* + *drain* del viejo, o actualización rodante.
3. Oracle retira versiones antiguas: sigue el calendario *(verifica)*.

### Identidad
- Los pods usan [workload identity](../../02-iam/workload-identity-oke/README.md) (clúster *enhanced*), no la identidad del nodo.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Muchos microservicios con ciclos de despliegue distintos | OKE |
| Una o dos tareas por lotes | [Container Instances](../container-instances/README.md) |
| Picos esporádicos pequeños | [Functions](../functions/README.md) |
| Una app monolítica sin contenedores | [VM](../compute-instancias/README.md) |
| Equipo sin experiencia en Kubernetes y 2 servicios | **No** empieces por aquí |
| API del clúster abierta a Internet | **No** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Pod** | La unidad mínima: uno o más contenedores |
| **Deployment** | Declara cuántas réplicas y qué imagen |
| **Node pool** | Grupo de nodos del mismo tipo |
| **Nodo virtual** | Capacidad por pod, sin VM visibles |
| **CNI nativo** | Los pods tienen IP real de la VCN |
| **Ingress** | Reglas de entrada HTTP hacia servicios |
| **HPA / Cluster Autoscaler** | Escalar pods / nodos automáticamente |

## 5. Cómo se usa
1. Red: subredes separadas ([Red](../../01-red/README.md)).
2. Clúster y node pool: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Acceso: `oci ce cluster create-kubeconfig …` ([`ejemplos/cli/oke.sh`](ejemplos/cli/oke.sh)).
4. Despliega con [`ejemplos/k8s/deployment.yaml`](ejemplos/k8s/deployment.yaml).
5. Audita versiones desde [Java](uso-en-java.md).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administradores de plataforma | `manage cluster-family` + RBAC de Kubernetes `cluster-admin` (pocos) | — |
| Equipos | RBAC por namespace | Sus propios pods |
| Pods | — | Workload identity con política mínima |

- **API privada**, acceso por Bastion/VPN.
- **RBAC por namespace**; `NetworkPolicy` entre servicios.
- Imágenes de OCIR con escaneo; nada de `latest`.
- Secretos de [Vault](../../03-secretos/README.md), no de manifiestos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Clúster *enhanced* con API privada | API pública sin restricciones |
| Subredes separadas (API/nodos/pods/LB) | Todo en una subred |
| `requests` y `limits` en cada pod | Pods sin límites |
| Probes de salud y `PodDisruptionBudget` | Despliegues sin probes |
| Actualizar plano y pools con calendario | Quedarse en versiones retiradas |
| Workload identity | Llaves en Secrets de Kubernetes |

## 8. Límites, costos y versiones
- **Costo:** el clúster *basic* no cobra plano de control; el *enhanced* tiene tarifa por clúster-hora *(verifica)*; nodos como VM; nodos virtuales por pod.
- **Límites** (verifica): nodos por pool, pods por nodo, clústeres por región.
- **Terraform:** `oci_containerengine_cluster`, `oci_containerengine_node_pool`, `oci_containerengine_addon`.
- **SDK:** `ContainerEngineClient` (`oci-java-sdk-containerengine`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
