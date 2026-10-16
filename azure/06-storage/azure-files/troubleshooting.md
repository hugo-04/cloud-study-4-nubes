# Azure · Azure Files · Troubleshooting

El camino de una operación sobre Azure Files: **nombre (DNS) → red (445/2049, Private Endpoint, firewall) → autenticación (identidad/clave) → autorización (RBAC de share + ACL) → rendimiento (cuota/IOPS)**. Descarta en ese orden.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `mount error(115)` / timeout al montar | Puerto 445 bloqueado, firewall de la cuenta, DNS a IP equivocada | `nc -zv <cuenta>.file.core.windows.net 445`; `nslookup` | VPN/Private Endpoint; reglas de red; DNS privado |
| `mount error(13): Permission denied` | Clave mala, rol de share ausente, ticket Kerberos inválido | Roles del usuario en el share; `klist` | Dar rol *SMB Share Contributor*; renovar ticket; clave correcta |
| `mount error(2)` / "No such file or directory" | Nombre de share o cuenta incorrectos | `az storage share-rm list` | Corregir nombre |
| `mount error(95)` o cifrado no soportado | Cliente con kernel viejo o SMB sin cifrado | Versión del kernel; `vers=` | Actualizar el cliente; `vers=3.1.1` |
| Acceso con clave falla con `403`/"key based authentication is not permitted" | `shared_access_key_enabled = false` | Propiedad de la cuenta | Usar identidad; o separar cuenta para clientes que solo usan clave |
| SDK Java: `403 AuthorizationFailure` / `AuthorizationPermissionMismatch` | Falta *Storage File Data Privileged …* o no se declaró `ShareTokenIntent.BACKUP` | Roles; configuración del cliente | Rol y `shareTokenIntent(BACKUP)` |
| SDK Java: `ResourceAlreadyExists` al crear carpetas | Carrera entre instancias | Excepción 409 | Tratarla como éxito |
| SDK Java: archivo > 4 MiB falla con `upload` | `upload` limita el tamaño por llamada | Mensaje de error | `uploadFromFile` o subir por rangos |
| NFS: "access denied by server" | Cliente fuera de la red permitida o `secure transfer` activo | Reglas de red; `https_traffic_only` | Private Endpoint/Service Endpoint; cuenta NFS aparte |
| Pod de AKS no monta: `mount failed` / `Pending` | Nodo sin salida al 445, NSG, StorageClass mal, cuenta con firewall | `kubectl describe pod/pvc`; eventos | Permitir subred de AKS en la cuenta; revisar clase y secreto |
| PVC `Pending` | StorageClass inexistente o cuota insuficiente | `kubectl describe pvc` | Corregir clase; cuota de la suscripción |
| Muy lento al listar o abrir muchos archivos | Estándar (HDD), directorio enorme, latencia de red | Métricas de latencia; tamaño del directorio | Premium; particionar; cache de montaje (`actimeo`) |
| Rendimiento se estanca en un valor | Límite de IOPS/ancho de banda por cuota (premium) | Métrica de *throttling* / transacciones | Aumentar cuota; SMB Multichannel; repartir shares |
| Errores `503 ServerBusy` | Límite de la cuenta/share superado | Métricas de transacciones | Reintentos con retroceso; repartir carga |
| Archivo "bloqueado" por otro cliente | Bloqueos SMB/leases de otro proceso | Lista de handles abiertos | Cerrar handles; diseñar sin bloqueos compartidos |
| Cambios de otro cliente no se ven | Caché de atributos del cliente (`actimeo`) | Opciones de montaje | Bajar `actimeo`; usar `cache=none` solo si es necesario |
| `WatchService` no avisa | No funciona sobre SMB/NFS remotos | — | Sondeo |
| Borrado accidental | Sin *soft delete*/instantáneas | Papelera del share | Restaurar share/archivo; activar protección |
| Cuenta con Private Endpoint pero sale por Internet | DNS local sin reenviador | `nslookup` desde el cliente | Reenviador a `privatelink.file.core.windows.net` |
| Backup del share falla | Cuenta sin permitir servicios de confianza | Configuración de red | `bypass = AzureServices`; revisar compatibilidad |
| Costo sube sin motivo | Cuota premium sobredimensionada, instantáneas con muchos cambios | Cuota vs uso; tamaño de instantáneas | Ajustar cuota; retención de instantáneas |

## Secuencia recomendada
1. `nslookup` y `nc` al 445 desde **el mismo equipo** que falla.
2. ¿Rol de share y ACL correctos para **esa** identidad?
3. ¿Método de autenticación coherente con la configuración de la cuenta (claves desactivadas, Kerberos habilitado)?
4. ¿Métricas de latencia, transacciones y *throttling*?
5. ¿Estructura de carpetas razonable y nivel adecuado?

## KQL (con diagnóstico de la cuenta hacia Log Analytics)
```kusto
StorageFileLogs
| where TimeGenerated > ago(1h) and StatusCode !startswith "2"
| summarize errores = count() by StatusCode, StatusText, OperationName, AuthenticationType
| order by errores desc
```
```kusto
StorageFileLogs
| where TimeGenerated > ago(24h) and OperationName in ("Create", "Write", "Read", "Delete")
| summarize operaciones = count(), p95_ms = percentile(DurationMs, 95) by bin(TimeGenerated, 1h), OperationName
| render timechart
```
*Verifica nombres de columnas en la doc vigente.*
