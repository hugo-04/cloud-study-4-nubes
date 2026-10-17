# AWS · Storage · Amazon EFS (sistema de archivos compartido)

**EFS (Elastic File System) es un sistema de archivos de red (NFS) administrado: lo montas como una carpeta en muchas máquinas o contenedores a la vez, crece y se encoge solo, y es multi-AZ.** Es lo que usas cuando tu aplicación necesita **rutas y archivos POSIX compartidos** (abrir, bloquear, renombrar, listar) y S3 —que es de objetos— no encaja.

## 1. Qué es

**Analogía:** la **carpeta compartida de la oficina**: todos los equipos la ven como una unidad de red, abren los mismos archivos y la capacidad se ajusta sola. A diferencia de un disco local, es más lento por viajar por la red, pero lo ven todos.

```
 AZ-a                          AZ-b                          AZ-c
┌─────────────┐              ┌─────────────┐              ┌─────────────┐
│ ECS / EKS / │              │ ECS / EKS / │              │   Lambda    │
│ EC2 (app)   │              │ EC2 (app)   │              │ (en la VPC) │
└──────┬──────┘              └──────┬──────┘              └──────┬──────┘
       │ NFS :2049                  │                            │
┌──────▼──────┐              ┌──────▼──────┐              ┌──────▼──────┐
│ Mount target│              │ Mount target│              │ Mount target│  ← una IP por AZ
└──────┬──────┘              └──────┬──────┘              └──────┬──────┘
       └────────────────────────────┴─────────────┬──────────────┘
                                         ┌────────▼────────┐
                                         │  EFS (regional) │  datos replicados en varias AZ
                                         └─────────────────┘
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Sistema de archivos** | El recurso principal; protocolo NFS 4.1; capacidad elástica |
| **Mount target** | Punto de entrada (IP) en una subred; **uno por zona de disponibilidad** |
| **Grupo de seguridad** | Debe permitir TCP 2049 desde tus aplicaciones |
| **Punto de acceso (*access point*)** | Entrada con **directorio raíz y usuario/grupo POSIX forzados**: aísla a cada aplicación |
| **Modo de rendimiento** | *General Purpose* (por defecto; la opción normal) |
| **Modo de throughput** | *Elastic* (recomendado: paga lo que usa), *Provisioned*, *Bursting* *(verifica)* |
| **Clases de almacenamiento** | Standard, Infrequent Access (IA), Archive; *One Zone* para cargas sin multi-AZ |
| **Ciclo de vida** | Mueve archivos sin uso a IA/Archive y de vuelta al primer acceso |
| **Cifrado** | En reposo con KMS (se decide **al crear**); en tránsito con TLS (`efs-utils`, o `transitEncryption` en ECS/EKS) |
| **Política del sistema de archivos** | Recurso: exigir TLS, exigir IAM, limitar por punto de acceso |
| **Respaldo y replicación** | AWS Backup; replicación a otra región |

Quién lo monta: EC2, **ECS** (EC2 y Fargate), **EKS** (driver CSI de EFS), **Lambda** (por punto de acceso y VPC), servidores locales (VPN/Direct Connect).

**Consistencia:** *close-to-open* (lo que escribes se ve en otro cliente al cerrar/abrir el archivo). Los bloqueos son los de NFS (`flock`/`fcntl`, de tipo consultivo).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Archivos compartidos entre varios contenedores/instancias con semántica POSIX | **EFS** |
| Modelos de ML, librerías o datos de referencia compartidos entre invocaciones de Lambda | **EFS** |
| CMS / medios de aplicaciones heredadas que exigen un directorio | **EFS** |
| Archivos de usuario modernos, subidas, backups, logs | **No**: **S3** |
| Archivos de base de datos, colas en disco | **No**: bases de datos / discos EBS |
| Archivos de una sola instancia con máximo rendimiento | **No**: EBS o NVMe local |
| Windows/SMB | **No**: FSx para Windows |
| Muchos archivos pequeños con latencia crítica | Cuidado: cada operación va por red |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **NFS** | Protocolo para compartir carpetas por red |
| **Mount target** | La «puerta» del sistema de archivos en cada zona |
| **Punto de acceso** | Una carpeta raíz con usuario fijo para cada aplicación |
| **Elastic throughput** | Ancho de banda que sube y baja según uso |
| **IA / Archive** | Clases más baratas para archivos fríos |
| **Close-to-open** | Garantía de consistencia al cerrar y abrir |
| **efs-utils** | Ayudante de montaje con TLS e IAM |
| **POSIX uid/gid** | Dueño numérico del archivo |

## 5. Cómo se usa
1. Crea el sistema de archivos **cifrado**, un *mount target* por zona y el grupo de seguridad: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Crea un **punto de acceso por aplicación** (usuario y raíz propios).
3. Monta:
   - **ECS/Fargate:** volumen EFS en la definición de tarea con punto de acceso y `transitEncryption`: [`ejemplos/json/ecs-volumen.json`](ejemplos/json/ecs-volumen.json).
   - **EKS:** driver CSI, `StorageClass` y `PersistentVolumeClaim`: [`ejemplos/k8s/efs.yaml`](ejemplos/k8s/efs.yaml).
   - **Lambda:** `FileSystemConfigs` (ARN del punto de acceso + ruta local `/mnt/...`).
   - **EC2:** `mount -t efs -o tls,iam fs-xxxx:/ /mnt/efs`.
4. Desde Java es una carpeta normal; cuida rutas, escrituras atómicas y timeouts ([uso en Java](uso-en-java.md)).
5. Comandos útiles: [`ejemplos/cli/efs.sh`](ejemplos/cli/efs.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Aplicación (rol de tarea/pod/función)** | — | `elasticfilesystem:ClientMount`, `ClientWrite` (y `ClientRootAccess` si no usas punto de acceso) con montaje IAM |
| **Pipeline** | `elasticfilesystem:CreateFileSystem`, `CreateMountTarget`, `PutFileSystemPolicy`… | — |
| **Permisos POSIX** | — | uid/gid y modos de archivo dentro del sistema |

- **Red:** los *mount targets* viven en subredes privadas; el grupo de seguridad admite 2049 **solo** desde el grupo de seguridad de la aplicación.
- **Aislamiento:** un punto de acceso por aplicación con raíz distinta; así una app no ve los archivos de otra.
- **Política del sistema de archivos:** exigir TLS (`aws:SecureTransport`) y montaje autenticado con IAM.
- **Cifrado en reposo:** se decide al crear (no se puede activar después); usa clave KMS propia si lo exige tu política.
- **No guardes secretos** en archivos del EFS: [Secrets Manager](../../03-secretos/secrets-manager/README.md).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Elastic throughput por defecto | Provisionar throughput «por si acaso» |
| Un punto de acceso por aplicación | Todos con raíz `/` y root |
| Cifrado en reposo y TLS | Montar sin TLS |
| Regla de ciclo de vida a IA | Dejar todo en Standard |
| Escrituras atómicas (temporal + `move`) y rutas validadas | Escribir directo y confiar en nombres del usuario |
| Timeouts en las comprobaciones de salud | Tocar el montaje sin timeout (un NFS caído bloquea el hilo) |
| Un mount target por AZ usada | Cruzar AZ (latencia y costo) |
| Backups con AWS Backup | Confiar en «es multi-AZ» como respaldo |

## 8. Límites, costos y versiones
- **Costo:** GB-mes por clase (Standard > IA > Archive), **lecturas/escrituras en modo Elastic** (por GB transferido), accesos a IA/Archive; la transferencia entre AZ distinta a la del mount target puede cobrar.
- **Límites** *(verifica)*: tamaño de archivo individual, número de conexiones por sistema, mount targets por AZ (uno).
- **Rendimiento:** la latencia es de milisegundos por operación; agrupa operaciones, evita listados enormes.
- **Terraform:** `aws_efs_file_system`, `aws_efs_mount_target`, `aws_efs_access_point`, `aws_efs_file_system_policy`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
