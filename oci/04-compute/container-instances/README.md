# Oracle OCI · Compute · Container Instances (contenedores sin clúster)

Le das a OCI una o varias imágenes, la forma (OCPU y memoria) y una subred, y OCI arranca los contenedores en una máquina que tú no administras. Sin Kubernetes, sin nodos, sin parches del sistema operativo.

## 1. Qué es

**Analogía:** alquilar un *food truck* listo para cocinar. Tú llevas la receta (la imagen) y los ingredientes (variables, volúmenes); el camión, el motor y el permiso de circulación son del dueño. Cuando terminas, lo devuelves.

```
 Terraform / SDK ──► Container Instance (forma: 2 OCPU, 8 GB) ── VNIC en TU subred privada
                        ├─ contenedor "reporte"  (imagen OCIR:1.4.2)
                        └─ contenedor "sidecar"  (opcional; comparten red y volúmenes)
                     identidad: resource principal ──► Object Storage, Vault, Queue…
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Container instance** | La unidad que se crea y se cobra; aloja 1 a N contenedores *(verifica el máximo)* |
| **Forma** | Flexible (`CI.Standard.E4.Flex`, `CI.Standard.A1.Flex`…): eliges OCPU y memoria |
| **Contenedor** | Imagen + comando + variables + límites de CPU/memoria propios + chequeos de salud |
| **VNIC** | Interfaz en tu subred; IP privada, NSG, IP pública opcional |
| **Volúmenes** | `EMPTYDIR` (temporal, compartido entre contenedores) o `CONFIGFILE` (archivos de configuración) |
| **Política de reinicio** | `ALWAYS`, `NEVER`, `ON_FAILURE` |
| **Image pull secrets** | Credenciales para registros privados; con OCIR puede usarse la identidad del recurso |
| **Resource principal** | Cada contenedor puede obtener credenciales de OCI sin llaves |

### Ciclo de vida
1. `CreateContainerInstance` → `CREATING` (se reserva capacidad y se descargan imágenes).
2. `ACTIVE` mientras al menos un contenedor corre o se reinicia según la política.
3. Con `NEVER`, cuando todos terminan la instancia queda `INACTIVE`: los registros y el código de salida siguen consultables.
4. `DeleteContainerInstance` libera todo. **No hay actualización en caliente** de imagen: se crea otra instancia *(verifica qué campos admiten `Update`)*.

### Lo que no tiene (a propósito)
- Sin autoescalado ni balanceo propios: si necesitas réplicas, pon varias instancias detrás de un [Load Balancer](../../05-ingress-api/README.md) o usa [OKE](../oke/README.md).
- Sin almacenamiento persistente de bloque: lo que quede en `EMPTYDIR` se pierde al borrar.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Lote nocturno de 40 minutos (reporte, migración, ETL) | **Container Instance** con `NEVER` |
| Trabajo de < 5 minutos disparado por evento | [Functions](../functions/README.md) |
| API con réplicas, despliegues graduales y malla | [OKE](../oke/README.md) |
| Herramienta interna pequeña siempre encendida | Container Instance detrás de un balanceador |
| Necesitas GPU, kernel propio o agentes del sistema | [VM](../compute-instancias/README.md) |
| Decenas de microservicios que se hablan entre sí | **No**: OKE |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Etiqueta inmutable** | `pedidos:1.4.2` o el *digest* `@sha256:…`; nunca `latest` |
| **Política de reinicio** | Qué hace OCI cuando el proceso termina |
| **Apagado ordenado** | Segundos de gracia entre `SIGTERM` y `SIGKILL` |
| **`opcRetryToken`** | Clave de idempotencia: reintentar la creación no crea dos instancias |
| **Chequeo de salud** | HTTP, TCP o comando; si falla, actúa la política de reinicio |

## 5. Cómo se usa
1. Sube la imagen a OCIR con etiqueta fija.
2. Crea la instancia: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. O lánzala desde un orquestador en Java con validación previa: [uso en Java](uso-en-java.md).
4. Consulta estado y registros: [`ejemplos/cli/container-instances.sh`](ejemplos/cli/container-instances.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma / CI | `manage compute-container-family` en el compartimento | — |
| Orquestador Java | `manage compute-container-instances` + `use subnets`, `use vnics`, `use network-security-groups` | — |
| El contenedor | — | Resource principal (`resource.type = 'computecontainerinstance'`) con política mínima |
| Descarga de imagen | — | `read repos` en el compartimento de OCIR |

- Subred **privada**; salida por NAT o puerta de servicios; NSG con solo los puertos necesarios.
- Secretos desde [Vault](../../03-secretos/README.md) al arrancar, **nunca** en variables de entorno (se ven en la consola y en la API).
- Desactiva el resource principal (`isResourcePrincipalDisabled`) en contenedores que no hablan con OCI, como un sidecar.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Etiqueta inmutable o digest | `latest` (cada arranque puede traer otra cosa) |
| `opcRetryToken` al crear desde código | Reintentar `Create` sin token |
| Límites por contenedor dentro de la forma | Dejar que un contenedor se coma toda la memoria |
| Apagado ordenado y manejo de `SIGTERM` | Matar trabajos a mitad de escritura |
| Borrar las instancias `INACTIVE` (o automatizarlo) | Acumular instancias terminadas |
| Etiquetas (`proyecto`, `entorno`) para costos | Instancias huérfanas sin dueño |

## 8. Límites, costos y versiones
- **Costo:** por OCPU-hora y GB-hora de la forma mientras la instancia existe y está activa; sin cargo extra por el servicio *(verifica)*.
- **Límites** (verifica): contenedores por instancia, OCPU y memoria máximas por forma, instancias por región (cuotas de servicio).
- **Terraform:** `oci_container_instances_container_instance`.
- **SDK:** `ContainerInstanceClient` (`oci-java-sdk-containerinstances`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
