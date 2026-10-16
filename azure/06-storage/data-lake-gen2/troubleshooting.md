# Azure · Data Lake Gen2 · Troubleshooting

Un fallo de Data Lake casi siempre es de uno de estos cinco niveles: **endpoint/DNS → red → autenticación → autorización (RBAC + ACL) → formato/rendimiento**.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `403 AuthorizationPermissionMismatch` | Sin rol de datos y sin ACL suficientes | Roles de la identidad; `az storage fs access show` | Añadir ACL a un **grupo** (con `x` en toda la ruta) o el rol de datos justo |
| 403 solo en subcarpetas | Falta `--x` en un directorio padre | ACL de cada nivel hasta la raíz | Conceder `x` en los padres |
| Funciona para unos usuarios y no para otros | Unos tienen rol de datos (salta ACL), otros dependen de ACL | Asignaciones de roles | Unificar el modelo: ACL por grupos y sin roles amplios |
| Lo nuevo hereda permisos, lo viejo no | ACL por defecto no son retroactivas | ACL de un archivo antiguo | `update-recursive` sobre el árbol |
| Una operación recursiva de ACL deja fallos | Rutas con conflictos, permisos del ejecutor insuficientes | Contadores y entradas con error | Reintentar con el token de continuación; el ejecutor debe ser *Data Owner* |
| `This request is not authorized to perform this operation` desde la red | Firewall/Private Endpoint no incluye el origen | Reglas de red; endpoint usado (`dfs`) | Private Endpoint de `dfs` **y** `blob`; DNS privado |
| Spark/Databricks no conecta (`UnknownHostException`) | DNS no resuelve `*.dfs.core.windows.net` a la IP privada | `nslookup` desde el clúster | Zona `privatelink.dfs.core.windows.net` enlazada a la VNet |
| `OAuth` falla en ABFS (`401`/`403` al token) | Proveedor mal configurado, tenant o client id erróneos | Logs del driver; claves `fs.azure.account.*` | Revisar [abfs-config.properties](ejemplos/spark/abfs-config.properties) |
| Sin acceso por clave | `shared_access_key_enabled=false` | Propiedad de la cuenta | Usar identidad o SAS de delegación |
| `HierarchicalNamespaceNotEnabled` / operación no soportada | La cuenta no tiene HNS y usas API `dfs` | Propiedad `isHnsEnabled` | Usar cuenta con HNS |
| Función de Blob no disponible (versionado/instantáneas) | No soportada con HNS | Tabla de compatibilidad vigente | Alternativas (soft delete, réplicas, reproceso desde bronce) |
| Lectura muy lenta, muchos archivos pequeños | Problema de archivos pequeños | Cantidad y tamaño de archivos | Compactar a Parquet/Delta; micro-lotes |
| Lectores ven archivos a medias | Se escribió directo en la ruta final | Momento de creación vs flush | `_tmp/` + `rename` atómico |
| Datos "no aparecen" tras `append` | Falta el `flush` | Longitud del archivo | `flush(posición)` al final |
| Costo de transacciones alto | Appends diminutos, listados masivos, ACL recursivas repetidas | Métricas de transacciones | Acumular en trozos; evitar listados; planificar ACL |
| Migración a HNS falla en validación | Funciones incompatibles activas | Informe de validación | Desactivar/ajustar funciones y reintentar |
| SFTP no conecta | SFTP no habilitado, usuario local sin llave, red | Estado del SFTP; reglas de red | Habilitar SFTP y local user; permitir IP |
| Eventos de renombrado inesperados | Operaciones de directorio generan eventos propios | Tipos de evento recibidos | Filtrar por tipo y `api` |

## Secuencia recomendada
1. ¿Qué endpoint usa el cliente (`dfs` o `blob`) y a qué IP resuelve?
2. ¿La cuenta tiene HNS y la identidad llega por red?
3. ¿Qué rol de datos tiene la identidad? (si tiene uno amplio, las ACL no importan)
4. Si no hay rol: ¿ACL con `x` en toda la ruta y el permiso final en el objetivo?
5. ¿Es un problema de formato (archivos pequeños, sin `flush`, escritura directa)?

## KQL (diagnóstico de la cuenta hacia Log Analytics)
```kusto
StorageBlobLogs
| where TimeGenerated > ago(1h) and StatusCode == 403
| summarize rechazos = count() by CallerIpAddress, AuthenticationType, OperationName, Uri
| order by rechazos desc
```
```kusto
StorageBlobLogs
| where TimeGenerated > ago(24h) and OperationName in ("CreateFile", "AppendFile", "FlushFile", "RenamePath", "DeletePath")
| summarize operaciones = count() by OperationName, bin(TimeGenerated, 1h)
| render timechart
```
*Verifica nombres de columnas y operaciones en la doc vigente.*
