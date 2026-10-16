# Azure · Storage · Data Lake Storage Gen2 (Blob con carpetas reales para analítica)

## 1. Qué es

**Data Lake Storage Gen2 (ADLS Gen2) es Blob Storage con el "espacio de nombres jerárquico" (*hierarchical namespace*, HNS) activado.** Los "directorios" dejan de ser un truco del nombre (`carpeta/archivo`) y pasan a ser **objetos reales**: se pueden renombrar y mover de forma **atómica y casi instantánea**, y llevan **permisos tipo POSIX (ACL)**. Es la base de los *data lakes* y de las plataformas de analítica (Spark, Databricks, Synapse, Fabric, Data Factory).

Analogía: en Blob normal los "pasillos" son solo parte de la etiqueta de cada caja (`pasillo-3/estante-2/caja-77`); si renombras el pasillo hay que **reetiquetar millones de cajas**. Con HNS los pasillos existen de verdad: **cambias el letrero del pasillo y listo**.

```
 Blob sin HNS (espacio plano)                    Data Lake Gen2 (HNS)
 ───────────────────────────                     ────────────────────
 nombre: "ventas/2026/10/a.csv"                  /ventas              (directorio real, con ACL)
 "directorio" = prefijo del nombre                 └─ /2026
 renombrar carpeta = copiar + borrar N blobs         └─ /10
 permisos: solo RBAC/SAS por contenedor                 └─ a.csv     (archivo)
                                                 renombrar carpeta = 1 operación atómica
                                                 permisos: RBAC + ACL por directorio/archivo

 Dos puertas al mismo dato:
   https://cuenta.blob.core.windows.net/...      (API de Blob)
   https://cuenta.dfs.core.windows.net/...       (API de Data Lake / ABFS)   abfss://sistema@cuenta.dfs.core.windows.net/ruta
```

---

## 2. Cómo funciona por dentro

### 2.1 Qué añade el espacio de nombres jerárquico

| Capacidad | Sin HNS | Con HNS |
|---|---|---|
| Directorios | Simulados por prefijos | **Reales** (se crean, renombran, borran) |
| Renombrar/mover una carpeta | Copiar y borrar cada blob (lento, no atómico) | **Una operación de metadatos, atómica** |
| Borrar una carpeta | Borrar blob por blob | Una operación (recursiva) |
| Permisos finos | Solo RBAC y SAS | **RBAC + ACL POSIX** por directorio y archivo |
| Endpoint de analítica | Blob | **`dfs`** (ABFS) además del de Blob |
| Escritura incremental | Bloques | `append` + `flush` (confirmar) |
| Protocolos extra | — | **SFTP** y **NFS 3.0** sobre el almacenamiento (requieren HNS) |
| Algunas funciones de Blob | Disponibles | Algunas **no** se soportan o difieren (p. ej. versionado, instantáneas): *verifica la tabla de compatibilidad vigente* |

HNS se decide **al crear la cuenta**. Se puede **actualizar** una cuenta existente (migración con validación previa), pero es **un camino de ida y con ventana de mantenimiento**: planifícalo.

### 2.2 Las piezas

| Pieza | Papel |
|---|---|
| **Cuenta con HNS** | `StorageV2` con `is_hns_enabled = true` |
| **Sistema de archivos** (*file system* = contenedor) | Raíz del lago; en Blob se llama "contenedor" |
| **Directorio** | Objeto real; lleva ACL; admite ACL por defecto |
| **Archivo** (*path*) | Datos + ACL; se escribe con `append` y se confirma con `flush` |
| **ABFS** | Controlador de Hadoop (`abfss://`) usado por Spark, Databricks, Synapse, Fabric |
| **ACL de acceso** | Permisos aplicados **a ese** directorio/archivo |
| **ACL por defecto** (*default*) | Plantilla que heredan los elementos **nuevos** creados dentro del directorio |
| **Súper-usuario** | *Storage Blob Data Owner*: puede todo |

### 2.3 Autorización: RBAC + ACL (el orden importa)
1. Azure evalúa primero **RBAC**: si tienes un rol de datos que concede la acción (*Storage Blob Data Owner/Contributor/Reader*), **se permite y no se miran las ACL**.
2. Si ningún rol lo concede, se evalúan las **ACL**: necesitas **ejecutar (`x`) en cada directorio del camino** y el permiso final (`r`, `w`) en el objetivo.

Consecuencia práctica: **dar *Contributor* o *Reader* a nivel de cuenta salta todas tus ACL**. Para controlar por carpeta, no des roles de datos amplios; usa ACL con **grupos de Entra ID**.

| Permiso | En archivo | En directorio |
|---|---|---|
| `r` | Leer contenido | Listar |
| `w` | Escribir | Crear/borrar/renombrar hijos (necesita también `x`) |
| `x` | (sin efecto) | **Atravesar** el directorio: sin esto no llegas a nada de abajo |

Notación `rwx`; en la CLI y el SDK: `user::rwx,group::r-x,other::---,user:<objectId>:r-x,default:group:<objectId>:r-x`. El número de entradas por objeto es limitado (decenas): **asigna a grupos, no a personas** (*verifica el límite vigente*).

> **ACL por defecto no son retroactivas.** Se aplican a lo que se cree **después**. Para lo existente hay que aplicar ACL **de forma recursiva** (operación que recorre el árbol y cuesta tiempo/transacciones).

### 2.4 Cómo se organiza un lago (arquitectura *medallion*)

| Zona | Contenido | Quién escribe | Quién lee |
|---|---|---|---|
| **landing / raw (bronce)** | Datos tal cual llegan, inmutables | Ingestas (Data Factory, Event Hubs Capture, SFTP) | Solo pipelines |
| **curated / silver** | Limpios, tipados, deduplicados (Parquet/Delta) | Trabajos de transformación | Ingeniería de datos |
| **gold / consumo** | Modelos listos para negocio | Trabajos de agregación | Analistas, BI, APIs |

Convención de rutas con **particiones**: `silver/ventas/anio=2026/mes=10/dia=16/part-0001.parquet`. Pocos archivos **grandes** (decenas–cientos de MB) rinden mucho más que millones de archivos diminutos.

### 2.5 Escritura: `append` + `flush` y publicación atómica
Un archivo grande se escribe en trozos (`append` en un `offset`) y **no es visible/consistente hasta el `flush`** final. Patrón seguro: escribir en `_tmp/` y **renombrar** a la ruta final (operación atómica) para que los lectores nunca vean archivos a medias.

### 2.6 Eventos y otros accesos
- Los eventos de Event Grid llegan como `BlobCreated` con `api = CreateFile/FlushWithClose` y eventos de directorio (`DirectoryRenamed`, etc.): ver [Eventos de Blob](../eventos-blob/README.md).
- **SFTP** (con usuarios locales y directorio de inicio) para socios que solo hablan SFTP.
- **Event Hubs Capture** vuelca los eventos de un hub como archivos Avro al lago.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Data lake / lakehouse**: zonas bronce-plata-oro, Parquet/Delta, Spark.
- **Zonas de aterrizaje** de ingestas con permisos por equipo (ACL por directorio).
- **Cargas de analítica** que renombran/mueven grandes conjuntos (confirmación de trabajos Spark).
- **Datasets de Machine Learning** y exportaciones masivas de bases de datos.
- **Intercambio con socios por SFTP** con carpetas aisladas.
- **Archivado analítico** con ciclo de vida por zona.

| NO lo uses si | Alternativa |
|---|---|
| Solo sirves imágenes/PDF a una web y necesitas versionado, retención WORM o funciones de Blob no soportadas con HNS | **Blob Storage** sin HNS |
| Tu aplicación espera un sistema de archivos montado con bloqueos | **Azure Files** |
| Necesitas actualizaciones aleatorias frecuentes de registros | Base de datos |
| Solo hay pocos archivos pequeños | Blob normal (HNS no aporta) |
| Quieres permisos por archivo para miles de usuarios individuales | Grupos + ACL por directorio; o aplicar el control en tu API |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **HNS** | Directorios reales en el almacenamiento | `is_hns_enabled = true` |
| **ADLS Gen2** | Blob + HNS + endpoint `dfs` | `cuenta.dfs.core.windows.net` |
| **File system** | El contenedor raíz del lago | `silver` |
| **ABFS / `abfss://`** | Controlador/URI que usa Spark | `abfss://silver@cuenta.dfs.core.windows.net/ventas` |
| **ACL** | Permisos POSIX por objeto | `group:<id>:r-x` |
| **ACL por defecto** | Plantilla heredada por lo nuevo | `default:group:<id>:r-x` |
| **Medallion** | Zonas bronce/plata/oro | `bronze/silver/gold` |
| **Partición** | Carpetas por valor de columna | `anio=2026/mes=10` |
| **Append/Flush** | Escribir trozos y confirmar | Subida de un NDJSON |
| **Rename atómico** | Mover sin copiar | `_tmp/x` → `silver/x` |
| **Parquet/Delta** | Formatos columnares para analítica | `part-0001.parquet` |
| **Data Owner** | Rol súper-usuario del lago | Administradores |

---

## 5. Cómo se usa

1. **Crea la cuenta con HNS** (o migra una existente con validación previa) y los sistemas de archivos por zona.
2. **Diseña rutas y particiones** y la política de acceso por zona/dominio con **grupos**.
3. **Aplica ACL** (con ACL por defecto en los directorios padre **antes** de que lleguen datos).
4. **Roles de datos** mínimos para pipelines (*Contributor*) y lectura amplia solo donde corresponda.
5. **Red:** Private Endpoints de **`dfs`** y de **`blob`** (dos subrecursos) y DNS privado de ambos.
6. **Ingesta:** Data Factory, Event Hubs Capture, SFTP, SDK de Java.
7. **Consumo:** Spark/Databricks/Synapse/Fabric con `abfss://`; APIs con el SDK `azure-storage-file-datalake`.
8. **Ciclo de vida** por zona (bronce a frío/archivo, temporales fuera).
9. **Observa:** métricas, diagnóstico de la cuenta, eventos de directorio.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/data-lake.sh) · [Configuración ABFS/Spark](ejemplos/spark/abfs-config.properties) · [Diseño de ACL](ejemplos/acl/diseno-acl.md).

---

## 6. Seguridad

- **Capas:** red (firewall/Private Endpoint) → identidad (Entra ID) → **RBAC** → **ACL** → cifrado.
- **Desactiva la clave de la cuenta** (`shared_access_key_enabled=false`) y usa identidad; para terceros, **SAS de delegación de usuario**.
- **Mínimo privilegio con ACL por grupos**: lectura (`r-x`) para analistas; escritura (`rwx`) solo para pipelines; sin roles amplios que salten las ACL.
- **Execute en la ruta completa**: sin `x` en los padres no se llega al dato.
- **Privacidad**: separa datos personales en zonas/carpetas con ACL propias y retención; evita datos personales en nombres de ruta.
- **Protección**: *soft delete* de blobs y contenedores, bloqueo del recurso, réplicas (GRS/GZRS) para continuidad. *Las funciones de protección soportadas con HNS cambian: verifica la tabla.*
- **SFTP**: solo si hace falta, con usuarios locales, directorios de inicio aislados y llaves SSH (no contraseñas); límites de red.
- **Auditoría**: diagnóstico a Log Analytics (lecturas, escrituras, fallos de ACL).

### IAM de este servicio

| Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|
| Pipelines de ingesta/transformación | Crear, escribir, renombrar | *Storage Blob Data Contributor* (o ACL `rwx` en sus carpetas, sin rol) |
| Analistas/BI | Leer | ACL `r-x` por grupo en las zonas permitidas (o *Storage Blob Data Reader* si es toda la cuenta) |
| Administradores del lago | Gestionar ACL y propietarios | *Storage Blob Data Owner* |
| App Java con SDK | Operar con identidad administrada | *Storage Blob Data Contributor* o ACL en su ruta |
| Spark/Databricks | Acceder con identidad administrada o principal de servicio | Rol de datos + ACL según la zona |
| Quien administra la cuenta | Plano de control | *Contributor* sobre la cuenta (no da acceso a datos) |
| SFTP | Usuario local con permisos por contenedor y directorio de inicio | Permisos del usuario local |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Decidir HNS **desde el diseño**; documentar la estrategia de rutas y particiones.
- Asignar ACL a **grupos**; fijar **ACL por defecto** en los directorios padre antes de cargar datos.
- Escribir en `_tmp/` y **renombrar** al terminar.
- Pocos archivos grandes en formatos columnares (Parquet/Delta).
- Private Endpoint para **`dfs` y `blob`**.
- Ciclo de vida por zona; *soft delete*.
- Auditar con diagnóstico y revisar quién tiene *Data Owner*.

**Qué NO hacer**
- Dar *Storage Blob Data Contributor/Reader* a nivel de cuenta y esperar que las ACL restrinjan.
- ACL por usuario individual (se agota el límite y es inmanejable).
- Olvidar el permiso `x` en los directorios intermedios.
- Millones de archivos de pocos KB.
- Aplicar ACL recursivas sobre árboles enormes en horas pico sin medir.
- Habilitar SFTP "por si acaso" ni exponerlo sin restricción de red.
- Asumir que todas las funciones de Blob (versionado, instantáneas) funcionan con HNS.

---

## 8. Límites, costos y versiones
- Costos: capacidad + transacciones (las de HNS se facturan distinto que las de Blob plano) + escritura/lectura de metadatos + ACL recursivas + SFTP (se cobra por hora habilitado) + salida de datos.
- Límites: entradas de ACL por objeto, tamaño de archivo/ruta, longitud de nombres y profundidad: *verifica los vigentes*.
- La migración a HNS es de un solo sentido; valida antes.
- Compatibilidad de funciones entre Blob y HNS evoluciona: consulta siempre la tabla oficial.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
