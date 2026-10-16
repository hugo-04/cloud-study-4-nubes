# Azure · SAS tokens · Troubleshooting

La respuesta de error de Storage trae `x-ms-error-code` y en el cuerpo `AuthenticationErrorDetail` (qué parte de la firma no cuadró). Con `StorageBlobLogs` filtra `AuthenticationType == "SAS"`.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| **403** `AuthenticationFailed` ("Signature did not match") | URL modificada, doble codificación, parámetros reordenados, clave rotada, versión (`sv`) | Compara la URL con la original; mira `AuthenticationErrorDetail` (string-to-sign esperado) | Regenerar; no tocar parámetros; no volver a codificar `%` |
| 403 `AuthenticationFailed` "Server failed to authenticate… Signed expiry time" | `se` en el pasado o reloj | Compara `se` con la hora UTC | Generar de nuevo; sincronizar relojes |
| 403 `AuthenticationFailed` "Signature not valid in the specified time frame" | `st` en el futuro (desfase) | `st` vs hora UTC | Quitar `st` o poner −5 min |
| 403 `AuthorizationPermissionMismatch` / "not authorized to perform this operation using this permission" | `sp` no incluye el permiso | Parámetro `sp` | Generar con `r`, `cw`, `w`, etc. según la operación |
| 403 `AuthorizationSourceIPMismatch` | `sip` no coincide con la IP del cliente | `CallerIpAddress` en el log | Ajustar rango o quitar `sip` (NAT/móviles) |
| 403 `AuthorizationProtocolMismatch` | `spr=https` y se usó HTTP | URL | Usar HTTPS |
| 403 `AuthorizationFailure` con SAS válida | Firewall de la cuenta/Private Endpoint | Redes de la cuenta | Permitir la IP/VNet; DNS privado |
| 403 de una SAS de delegación que "ayer funcionaba" | Firmante sin rol, clave de delegación revocada/vencida | Roles del firmante; `ske` | Restaurar rol; emitir con clave nueva |
| 403 `KeyBasedAuthenticationNotPermitted` al emitir SAS de servicio/cuenta | Clave compartida deshabilitada | Configuración de la cuenta | Usar SAS de delegación |
| `generateUserDelegationKey` falla (403) | Falta *Storage Blob Delegator* | Roles del firmante a nivel de cuenta | Asignarlo en la cuenta (no en el contenedor) |
| 403 al usar `sr=c` pero el recurso es un blob | `sr` incorrecto | Parámetro `sr` | `sr=b` para blobs |
| **400** `MissingRequiredHeader` / "x-ms-blob-type" | PUT sin cabecera | Cabeceras | Agregar `x-ms-blob-type: BlockBlob` |
| 400 `InvalidQueryParameterValue` | Formato de fecha, `sp` inválido para el recurso | Valores de la URL | Formato `YYYY-MM-DDThh:mm:ssZ` y permisos válidos |
| **409** `BlobAlreadyExists` | `If-None-Match:*` o intento de crear existente | Cabeceras | Otro nombre (UUID) |
| **CORS** (navegador) | Falta regla en el servicio | Consola; preflight `OPTIONS` | Regla CORS: origen exacto, métodos `PUT, GET, OPTIONS`, cabeceras `x-ms-*`, `content-type` |
| `CORS` solo falla en `PUT` de bloque | Cabeceras `x-ms-blob-type`/`x-ms-version` no permitidas | `Access-Control-Request-Headers` | `allowed_headers = *` o la lista exacta |
| Timeout desde casa | Cuenta solo privada | `nslookup`, `curl -v` | Endpoint público de subida o VPN |
| 404 `BlobNotFound` con SAS válida | Nombre/prefijo/versión diferente | Lista del contenedor | Corregir el nombre; revisar soft delete |
| Descarga con nombre feo | Falta `rscd` | Cabecera `Content-Disposition` | Agregar `rscd` |
| Subió, pero la app no se entera | No se confirmó / no llegó el evento | Eventos y confirmación | [Eventos de blob](../eventos-blob/README.md) o `POST confirmar` |
| `429`/`503` al emitir miles de SAS | Se pide la clave de delegación en cada petición | Llamadas a `getUserDelegationKey` | Cachear la clave con margen |

## Cómo depurar una firma
1. Copia la URL **tal cual** de la respuesta de tu API (sin pasar por herramientas que re-codifiquen).
2. Revisa en el cuerpo del 403 la `StringToSign` que esperaba Storage y compárala con lo que calculó el SDK (si usas firma manual).
3. Comprueba fechas en **UTC** y el formato.
4. Prueba con `curl -v` desde la misma red que el cliente real.
5. Mira `StorageBlobLogs`: `AuthenticationType`, `StatusText`, `CallerIpAddress`.

```kusto
StorageBlobLogs
| where TimeGenerated > ago(1h) and AuthenticationType == "SAS" and StatusCode >= 400
| summarize n = count() by StatusText, OperationName, CallerIpAddress
| order by n desc
```
