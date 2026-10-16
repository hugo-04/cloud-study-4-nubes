# Azure · Redis · Troubleshooting

Sigue el flujo: **¿llega a la instancia (DNS, red, puerto 10000, TLS)? → ¿se autentica (Entra ID, token vigente, object id)? → ¿qué error devuelve Redis? → ¿hay memoria y CPU (`serverLoad`)? → ¿las claves están bien diseñadas (slots, tamaño, TTL)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Tiempo de espera al conectar | DNS resuelve a IP pública con acceso público cerrado, NSG/UDR, puerto 10000 bloqueado | `nslookup <host>.redis.azure.net`; `Test-NetConnection`/`nc -vz <host> 10000` desde el pod | Zona DNS privada `privatelink.redis.azure.net` enlazada a la red; abrir 10000 (y el rango 85XX en OSSCluster) |
| Fallo de TLS / `SSLHandshakeException` | Cliente sin TLS, versión < TLS 1.2, certificado no confiable en la imagen | Mensaje del error; `openssl s_client -connect <host>:10000` | `useSsl()`; actualizar almacén de certificados; no usar `Plaintext` |
| `NOAUTH` / `WRONGPASS` / `invalid username-password pair` | Usuario no es el **object id**, token de otro tenant o caducado, identidad sin asignar en la política de acceso | `REDConnectionEvents` (autenticación fallida); asignaciones de política de acceso de la base de datos (portal, Terraform o `az redisenterprise database access-policy-assignment -h`; *verifica el comando vigente*) | Usuario = object id de la identidad; asignar la política de acceso; ámbito `https://redis.azure.com/.default` |
| Errores periódicos con el ritmo de caducidad del token (~1 h) | El token no se renueva ni se reautentica | Marcas de tiempo de los errores; `ConnectionEvents` | `redis-authx-entraid` con `ReauthenticateBehavior.ON_NEW_CREDENTIALS` |
| `MOVED` / `ASK` en cada operación | Cliente **sin soporte de clúster** contra política OSSCluster | `INFO cluster`; tipo de cliente | Cliente de clúster (Lettuce `RedisClusterClient`) o recrear con EnterpriseCluster |
| `CROSSSLOT Keys in request don't hash to the same slot` | Comando multiclave (`MGET`, `MULTI`, Lua con varias claves) con slots distintos | `CLUSTER KEYSLOT <clave>` para cada clave | Etiquetas de hash `{...}`; operaciones por clave; scripts con una sola clave |
| `OOM command not allowed when used memory > 'maxmemory'` | Memoria llena y `NoEviction`, o política `Volatile*` con claves sin TTL | `usedmemorypercentage`; `INFO memory`; `TTL` de claves | Poner TTL, cambiar a `AllKeysLRU` si es caché, subir de tamaño, borrar claves grandes |
| `evictedkeys` crece / la tasa de aciertos baja | Memoria insuficiente para el conjunto de trabajo | `evictedkeys`, `cachehits`/`cachemisses` | Aumentar SKU, reducir tamaño de valores, TTL más cortos |
| `serverLoad` cerca de 100 % | Comandos O(N), claves grandes/calientes, demasiadas operaciones | `SLOWLOG GET`; `serverLoad`, `operationsPerSecond`; `redis-cli --bigkeys`/`--hotkeys` | Eliminar `KEYS`, dividir claves, escalar SKU (Compute Optimized), pipelining |
| Latencia alta de forma intermitente | Claves grandes, comandos lentos, mantenimiento/conmutación, red entre regiones | `cacheLatency`, `SLOWLOG`, eventos de mantenimiento | Corregir modelo; reconexión y reintentos; mismo región cliente–Redis |
| Conexiones cerradas durante mantenimiento | Conmutación de nodos (normal en HA) | `ConnectionEvents` cerca de la hora de mantenimiento | Reconexión automática, reintentos con espera, tiempos cortos; probar el escenario |
| Muchas conexiones nuevas por segundo | Una conexión por solicitud, pool mal configurado | `connectedclients`; `REDConnectionEvents` | Conexión compartida (Lettuce) / pool acotado |
| `ERR unknown command` / comando bloqueado | Comando administrativo bloqueado (`BGSAVE`, `SAVE`, `REPLICAOF`, `SHUTDOWN`, `FLUSHALL` en geo) | Mensaje del error | Usar las operaciones de Azure (exportar, vaciar) en lugar del comando |
| `READONLY` / escrituras fallan | Conmutación en curso o instancia sin HA reiniciándose | `ConnectionEvents`, estado de la instancia | Reintentar; en producción mantener HA |
| `SELECT 1` falla | Solo hay **una base de datos** por instancia | Mensaje del error | Separar por prefijos de clave |
| Script Lua falla con `Script attempted to access a non-declared key` | Claves usadas en el script no pasadas en `KEYS` | Revisar el script | Pasar todas las claves en `KEYS[]`; en clúster, del mismo slot |
| El bloqueo lo toman dos réplicas | TTL vencido durante el trabajo; liberación sin token | Registros con tiempos | Token + Lua; TTL con margen; proteger el recurso final (restricción única) |
| Claves que "no vencen" | Escritura con `SET` sin `EX`, `PERSIST`, o comando sobrescribe el TTL | `TTL <clave>` (-1 = sin TTL) | `SET ... EX`; revisar código que reescribe claves; barrido con `SCAN` |
| Lecturas con datos viejos | Invalidación omitida; TTL largo; caché local L1 | Revisar flujo de escritura | Invalidar tras escribir; TTL más corto; Pub/Sub para L1 |
| Geo-replicación "no saludable" | Memoria llena en una instancia, clave enorme, región caída | Métrica `geoReplicationHealthy` | Liberar memoria; dividir claves; *force unlink* en caída regional y recrear |
| No puedes añadir instancia existente al grupo geo | Solo se configura al crear (enlazar una existente borra sus datos) | Documentación de geo-replicación | Crear la instancia ya dentro del grupo; planificar |
| Cambio de política de clúster rechazado | No se puede cambiar OSS ↔ Enterprise | Mensaje del error | Crear instancia nueva y migrar |
| Pub/Sub no entrega | Suscriptor desconectado en ese instante; canal distinto | Registros del suscriptor | Pub/Sub es efímero: usa Streams o un broker para entrega garantizada |
| Stream sin consumir / `PEL` crece | Consumidores caídos, sin `XACK`, errores en el procesamiento | `XPENDING`, `XINFO GROUPS` | Reclamar pendientes (`XCLAIM`/`XAUTOCLAIM`), idempotencia, recorte con `MAXLEN` |
| Costo inesperado | SKU sobredimensionada, instancias de geo-replicación, entorno de desarrollo siempre encendido | Costos por recurso y métricas de memoria | Ajustar SKU, apagar desarrollo, `Memory Optimized` para pruebas, revisar necesidad de geo |

## Comandos de diagnóstico útiles (con permiso)
Ver [redis-cli](ejemplos/redis-cli/comandos.md): `INFO`, `SLOWLOG GET`, `MEMORY USAGE <clave>`, `OBJECT ENCODING`, `CLUSTER KEYSLOT`, `SCAN` con `--bigkeys`. Consultas KQL de apoyo en [kql-redis.md](ejemplos/kql/kql-redis.md).

## Secuencia recomendada
1. **Conectividad:** DNS, ruta, puerto 10000, TLS, política de clúster y tipo de cliente.
2. **Identidad:** object id, ámbito del token, asignación de la política de acceso, renovación del token.
3. **Error exacto de Redis:** `OOM`, `MOVED`, `CROSSSLOT`, `NOAUTH`, `READONLY`.
4. **Memoria y CPU:** `usedmemorypercentage`, `evictedkeys`, `serverLoad`, `SLOWLOG`.
5. **Diseño de claves:** tamaño, TTL, slots, claves calientes.
6. **Conexiones:** `connectedclients`, conexiones nuevas, reconexión.
7. **Aplicación:** tiempos de espera, degradación a la base, disyuntor, reintentos.
8. **Replicación geográfica:** `geoReplicationHealthy`, memoria libre, claves enormes.
