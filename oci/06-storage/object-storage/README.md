# Oracle OCI · Storage · Object Storage

Almacenamiento de objetos regional, prácticamente ilimitado y muy durable: guardas archivos (fotos, comprobantes, respaldos, *data lake*) como objetos dentro de *buckets*, y los lees por API HTTP. No es un disco: no se monta ni se edita una parte de un objeto.

## 1. Qué es

**Analogía:** una bodega de cajas con etiqueta. Cada caja (objeto) tiene un nombre único en su estante (bucket), una etiqueta con datos (metadatos) y un tipo de bodega según qué tan seguido la sacas (niveles de almacenamiento). No abres la caja para cambiar una página: reemplazas la caja.

```
 Namespace del tenancy (único)
  └─ Bucket "comprobantes" (compartimento tienda-prod, región sa-saopaulo-1, privado, cifrado con tu llave)
       ├─ pedidos/2026/10/17/P-100.pdf   (Standard, metadatos opc-meta-*)
       ├─ pedidos/2025/…                 (regla de ciclo de vida → Archive)
       └─ versiones anteriores           (versionado activo)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Namespace** | Nombre único del tenancy en Object Storage; forma parte de cada URL |
| **Bucket** | Contenedor de objetos con nivel por defecto, visibilidad, cifrado, versionado, eventos |
| **Objeto** | Datos + nombre (puede contener `/` como «carpeta» lógica) + metadatos + ETag |
| **Niveles** | `Standard`, `InfrequentAccess`, `Archive` (restaurar tarda horas) *(verifica)* |
| **Auto-tiering** | Mueve objetos poco usados a acceso infrecuente automáticamente |
| **Ciclo de vida** | Reglas por prefijo y edad: mover de nivel o borrar |
| **Versionado** | Conserva versiones anteriores al sobrescribir o borrar |
| **Retención** | Reglas que impiden borrar o modificar (cumplimiento, WORM) |
| **Replicación** | Copia asíncrona a un bucket de otra región |
| **Multipart** | Subida en partes para objetos grandes (recomendada desde ~100 MB) |

### Consistencia y concurrencia
- Lectura después de escritura **fuertemente consistente**.
- Escrituras condicionales con `If-Match` (ETag) e `If-None-Match: *` (crear solo si no existe).
- No hay bloqueos: la última escritura gana salvo que uses condiciones.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Fotos de productos, comprobantes PDF, exportes | **Object Storage** |
| Respaldo y archivo de años | Object Storage + `Archive` + retención |
| Compartir un archivo por tiempo limitado | [PAR](../par/README.md) |
| Varias VM/pods leyendo y escribiendo archivos como disco | [File Storage](../file-storage/README.md) |
| Reaccionar a cada archivo subido | [Eventos de Object Storage](../eventos-object-storage/README.md) |
| Mensajes grandes en una cola | [Claim check](../claim-check/README.md) |
| Base de datos o archivo que se edita a trozos | **No** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **ETag** | Huella de la versión actual del objeto |
| **Prefijo** | La parte inicial del nombre; organiza y filtra |
| **Metadatos `opc-meta-*`** | Pares clave/valor propios del objeto |
| **Bucket privado** | Sin acceso anónimo; todo pasa por IAM o PAR |
| **Llave propia (CMK)** | Cifrado con una llave de tu Vault |

## 5. Cómo se usa
1. Bucket privado, versionado, con CMK, eventos y ciclo de vida: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Sube con nombre determinista y sin sobrescribir: [uso en Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/object-storage.sh`](ejemplos/cli/object-storage.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage buckets` | — |
| App de pedidos | `read buckets` (si lista) | `manage objects` acotado con `target.bucket.name` |
| Lectores de reportes | — | `read objects` en su bucket |
| Object Storage (servicio) | — | `use keys` sobre la CMK |

- Buckets **privados** siempre; para compartir usa PAR.
- Acceso por **puerta de servicios** desde subredes privadas (sin Internet).
- Política por bucket (`where target.bucket.name = '…'`) y, si hace falta, por prefijo con `target.object.name`.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Nombres deterministas por fecha/ID | Nombres aleatorios imposibles de encontrar |
| `If-None-Match: *` para no pisar | Sobrescribir sin querer |
| Ciclo de vida desde el día uno | Pagar `Standard` por respaldos de hace 3 años |
| Multipart para archivos grandes | Un `PUT` de 5 GB que falla al 99 % |
| Validar tipo y tamaño antes de subir | Aceptar cualquier archivo del usuario |
| Bucket privado + PAR | Bucket público «temporal» |

## 8. Límites, costos y versiones
- **Costo:** GB-mes por nivel + peticiones; salida a Internet por GB (con cuota gratuita mensual); recuperar de `Archive` tiene costo *(verifica)*.
- **Límites** (verifica): tamaño máximo de objeto (10 TiB con multipart), tamaño de una sola subida, metadatos.
- **Terraform:** `oci_objectstorage_bucket`, `oci_objectstorage_object_lifecycle_policy`, `oci_objectstorage_replication_policy`, `data.oci_objectstorage_namespace`.
- **SDK:** `ObjectStorageClient`, `UploadManager` (`oci-java-sdk-objectstorage`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
