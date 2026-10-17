# Google Cloud · Storage · Cloud Storage

Almacenamiento de objetos global, durable y prácticamente ilimitado: guardas archivos como **objetos** en **buckets**, los lees por API (JSON/XML) y eliges ubicación (región, doble región, multirregión) y **clase** (Standard, Nearline, Coldline, Archive) según cuánto los usas.

## 1. Qué es

**Analogía:** una bodega de cajas con etiqueta. Cada caja (objeto) tiene un nombre único en su estante (bucket), una etiqueta con datos (metadatos) y un número de versión (generación). No abres la caja para cambiar una página: reemplazas la caja.

```
 Bucket "modalima-tienda-prod-comprobantes" (southamerica-west1, Standard, acceso uniforme, CMEK, versionado)
   ├─ pedidos/2026/10/17/P-100.pdf   generación 1734…  metadatos: pedido=P-100
   ├─ ciclo de vida: Coldline a los 90 días, borrar a los 7 años
   └─ retención (opcional, bloqueable) · prevención de acceso público
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Bucket** | Nombre global único; ubicación y clase por defecto; no se renombra |
| **Objeto** | Datos + nombre (con `/` como carpeta lógica) + metadatos + **generación** |
| **Clases** | Standard, Nearline (30 días mín.), Coldline (90), Archive (365) *(verifica)* |
| **Autoclass** | Mueve objetos de clase según su uso |
| **Acceso uniforme a nivel de bucket** | Solo IAM (sin ACL por objeto) |
| **Prevención de acceso público** | Impide `allUsers` aunque alguien lo intente |
| **Versionado / soft delete** | Recuperar objetos borrados o sobrescritos |
| **Retención y bloqueo** | WORM para cumplimiento |
| **Ciclo de vida** | Reglas por edad, prefijo, clase o versiones |
| **Precondiciones** | `ifGenerationMatch` (0 = solo si no existe), `ifMetagenerationMatch` |
| **Subida reanudable / compuesta** | Para archivos grandes |

### Consistencia
Fuerte: después de escribir, cualquier lectura ve el objeto (y los listados también).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Comprobantes, fotos, exportes, respaldos | **Cloud Storage** |
| Compartir un archivo temporalmente | [URLs firmadas](../urls-firmadas/README.md) |
| Reaccionar a archivos nuevos | [Eventos de Cloud Storage](../eventos-cloud-storage/README.md) |
| Mensajes grandes por una cola | [Claim check](../claim-check/README.md) |
| Carpeta compartida montable (NFS) | [Filestore](../filestore/README.md) |
| Editar partes de un archivo o base de datos | **No** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Generación** | Versión del objeto; cambia en cada escritura |
| **`ifGenerationMatch=0`** | «Solo si no existe» |
| **Acceso uniforme** | Permisos solo por IAM |
| **Clase** | Precio de guardar vs precio de leer |
| **Soft delete** | Papelera con retención |

## 5. Cómo se usa
1. Bucket con acceso uniforme, prevención pública, versionado, CMEK y ciclo de vida: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Guardado idempotente con `doesNotExist()` desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/gcs.sh`](ejemplos/cli/gcs.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/storage.admin` | — |
| App que escribe | — | `roles/storage.objectCreator` (o `objectUser`) en el bucket |
| App que lee | — | `roles/storage.objectViewer` en el bucket |
| Agente de Cloud Storage | — | Llave CMEK |

- Acceso uniforme + prevención de acceso público (también por política de organización).
- Permisos por bucket; condiciones IAM por prefijo si hace falta.
- Acceso privado desde VPC con Private Google Access o PSC.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Nombres deterministas | Nombres aleatorios imposibles de rastrear |
| `doesNotExist()` para no pisar | Sobrescribir sin querer |
| Ciclo de vida desde el día uno | Pagar Standard por años de respaldos |
| Subida reanudable para archivos grandes | Un `PUT` de varios GB |
| URLs firmadas para compartir | `allUsers` |

## 8. Límites, costos y versiones
- **Costo:** GB-mes por clase y ubicación, operaciones (A/B), salida a Internet, recuperación en clases frías *(verifica)*.
- **Límites** (verifica): tamaño de objeto (5 TiB), tasa de escritura por objeto (1/s), nombres de bucket.
- **Terraform:** `google_storage_bucket`, `google_storage_bucket_iam_member`.
- **Java:** `Storage` (`google-cloud-storage`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
