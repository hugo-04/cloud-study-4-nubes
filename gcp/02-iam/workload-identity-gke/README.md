# Google Cloud · IAM · Workload Identity Federation for GKE

Cómo un **pod** obtiene permisos de Google Cloud **sin llaves**: la cuenta de servicio de Kubernetes (KSA) del pod se vuelve un **principal de IAM**. Puedes otorgarle roles **directamente** (`principal://…/subject/ns/<ns>/sa/<ksa>`) o dejar que **suplante** a una cuenta de servicio de IAM (modo clásico con la anotación `iam.gke.io/gcp-service-account`).

## 1. Qué es

**Analogía:** el pase de un trabajador emitido por su empresa contratista (Kubernetes) que el edificio (Google Cloud) reconoce en la entrada porque confía en esa empresa: no hace falta darle una llave del edificio.

```
 Pod (namespace "tienda", KSA "pedidos")
   └─ biblioteca cliente → ADC → servidor de metadatos de GKE (GKE metadata server)
        └─ intercambia el token de la KSA por un token federado del pool  <PROYECTO>.svc.id.goog
             ├─ Opción A (directa):  IAM otorga roles a principal://…/subject/ns/tienda/sa/pedidos
             └─ Opción B (suplantar): KSA → roles/iam.workloadIdentityUser → pedidos@<proyecto>.iam.gserviceaccount.com
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Workload pool** | `<PROYECTO>.svc.id.goog`, se activa en el clúster |
| **GKE metadata server** | Corre en cada nodo (node pools con `GKE_METADATA`) y entrega tokens a los pods |
| **KSA** | La cuenta de servicio de Kubernetes del pod |
| **Principal directo** | `principal://iam.googleapis.com/projects/<NÚMERO>/locations/global/workloadIdentityPools/<PROYECTO>.svc.id.goog/subject/ns/<ns>/sa/<ksa>` |
| **principalSet** | Grupos de identidades (todo un namespace, por ejemplo) |
| **Modo suplantación** | Anotación en la KSA + `roles/iam.workloadIdentityUser` en la cuenta de IAM |

### Directo vs suplantación
| | Directo | Suplantación |
|---|---|---|
| Cuentas de servicio de IAM | No hace falta | Una por app |
| Compatibilidad | La mayoría de servicios *(verifica excepciones)* | Todos |
| Auditoría | Se ve el principal federado | Se ve la cuenta de IAM |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Pods que llaman APIs de Google | **Workload Identity** siempre |
| API que no acepta principales federados | Modo suplantación |
| Pod que necesita la cuenta del nodo | **No**: es demasiado amplia |
| Llaves JSON montadas como secreto | **Nunca** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **KSA** | Identidad del pod dentro de Kubernetes |
| **Pool de identidad del clúster** | El «emisor» en el que IAM confía |
| **Principal federado** | Identidad externa a IAM a la que se le dan roles |
| **Cuenta del nodo** | La identidad de la VM; los pods no deben usarla |

## 5. Cómo se usa
1. Clúster con Workload Identity, node pool con `GKE_METADATA` y roles directos a la KSA: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. KSA y deployment: [`ejemplos/k8s/ksa.yaml`](ejemplos/k8s/ksa.yaml).
3. Verifica desde el pod qué identidad tiene y si tiene el rol esperado: [uso en Java](uso-en-java.md) y [`ejemplos/cli/wi.sh`](ejemplos/cli/wi.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/container.admin` (clúster) | — |
| Admin de IAM | Otorga roles al principal de la KSA | — |
| Equipo de la app | RBAC en su namespace (crear KSA) | Lo que IAM dé a su KSA |

- Quien puede crear KSA en un namespace puede usar los roles de ese namespace: protege con RBAC.
- Mismo nombre de namespace/KSA en otro clúster del mismo proyecto comparte identidad («igualdad de identidad»): ojo con clústeres de prueba en el proyecto de prod.
- Cuenta del nodo con roles mínimos (logging, monitoring, lectura de imágenes).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Una KSA por app | KSA `default` con permisos |
| Roles en el recurso más pequeño | Roles de proyecto a todo |
| Clústeres de prueba en otro proyecto | Mezclar pruebas y prod en el mismo pool |
| Node pools con `GKE_METADATA` | Pods leyendo el metadata server de la VM |

## 8. Límites, costos y versiones
- **Costo:** sin cargo.
- **Versiones** (verifica): la versión de GKE que admite principales directos; Autopilot lo trae activo.
- **Terraform:** `google_container_cluster` (`workload_identity_config`), `google_container_node_pool` (`workload_metadata_config`), `google_project_iam_member` con `principal://…`.
- **Java:** nada especial: ADC lo resuelve; para verificar, el servidor de metadatos y `ProjectsClient.getIamPolicy`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
