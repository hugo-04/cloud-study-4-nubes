# Google Cloud · Compute · Compute Engine (máquinas virtuales)

VMs en la infraestructura de Google: eliges tipo de máquina (o una personalizada), disco, imagen, red y cuenta de servicio. Para producción se usan **plantillas de instancia** y **grupos de instancias administrados (MIG)** que reparan, escalan y actualizan solos.

## 1. Qué es

**Analogía:** alquilar departamentos en un edificio. Puedes alquilar uno suelto (VM), pero si vas a tener muchos iguales, usas un plano tipo (plantilla) y un administrador (MIG) que reemplaza el que se daña y agrega más cuando llegan inquilinos.

```
 Plantilla "pedidos-v14" (e2-standard-4, imagen endurecida, sin IP externa, SA pedidos@, Shielded VM)
   └─ MIG regional (southamerica-west1-a/b/c): 3–10 VMs
        ├─ autoescalado por CPU o métricas · autocuración con chequeo de salud
        └─ actualización progresiva (maxSurge 1, maxUnavailable 0)
 Discos: Persistent Disk / Hyperdisk (zonal o regional) · snapshots programados
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Tipo de máquina** | Familias E2, N2/N4, C3/C4, T2D/T2A (Arm), A3 (GPU)…; o personalizada |
| **VM Spot** | Mucho más barata, Google la puede detener con aviso corto |
| **Disco de arranque y datos** | Persistent Disk o Hyperdisk; zonal o regional |
| **Imagen** | Pública, personalizada o familia de imágenes |
| **Cuenta de servicio adjunta** | La identidad de la VM (con alcance `cloud-platform` + IAM) |
| **Metadatos** | Scripts de inicio, claves (mejor OS Login), configuración |
| **Shielded VM** | Arranque seguro, vTPM y monitoreo de integridad |
| **Confidential VM** | Memoria cifrada en uso *(verifica tipos compatibles)* |
| **Plantilla de instancia** | Configuración inmutable para crear VMs iguales |
| **MIG** | Grupo zonal o regional con autoescalado, autocuración y actualizaciones |
| **OS Login** | Acceso SSH con identidades de IAM en lugar de llaves sueltas |

### Ciclo de vida
`PROVISIONING → STAGING → RUNNING → STOPPING → TERMINATED` (y `SUSPENDED`). Detenida no cobra CPU/RAM, pero sí discos e IPs reservadas.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Software que exige el SO, agentes o licencias | **Compute Engine** |
| Cargas con GPU | Compute Engine (o GKE con GPU) |
| Lotes tolerantes a interrupción | VMs Spot en MIG |
| API HTTP de contenedor sin estado | [Cloud Run](../cloud-run/README.md) |
| Muchos microservicios con plataforma | [GKE](../gke/README.md) |
| Reacciones cortas a eventos | [Cloud Run functions](../cloud-functions/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **MIG** | Grupo de VMs iguales que se cuida solo |
| **Autocuración** | Reemplazar la VM que falla el chequeo |
| **Spot** | Barata pero interrumpible |
| **OS Login** | SSH con IAM |
| **Imagen endurecida** | Imagen base con parches y configuración segura |

## 5. Cómo se usa
1. Plantilla sin IP externa, Shielded VM, OS Login, cuenta propia y MIG regional con autocuración: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Audita VMs (IP externa, cuenta por defecto, Shielded, etiquetas) desde [Java](uso-en-java.md).
3. CLI y SSH por IAP: [`ejemplos/cli/vm.sh`](ejemplos/cli/vm.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/compute.instanceAdmin.v1` | — |
| Operadores | `roles/compute.osAdminLogin` / `osLogin` + IAP | SSH por IAP |
| La VM | Cuenta de servicio propia con roles mínimos | — |

- Políticas de organización: sin IP externa, OS Login obligatorio, Shielded VM obligatorio.
- Nunca la cuenta por defecto de Compute.
- Parcheo con VM Manager / imágenes nuevas, no a mano.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| MIG regional con plantilla | VMs sueltas «mascota» |
| Sin IP externa + IAP | SSH abierto a Internet |
| Cuenta de servicio propia | Cuenta por defecto con `editor` |
| Snapshots programados | Respaldos manuales |
| Etiquetas (`labels`) de costo | VMs sin dueño |

## 8. Límites, costos y versiones
- **Costo:** por segundo de vCPU/RAM según familia; descuentos por uso continuo y compromisos; Spot con gran descuento; discos e IPs aparte *(verifica)*.
- **Límites** (verifica): cuotas de CPU por región y familia, discos por VM.
- **Terraform:** `google_compute_instance_template`, `google_compute_region_instance_group_manager`, `google_compute_health_check`, `google_compute_region_autoscaler`.
- **Java:** `InstancesClient`, `InstanceGroupManagersClient` (`google-cloud-compute`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
