# AWS · ElastiCache · Troubleshooting

Orden: **¿conecta (red, grupo de seguridad, VPC)? → ¿TLS y autenticación correctas? → ¿endpoint correcto (primario / lectura / configuración)? → ¿memoria y expulsiones? → ¿comandos lentos o claves enormes? → ¿conexiones? → ¿failover y DNS?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Timeout al conectar | Grupo de seguridad sin el origen; subredes/rutas; intentas conectar desde fuera de la VPC | Reglas del SG (puerto 6379); desde un host de la VPC: `redis-cli -h host --tls ping` | Permitir el SG de la app; ejecutar desde la VPC (o túnel); no hay IP pública |
| `SSL/TLS handshake` o conexión cerrada al instante | Cliente sin TLS contra grupo con cifrado en tránsito (o al revés) | Configuración del grupo (`TransitEncryptionEnabled`) | `rediss://` / `ssl.enabled=true` |
| `NOAUTH Authentication required` / `WRONGPASS` | Falta usuario/contraseña o son incorrectos; token vencido | `ACL WHOAMI`; usuario y grupo de usuarios del grupo de replicación | Credenciales desde Secrets Manager; nombre de usuario correcto |
| `NOPERM this user has no permissions` | ACL del usuario no permite el comando o la clave | `ACL GETUSER` | Ajustar la cadena de acceso (prefijo y categorías) |
| `READONLY You can't write against a read only replica` | Escribes en réplica o el DNS aún apunta al primario viejo tras failover | Endpoint usado; `INFO replication` | Endpoint primario para escribir; DNS corto en la JVM; reintento |
| `MOVED` / `ASK` | Cliente sin modo clúster contra un clúster | Modo del grupo | Cliente de clúster y endpoint de configuración |
| `CROSSSLOT Keys in request don't hash to the same slot` | Operación multi-clave entre slots distintos | Claves involucradas | Etiquetas de hash `{...}` |
| `OOM command not allowed when used memory > 'maxmemory'` | Memoria llena con política `noeviction` | `INFO memory`, parámetro `maxmemory-policy` | TTL; política `allkeys-lru` para caché; nodo mayor o más shards |
| Muchas expulsiones (`Evictions`) | Memoria insuficiente o claves sin TTL útil | Métrica `Evictions`, `DatabaseMemoryUsagePercentage` | Menos datos/TTL; más memoria; revisar tamaño de valores |
| Latencia con picos | Comandos lentos (`KEYS`, `SMEMBERS` enorme), claves gigantes, CPU alta | `SLOWLOG GET 20`, `EngineCPUUtilization`, `redis-cli --bigkeys` (en réplica) | Quitar comandos O(N); dividir claves; `SCAN` |
| `Connection reset` / agotamiento de conexiones | Cliente nuevo por petición; fugas | `CurrConnections`, `CLIENT LIST` | Un cliente por proceso; pool acotado |
| La app se cuelga durante un corte | Comandos acumulados mientras reconecta | Comportamiento del cliente | Rechazar comandos al desconectar, tiempo de espera corto, caché opcional |
| Lecturas desactualizadas | Retraso de réplica | `ReplicationLag` | Leer del primario cuando importa la frescura |
| Todo falla tras un reinicio | Sin copias o datos efímeros asumidos como durables | Copias/retención | La caché se reconstruye desde el origen; no es fuente de verdad |
