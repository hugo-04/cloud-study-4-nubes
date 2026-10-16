# Azure · Redis · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · La caché se llenó y las escrituras empezaron a fallar
- **Problema:** una mañana el servicio de catálogo empezó a devolver errores `OOM command not allowed when used memory > 'maxmemory'`. La métrica de memoria usada estaba al 100 %.
- **Causa:** la política de expulsión era `VolatileLRU` (solo expulsa claves **con TTL**) y varias partes del código guardaban claves **sin TTL** (resultados de búsquedas y sesiones de prueba). Con el tiempo, esas claves nunca vencían ni se expulsaban.
- **Solución:** poner TTL a toda clave de caché (envoltorio único `CacheAside` que obliga a pasar un TTL), limpiar las claves huérfanas con `SCAN` + `TTL` (las que devuelven `-1`), alerta de memoria > 80 % y revisión de la política: `AllKeysLRU` para una caché pura.
- **Lección:** la política de expulsión debe coincidir con cómo escribes. Con `Volatile*` y claves sin TTL, Redis no tiene qué expulsar. **TTL en todo lo que sea caché.**

## Caso 2 · La estampida de medianoche
- **Problema:** todos los días a las 00:00 la base de datos del catálogo subía al 100 % de CPU durante un minuto y la API respondía 503.
- **Causa:** un proceso nocturno cargaba 5 000 productos en Redis con **el mismo TTL de 24 h**; al día siguiente vencían todos juntos y, además, el producto estrella recibía cientos de solicitudes que recargaban a la vez (*stampede*).
- **Solución:** TTL con *jitter* (±20 %), **una sola carga por clave** (bloqueo corto o `Mono.cache()` dentro del pod) y precalentar el top 50 antes de que venza. Ver `CacheAside` en [uso en Java](uso-en-java.md).
- **Lección:** la caché no solo acelera; **concentra** la carga cuando falla a la vez. Dispersa los vencimientos y limita las recargas.

## Caso 3 · `CROSSSLOT` en el carrito
- **Problema:** al migrar a Azure Managed Redis con política **OSSCluster**, el servicio de carrito empezó a fallar con `CROSSSLOT Keys in request don't hash to the same slot`.
- **Causa:** el código hacía `MGET carrito:C-001 carrito:C-002 …` y una transacción `MULTI` sobre claves distintas. En un clúster, cada clave cae en un *slot* y los comandos multiclave exigen el mismo.
- **Solución:** diseñar las claves con **etiquetas de hash**: `{cliente:C-001}:carrito`, `{cliente:C-001}:perfil` (todo lo del mismo cliente en el mismo slot) y reemplazar los `MGET` entre clientes por lecturas individuales en *pipeline*.
- **Lección:** pasar de "una instancia" a "clúster" cambia el modelo de claves. Prueba con una instancia de la misma política desde el principio. Y no pongas **todos** los clientes bajo la misma etiqueta: crearías una partición caliente.

## Caso 4 · Errores cada hora, como un reloj
- **Problema:** cada ~60–90 minutos aparecían 20 segundos de errores `NOAUTH`/conexión cerrada en todos los pods; luego todo volvía a la normalidad.
- **Causa:** la aplicación pedía el token de Entra ID **una vez al arrancar** y lo usaba como contraseña. Al caducar el token, Redis cerraba las conexiones; el reintento ya usaba un token vencido hasta que el pod reiniciaba su proveedor.
- **Solución:** usar `redis-authx-entraid` (`TokenBasedRedisCredentialsProvider`), que renueva el token antes de que caduque y **reautentica** las conexiones abiertas (`ReauthenticateBehavior.ON_NEW_CREDENTIALS`). Prueba de humo: dejar un cliente corriendo más de 2 horas en desarrollo.
- **Lección:** con Entra ID, el token es una credencial **con fecha de vencimiento** y la renovación es parte de la conexión. Un problema periódico con la misma frecuencia que la vida del token casi siempre es esto.

## Caso 5 · `KEYS *` en producción
- **Problema:** una pantalla de administración "limpiar caché de un cliente" congeló el sitio durante 8 segundos.
- **Causa:** buscaba las claves con `KEYS cliente:C-001:*`. `KEYS` recorre **todas** las claves y bloquea el hilo del shard mientras tanto; con 30 millones de claves, todo lo demás esperó.
- **Solución:** reemplazar por `SCAN` con `MATCH` y `COUNT` (por lotes), y mejor aún guardar las claves del cliente bajo un **conjunto índice** (`SADD indice:cliente:C-001 clave`) o usar un prefijo de versión (`cliente:C-001:v7:…`) y simplemente incrementar la versión para "invalidar".
- **Lección:** los comandos O(N) son peligrosos en un servidor que ejecuta los comandos de cada shard uno por uno. Invalidar por **versión** es más barato que borrar por patrón.

## Caso 6 · La clave de 1,5 GB
- **Problema:** durante un mantenimiento, la latencia subió y hubo desconexiones; la geo-replicación quedó "no saludable".
- **Causa:** el equipo guardaba el catálogo completo (millones de líneas) en **un solo hash**. Mover o replicar una clave así bloquea al shard, y la sincronización entre regiones se pausó por falta de memoria libre.
- **Solución:** dividir el catálogo en claves pequeñas por producto (`catalogo:v1:{sku}`), con valores de pocos KB; un índice aparte para los listados; monitorizar el tamaño de las claves.
- **Lección:** **claves grandes** y **claves calientes** son los dos enemigos de Redis. Valores de KB, colecciones acotadas.

## Caso 7 · Dos réplicas hicieron el cierre diario a la vez
- **Problema:** el cierre de caja del día se ejecutó dos veces y descontó los vales dos veces.
- **Causa:** el bloqueo en Redis tenía un TTL de 30 s, pero el cierre tardó 45 s por un pico de carga; el bloqueo venció a mitad del proceso y otra réplica lo tomó. Además, el primero liberaba el bloqueo **sin comprobar que seguía siendo suyo**, rompiendo el del segundo.
- **Solución:** (1) bloqueo con **token de dueño** y liberación con Lua (comparar y borrar), (2) TTL con margen y renovación mientras trabaja, (3) y sobre todo **proteger el recurso final**: una restricción única `(fecha, tipo)` en la base de datos, de modo que un segundo cierre falle aunque ambos crean tener el bloqueo.
- **Lección:** un bloqueo en Redis sirve para **evitar trabajo duplicado**, no para garantizar exactitud. La corrección va en la base de datos (restricción única, ETag, token de cercado).

## Caso 8 · Clientes bloqueados "para siempre"
- **Problema:** unos clientes recibían 429 (límite de tasa) durante horas, aunque no enviaban solicitudes.
- **Causa:** el limitador hacía `INCR limite:cliente` y después `EXPIRE` como **dos llamadas separadas**. Un reinicio del pod entre ambas dejó claves con contador y **sin TTL**: nunca se reiniciaban.
- **Solución:** un script Lua que hace `INCR` y `EXPIRE` en una sola operación atómica ([`limitador-ventana-fija.lua`](ejemplos/lua/limitador-ventana-fija.lua)), y una limpieza de las claves `limite:*` con TTL `-1`.
- **Lección:** si dos comandos deben ocurrir juntos, **o ambos o ninguno**: Lua o `SET ... EX` en una sola llamada.

## Caso 9 · El stock "en Redis" que desapareció
- **Problema:** tras un mantenimiento, los contadores de stock volvieron a valores antiguos y se vendió producto agotado.
- **Causa:** el stock oficial vivía **solo en Redis** (sin persistencia) para ir rápido. En una conmutación, la réplica no tenía las últimas escrituras (la replicación es asíncrona).
- **Solución:** el stock oficial se movió a la base de datos; Redis quedó como **reserva rápida** (script Lua) con conciliación cada minuto, y un proceso de **reconstrucción** desde la base si falta la clave. Se habilitó persistencia solo para acelerar la recuperación, no como garantía.
- **Lección:** Redis es memoria. Lo que no puedas reconstruir o perder, **no vive solo allí**.

## Caso 10 · Usar Redis como cola de pedidos
- **Problema:** durante una conmutación por error se perdieron 140 pedidos pendientes en una lista de Redis.
- **Causa:** el equipo usaba una lista (`LPUSH/RPOP`) como cola de pedidos. Con replicación asíncrona y sin confirmación por mensaje, un mensaje leído y no procesado se pierde si el consumidor cae.
- **Solución:** los pedidos pasaron a **Service Bus** (cola con bloqueo de lectura, reintentos y cola de mensajes fallidos). Redis Streams se mantuvo para tareas internas poco críticas con grupos de consumidores y `XACK`. Ver [Service Bus](../../07-mensajeria/service-bus/README.md).
- **Lección:** Pub/Sub y listas **no son colas durables**; Streams mejora mucho, pero no iguala a un broker cuando el mensaje vale dinero.

## Caso 11 · Cuando la caché cae y se lleva el servicio
- **Problema:** una conmutación por mantenimiento de Redis (unos segundos) tumbó la tienda durante 6 minutos.
- **Causa:** el cliente no tenía tiempos de espera: los hilos quedaron esperando a Redis, el *pool* de Tomcat se agotó y el servicio dejó de responder, incluso para rutas que no usaban caché.
- **Solución:** tiempos de espera de 2 s en comandos y 5 s en conexión, **degradar a la base** cuando Redis falla (con un límite de concurrencia), disyuntor (*circuit breaker*) y reconexión automática. Prueba de resiliencia mensual: detener Redis en preproducción.
- **Lección:** la caché debe ser una **optimización**, no una dependencia dura. Diseña para "Redis lento o caído".

## Caso 12 · Cliente que no entiende de clúster
- **Problema:** al elegir **OSSCluster**, un servicio antiguo (cliente simple) recibía `MOVED` en la mitad de las operaciones; otro servicio necesitaba **RediSearch**, que no funcionaba.
- **Causa:** OSSCluster exige un cliente **compatible con clúster** (descubre y habla directamente con los shards). RediSearch, en cambio, requiere la política **EnterpriseCluster** (y `NoEviction`). La política **no se puede cambiar** después de crear la instancia.
- **Solución:** dos instancias: una `OSSCluster` para la caché de alto rendimiento de los servicios modernos, y otra `EnterpriseCluster` con RediSearch para la búsqueda de catálogo. Los clientes antiguos migraron al cliente de clúster de Lettuce.
- **Lección:** decide la política de clúster **antes de crear**, mirando los clientes y los módulos que vas a necesitar. Recrear implica migrar datos.

## Caso 13 · Dos regiones, un mismo carrito
- **Problema:** con geo-replicación activa entre Brasil y Estados Unidos, un carrito editado casi a la vez desde dos regiones perdía artículos.
- **Causa:** el carrito se guardaba como una **cadena JSON completa**; con escrituras simultáneas en las dos regiones, gana el último escritor y se pierde el cambio del otro (la replicación es eventual).
- **Solución:** modelar el carrito como **hash** (un campo por artículo) o conjunto, de modo que los cambios de distintos artículos se combinen; contadores con tipos que convergen. Y para lo que no debe divergir (pagos), una sola región de escritura.
- **Lección:** en activo-activo, el tipo de dato decide cómo se resuelven los conflictos. Cadenas enteras = último gana; estructuras finas = se fusionan mejor. *Verifica las reglas de resolución por tipo en la documentación vigente.*

## Caso 14 · Datos personales en los nombres de las claves
- **Problema:** una auditoría encontró correos de clientes en los registros de diagnóstico.
- **Causa:** las claves eran `sesion:cliente@correo.com`, y los diagnósticos y la salida de `SLOWLOG` las mostraban en claro.
- **Solución:** claves con identificadores opacos (`sesion:v1:{C-001}`), valores mínimos y TTL cortos para sesiones; revisión de qué datos personales se guardan en la caché.
- **Lección:** los nombres de las claves también aparecen en registros y herramientas. La caché contiene datos del cliente: **minimiza y vence**.

## Caso 15 · Se filtró una clave de acceso
- **Problema:** una clave de acceso de la instancia apareció en un repositorio.
- **Solución:** regenerar las claves, **desactivar la autenticación por claves** (al hacerlo se cortan todas las conexiones que las usaban, así que se programó en una ventana con los clientes ya migrados a Entra ID), asignar la política de acceso a cada identidad administrada y cerrar el acceso público con Private Endpoint.
- **Lección:** pasa primero a Entra ID y después desactiva las claves; avisa a los equipos del corte. Una clave es acceso total y no caduca sola.

---

## Resumen de patrones que se repiten
| Patrón | Casos |
|---|---|
| TTL siempre, con jitter | 1, 2 |
| Operaciones compuestas atómicas (Lua) | 7, 8, 9 |
| Redis no es la fuente de verdad ni un broker | 9, 10 |
| Diseñar para que la caché falle | 11 |
| Modelo de claves en clúster | 3, 5, 6, 12 |
| Credenciales con vencimiento | 4, 15 |
| Activo-activo y conflictos | 13 |
| Datos sensibles y claves | 14 |
