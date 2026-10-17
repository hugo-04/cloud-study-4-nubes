# Oracle OCI · Terraform · Estado remoto

El **estado** es el archivo donde Terraform/OpenTofu recuerda qué recursos creó y con qué IDs. Guardarlo en tu laptop funciona hasta que dos personas aplican a la vez o se pierde el disco. En OCI se guarda en **Object Storage** (backend `oci` nativo o la API compatible con S3) o se delega a **Resource Manager**, que administra estado, bloqueo y ejecución por ti.

## 1. Qué es

**Analogía:** el libro de inventario de una bodega compartida. Si cada encargado tiene su copia, se contradicen; por eso hay un único libro en la oficina (bucket), con candado mientras alguien escribe (bloqueo) y fotocopias de cada versión anterior (versionado).

```
 Pipeline / persona ── tofu plan/apply ──► backend
    ├─ Object Storage: bucket "tfstate-modalima" (privado, versionado, CMK)
    │     modalima/prod/red.tfstate      + bloqueo (según backend)
    │     modalima/prod/tienda.tfstate
    └─ Resource Manager: stack = código + variables + estado + jobs (plan/apply/drift)
```

## 2. Cómo funciona por dentro

### Opciones de backend en OCI
| Opción | Cómo funciona | Bloqueo | Cuándo |
|---|---|---|---|
| **Backend `oci`** (Terraform 1.12+ *(verifica)*) | Nativo, autentica como el provider (API key, instance/resource principal) | Sí (objeto de bloqueo) | Terraform reciente |
| **Backend `s3` contra Object Storage** | Endpoint compatible con S3 + *Customer Secret Key* | Con `use_lockfile` según versión *(verifica)* | OpenTofu/Terraform que no tienen `oci` |
| **Backend `http` con PAR** | URL preautenticada de lectura/escritura | No | Laboratorios; evitar en producción |
| **Resource Manager** | Servicio administrado que guarda el estado del stack | Sí (un job a la vez) | Equipos que prefieren no gestionar backend |

### Qué contiene el estado
- IDs, atributos y **valores sensibles en claro** (contraseñas generadas, llaves privadas): el estado es un secreto.
- Una «clave» (ruta) por **componente y entorno**: estados pequeños fallan menos y bloquean menos.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Equipo que aplica desde un pipeline | Backend remoto con bloqueo |
| Varios entornos y componentes | Una clave por componente/entorno |
| Equipo pequeño sin ganas de gestionar backend ni runners | Resource Manager |
| Estado en el repositorio Git | **Nunca** |
| Un estado gigante para todo el tenancy | **No**: divide por componente |
| Editar el estado a mano | **No**: `state mv`, `import`, `removed`, `moved` |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Bloqueo** | Evita dos `apply` simultáneos sobre el mismo estado |
| **Versionado** | Permite volver a un estado anterior si se corrompe |
| **Drift** | Diferencia entre el estado y la realidad (cambios a mano) |
| **`terraform_remote_state`** | Leer salidas de otro estado (con moderación) |
| **Clave del estado** | Ruta del objeto: `unidad/entorno/componente.tfstate` |

## 5. Cómo se usa
1. Bucket del estado (privado, versionado, CMK, retención de versiones) y backend: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) y [`ejemplos/terraform/backend.tf.ejemplo`](ejemplos/terraform/backend.tf.ejemplo).
2. Audita el bucket y busca bloqueos colgados desde [Java](uso-en-java.md).
3. Operación: [`ejemplos/cli/estado.sh`](ejemplos/cli/estado.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage buckets` del bucket del estado | — |
| Pipeline de prod | — | `manage objects` solo bajo `modalima/prod/` |
| Pipeline de no-prod | — | `manage objects` solo bajo `modalima/no-prod/` |
| Lectura de salidas | — | `read objects` de claves concretas |

- El estado contiene secretos: bucket privado, CMK, acceso mínimo, sin PAR permanentes.
- Política por prefijo (`target.object.name`) para separar entornos.
- Versionado + regla de ciclo de vida que conserve versiones anteriores N días.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Un bucket de estado por unidad, como código (con un estado «semilla») | Crear el bucket a mano y olvidarlo |
| Claves por componente/entorno | Un estado monolítico |
| Bloqueo siempre | Dos pipelines aplicando en paralelo |
| `moved`/`import`/`removed` en código | Editar el JSON del estado |
| Detección de drift periódica | Descubrir cambios a mano en el siguiente `apply` |

## 8. Límites, costos y versiones
- **Costo:** almacenamiento y peticiones de Object Storage (mínimos); Resource Manager sin cargo propio *(verifica)*.
- **Versiones:** backend `oci` desde Terraform 1.12; OpenTofu con backend `s3` y endpoint de OCI *(verifica)*.
- **Terraform:** `oci_objectstorage_bucket`, `oci_identity_customer_secret_key` (para `s3`), `oci_resourcemanager_stack`.
- **SDK:** `ObjectStorageClient`, `ResourceManagerClient`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
