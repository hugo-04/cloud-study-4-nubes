# Azure · PostgreSQL Flexible Server · Troubleshooting

Sigue el flujo: **¿llega al servidor? → ¿se autentica? → ¿tiene permisos? → ¿responde a tiempo? → ¿hay recursos?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `connection timed out` / `could not connect to server` | Red: DNS resuelve IP pública, firewall, NSG o subred sin ruta | `nslookup <servidor>.postgres.database.azure.com`; reglas de firewall | Zona DNS privada enlazada a la red; regla de IP (dev) o Private Endpoint |
| `no pg_hba.conf entry for host ... SSL off` | El cliente no usa TLS | `sslmode` | `sslmode=require` o `verify-full` |
| `password authentication failed for user "..."` | Token vencido o ámbito incorrecto; nombre del rol distinto a la identidad | Fecha del token; `pgaadauth_list_principals` | Token nuevo por conexión; ámbito `https://ossrdbms-aad.database.windows.net/.default`; nombre exacto del rol |
| `FATAL: role "..." does not exist` | El rol de Entra no se creó en el servidor | `\du` | `pgaadauth_create_principal('nombre', false, false)` |
| `FATAL: Microsoft Entra authentication ... password authentication is disabled` | Se intentó usuario/clave con password auth desactivado | Configuración de autenticación | Usar Entra ID |
| `permission denied for schema/table` | Faltan `GRANT` o `DEFAULT PRIVILEGES` tras nuevas migraciones | `\dp`, `\ddp` | `GRANT` + `ALTER DEFAULT PRIVILEGES FOR ROLE <dueña>` |
| `permission denied to create extension` | Extensión no permitida | Parámetro `azure.extensions` | Añadirla al parámetro y luego `CREATE EXTENSION` |
| `FATAL: remaining connection slots are reserved` / `too many connections` | `pods × pool` > `max_connections` | `pg_stat_activity` por aplicación | PgBouncer, pools pequeños, cerrar fugas |
| `prepared statement "S_1" already exists` / `does not exist` | PgBouncer modo transacción con sentencias preparadas del driver | Puerto 6432 en uso | `prepareThreshold=0` (JDBC) o versión de PgBouncer con soporte de protocolo |
| `LISTEN/NOTIFY` no llega, o bloqueo consultivo de sesión "se pierde" | PgBouncer en modo transacción | Puerto 6432 | Conexión directa (5432) para esas funciones; usar `pg_advisory_xact_lock` |
| `canceling statement due to statement timeout` | `statement_timeout` del rol/servidor | `SHOW statement_timeout` | Optimizar la consulta o subir el límite del rol que lo necesite |
| `deadlock detected` (`40P01`) | Orden distinto de acceso a filas | Registros del servidor | Orden consistente, transacciones cortas, reintento |
| `could not serialize access` (`40001`) | Aislamiento `SERIALIZABLE`/`REPEATABLE READ` con conflictos | SQLSTATE | Reintentar la transacción completa |
| Bloqueos largos | Transacciones abiertas o `idle in transaction` | `04-diagnostico.sql` §3 y §4 | Cerrar, timeouts, corregir el código |
| Consulta lenta tras migrar o actualizar | Estadísticas viejas, falta de índice, plan distinto | `EXPLAIN (ANALYZE, BUFFERS)` | `ANALYZE`, índices, `pg_stat_statements` |
| El disco se llena | Bloat, WAL retenido por una ranura de replicación, logs | `04-diagnostico.sql` §5 y §7; ranuras de replicación | Autovacuum, eliminar ranuras huérfanas, ampliar almacenamiento |
| El servidor entra en solo lectura / `storage full` | Almacenamiento al 100 % | Métrica `storage_percent` | Ampliar almacenamiento (autogrow); no se puede reducir |
| Retraso de réplica creciente | Réplica pequeña o carga de escritura alta, consultas largas en la réplica | `physical_replication_delay_in_seconds` | Dimensionar igual que el primario; limitar consultas largas |
| Corte de conexiones en mantenimiento/failover | Mantenimiento o conmutación de HA | Hora del evento | Reintentos y pool que valida |
| `no se puede cambiar a acceso privado` | El servidor se creó con acceso público | Configuración de red | Crear servidor nuevo con subred delegada y migrar |
| Extensión no disponible en la versión | No todas las extensiones existen en todas las versiones | Lista por versión | Cambiar de versión o alternativa |
| Costo alto | Cómputo sobredimensionado, HA en dev, réplicas olvidadas, almacenamiento inflado | Costos por recurso | Burstable + parar fuera de horario en dev; revisar réplicas |

## Secuencia recomendada
1. **Red y DNS:** `nslookup`, TLS, puerto (5432/6432).
2. **Identidad:** token vigente, rol existente.
3. **Permisos:** `GRANT` y privilegios por defecto.
4. **Conexiones:** `pg_stat_activity` y `max_connections`; PgBouncer.
5. **Consultas:** `pg_stat_statements`, `EXPLAIN`.
6. **Concurrencia:** bloqueos, deadlocks, transacciones largas.
7. **Almacenamiento:** bloat, WAL, ranuras.
8. **Aplicación:** pool, reintentos, timeouts.

SQL en [ejemplos/sql](ejemplos/sql/04-diagnostico.sql); KQL en [ejemplos/kql](ejemplos/kql/kql-postgresql.md); consola en [ejemplos/cli](ejemplos/cli/postgresql-flexible.sh).
