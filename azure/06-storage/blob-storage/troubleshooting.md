# Azure · Blob Storage · Troubleshooting

Mira el código de error de **Storage** (`x-ms-error-code`), no solo el HTTP. Con `StorageBlobLogs` en Log Analytics tienes `StatusCode`, `StatusText`, `AuthenticationType`, `CallerIpAddress`, `Uri` y `ServerLatencyMs`.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| **403** `AuthorizationPermissionMismatch` | La identidad no tiene rol de **datos** | Roles asignados (los *Contributor* no dan datos) | *Storage Blob Data Reader/Contributor* al alcance correcto; esperar propagación (minutos) |
| 403 `AuthorizationFailure` | Firewall de la cuenta o Private Endpoint | Redes de la cuenta; IP del cliente | Permitir la IP/VNet; DNS privado ([diagnóstico](../../01-red/diagnostico-conectividad/README.md)) |
| 403 `KeyBasedAuthenticationNotPermitted` | Clave compartida deshabilitada | Configuración de la cuenta | Usar Entra ID o SAS de delegación |
| 403 `AuthenticationFailed` (SAS) | Firma inválida, URL alterada, reloj | Parámetros `sv/se/sig` | Ver [SAS · troubleshooting](../sas-tokens/troubleshooting.md) |
| **404** `BlobNotFound` / `ContainerNotFound` | Nombre incorrecto (mayúsculas, prefijo), borrado | `list` con el prefijo; soft delete | Corregir nombre; restaurar si fue borrado |
| 404 `ResourceNotFound` con Private Endpoint | DNS apunta a otra IP o cuenta distinta | `nslookup <cuenta>.blob.core.windows.net` | Zona privada y enlace a la VNet |
| **409** `BlobAlreadyExists` / `LeaseIdMissing` | Condición `If-None-Match:*` o blob con lease | Cabeceras de la petición | Cambiar el nombre; usar el id del lease |
| **412** `ConditionNotMet` | ETag cambió (concurrencia optimista) | `If-Match` enviado | Releer, fusionar, reintentar |
| **416** `InvalidRange` | Rango fuera del tamaño del blob | `Content-Length` | Corregir el rango |
| **400** `InvalidBlobType` / `InvalidHeaderValue` | Falta `x-ms-blob-type`, versión de API no soportada | Cabeceras | `BlockBlob`; actualizar el SDK |
| **409** `BlobArchived` / `This operation is not permitted on an archived blob` | El blob está en Archive | Tier del blob | Rehidratar |
| 400 `BlobBeingRehydrated` | Rehidratación en curso | Estado de archivo del blob | Esperar |
| **503** `ServerBusy` / `500` `OperationTimedOut` | Límite de escala o tiempo de espera | Métricas de la cuenta; `ServerLatencyMs` | Reintentos con *backoff*; repartir nombres; menos concurrencia; dividir cuentas |
| Subidas lentas | Bloques pequeños, concurrencia 1, ancho de banda | Parámetros de transferencia | Bloques 8–100 MiB y concurrencia mayor; AzCopy |
| `OutOfMemoryError` al descargar | Contenido completo en memoria | Pila del error | *Streaming* o `downloadToFile` |
| Error de **CORS** en el navegador | Falta regla CORS del servicio Blob | Consola del navegador; preflight `OPTIONS` | Configurar CORS: origen, métodos, cabeceras, `ExposedHeaders` |
| Datos viejos al leer | Caché de CDN/navegador | `Cache-Control`, ETag | Ajustar caché; purgar |
| No puedo borrar/modificar | Inmutabilidad o *legal hold* | Políticas del contenedor | Esperar la retención; no hay atajo |
| Factura alta | Operaciones, salida o Archive/Cool mal usados | Cost Analysis por medidor | Ciclo de vida; tier adecuado; CDN; evitar listados masivos |
| Evento `BlobCreated` no llegó | Suscripción mal filtrada o aún sin confirmar bloques | Ver [eventos](../eventos-blob/troubleshooting.md) | Revisar filtro y entrega |
| `Defender` alerta de malware | Archivo subido malicioso | Alertas | Cuarentena y borrado; análisis previo al procesamiento |

## Consultas KQL útiles
```kusto
StorageBlobLogs
| where TimeGenerated > ago(1h) and StatusCode >= 400
| summarize n = count() by StatusCode, StatusText, OperationName, AuthenticationType
| order by n desc
```
```kusto
StorageBlobLogs
| where TimeGenerated > ago(24h)
| summarize ms_p95 = percentile(ServerLatencyMs, 95), peticiones = count() by OperationName
| order by peticiones desc
```

## Secuencia recomendada
1. ¿HTTP 4xx o 5xx? → 4xx: autorización/red/nombre; 5xx: límites y reintentos.
2. `AuthenticationType` en el log: ¿OAuth, SAS o clave?
3. DNS y red: ¿resuelve a la IP privada esperada?
4. ¿Rol de **datos** asignado al principal correcto?
5. Revisa límites de escala y la forma de los nombres.
