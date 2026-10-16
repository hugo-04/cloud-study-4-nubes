# Azure · Azure SQL Database · Troubleshooting

Sigue el flujo: **¿llega a la base? → ¿se autentica? → ¿tiene permisos? → ¿responde a tiempo? → ¿hay recursos?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Cannot open server ... requested by the login. Client with IP address ... is not allowed` (error 40615) | Firewall del servidor sin la IP o acceso público cerrado | Reglas de firewall; `publicNetworkAccess` | Conectar por Private Endpoint o añadir la IP (solo desarrollo) |
| Timeout al conectar desde la red privada | Resolución DNS a IP pública, Private Endpoint sin aprobar, directiva Redirect sin puertos 11000–11999 | `nslookup <servidor>.database.windows.net` debe dar IP privada | Zona `privatelink.database.windows.net` enlazada; Private Endpoint aprobado |
| `Login failed for user '<token-identified principal>'` (18456) | La identidad no existe como usuario en **esa base** | `sys.database_principals` | `CREATE USER [identidad] FROM EXTERNAL PROVIDER` y roles |
| `Login failed for user ''` con identidad administrada | `msiClientId` incorrecto o identidad no asignada al recurso | Identidad del App Service/pod | Asignar la identidad; poner el `clientId` correcto |
| `Login failed. Cannot authenticate using Azure AD password`/token | Servidor solo-Entra y la cadena usa usuario/clave | Cadena de conexión | `authentication=ActiveDirectoryManagedIdentity` |
| `The server principal is not able to access the database ... under the current security context` | Usuario en master pero no en la base, o la base no existe | Base y usuario | Crear usuario contenido en la base |
| `SELECT permission was denied on object ...` | Falta rol o `GRANT` | Roles del usuario | `db_datareader` o `GRANT` específico |
| Error 40613 `Database ... is not currently available` | Reconfiguración, failover, escalado o base pausada (serverless) | Estado de la base; hora del evento | Reintento con retroceso; revisar mantenimiento |
| Error 40501 / 10928 / 10929 `resource limit` | Alcanzaste límite de workers/sesiones/E/S | `sys.dm_db_resource_stats` | Reducir pool/concurrencia; optimizar consulta; escalar |
| Error 1205 `deadlock victim` | Orden de acceso distinto entre transacciones | Registros `Deadlocks` | Orden consistente; transacciones cortas; reintentar |
| Consultas lentas de repente | Plan regresado, estadísticas, falta de índice | Query Store, `missing_index` | Forzar plan; crear índice; actualizar estadísticas |
| Bloqueos largos | Transacción abierta (a veces durante una llamada HTTP) | `03-diagnostico.sql` §3 y §4 | Transacciones cortas; arreglar el código |
| `Transaction (Process ID) was deadlocked ...` en JPA | Lo mismo que 1205 envuelto por Spring | Excepción `CannotAcquireLockException` | Reintento + orden |
| Primera conexión tarda decenas de segundos | Base serverless pausada | `status = Paused` | Aumentar timeouts y reintentos; usar provisionado en prod |
| `Pool exhausted` / `Connection is not available` (Hikari) | Pool pequeño con consultas lentas, transacciones largas, fugas | `leak-detection-threshold`, métricas del pool | Corregir consultas lentas y fugas; no solo ampliar el pool |
| Conexiones agotadas en la base | `pods × pool` demasiado alto | `sys.dm_exec_sessions` por programa | Pool por pod más bajo; PgBouncer-equivalente no existe: ajusta tamaños |
| `Conversion failed when converting ...` | Tipos incompatibles en parámetros | Tipos de columnas vs parámetros | Parámetros tipados; `sendStringParametersAsUnicode` según el caso |
| Índices que "no se usan" con `nvarchar` | Parámetro Java `String` enviado como `nvarchar` sobre columna `varchar` → conversión implícita | Plan de ejecución | Alinear tipos (`sendStringParametersAsUnicode=false` si la columna es varchar) |
| `Msg 3930 / The current transaction cannot be committed` | Error dentro de transacción con XACT_ABORT | Mensajes previos | Revertir y reintentar la operación completa |
| Restauración "no aparece" | Se restaura como otra base con otro nombre | Lista de bases | Buscar `--dest-name` |
| Costo alto | Cómputo sobredimensionado, serverless sin pausa, copias redundantes geo | Costos por recurso | Ajustar vCores; reservas; revisar redundancia |
| Auditoría vacía | Falta diagnóstico de `master` hacia Log Analytics | Configuración de diagnóstico | Activar `SQLSecurityAuditEvents` |

## Secuencia recomendada
1. **Red y DNS:** `nslookup`, Private Endpoint, directiva de conexión.
2. **Identidad:** token correcto, usuario contenido en la base.
3. **Permisos:** roles y `GRANT`.
4. **Recursos:** `dm_db_resource_stats` (CPU, E/S, workers, sesiones).
5. **Consultas:** Query Store, planes, índices faltantes.
6. **Concurrencia:** bloqueos, deadlocks, transacciones largas.
7. **Aplicación:** pool, reintentos, timeouts.

SQL en [ejemplos/sql](ejemplos/sql/03-diagnostico.sql); KQL en [ejemplos/kql](ejemplos/kql/kql-azure-sql.md); consola en [ejemplos/cli](ejemplos/cli/azure-sql.sh).
