# Oracle OCI · Storage · File Storage (NFS administrado)

Un sistema de archivos de red (NFS v3, y opciones más nuevas *(verifica)*) que crece solo y que montan a la vez muchas VM o pods. Es lo que necesitas cuando el software espera **una carpeta compartida** y no una API de objetos.

## 1. Qué es

**Analogía:** la carpeta compartida de la oficina en el servidor. Todos la ven como una unidad más de su computadora, leen y escriben archivos, y el área de sistemas se encarga de que no se llene ni se pierda.

```
 Subred privada
   ├─ Mount target (IP 10.0.4.20, NSG: NFS solo desde las apps)
   │     └─ Export set
   │          └─ Export "/catalogo-media" ──► File system "fs-media" (crece solo, snapshots)
   ├─ VM legacy    mount 10.0.4.20:/catalogo-media /mnt/media
   └─ Pods de OKE  PersistentVolume (CSI de File Storage, ReadWriteMany)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **File system** | Los datos; vive en un dominio de disponibilidad; crece y decrece solo |
| **Mount target** | Punto de red (IP privada en tu subred) por donde se monta |
| **Export set / export** | Ruta publicada (`/catalogo-media`) + opciones por cliente |
| **Export options** | Por CIDR de origen: `READ_WRITE`/`READ_ONLY`, *identity squash*, puerto privilegiado |
| **Snapshots** | Copias puntuales de solo lectura (`.snapshot`); políticas de snapshot programadas |
| **Clones** | File system nuevo a partir de un snapshot, casi instantáneo |
| **Replicación** | Copia asíncrona a otra región o AD |
| **Cifrado** | En reposo con llave de Oracle o tuya; en tránsito con TLS (paquete `oci-fss-utils`) |

### Rendimiento
- El rendimiento escala con los datos guardados y con los *mount targets* (y con opciones de alto rendimiento *(verifica)*).
- Muchos archivos pequeños y operaciones de metadatos son lo más lento: no es un disco local.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Aplicación heredada que lee/escribe en una carpeta compartida | **File Storage** |
| Varios pods necesitan `ReadWriteMany` | **File Storage** (CSI) |
| Archivos para servir o archivar | [Object Storage](../object-storage/README.md) |
| Base de datos | **No**: volumen en bloque o servicio de base de datos |
| Disco de un solo servidor con IOPS altos | **No**: Block Volume |
| Intercambio de archivos con terceros | **No**: Object Storage + [PAR](../par/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **NFS** | Protocolo para montar carpetas por red |
| **Root squash** | El usuario `root` del cliente se convierte en anónimo |
| **Puerto privilegiado** | Solo acepta clientes que montan desde puertos < 1024 (root) |
| **Snapshot** | Foto del sistema de archivos en un instante |
| **`ReadWriteMany`** | Volumen de Kubernetes montable por muchos pods a la vez |

## 5. Cómo se usa
1. File system + mount target + export con opciones estrictas + política de snapshots: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. NSG del mount target: TCP 111, 2048–2050 y UDP 111, 2048 solo desde las apps *(verifica puertos)*.
3. Monta y verifica: [`ejemplos/cli/file-storage.sh`](ejemplos/cli/file-storage.sh).
4. Audita las opciones de export de todo el compartimento: [uso en Java](uso-en-java.md).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage file-family` | — |
| Auditoría | `read file-family` | — |
| Clientes NFS | — | Export options por CIDR + permisos UNIX |
| Servicio (CMK) | — | `use keys` |

- El control de acceso a los datos es **por red y UID/GID**, no por IAM: las *export options* son tu política.
- Nunca `0.0.0.0/0`; `READ_ONLY` para quien solo lee; `ROOT` squash por defecto.
- Cifrado en tránsito si cruza fronteras de confianza.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Export options por subred concreta | `0.0.0.0/0` con `READ_WRITE` |
| Root squash y puerto privilegiado | Permitir `root` remoto sin squash |
| Política de snapshots (diaria/semanal) | Confiar en que «nadie borra nada» |
| Montar con `nosuid` y opciones probadas | Opciones de montaje por defecto en producción |
| Separar file systems por aplicación | Un file system gigante para todo |

## 8. Límites, costos y versiones
- **Costo:** GB-mes almacenado (los snapshots cuentan solo lo que cambió); mount targets sin costo en el nivel estándar *(verifica)*.
- **Límites** (verifica): file systems y mount targets por AD, exports por export set, tamaño máximo.
- **Terraform:** `oci_file_storage_file_system`, `oci_file_storage_mount_target`, `oci_file_storage_export`, `oci_file_storage_filesystem_snapshot_policy`.
- **SDK:** `FileStorageClient` (`oci-java-sdk-filestorage`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
