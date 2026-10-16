# redis-cli y estructuras de datos (ejemplos con ModaLima y Café Andino)

## 1. Conectar con Entra ID y TLS
```bash
HOST="amr-modalima-demo01.eastus2.redis.azure.net"        # copia el nombre exacto de la página Overview
TOKEN=$(az account get-access-token --scope https://redis.azure.com/.default --query accessToken -o tsv)
OID=$(az ad signed-in-user show --query id -o tsv)         # tu object id (para una identidad administrada: su object id)

# -c: seguir redirecciones (política OSSCluster). Con EnterpriseCluster no hace falta.
redis-cli -h "$HOST" -p 10000 --tls --user "$OID" --pass "$TOKEN" -c
PING
```
El token caduca: vuelve a pedirlo antes de que expire (en aplicaciones lo hace la librería, ver [uso en Java](../../uso-en-java.md)).

## 2. Cadenas (caché, banderas, bloqueos, idempotencia)
```text
SET catalogo:v1:sku:POL-ROJO-M "{\"precio\":8990}" EX 300          # caché con vencimiento de 5 min
GET catalogo:v1:sku:POL-ROJO-M
TTL catalogo:v1:sku:POL-ROJO-M                                       # segundos restantes (-1 sin TTL, -2 no existe)
SET idem:pedido:abc123 "PED-2026-000123" NX EX 86400                 # solo si no existe (idempotencia 24 h) → OK o (nil)
SET bloqueo:reporte-diario "pod-7" NX PX 30000                       # bloqueo simple de 30 s
INCR visitas:pagina:inicio                                           # contador atómico
INCRBY stock:POL-ROJO-M -2                                           # descontar (ojo: no valida mínimo; usa Lua para eso)
```

## 3. Hashes (objetos pequeños)
```text
HSET sesion:u-77 usuario "ana" rol "cliente" ultimaVisita "2026-10-16T14:05:00Z"
HGETALL sesion:u-77
HINCRBY sesion:u-77 paginasVistas 1
EXPIRE sesion:u-77 1800                                              # sesión de 30 min
```

## 4. Conjuntos y conjuntos ordenados
```text
SADD clientes:vip C-001 C-002
SISMEMBER clientes:vip C-001
ZADD ranking:ventas:2026-10 3598 "POL-ROJO-M" 1200 "JEA-AZUL-32"      # puntaje → miembro
ZREVRANGE ranking:ventas:2026-10 0 9 WITHSCORES                      # top 10
ZINCRBY ranking:ventas:2026-10 1 "POL-ROJO-M"
```

## 5. Listas y Streams (colas ligeras)
```text
LPUSH cola:correos "{\"pedido\":\"PED-1\"}"
BRPOP cola:correos 5                                                 # consumir bloqueando 5 s (se pierde si el consumidor cae)

# Streams con grupos de consumidores (mejor que listas: reintento y confirmación)
XADD pedidos:eventos * tipo PedidoPagado pedidoId PED-1
XGROUP CREATE pedidos:eventos facturacion $ MKSTREAM
XREADGROUP GROUP facturacion pod-1 COUNT 10 BLOCK 5000 STREAMS pedidos:eventos >
XACK pedidos:eventos facturacion 1697466300000-0
XPENDING pedidos:eventos facturacion                                 # mensajes sin confirmar
```

## 6. Pub/Sub (efímero: sin historial)
```text
SUBSCRIBE canal:stock
PUBLISH canal:stock "POL-ROJO-M agotado"
```

## 7. Estructuras probabilísticas y geográficas
```text
PFADD visitantes:hoy u-1 u-2 u-3                                     # HyperLogLog: conteo aproximado de únicos
PFCOUNT visitantes:hoy
GEOADD tiendas:lima -77.0311 -12.1219 "Miraflores" -77.0428 -12.0464 "Centro"
GEOSEARCH tiendas:lima FROMLONLAT -77.03 -12.10 BYRADIUS 5 km ASC
```

## 8. Módulos (si los habilitaste al crear)
```text
JSON.SET producto:POL-ROJO-M $ "{\"nombre\":\"Polo\",\"colores\":[\"rojo\",\"azul\"],\"precio\":8990}"
JSON.GET producto:POL-ROJO-M $.colores
FT.CREATE idx:productos ON JSON PREFIX 1 producto: SCHEMA $.nombre AS nombre TEXT $.precio AS precio NUMERIC
FT.SEARCH idx:productos "@nombre:polo"
```
RediSearch exige política de clúster **Enterprise** y expulsión **NoEviction**.

## 9. Etiquetas de hash (`{}`) para varias claves en el mismo slot
En clúster, las operaciones con varias claves exigen el mismo *slot*. Lo que está entre llaves decide el slot:
```text
MSET {cliente:C-001}:carrito "..." {cliente:C-001}:perfil "..."      # misma etiqueta → mismo slot
```
Úsalo con mesura: demasiadas claves con la misma etiqueta crean una partición caliente.

## 10. Diagnóstico
```text
INFO memory                          # used_memory, maxmemory, fragmentación
INFO stats                           # keyspace_hits, keyspace_misses, evicted_keys
INFO clients                         # clientes conectados
DBSIZE
SCAN 0 MATCH catalogo:v1:* COUNT 100  # recorrer claves SIN bloquear (nunca KEYS * en producción)
MEMORY USAGE catalogo:v1:sku:POL-ROJO-M
OBJECT FREQ catalogo:v1:sku:POL-ROJO-M   # (con políticas LFU)
SLOWLOG GET 10
CLIENT LIST
LATENCY DOCTOR
```
Algunos comandos administrativos (`BGSAVE`, `SAVE`, `REPLICAOF`, `SHUTDOWN`) están bloqueados en el servicio gestionado.
