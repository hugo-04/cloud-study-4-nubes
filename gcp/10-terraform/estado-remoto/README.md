# Google Cloud · Terraform · Estado remoto (backend `gcs`)

El **estado** es el mapa entre tu código y los recursos reales. En equipo vive en un **bucket de Cloud Storage** con el backend `gcs`: versionado (para volver atrás), con **bloqueo** nativo (un archivo `.tflock` evita dos `apply` a la vez), cifrado con **CMEK** y acceso solo para los pipelines. El estado contiene **secretos en texto claro**: trátalo como tal. Lo genérico de Terraform/OpenTofu está en el módulo transversal [Terraform](../../../transversal/terraform/README.md).

## 1. Qué es

**Analogía:** el plano oficial de la obra guardado en la caja fuerte de la constructora: una sola persona lo puede tener abierto a la vez (candado), se guardan las versiones anteriores y solo los capataces (pipelines) tienen la llave.

```
 Proyecto modalima-tfstate (solo plataforma)
   └── bucket modalima-tfstate-prod  (versionado · acceso uniforme · sin acceso público · CMEK)
         ├── red/default.tfstate          ← pipeline "red"
         ├── red/default.tflock           ← candado mientras corre un apply
         ├── tienda/default.tfstate
         └── datos/default.tfstate
 Pipelines (Workload Identity Federation) → SA tf-prod → roles/storage.objectUser en el bucket
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Backend `gcs`** | `bucket` + `prefix`; cada workspace es `<prefix>/<workspace>.tfstate` |
| **Bloqueo** | Archivo `.tflock` creado con precondición de generación (atómico) |
| **Versionado** | Recupera estados anteriores; limita versiones con ciclo de vida |
| **Cifrado** | Por defecto de Google, CMEK (`kms_encryption_key` o clave por defecto del bucket) o CSEK |
| **Credenciales** | ADC: la del pipeline vía federación o suplantación (`impersonate_service_account`) |
| **Separación** | Un estado por componente y entorno; bucket por entorno |
| **`terraform_remote_state`** | Leer salidas de otro estado (prefiere fuentes de datos) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Equipo con varios pipelines | Backend `gcs` con bloqueo |
| Recuperar un estado roto | Versión anterior del objeto |
| Proyecto personal de prueba | Estado local vale (sin secretos reales) |
| Compartir salidas entre componentes | Fuentes de datos por nombre o `remote_state` acotado |
| Guardar secretos en el estado | Evítalo: Secret Manager y referencias |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Estado** | Lo que Terraform cree que existe |
| **Lock** | Candado mientras alguien escribe |
| **`force-unlock`** | Quitar un candado huérfano (con cuidado) |
| **Deriva** | Diferencia entre estado y realidad |
| **Bootstrap** | El bucket del estado se crea antes, con su propio estado local |

## 5. Cómo se usa
1. Bucket del estado (bootstrap) y configuración del backend: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) y [`backend.tf.ejemplo`](ejemplos/terraform/backend.tf.ejemplo).
2. Auditor de solo lectura del bucket y de candados viejos en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/estado.sh`](ejemplos/cli/estado.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma (bootstrap) | `roles/storage.admin` en el proyecto del estado | — |
| Pipeline de prod | — | `roles/storage.objectUser` en el bucket de prod |
| Pipeline de no-prod | — | Solo su bucket |
| Auditoría | `roles/storage.legacyBucketReader` / `objectViewer` *(verifica)* | Lista objetos (no los descargues) |

- Nadie más lee el estado: contiene contraseñas, llaves y certificados.
- CMEK con rotación; versiones antiguas expiran por ciclo de vida.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Bucket por entorno, versionado y privado | Un bucket para todo con acceso amplio |
| Estados pequeños por componente | Un monolito de 2 000 recursos |
| `force-unlock` solo tras confirmar que nadie corre | Quitar candados por impaciencia |
| Suplantación o federación | Llaves JSON en el pipeline |
| `prevent_destroy` en el bucket | Borrar el bucket del estado |

## 8. Límites, costos y versiones
- **Costo:** almacenamiento y operaciones del bucket (mínimo) más KMS *(verifica)*.
- **Versiones:** Terraform ≥ 1.5 u OpenTofu; provider `hashicorp/google ~> 8.0` *(verifica)*.
- **Terraform:** `backend "gcs"`, `google_storage_bucket`, `google_kms_crypto_key`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
