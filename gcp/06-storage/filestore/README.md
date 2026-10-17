# Google Cloud · Storage · Filestore (NFS administrado)

Sistema de archivos **NFS** administrado que montan a la vez muchas VMs o pods de GKE (`ReadWriteMany`). Para software que espera una **carpeta compartida** y no una API de objetos.

## 1. Qué es

**Analogía:** la carpeta compartida de la oficina en el servidor. Todos la ven como una unidad más; el área de sistemas cuida que no se llene ni se pierda.

```
 Instancia Filestore "media" (nivel ZONAL/REGIONAL/ENTERPRISE, 1 TiB, red modalima-vpc vía PSA)
   └─ recurso compartido /catalogo (opciones de exportación por rango IP: RW/RO, squash)
 VMs:  mount 10.50.0.2:/catalogo /mnt/media
 GKE:  StorageClass del driver CSI de Filestore → PVC ReadWriteMany
 Snapshots y respaldos programados
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Instancia** | Nivel (Basic HDD/SSD, Zonal, Regional, Enterprise *(verifica)*), capacidad, red |
| **Recurso compartido (file share)** | Nombre y capacidad; uno o varios según el nivel |
| **Opciones de exportación NFS** | Por rango IP: `READ_WRITE`/`READ_ONLY`, `ROOT_SQUASH`/`NO_ROOT_SQUASH`, UID/GID anónimos |
| **Conexión de red** | Peering administrado (PSA) o PSC según el nivel *(verifica)* |
| **Snapshots / respaldos** | Puntuales y programados; respaldos fuera de la instancia |
| **Driver CSI** | Aprovisiona volúmenes en GKE |

### Rendimiento
Depende del nivel y la capacidad: más TiB, más rendimiento. Muchos archivos pequeños son lo más lento.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| CMS heredado que escribe en disco compartido | **Filestore** |
| Varios pods con `ReadWriteMany` | **Filestore** (CSI) |
| Servir archivos a usuarios o archivar | [Cloud Storage](../cloud-storage/README.md) |
| Base de datos | **No** |
| Intercambio con terceros | **No**: Cloud Storage + URLs firmadas |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **NFS** | Montar carpetas por red |
| **Root squash** | El root del cliente se vuelve anónimo |
| **Opciones de exportación** | Quién monta y cómo |
| **`ReadWriteMany`** | Volumen montable por muchos pods |
| **Nivel** | Durabilidad, rendimiento y precio |

## 5. Cómo se usa
1. Instancia con opciones de exportación estrictas: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Volumen en GKE: [`ejemplos/k8s/pvc.yaml`](ejemplos/k8s/pvc.yaml).
3. Audita las opciones de exportación de todas las instancias con Cloud Asset Inventory desde [Java](uso-en-java.md).
4. CLI: [`ejemplos/cli/filestore.sh`](ejemplos/cli/filestore.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/file.editor` | — |
| Auditoría | `roles/file.viewer` / `roles/cloudasset.viewer` | — |
| Clientes NFS | — | Opciones de exportación + permisos UNIX |

- El acceso a los datos es **por red y UID/GID**, no por IAM.
- Rangos de IP exactos, `ROOT_SQUASH` por defecto, `READ_ONLY` para lectores.
- Firewall: solo las subredes que deben montar.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Opciones de exportación por rango | Montar desde toda la red sin reglas |
| Root squash | Root remoto con poderes |
| Snapshots y respaldos programados | Confiar en que nadie borra |
| Nivel acorde a la disponibilidad | Basic para algo crítico |
| Cloud Storage para servir archivos | NFS para descargas públicas |

## 8. Límites, costos y versiones
- **Costo:** por GiB aprovisionado y nivel (no por lo usado), snapshots y respaldos *(verifica)*.
- **Límites** (verifica): capacidad mínima por nivel, recursos compartidos por instancia, rendimiento por TiB.
- **Terraform:** `google_filestore_instance`, `google_filestore_snapshot`, `google_filestore_backup`.
- **Java:** no hay biblioteca de Filestore en el BOM usado aquí; se audita con Cloud Asset Inventory (`google-cloud-asset`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
