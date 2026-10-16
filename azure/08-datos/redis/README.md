# Azure · Datos · Azure Managed Redis

## 1. Qué es

**Es Redis —la base de datos en memoria, clave-valor, ultrarrápida— ofrecido como servicio administrado de Azure.** Guardas datos en la memoria RAM de un grupo de servidores que Azure opera por ti (parches, alta disponibilidad, escalado, métricas), y los lees en **menos de un milisegundo**. Se usa sobre todo como **caché** delante de una base de datos más lenta, pero también para **sesiones, contadores, limitadores de tasa, bloqueos, colas ligeras, rankings, búsqueda y vectores**.

Dos nombres que conviene distinguir:
- **Azure Managed Redis (AMR)** es el servicio **actual y recomendado**, basado en *Redis Enterprise* (versión 7.4.x a la fecha de redacción; verifica la vigente).
- **Azure Cache for Redis** (niveles Basic, Standard, Premium, Enterprise) es el servicio **anterior, en retiro**: Basic/Standard/Premium se retiran el **30 de septiembre de 2028** y Enterprise/Enterprise Flash el **31 de marzo de 2027**; el reemplazo es AMR. **Todo diseño nuevo debe usar Azure Managed Redis.**

Analogía: **el mostrador de una tienda frente a la bodega del fondo**. La bodega (tu base de datos) guarda todo, pero ir hasta allá cuesta tiempo. El mostrador (Redis) tiene a mano lo que más se pide: respuesta inmediata. Si lo que piden no está en el mostrador (*cache miss*), alguien va a la bodega, lo trae y lo deja en el mostrador con una etiqueta de vencimiento (TTL).

```
 Aplicaciones (Spring / Quarkus)  ──TLS, puerto 10000, token de Entra──►  amr-modalima.<región>.redis.azure.net
                                                                          │
                      ┌───────────────────── Instancia de Azure Managed Redis (SKU, p. ej. Balanced_B5) ───────────────────┐
                      │  Nodo A (zona 1): proxy + shards primarios 1,3   ◄══ replicación ══►  Nodo B (zona 2): shards réplica 1,3 + primarios 2,4 │
                      │  • una sola base de datos  • memoria en RAM (~20 % reservada como colchón)  • módulos (JSON, Search, Bloom, TimeSeries)    │
                      │  • persistencia opcional (RDB/AOF)  • Entra ID (o claves)  • Private Endpoint                                              │
                      └───────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────┘
                                                      │ geo-replicación activa (opcional, hasta 5 instancias, escritura en todas)
                                          Instancia en otra región  (consistencia eventual)
```

---

## 2. Cómo funciona por dentro

### 2.1 Arquitectura: nodos, shards y proxy
- Una instancia son **varios nodos** (máquinas virtuales). Cada nodo ejecuta **varios procesos de Redis llamados *shards***, y un **proxy** que administra conexiones y autorreparación.
- Los datos se reparten entre shards por **slots de hash** (16 384 slots, como en Redis Cluster). Cada shard primario tiene una réplica en otro nodo (con HA).
- Aproximadamente el **20 % de la memoria** queda reservado como colchón para operaciones que no son de caché (replicación, conmutación, geo-replicación). Tu "espacio útil" es menor que el tamaño nominal.
- **No puedes elegir el número de nodos**: lo determina la SKU.

### 2.2 Niveles y SKU
El nombre de la SKU es `Familia_Tamaño`, por ejemplo `Balanced_B5`.

| Nivel | Relación memoria:vCPU | Para qué | Familias de SKU (tamaños) |
|---|---|---|---|
| **Memory Optimized** | 8:1 | Mucha memoria a menor precio; desarrollo y pruebas, cachés grandes con poca carga | `MemoryOptimized_M10` … `M2000` |
| **Balanced** | 4:1 | La mayoría de cargas; punto de partida recomendado | `Balanced_B0` … `B1000` |
| **Compute Optimized** | 2:1 | Máximo rendimiento (muchas operaciones por segundo) | `ComputeOptimized_X3` … `X700` |
| **Flash Optimized** | RAM + NVMe | Conjuntos grandes donde los datos poco usados pueden vivir en disco rápido | `FlashOptimized_A250` … `A4500` |

- El número de la SKU es aproximadamente la memoria en GB (consulta la tabla vigente de tamaños; hay tamaños en vista previa).
- **Flash Optimized** no admite módulos de búsqueda/Bloom/TimeSeries ni geo-replicación activa. **B0 y B1** tampoco admiten geo-replicación.
- *Verifica SKU disponibles por región, tamaños en vista previa y precios.*

### 2.3 Alta disponibilidad (HA)
- Con **HA habilitada** (por defecto) hay réplicas de cada shard en **al menos dos nodos**; en regiones con zonas de disponibilidad, los nodos se reparten entre zonas. Tiene SLA.
- **Sin HA** no hay réplicas ni SLA: úsalo solo en desarrollo. Se puede **activar** en una instancia existente, pero **no desactivar**.
- Durante mantenimientos o conmutaciones, las conexiones se cortan unos instantes: el cliente debe **reconectar** y reintentar.

### 2.4 Política de clúster (se elige al crear y no cambia)
| Política | Cómo funciona | Cliente | Notas |
|---|---|---|---|
| **OSSCluster** | API de Redis Cluster: el cliente descubre los shards y habla directo con ellos (primer contacto en el puerto 10000; los shards usan puertos del rango 85XX que **no debes fijar**) | **Debe ser compatible con clúster** (Lettuce `RedisClusterClient`, Jedis clúster, etc.) | Mejor rendimiento y latencia; comandos multiclave exigen el mismo *slot* |
| **EnterpriseCluster** | Un solo endpoint (puerto 10000): un proxy interno enruta al shard correcto | **Cualquier cliente Redis** | Un proxy puede ser cuello de botella; **necesaria para RediSearch**; algunas operaciones multiclave sí cruzan slots |
| **NoCluster** | Sin fragmentar, un único proceso | Cualquier cliente | Máximo **25 GB**; es el menos eficiente; puede pasarse a clúster después (salvo en geo-replicación) |

Un error típico del modo clúster es **`CROSSSLOT`**: un comando con varias claves cuyas claves caen en slots distintos. Solución: diseñar claves con **etiquetas de hash** (`{cliente:C-001}:carrito`, lo que va entre llaves decide el slot) o hacer operaciones por clave.

### 2.5 Memoria, expulsión y vencimiento (TTL)
- Redis guarda **todo en RAM**: cuando se llena, depende de la **política de expulsión**:

| Política | Qué hace |
|---|---|
| `VolatileLRU` *(por defecto en CLI)* | Expulsa las claves **con TTL** menos usadas recientemente. Ideal para caché con TTL |
| `AllKeysLRU` / `AllKeysLFU` | Expulsa entre **todas** las claves (menos usadas recientemente / menos frecuentes) |
| `VolatileLFU`, `VolatileTTL`, `VolatileRandom`, `AllKeysRandom` | Variantes por frecuencia, por vencimiento más próximo o al azar |
| `NoEviction` | **No expulsa**: cuando se llena, las escrituras **fallan**. Para datos que no pueden perderse; **obligatoria con RediSearch** |

- **TTL:** cada clave puede tener vencimiento (`EXPIRE`, `SET ... EX`). Es la herramienta principal para que una caché no crezca sin control. **Pon TTL a todo lo que sea caché.**
- Los cambios de política en instancias en un grupo de geo-replicación no se permiten.

### 2.6 Persistencia (opcional)
Redis es memoria, pero puede guardar copias en disco para recuperarse tras un reinicio: **RDB** (instantáneas periódicas, p. ej. cada hora) o **AOF** (registro de escrituras, p. ej. cada segundo). Úsala para sesiones o datos que conviene recuperar, **no** como sustituto de una base de datos. **No es compatible con la geo-replicación activa.** *Verifica frecuencias y compatibilidad vigentes.*

### 2.7 Módulos (se eligen al crear y no cambian)
| Módulo | Qué aporta |
|---|---|
| **RedisJSON** | Documentos JSON con operaciones por ruta (todas las SKU) |
| **RediSearch** | Índices secundarios, búsqueda de texto completo y **búsqueda vectorial** (no en Flash; exige EnterpriseCluster + NoEviction) |
| **RedisBloom** | Estructuras probabilísticas: filtros Bloom/Cuckoo, Count-Min, Top-K |
| **RedisTimeSeries** | Series de tiempo |

### 2.8 Geo-replicación activa
- Hasta **5 instancias** (en regiones distintas) forman un grupo **activo-activo**: se puede **escribir en todas**, con replicación bidireccional y resolución de conflictos mediante tipos de datos CRDT. Consistencia **eventual** (sin SLA de tiempo de sincronización).
- **Se configura al crear** (para añadir una existente hay que forzar el enlace, lo que **borra sus datos**).
- Todas las instancias deben tener **la misma SKU, capacidad, política de expulsión, de clúster, módulos y TLS**. Sin persistencia. Solo RediSearch y RedisJSON como módulos.
- `FLUSHALL`/`FLUSHDB` están bloqueados (hay una operación de vaciado que afecta a **todo el grupo**).
- Ante la caída de una región: *force unlink*, redirigir el tráfico, y recrear la instancia afectada al volver. Métrica **Geo Replication Healthy**.
- Evita claves enormes (< 500 MB) y deja memoria libre: la sincronización se pausa sin memoria.

### 2.9 Red
- **Puerto 10000** y **TLS** (`Encrypted`; el modo `Plaintext` existe pero no lo uses). Nombre DNS: `<nombre>.<región>.redis.azure.net` (cópialo de la página *Overview*).
- **Private Endpoint** (subrecurso `redisEnterprise`, zona DNS privada `privatelink.redis.azure.net`): recomendado para producción; si borras todos los endpoints privados, la red vuelve a acceso público. No usar `<nombre>.privatelink.redis.azure.net` en las cadenas de conexión.
- **No hay reglas de firewall por IP**: o acceso público (protegido por TLS + autenticación) o solo privado (`public_network_access = Disabled`).
- Un Private Endpoint no aplica reglas NSG/UDR por defecto (hay que habilitar las políticas de red de la subred).

### 2.10 Autenticación y autorización
- **Microsoft Entra ID** (recomendado): la aplicación obtiene un **token** para el ámbito `https://redis.azure.com/.default` y envía `AUTH <object id> <token>`. El **usuario es el *object id*** de la identidad administrada o del principal de servicio; la contraseña es el token. Solo funciona sobre TLS. **No admite grupos de Entra**: se asignan identidades individuales.
- El token **caduca**: hay que renovarlo y volver a enviar `AUTH` **antes** de que expire (al menos ~3 minutos antes, con *jitter* para no coincidir todos los clientes). Si no, el servidor corta la conexión. Las bibliotecas oficiales (`redis-authx-entraid`) lo hacen solas.
- **Política de acceso:** por defecto, acceso a todos los comandos y claves; hay una función en vista previa para permisos de datos personalizados.
- **Claves de acceso:** existen pero **conviene desactivarlas** en producción (al desactivarlas se cortan todas las conexiones).
- Un cliente solo puede usar **una base de datos** (no existe `SELECT 1`): separa por **prefijos de clave**.

### 2.11 Escalado y mantenimiento
- Escalar es cambiar de SKU/tamaño (sube memoria, vCPU y shards). **Reducir no está soportado** (limitado). Haz el cambio fuera de horas pico y con clientes que reconecten.
- Hay opción de **diferir** las actualizaciones de versión de Redis.
- Algunos comandos administrativos están bloqueados (`BGSAVE`, `SAVE`, `REPLICAOF`, `SHUTDOWN`).

### 2.12 Observabilidad
- **Métricas** (espacio `Microsoft.Cache/redisEnterprise`): `usedmemorypercentage`, `usedmemory`, `serverLoad`, `percentProcessorTime`, `connectedclients`, `operationsPerSecond`, `cachehits`, `cachemisses`, `evictedkeys`, `expiredkeys`, `cacheLatency`, `totalkeys`, `geoReplicationHealthy`, y métricas por shard (vista previa).
- **Registros:** `ConnectionEvents` → tabla `REDConnectionEvents` (nuevas conexiones, autenticaciones, cierres).
- Alertas útiles: memoria > 80 %, `serverLoad` > 80 %, `evictedkeys` > 0 con `NoEviction` (errores), `geoReplicationHealthy` < 1.
- Ver [KQL](ejemplos/kql/kql-redis.md).

### 2.13 Patrones de uso (qué problema resuelve cada estructura)
| Patrón | Estructura | Idea |
|---|---|---|
| **Cache-aside** | cadena + TTL | Leer: caché → si falla, base → guardar con TTL. Escribir: base → invalidar |
| **Sesión / carrito** | hash + TTL | Datos pequeños de corta vida |
| **Idempotencia** | `SET clave NX EX` | "Solo la primera vez" durante 24 h |
| **Limitador de tasa** | contador + TTL (Lua) | N solicitudes por ventana |
| **Bloqueo distribuido** | `SET NX PX` + liberar con Lua | Un solo trabajador a la vez (con cautela, ver §7) |
| **Reserva atómica de stock** | Lua sobre hash | Descontar sin pasar de cero |
| **Ranking** | conjunto ordenado | Top ventas |
| **Cola ligera / eventos** | Streams + grupos | Reintento y confirmación; no es un log durable como un broker |
| **Mensajería efímera** | Pub/Sub | Notificar invalidaciones a instancias (sin historial) |
| **Conteo de únicos** | HyperLogLog | Visitantes únicos aproximados |
| **Búsqueda / vectores** | RediSearch | Búsqueda de texto y similitud |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Caché** de lecturas costosas o muy repetidas (catálogo, precios, configuración, resultados de consultas).
- **Sesiones y carritos** de corta duración con acceso inmediato.
- **Limitadores de tasa, contadores, banderas de funcionalidad, idempotencia.**
- **Bloqueos y coordinación ligera** entre instancias; **reservas atómicas** con Lua.
- **Rankings, contadores en tiempo real, estructuras probabilísticas.**
- **Búsqueda y vectores** (RediSearch) sobre un conjunto que cabe en memoria.
- **Colas pequeñas y notificaciones** (Streams, Pub/Sub) cuando no necesitas durabilidad de broker.

| NO lo uses si | Alternativa |
|---|---|
| Es la **única copia** de datos importantes (la memoria es volátil) | Base de datos: **Azure SQL, PostgreSQL o Cosmos DB** |
| Necesitas consultas relacionales, transacciones entre entidades | **Azure SQL / PostgreSQL** |
| Necesitas un log de eventos durable, reproducible y con retención | **Event Hubs / Kafka**, **Service Bus** |
| Los datos son enormes y poco consultados | Base de datos o **Blob** (Flash Optimized solo en casos concretos) |
| Guardas archivos | **Blob Storage** |
| Necesitas índices y consultas flexibles sobre muchísimos datos fríos | Cosmos DB / PostgreSQL |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Clave-valor** | Cada dato se guarda y se busca por su clave | `catalogo:v1:sku:POL-ROJO-M` |
| **TTL** | Tiempo de vida de una clave | `EX 300` (5 min) |
| **Cache-aside** | La aplicación consulta la caché y, si falla, carga de la base | Catálogo |
| **Acierto / fallo (*hit / miss*)** | Estaba / no estaba en caché | Tasa de aciertos |
| **Expulsión (*eviction*)** | Redis borra claves al llenarse | `VolatileLRU` |
| **Shard** | Fragmento de datos con su proceso de Redis | Cada nodo aloja varios |
| **Slot** | Cubeta de hash (0–16 383) que decide el shard de una clave | `CLUSTER KEYSLOT` |
| **Etiqueta de hash `{}`** | Fuerza que varias claves caigan en el mismo slot | `{cliente:C-001}:perfil` |
| **CROSSSLOT** | Error de un comando multiclave con slots distintos | `MGET a b` en clúster |
| **OSSCluster / EnterpriseCluster** | Dos formas de exponer el clúster | Cliente con o sin soporte de clúster |
| **Entra ID / AUTH** | Autenticación por token; usuario = object id | Sin contraseñas |
| **Stampede (*estampida*)** | Muchos fallos simultáneos tras expirar una clave popular | Todos recargan a la vez |
| **Clave caliente** | Una clave recibe tráfico desproporcionado | Producto estrella |
| **Clave grande** | Valor enorme que bloquea al servidor al moverlo | Lista de millones |
| **Stream / grupo de consumidores** | Registro de mensajes con confirmación (`XACK`) | Cola de eventos ligera |
| **Lua / EVAL** | Script que Redis ejecuta de forma atómica | Reserva de stock |

---

## 5. Cómo se usa

1. **Decide si Redis es la herramienta:** ¿es una caché o dato efímero que puedes reconstruir? Si es el único almacén de algo valioso, no.
2. **Elige la SKU y la política de clúster** (no se cambia): `Balanced` para empezar; **OSSCluster** si tu cliente es compatible con clúster (mejor rendimiento) o **EnterpriseCluster** si necesitas simplicidad o RediSearch. Define la política de **expulsión** y los **módulos** *antes* de crear.
3. **Crea la instancia** con HA en producción, **Entra ID** (claves desactivadas), **Private Endpoint** y acceso público cerrado.
4. **Asigna la identidad** de cada aplicación en la política de acceso (identidad administrada → su *object id*).
5. **Diseña las claves:** prefijo por servicio y versión (`pedidos:v1:cliente:{C-001}:resumen`), siempre con TTL si es caché; etiquetas `{}` solo cuando necesites multiclave.
6. **Conecta desde Java:** Lettuce (cliente de clúster u normal) con `redis-authx-entraid`; pool/conexión compartida, reconexión automática y reautenticación al renovar el token.
7. **Implementa cache-aside** con TTL con *jitter*, caché negativa y protección contra estampidas.
8. **Observa:** memoria, `serverLoad`, tasa de aciertos, expulsiones, conexiones nuevas; alertas.
9. **Prueba la resiliencia:** reinicios, conmutaciones y vencimiento de token.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/redis.sh) · [redis-cli](ejemplos/redis-cli/comandos.md) · [Lua](ejemplos/lua/) · [KQL](ejemplos/kql/kql-redis.md).

---

## 6. Seguridad

- **Entra ID, sin claves:** desactiva la autenticación por claves de acceso; identidades administradas por aplicación.
- **Red:** Private Endpoint + acceso público desactivado; zona DNS `privatelink.redis.azure.net` enlazada a las redes que consumen.
- **TLS siempre** (`Encrypted`, TLS 1.2 como mínimo); nunca `Plaintext`.
- **Cifrado en reposo:** clave de Microsoft o **clave propia** (CMK) en Key Vault (afecta a archivos de persistencia).
- **No pongas secretos ni datos sensibles sin proteger en la caché**; los datos de una caché también son datos del cliente: aplica TTL cortos y minimiza campos.
- **Aislamiento entre inquilinos:** prefijos de clave por inquilino y comprobación en el código; una instancia por nivel de confianza si el riesgo lo exige.
- **Vaciado:** el comando de vaciado borra todo (y todo el grupo en geo-replicación): limita quién puede ejecutarlo.
- **Auditoría:** `ConnectionEvents` a Log Analytics; alertas por fallos de autenticación.

### IAM de este servicio

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control** (Azure RBAC) | Plataforma/IaC | Crear y configurar instancias | *Contributor* acotado al grupo de recursos (o rol personalizado `Microsoft.Cache/redisEnterprise/*`) |
| **Control** | Seguridad | Red, claves, diagnóstico | *Contributor* con alcance a la instancia |
| **Control** | Observabilidad | Ver métricas y configuración | *Reader* y *Monitoring Reader* |
| **Datos** (política de acceso de Redis) | Aplicación (identidad administrada) | Leer y escribir claves | Asignación de la política de acceso al *object id* de la identidad |
| **Datos** | Administración/soporte | Diagnóstico (`INFO`, `SLOWLOG`) | Identidad personal asignada de forma temporal |
| **Datos** | Claves de acceso | Acceso total | **Desactivadas** en producción |

> El rol *Contributor* de Azure **no** da acceso a los datos de Redis: la autenticación de datos es la política de acceso de Entra ID (o las claves, si siguen activas).

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- **Poner TTL a toda clave de caché**, con *jitter* (±10–20 %) para no expirar todo a la vez.
- **Cache-aside** con carga única por clave (evitar estampida) y **caché negativa** corta para "no existe".
- Claves con **prefijo + versión** (`servicio:v1:...`); cambia la versión al cambiar el formato.
- Serializar en **JSON/binario controlado**, nunca con serialización nativa de Java.
- **Scripts Lua** (o transacciones) para operaciones compuestas atómicas.
- **`SCAN`** para recorrer, jamás `KEYS *`.
- **Reutilizar conexiones** (una conexión multiplexada con Lettuce); reconectar y reintentar.
- Mantener la tasa de aciertos y la memoria bajo vigilancia; `NoEviction` solo con datos críticos.
- Desactivar claves, usar Private Endpoint y renovar tokens automáticamente.
- Dimensionar con **pruebas de carga** realistas; dejar margen de memoria (~20 % ya reservado).
- Diseñar para que la aplicación **funcione degradada si Redis cae** (ir a la base con límites).

**Qué NO hacer**
- Tratar Redis como **base de datos principal** sin persistencia ni copia.
- Guardar valores gigantes o colecciones sin límite (claves grandes bloquean a Redis).
- `KEYS *`, `FLUSHALL` o comandos O(N) sobre colecciones enormes en producción.
- Crear una conexión por solicitud.
- Obtener el token de Entra una sola vez y no renovarlo (la conexión se corta al caducar).
- Bloqueos distribuidos "a ciegas": sin TTL ni token de dueño, o confiando en ellos para exactitud estricta (un bloqueo expirado puede coexistir con otro dueño; usa **tokens de cercado** o restricciones en la base de datos).
- Usar Pub/Sub como cola durable (los mensajes se pierden si nadie escucha).
- Asumir que `MGET`/`MSET` multiclave siempre funcionan en clúster (`CROSSSLOT`).
- Elegir "NoCluster" o política de clúster "por ahora": no se puede cambiar OSS ↔ Enterprise sin recrear.
- Poner datos de un solo cliente en etiquetas `{}` comunes a todos (partición caliente).
- Dejar el acceso público abierto "para probar".

---

## 8. Límites, costos y versiones
- **Costo:** por SKU y por hora (más HA y réplicas, que ya se incluyen en la SKU), más instancias adicionales para geo-replicación; el costo crece con la memoria. *Verifica precios, reservas y tamaños en vista previa.*
- **Límites:** una base de datos por instancia; máximo de conexiones y de rendimiento según SKU; hasta 5 instancias por grupo de geo-replicación; 84 enlaces privados por instancia; clave/valor de hasta 512 MB (recomendable mucho menos). *Verifica la tabla vigente.*
- **Versiones:** Redis 7.4.x; bibliotecas: **Lettuce 7.x** (administrada por Spring Boot 4.1) y **`redis-authx-entraid` 0.2.0** (a la fecha de redacción; versiones anteriores eran *beta*). Quarkus 3.40 trae `quarkus-redis-client` (Vert.x), que **no renueva tokens de Entra** (ver [uso en Java](uso-en-java.md)).
- **Migración desde Azure Cache for Redis:** cambia nombre de host (`*.redis.azure.net:10000`), credenciales (Entra), y **revisa la compatibilidad con clúster** (comandos multiclave y `CROSSSLOT`).
- **Cambios frecuentes:** SKU, regiones y funciones (persistencia, permisos de datos, escalado en geo-replicación) siguen evolucionando: confirma antes de diseñar.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
