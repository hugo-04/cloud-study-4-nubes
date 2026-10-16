# Azure · 06 Storage

Dónde viven los datos que **no** están en una base de datos: archivos, imágenes, documentos, exportaciones, lotes y registros. Seis piezas, tres servicios de almacenamiento y tres "formas de usarlos":

| Pieza | Tipo | Analogía | La eliges para |
|---|---|---|---|
| [Blob Storage](blob-storage/README.md) | Almacén de **objetos** (REST/HTTP) | Bodega con etiquetas | Imágenes, PDF, videos, respaldos, exportaciones; el dato "grande" de casi todo |
| [SAS tokens](sas-tokens/README.md) | Permiso temporal sobre Blob | Llave de visitante con fecha de vencimiento | Subir/descargar directo desde el navegador o a terceros sin pasar por tu API |
| [Claim Check](claim-check/README.md) | **Patrón** (Blob + cola) | Ticket de guardarropa | Mover archivos grandes entre servicios enviando solo la referencia |
| [Eventos de Blob](eventos-blob/README.md) | Event Grid sobre Storage | Timbre de la puerta | Reaccionar cuando llega o se borra un archivo, sin sondear |
| [Azure Files](azure-files/README.md) | Sistema de **archivos** compartido (SMB/NFS) | Carpeta compartida de la oficina | Aplicaciones que esperan una ruta de archivos; volúmenes compartidos en AKS |
| [Data Lake Gen2](data-lake-gen2/README.md) | Blob + **directorios reales** y ACL | Biblioteca con pasillos reales | Analítica, lakehouse, Spark, zonas bronce/plata/oro |

## Árbol de decisión

```
¿Tu código hace  open("/ruta/archivo")  y no se puede cambiar?          → Azure Files
¿Vas a ejecutar Spark/Databricks/Synapse o necesitas ACL por carpeta?    → Data Lake Gen2 (Blob con HNS)
¿Guardas objetos y los sirves/procesas por HTTP?                         → Blob Storage
   ¿El navegador o un tercero debe subir/descargar directo?              → + SAS de delegación de usuario
   ¿El archivo debe pasar de un servicio a otro (cola/stream)?           → + Claim Check
   ¿Algo debe ocurrir cuando llega el archivo?                           → + Eventos de Blob (Event Grid)
```

## Comparativa de los tres almacenes

| Característica | Blob Storage | Azure Files | Data Lake Gen2 |
|---|---|---|---|
| Modelo | Objetos planos (contenedor/nombre) | Sistema de archivos (carpetas) | Objetos con jerarquía real |
| Acceso | REST/HTTPS (SDK), SAS | SMB / NFS / REST | REST (`blob` y `dfs`), ABFS, SFTP, NFS 3.0 |
| Permisos finos | RBAC, SAS, etiquetas | RBAC de share + ACL NTFS | RBAC + **ACL POSIX** |
| Montaje en SO/pods | No (solo con extras) | **Sí** | No habitual |
| Renombrar carpeta | Copiar + borrar | Rápido (operación de archivos) | **Atómico, de metadatos** |
| Escala típica | Petabytes, miles de millones de objetos | Hasta decenas de TiB por share | Petabytes, analítica |
| Analítica (Spark) | Posible | No | **Es su caso de uso** |
| Mejor para | Contenido, respaldos, servir archivos | Lift-and-shift, volúmenes compartidos | Lagos de datos |

## Patrones que se repiten

| Patrón | Cadena | Cuándo |
|---|---|---|
| **Subida directa** | Navegador → (SAS) → Blob | Archivos grandes sin cargar tu API |
| **Subida + procesamiento** | Blob → Event Grid → Service Bus → Procesador | Escaneo, extracción, miniaturas |
| **Claim Check** | Productor → Blob + ticket en cola → Consumidor lee con identidad | Archivos grandes entre microservicios |
| **Lago medallion** | Fuentes → landing → bronze → silver → gold | Analítica con trazabilidad |
| **Volumen compartido** | Pods → PVC `ReadWriteMany` → Azure Files | Contenido compartido en AKS |

## Reglas transversales de seguridad
- **Identidad antes que claves:** `shared_access_key_enabled = false` donde se pueda (ojo con los servicios que montan Azure Files con clave).
- **SAS solo de delegación de usuario**, cortas, mínimas y con HTTPS.
- **Private Endpoint** con su zona DNS privada (para Data Lake: `dfs` **y** `blob`).
- **Soft delete + versionado/instantáneas + ciclo de vida** desde el primer día.
- **Nada de datos personales** en nombres de blob, tickets ni logs.

## Cómo se relacionan con otros capítulos
- [Red · Private Endpoint y DNS](../01-red/private-endpoint-dns/README.md): acceso privado a Storage.
- [IAM · Managed Identity](../02-iam/managed-identity/README.md): acceso sin claves.
- [Key Vault](../03-secretos/key-vault/README.md): claves administradas por ti (CMK).
- [Compute](../04-compute/README.md): quién sube, procesa y monta los datos.
- [Mensajería](../07-mensajeria/README.md): Service Bus, Event Grid, Event Hubs y Storage Queues como transporte de tickets y eventos.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus), ejemplos (CLI, Terraform, YAML/KQL/JSON según el servicio), troubleshooting, repaso y prompt de NotebookLM.
