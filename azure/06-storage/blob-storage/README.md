# Azure · Storage · Blob Storage

## 1. Qué es

**Blob Storage es el almacén de objetos de Azure**: guardas "blobs" (archivos de cualquier tipo y tamaño: imágenes, PDF, videos, respaldos, logs, datasets) dentro de contenedores y los lees por HTTPS desde cualquier lugar. Está pensado para **cantidades enormes de datos no estructurados**, con durabilidad muy alta y costo por GB bajo.

Analogía: **una bodega con casilleros**.

| En la bodega | En Azure |
|---|---|
| El edificio con su dirección | **Cuenta de almacenamiento** (`stmodalima01.blob.core.windows.net`) |
| Un estante con nombre | **Contenedor** (`fotos`, `subidas`) |
| Una caja dentro del estante | **Blob** (`2026/10/foto.jpg`) |
| Pasillos | "Carpetas" virtuales: solo son **prefijos** en el nombre (salvo con namespace jerárquico) |
| La llave de un casillero que caduca | **SAS** ([SAS tokens](../sas-tokens/README.md)) |

> Un almacén de objetos **no es un disco**: no editas un pedazo del archivo; subes o reemplazas el blob completo (o bloques que luego confirmas).

---

## 2. Cómo funciona por dentro

### 2.1 Jerarquía
```
Cuenta de almacenamiento (única globalmente; define región, redundancia, red, cifrado)
 └── Contenedor  (nivel de acceso, políticas, inmutabilidad)
      └── Blob (nombre = ruta completa "a/b/c.jpg"; contenido + metadatos + etiquetas)
```

### 2.2 Tipos de cuenta y rendimiento

| Tipo | Para qué | Notas |
|---|---|---|
| **Standard general-purpose v2 (GPv2)** | Casi todo | Blob, Files, Queues, Tables, Data Lake; acceso a tiers Hot/Cool/Cold/Archive |
| **Premium block blob** | Latencia baja y muchas operaciones pequeñas (SSD) | Redundancia LRS/ZRS; sin Archive; costo por GB más alto |
| **Premium file shares / page blobs** | Archivos / discos | Ver [Azure Files](../azure-files/README.md) |
| General-purpose v1 / BlobStorage clásica | Heredadas | Migrar a GPv2 |

### 2.3 Tipos de blob

| Tipo | Se usa para | Característica |
|---|---|---|
| **Block blob** | Archivos, imágenes, documentos, respaldos | Hasta ~190 TiB; se sube en **bloques** (hasta 50 000) que se confirman |
| **Append blob** | Logs que solo crecen | Solo se añaden bloques al final |
| **Page blob** | Discos de máquinas virtuales (VHD) | Acceso aleatorio a páginas de 512 B |

### 2.4 Cómo se sube un block blob (importante para el rendimiento)
1. El cliente divide el archivo en **bloques** (p. ej. 4–100 MiB).
2. Sube los bloques **en paralelo** (`Put Block`), cada uno con un id.
3. Confirma la lista con `Put Block List`: **solo entonces** el blob existe y se emite `BlobCreated`.
4. Si el archivo es pequeño (< ~256 MiB según versión) puede ir en una sola operación (`Put Blob`).

Por eso los SDK/AzCopy son rápidos: paralelizan bloques. Un `PUT` manual de un archivo gigante no.

### 2.5 Tiers de acceso (costo vs frecuencia)

| Tier | Para qué | Almacenamiento | Acceso | Mínimo de permanencia |
|---|---|---|---|---|
| **Hot** | Datos de uso frecuente | Más caro | Barato | — |
| **Cool** | Acceso ocasional | Más barato | Más caro | 30 días |
| **Cold** | Acceso raro | Aún más barato | Aún más caro | 90 días |
| **Archive** | Retención larga, casi nunca se lee | Muy barato | **Offline**: hay que **rehidratar** (horas) | 180 días |

Borrar o mover antes del mínimo conlleva **cargo por borrado anticipado**. *Verifica precios y mínimos vigentes.* El tier se fija por cuenta (defecto) y por blob.

**Rehidratar** un blob de Archive: cambiar su tier a Hot/Cool (prioridad estándar: hasta ~15 h; alta: < 1 h para blobs pequeños) o copiarlo a otro blob.

### 2.6 Redundancia

| Sigla | Qué significa | Cuándo |
|---|---|---|
| **LRS** | 3 copias en un solo data center | Dev, datos reproducibles |
| **ZRS** | 3 copias en 3 zonas de una región | **Producción típica** |
| **GRS** | LRS + copia asíncrona a otra región | Recuperación ante desastres |
| **GZRS** | ZRS + copia a otra región | Producción crítica |
| **RA-GRS / RA-GZRS** | Lectura permitida en la región secundaria | Lectura aunque caiga la primaria |

La replicación geográfica es **asíncrona** (RPO > 0; mira `Last Sync Time`). La *conmutación por error* de cuenta es una operación explícita con pérdida potencial de las últimas escrituras.

### 2.7 Protección de datos

| Función | Qué hace | Recomendación |
|---|---|---|
| **Soft delete de blobs** | Conserva blobs borrados N días | Activar (7–30 días) |
| **Soft delete de contenedores** | Ídem para contenedores | Activar |
| **Versionado** | Conserva versiones anteriores en cada cambio | Activar con ciclo de vida que borre versiones viejas |
| **Snapshots** | Foto de solo lectura de un blob en un momento | Para puntos concretos |
| **Change feed** | Registro ordenado de cambios (crear/modificar/borrar) | Auditoría, replicación, analítica |
| **Point-in-time restore** | Restaura contenedores a un instante | Requiere versionado + change feed + soft delete |
| **Inmutabilidad (WORM)** | No permite modificar/borrar por un periodo, o con *legal hold* | Cumplimiento (SEC/FINRA, retención legal) |
| **Replicación de objetos** | Copia asíncrona entre cuentas/regiones | Cercanía de lectura, cumplimiento |
| **Backup de blobs (Azure Backup)** | Protección operativa/en bóveda | Datos críticos |

### 2.8 Ciclo de vida (lifecycle management)
Reglas declarativas que **mueven de tier o borran** según antigüedad, último acceso, prefijo o etiquetas. Es el mayor ahorro del servicio. Incluye acciones sobre versiones y snapshots. [Ejemplo JSON](ejemplos/cli/lifecycle.json).

### 2.9 Metadatos y etiquetas
- **Metadatos:** pares clave/valor adjuntos al blob (se devuelven con él; no se pueden consultar).
- **Etiquetas de índice (blob index tags):** pares clave/valor **indexados** (hasta 10) para **buscar** blobs (`@container = 'fotos' AND estado = 'pendiente'`) y para reglas de ciclo de vida.
- **Propiedades:** `Content-Type`, `Cache-Control`, `Content-Disposition`, `Content-MD5`, ETag, `Last-Modified`, lease.

### 2.10 Concurrencia y consistencia
- Lecturas y escrituras tienen **consistencia fuerte** (leer después de escribir devuelve lo último).
- **ETag + condiciones** (`If-Match`, `If-None-Match: *`) para concurrencia optimista: crear solo si no existe; reemplazar solo si no cambió.
- **Leases** (arrendamientos de 15–60 s o infinito) para exclusión mutua sobre un blob.

### 2.11 Cifrado
| Capa | Detalle |
|---|---|
| En reposo | Siempre cifrado (AES-256). Claves **gestionadas por Microsoft** (por defecto) o **gestionadas por el cliente** (Key Vault / HSM) |
| Doble cifrado | *Infrastructure encryption* (opcional, al crear la cuenta) |
| *Encryption scopes* | Claves distintas por contenedor/blob |
| En tránsito | HTTPS; `min TLS 1.2`; "Secure transfer required" |
| Del lado del cliente | Cifrar antes de subir (si no confías ni en la clave del servicio) |

### 2.12 Red y acceso

| Control | Qué hace |
|---|---|
| **Firewall de la cuenta** | `defaultAction: Deny` + reglas por IP/VNet |
| **Service endpoint** | La subred accede por la red troncal de Azure (sigue siendo IP pública) |
| **Private Endpoint** | IP privada en tu VNet ([Private Endpoint + DNS](../../01-red/private-endpoint-dns/README.md)); zona `privatelink.blob.core.windows.net` |
| **Servicios de confianza** | Excepciones para servicios de Azure (Backup, Event Grid…) |
| **`publicNetworkAccess = Disabled`** | Solo privado |
| **Acceso anónimo** | Se controla a nivel de cuenta (`allowBlobPublicAccess=false`) y contenedor |
| **Clave compartida** | `allowSharedKeyAccess=false` obliga a Entra ID o SAS de delegación |
| **`defaultToOAuthAuthentication`** | El portal usa Entra ID por defecto |
| **CORS** | Para que navegadores suban/lean desde otro origen |

### 2.13 Modos de autorización (de mejor a peor)

| Método | Nota |
|---|---|
| **Entra ID + RBAC** (identidad administrada) | **El preferido** para aplicaciones |
| **SAS de delegación de usuario** | Acceso temporal a terceros |
| SAS de servicio / de cuenta (con clave) | Solo si no hay alternativa |
| Clave de cuenta | **Evitar**: control total |
| Acceso anónimo | Solo contenido realmente público |

### 2.14 Otras capacidades
- **Sitio web estático** (`$web`): sirve SPAs de React/Angular, con dominio propio vía Front Door/CDN.
- **SFTP** (con namespace jerárquico) para socios que solo hablan SFTP.
- **NFS 3.0** (con namespace jerárquico) para cargas Linux/HPC.
- **Namespace jerárquico (HNS)** convierte la cuenta en **Data Lake Gen2** ([Data Lake Gen2](../data-lake-gen2/README.md)). No se desactiva después.
- **Blob inventory:** informes periódicos de todos los blobs (tamaño, tier, etiquetas).
- **Defender for Storage:** detecta accesos anómalos y malware (análisis de subidas).

### 2.15 Rendimiento y límites de escala
- Objetivos por cuenta (ingreso/egreso/IOPS) y por blob; superar el límite devuelve **`503 ServerBusy`** o **`500 OperationTimedOut`**: reintenta con *backoff exponencial*.
- **Nombres de blob y particiones:** el servicio reparte por rango de nombre. Prefijos secuenciales (`2026-10-16T10:00:01`) concentran la carga en una partición; anteponer un hash corto distribuye. *Verifica la guía actual: el servicio autoajusta particiones.*
- Para subidas grandes: bloques de 8–100 MiB y concurrencia 8–64.
- AzCopy es la herramienta de referencia para copias masivas.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para:** imágenes y documentos de usuarios, videos, respaldos, logs, datasets para analítica/ML, archivos de intercambio con socios, sitios estáticos, Claim Check, backups de bases de datos.

| NO lo uses si | Alternativa |
|---|---|
| Necesitas **consultas** o transacciones sobre los datos | Base de datos ([08-datos](../../08-datos/)) |
| Montas un disco que muchos procesos editan a pedazos | [Azure Files](../azure-files/README.md) o disco administrado |
| Mensajes pequeños de alta frecuencia | Service Bus / Event Hubs ([07-mensajeria](../../07-mensajeria/)) |
| Analítica con directorios, ACLs POSIX y renombrados atómicos | [Data Lake Gen2](../data-lake-gen2/README.md) |
| Archivos de 2 KB a millones por segundo con latencia de ms | Cache o base de datos clave-valor |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Cuenta** | Contenedor de más alto nivel; define región/redundancia/red | `stmodalima01` |
| **Contenedor** | Agrupa blobs; unidad de política | `fotos` |
| **Blob** | El archivo + propiedades | `2026/10/foto.jpg` |
| **Prefijo** | "Carpeta" virtual | `2026/10/` |
| **Tier** | Frecuencia de acceso/costo | Hot, Cool, Cold, Archive |
| **Rehidratar** | Sacar un blob de Archive | Hot en horas |
| **ETag** | Versión del contenido para concurrencia | `If-Match` |
| **Lease** | Candado temporal | 30 s |
| **Bloque** | Fragmento de subida | 8 MiB |
| **WORM** | Escribir una vez, leer muchas; inmutable | Retención legal |
| **HNS** | Namespace jerárquico (Data Lake) | `abfss://` |
| **Lifecycle** | Reglas de mover/borrar | Cool a 30 días |

---

## 5. Cómo se usa

1. Crear la **cuenta** (GPv2, ZRS, TLS 1.2, sin acceso público, sin clave compartida).
2. Crear **contenedores** y **roles RBAC** (identidades administradas).
3. Activar **soft delete, versionado y ciclo de vida**.
4. Poner la red: firewall + **Private Endpoint** si corresponde.
5. Conectar **diagnósticos** (`StorageBlobLogs`) y **Defender for Storage**.
6. Desde la app: SDK con `DefaultAzureCredential`.

Archivos: [CLI](ejemplos/cli/blob.sh) · [ciclo de vida](ejemplos/cli/lifecycle.json) · [Terraform](ejemplos/terraform/main.tf).

```bash
# Rápido (con tu identidad de Entra ID)
az storage container create --account-name $ST -n fotos --auth-mode login
az storage blob upload --account-name $ST -c fotos -f foto.jpg -n 2026/10/foto.jpg --auth-mode login
azcopy copy "./datos/*" "https://$ST.blob.core.windows.net/fotos/2026/?" --recursive   # con SAS o azcopy login
az storage blob list --account-name $ST -c fotos --prefix 2026/ --auth-mode login -o table
```

---

## 6. Seguridad
- **Sin claves:** `allowSharedKeyAccess=false`; aplicaciones con **identidad administrada** y RBAC.
- **Sin público:** `allowBlobPublicAccess=false` en la cuenta.
- **Red:** firewall `Deny` + Private Endpoint; en cuentas solo privadas, las SAS funcionan únicamente para clientes que alcanzan el endpoint.
- **TLS 1.2**, "secure transfer", y rotación de claves si aún se usa clave compartida.
- **Cifrado con CMK** si el cumplimiento lo pide; claves en Key Vault con *purge protection*.
- **Defender for Storage** y alertas de acceso anómalo.
- **Soft delete + versionado + inmutabilidad** contra borrado accidental y ransomware.
- **Registro de operaciones** (`StorageBlobLogs`) hacia Log Analytics.
- **SAS cortas y mínimas** ([SAS](../sas-tokens/README.md)); sin SAS en logs.
- **Analizar** los archivos subidos antes de procesarlos.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Aplicación que lee | Leer blobs | *Storage Blob Data Reader* |
| Aplicación que escribe | Crear/sobrescribir | *Storage Blob Data Contributor* (acotado al contenedor) |
| Aplicación que emite SAS | Pedir clave de delegación | *Storage Blob Delegator* **+** un rol de datos |
| Dueño de datos | Borrar/administrar ACL | *Storage Blob Data Owner* |
| Administrador de la cuenta | Configurar cuenta (no datos) | *Storage Account Contributor* |
| Servicio de ciclo de vida/replicación | Operaciones internas | Gestionadas por la plataforma |
| Auditoría | Ver configuración | *Reader* |

> Los roles de **administración** (Contributor) **no** dan acceso a los datos; los de **datos** sí. Son planos distintos.

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- ZRS (o GZRS) en producción; LRS solo para datos reproducibles.
- Identidad administrada + RBAC; sin claves compartidas.
- Soft delete, versionado y **ciclo de vida** desde el primer día.
- Nombres de blob generados por el servidor (UUID/fecha), no por el usuario.
- Subir en bloques con concurrencia; reintentos con *backoff*.
- Fijar `Content-Type` y `Cache-Control` al subir.
- Etiquetas de índice para búsquedas por estado.
- Un contenedor por **límite de seguridad/ciclo de vida**, no por usuario.
- Monitorear capacidad, transacciones, latencia y errores 4xx/5xx.

**Qué NO hacer**
- Usar la clave de cuenta en aplicaciones o compartirla por correo.
- Contenedores públicos "por comodidad".
- Millones de blobs diminutos sin necesidad (agrupa o usa otro servicio).
- Usar Archive para datos que se leen seguido.
- Cambiar de tier muchas veces (cargos de permanencia mínima).
- Cargar archivos grandes completos en memoria al descargarlos.
- Pasar los archivos grandes por tu API en vez de subir directo con SAS.
- Dejar la cuenta abierta a Internet con datos sensibles.
- Habilitar HNS sin pensar: no es reversible.

---

## 8. Límites, costos y versiones
- Costos: almacenamiento (GB/mes por tier), **operaciones** (por 10 000), **transferencia de salida**, replicación geográfica, recuperación de Cool/Cold/Archive, funciones opcionales (versionado, change feed, inventario).
- Límites relevantes (tamaño de blob, bloques, nº de contenedores, tasas por cuenta, etiquetas): *verifica la página de límites y de escalabilidad*.
- La versión de la API REST (`x-ms-version`) y las funciones de SDK evolucionan; fija una versión de SDK probada.
- Archive y algunas funciones no están en Premium ni en todas las regiones.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
