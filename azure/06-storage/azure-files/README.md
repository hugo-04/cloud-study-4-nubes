# Azure · Storage · Azure Files (carpetas compartidas administradas)

## 1. Qué es

**Azure Files ofrece carpetas compartidas ("file shares") en la nube a las que accedes con los protocolos de archivos de siempre —SMB (Windows/Linux/macOS) o NFS 4.1 (Linux)— y también por API REST.** Es un servidor de archivos sin servidor que mantener: no parchas, no administras discos, no montas clústeres.

Analogía: **la carpeta compartida de la oficina** (`\\servidor\contabilidad`) que todos montan como una unidad, pero alquilada y administrada por Azure, con copias de seguridad y permisos integrados.

```
 Máquinas virtuales ─┐
 Pods de AKS (PVC) ──┤  SMB 3.x / NFS 4.1      ┌─────────────────────────────────────────┐
 Container Apps ─────┼────────────────────────►│ Cuenta de almacenamiento                │
 App Service ────────┤  (puerto 445 / 2049)    │   └─ Recurso compartido "contabilidad"  │
 PCs / servidores ───┘  vía Private Endpoint   │        ├─ carpeta/archivo               │
 on-premises (VPN)                             │        └─ instantáneas (snapshots)      │
 Servidor Windows ◄── Azure File Sync ───────► └─────────────────────────────────────────┘
 (caché local)
```

**Frente a Blob:** Blob es un almacén de objetos (REST, billones de objetos, analítica). Files es un **sistema de archivos** con carpetas reales, bloqueos, permisos tipo Windows/POSIX y montaje. Si tu aplicación espera `open("/datos/archivo.txt")`, necesita Files (o disco), no Blob.

---

## 2. Cómo funciona por dentro

### 2.1 Tipos y niveles

| Modelo | Cuenta | Hardware | Se cobra por | Úsalo para |
|---|---|---|---|---|
| **Premium** | `FileStorage` | SSD | **Capacidad aprovisionada** (GiB) y rendimiento derivado | Baja latencia, cargas I/O intensivas, contenedores, perfiles, bases de datos que lo admiten |
| **Estándar – optimizado para transacciones** | `StorageV2` | HDD | Capacidad usada + transacciones | Aplicaciones con muchas operaciones pequeñas |
| **Estándar – Hot** | `StorageV2` | HDD | Capacidad usada + transacciones | Uso general |
| **Estándar – Cool** | `StorageV2` | HDD | Capacidad barata + transacciones/lecturas más caras | Archivos poco accedidos, respaldos |

*Los modelos de facturación del nivel estándar (pago por uso y "aprovisionado v2") evolucionan: verifica el vigente.*

| Protocolo | Sistemas | Autenticación | Notas |
|---|---|---|---|
| **SMB 3.x** (3.0/3.1.1) | Windows, Linux, macOS | Clave de la cuenta, o **identidad** (Active Directory local, Entra Domain Services, Entra Kerberos) | Cifrado en tránsito; puerto **445** |
| **NFS 4.1** | Linux | Red (no hay usuarios/clave): **Private Endpoint o Service Endpoint** | Solo **premium**; puerto 2049; semántica POSIX; *root squash* configurable |
| **REST** | Cualquiera | Entra ID (token) o clave/SAS | Lo usa el SDK de Java |

Redundancia: LRS, ZRS (zonas) y, en estándar, GRS/GZRS. *Verifica combinaciones por región.*

### 2.2 Piezas

| Pieza | Papel |
|---|---|
| **Cuenta de almacenamiento** | Contenedor lógico; define rendimiento (premium/estándar), red, cifrado y claves |
| **Recurso compartido** (*share*) | La "unidad" que montas; tiene cuota, nivel y protocolo (SMB o NFS) |
| **Directorios y archivos** | Estructura real de carpetas; metadatos y ACL tipo NTFS (SMB) o permisos POSIX (NFS) |
| **Instantánea** (*share snapshot*) | Copia de solo lectura del share en un instante; **incremental** (solo cambios) |
| **Eliminación temporal** (*soft delete*) | Un share borrado se puede recuperar durante unos días |
| **Azure Backup** | Copias programadas con retención administrada, apoyadas en instantáneas |
| **Azure File Sync** | Replica un share con servidores Windows locales (caché con *cloud tiering*) |
| **Cuota** | Tamaño máximo; en premium, además, **define** IOPS y ancho de banda |

### 2.3 Rendimiento (idea, verifica fórmulas vigentes)
- **Premium:** IOPS y rendimiento crecen con los **GiB aprovisionados** (una base fija + una cantidad por GiB, con ráfagas). Para más rendimiento, aprovisionas más capacidad aunque no la llenes.
- **Estándar (HDD):** IOPS por share limitados; listados de directorios enormes y miles de archivos pequeños son lentos.
- **SMB Multichannel** (premium) usa varias conexiones para subir el caudal.
- La latencia de un montaje remoto es **mucho mayor** que la de un disco local: no uses el share como disco temporal de una aplicación.

### 2.4 Autenticación y permisos (SMB)

Hay **dos capas** que se multiplican:

| Capa | Dónde se define | Qué controla |
|---|---|---|
| **Nivel de share** | RBAC de Azure | *Storage File Data SMB Share Reader / Contributor / Elevated Contributor*: ¿puede esta identidad entrar al share? |
| **Nivel de archivo/carpeta** | ACL tipo NTFS dentro del share | Qué puede hacer en cada ruta. *Elevated Contributor* permite cambiarlas |

Opciones de identidad: **Active Directory local** (servidores unidos al dominio), **Microsoft Entra Domain Services** o **Microsoft Entra Kerberos** (identidades híbridas). Sin identidad: **clave de la cuenta** (acceso total, evítalo).

Para el **plano REST** (SDK de Java) se usa Entra ID con roles de datos *Storage File Data Privileged Reader/Contributor* y el parámetro de **intención de token** (`backup`).

### 2.5 Red: el puerto 445
SMB usa el **puerto TCP 445**. Muchos proveedores de internet y firewalls lo bloquean de salida. Soluciones: montar **desde Azure** (VM, AKS), **VPN/ExpressRoute + Private Endpoint**, o REST/SDK por HTTPS (443). Con **Private Endpoint** (`privatelink.file.core.windows.net`) el nombre `cuenta.file.core.windows.net` resuelve a una IP privada: configura el DNS (zona privada o reenviadores).

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Lift-and-shift**: aplicaciones que esperan una ruta de archivos compartida.
- **Contenedores con almacenamiento compartido (ReadWriteMany)**: varios pods leyendo y escribiendo la misma carpeta (AKS con el controlador CSI de Azure Files).
- **Configuración y contenido compartido** entre instancias (plantillas, certificados públicos, recursos estáticos).
- **Perfiles de usuario** (FSLogix) en escritorios virtuales.
- **Intercambio de archivos con sistemas heredados** (SFTP de socios con espacio compartido, procesos batch que dejan archivos).
- **Híbrido**: Azure File Sync para sucursales con caché local.
- **Montajes** en App Service, Container Apps y Functions para contenido compartido.

| NO lo uses si | Alternativa |
|---|---|
| Almacenas objetos a gran escala accesibles por HTTP o necesitas analítica | **Blob Storage** / **Data Lake Gen2** |
| Necesitas un disco para una sola VM con IOPS altos y latencia mínima | Disco administrado |
| Tu aplicación escribe archivos temporales con mucha E/S | Disco efímero local |
| Cargas de base de datos transaccional | Servicio de base de datos administrado |
| Quieres exponer archivos a Internet con SAS por archivo | Blob + SAS |
| Necesitas inmutabilidad WORM | Blob con retención legal/por tiempo |
| Necesitas bloqueo estricto entre muchos escritores simultáneos sobre el mismo archivo | Diseña con un servicio coordinador o base de datos |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Share** | La carpeta raíz que se monta | `contabilidad` |
| **SMB / NFS** | Protocolos de archivos en red | SMB para Windows, NFS para Linux |
| **Aprovisionado** | Pagas la capacidad reservada, la uses o no | Premium 1 TiB |
| **Cuota** | Límite de tamaño del share | 5 TiB |
| **Instantánea** | Foto de solo lectura del share | Cada noche |
| **Soft delete** | Papelera del share | 7 días |
| **ACL NTFS** | Permisos finos por carpeta/archivo | `contabilidad\nomina` solo RRHH |
| **Kerberos** | Protocolo de autenticación por tickets | Acceso con identidad corporativa |
| **Private Endpoint** | IP privada del servicio dentro de tu VNet | `10.0.5.4` |
| **CSI driver** | Complemento de Kubernetes que monta almacenamiento | `file.csi.azure.com` |
| **PVC / PV** | Solicitud/volumen de almacenamiento en Kubernetes | `ReadWriteMany` |
| **File Sync** | Sincroniza un share con servidores Windows | Sucursal con caché |
| **Cloud tiering** | Deja en la nube los archivos fríos y conserva el "puntero" local | Libera disco del servidor |

---

## 5. Cómo se usa

1. **Elige modelo:** premium (rendimiento, contenedores) o estándar (económico, uso general); SMB o NFS.
2. **Crea la cuenta y el share** con cuota y *soft delete*; define la red (Private Endpoint).
3. **Autenticación:** SMB con identidad (Entra Kerberos/AD) o, solo para pruebas, la clave de la cuenta. NFS: red privada.
4. **Monta** en Linux (`mount -t cifs` / `mount -t nfs`), en Windows (`net use`), en AKS (PVC con el controlador CSI), en Container Apps/App Service (montajes del servicio).
5. **Desde Java:** (a) como ruta del sistema de archivos montada (`java.nio.file`), o (b) con el SDK `azure-storage-file-share` por REST con identidad administrada.
6. **Protección:** instantáneas programadas con Azure Backup, *soft delete*, bloqueo de recursos.
7. **Observa:** métricas de transacciones, latencia, disponibilidad, uso de IOPS/ancho de banda y capacidad.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/azure-files.sh) · [YAML de Kubernetes](ejemplos/yaml/azure-files-aks.yaml).

---

## 6. Seguridad

- **Identidad antes que claves:** SMB con Entra Kerberos/AD y RBAC de share + ACL; la clave de la cuenta es acceso total a todo.
- **Private Endpoint** y firewall de la cuenta; NFS **solo** por red privada.
- **Cifrado**: en tránsito (SMB 3.x con AES-128/256; versión mínima y cifrados configurables) y en reposo (claves de Microsoft o administradas por ti).
- **Endurece SMB**: solo SMB 3.1.1 si tus clientes lo permiten; desactiva autenticación NTLMv2 si no la usas (*verifica opciones vigentes*).
- **Cuidado con `shared_access_key_enabled = false`:** impide los montajes que usan la clave (AKS con secreto, App Service, Container Apps). Planifica identidad o separa cuentas.
- **Protección de datos:** *soft delete*, instantáneas, Azure Backup; bloqueo del recurso.
- **Defender for Storage** para detectar accesos anómalos.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Aplicaciones/usuarios que montan por SMB y leen | Leer en el share | *Storage File Data SMB Share Reader* |
| … y escriben | Leer/escribir/borrar | *Storage File Data SMB Share Contributor* |
| Administradores de permisos | Cambiar ACL NTFS | *Storage File Data SMB Share Elevated Contributor* |
| Aplicación Java con SDK (REST, intención `backup`) | Leer/escribir por API | *Storage File Data Privileged Contributor* (o *Privileged Reader*) |
| Quien crea shares | Plano de control | *Storage Account Contributor* o rol personalizado acotado |
| Backups | Operar instantáneas | Roles de *Backup Contributor* sobre la bóveda |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Premium para cargas intensivas o contenedores; estándar para uso general.
- Cuota **ajustada** (en premium la cuota es rendimiento y costo).
- Private Endpoint + DNS correcto (probar `nslookup` desde donde montas).
- Identidad (Kerberos) + RBAC de share + ACL por carpeta.
- *Soft delete*, instantáneas y Azure Backup desde el día 1.
- En AKS, `ReadWriteMany` con CSI; para NFS, protocolo `nfs` en la StorageClass.
- Subir con extensión temporal y **renombrar** al terminar (el lector ignora los temporales).
- Hacer **sondeo (*polling*)** de la carpeta; no confiar en notificaciones del sistema de archivos.

**Qué NO hacer**
- Montar con la **clave de la cuenta** en producción ni guardarla en repositorios o imágenes.
- Usar el share como disco temporal o de trabajo de una app (latencia).
- Esperar que `WatchService` de Java avise de cambios hechos por otros clientes sobre SMB/NFS.
- Depender de bloqueos de archivo entre varios escritores sin probarlo.
- Directorios con millones de archivos planos (particiona por fecha/prefijo).
- Abrir el puerto 445 a Internet.
- Olvidar que borrar el share borra instantáneas si no hay *soft delete* ni bloqueo.

---

## 8. Límites, costos y versiones
- Costos: capacidad (aprovisionada en premium; usada en estándar), transacciones (estándar), instantáneas (solo datos cambiados), copias de Azure Backup, salida de datos, Private Endpoint y File Sync.
- Límites (tamaño de share, tamaño de archivo, IOPS, ancho de banda, número de instantáneas, conexiones): *verifica los vigentes por modelo*.
- Versiones de SMB soportadas y cifrados: dependen del cliente (Linux: kernel reciente recomendado).
- `shared_access_key_enabled=false` y montajes por clave son incompatibles; algunos servicios PaaS solo montan con clave.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
