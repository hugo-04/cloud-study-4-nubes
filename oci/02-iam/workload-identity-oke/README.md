# Oracle OCI · IAM · Workload Identity en OKE (identidad de pods)

Un pod dentro de OKE necesita hablar con servicios de OCI (Object Storage, Vault, Queue…). **Workload identity** le da una identidad propia, ligada a su **ServiceAccount** de Kubernetes, sin llaves guardadas en el pod.

## 1. Qué es

**Analogía:** el gafete de visitante con nombre y piso. No se le entrega la llave maestra del edificio al camión de reparto: se le da un gafete que dice «entrega de Café Andino, piso 3, hoy». La política dice qué puertas abre ese gafete.

```
Pod (ServiceAccount app-tienda, namespace tienda, clúster X)
   │  pide un token a OCI con su identidad de Kubernetes
   ▼
 OCI IAM ──► Allow any-user to read objects … where request.principal.type = 'workload'
                                              and request.principal.namespace = 'tienda'
                                              and request.principal.service_account = 'app-tienda'
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Clúster OKE mejorado** | Workload identity requiere clúster *enhanced* *(verifica el requisito vigente)* |
| **Namespace + ServiceAccount** | La identidad de Kubernetes del pod |
| **Principal de tipo workload** | Lo que IAM ve: tipo, clúster, namespace, ServiceAccount |
| **Política** | Frase con `where all {request.principal.type = 'workload', …}` |
| **Proveedor del SDK** | `OkeWorkloadIdentityAuthenticationDetailsProvider` |

### Atributos de la petición
| Atributo | Contenido |
|---|---|
| `request.principal.type` | `workload` |
| `request.principal.cluster_id` | OCID del clúster |
| `request.principal.namespace` | Namespace de Kubernetes |
| `request.principal.service_account` | Nombre del ServiceAccount |

### Flujo
1. El pod corre con un ServiceAccount.
2. El SDK obtiene el token del ServiceAccount de Kubernetes y lo intercambia con OCI por credenciales **temporales**.
3. IAM evalúa la política contra los atributos del principal.
4. Las credenciales se renuevan solas.

### Frente a un grupo dinámico de nodos
- Con instance principals, **todos los pods del nodo** comparten la identidad de la VM: demasiado amplio.
- Con workload identity, **cada aplicación** tiene su propia identidad y sus propios permisos.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Pod que lee un bucket o un secreto | Workload identity con política mínima |
| Varias apps en el mismo clúster con permisos distintos | Un ServiceAccount por app |
| Clúster básico (no mejorado) | Planea el cambio a *enhanced* o usa otra opción *(verifica)* |
| Dar los permisos de la VM del nodo a todos los pods | **No** |
| Llaves API en secretos de Kubernetes | **No** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **ServiceAccount** | La identidad de Kubernetes de un pod |
| **Workload identity** | Esa identidad reconocida por OCI IAM |
| **Principal workload** | Lo que ve IAM: clúster + namespace + cuenta |
| **Credenciales temporales** | Se renuevan solas, no se guardan |
| **Clúster enhanced** | Tipo de clúster que habilita la función |

## 5. Cómo se usa
1. Crea el namespace y el ServiceAccount: [`ejemplos/k8s/serviceaccount.yaml`](ejemplos/k8s/serviceaccount.yaml).
2. Escribe la política con los cuatro atributos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. En Java usa el proveedor `oke` ([uso en Java](uso-en-java.md)).
4. Prueba con un pod efímero: [`ejemplos/cli/probar.sh`](ejemplos/cli/probar.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administrador del clúster | Crea namespaces y ServiceAccounts | — |
| Administrador de IAM | Escribe la política | — |
| El pod | — | Solo lo que la política del ServiceAccount permite |

- **Quien puede crear pods en un namespace puede usar sus ServiceAccounts:** controla permisos de Kubernetes (RBAC).
- Incluye **siempre** `cluster_id`, `namespace` y `service_account` en la condición.
- Un ServiceAccount **por aplicación**.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Política con tipo + clúster + namespace + cuenta | Solo `type = 'workload'` |
| Un ServiceAccount por app | El `default` para todo |
| RBAC estricto sobre quién crea pods | Cualquiera despliega en el namespace |
| Mínimo permiso (`read objects` de un bucket) | `manage object-family` |
| Probar con un pod efímero | Probar en producción |

## 8. Límites, costos y versiones
- **Costo:** la función no se cobra aparte; el clúster *enhanced* tiene su tarifa *(verifica)*.
- **Requisitos:** clúster mejorado, versión mínima de Kubernetes y del SDK *(verifica)*.
- **Terraform:** `oci_identity_policy` (y `oci_containerengine_cluster` con `type = "ENHANCED_CLUSTER"`).
- **Artefacto Java:** `oci-java-sdk-addons-oke-workload-identity`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
