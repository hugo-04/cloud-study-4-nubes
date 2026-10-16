# NotebookLM · Azure · Redis (Azure Managed Redis)

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI, redis-cli, Lua, KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Managed Redis, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes ni con servicios equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es Redis y qué es Azure Managed Redis; analogía de la mesa de trabajo (rápida, pequeña y con cosas que se pueden perder) frente al archivo; qué problema resuelve.
2. Arquitectura interna: nodos, shards, proxy, slots de hash, memoria reservada, alta disponibilidad con réplicas y zonas.
3. Niveles y SKU: Memory Optimized, Balanced, Compute Optimized y Flash Optimized; cuándo elegir cada uno; restricciones (geo-replicación, módulos).
4. Política de clúster: OSSCluster, EnterpriseCluster y NoCluster; qué cliente exige cada una; por qué no se puede cambiar; CROSSSLOT y etiquetas de hash.
5. Memoria: TTL, políticas de expulsión (VolatileLRU, AllKeysLRU, NoEviction…), claves grandes y calientes; persistencia opcional (RDB y AOF) y sus límites.
6. Módulos: RedisJSON, RediSearch, RedisBloom y RedisTimeSeries; cuándo importan.
7. Geo-replicación activa: activo-activo, hasta 5 instancias, consistencia eventual, resolución de conflictos por tipo de dato, requisitos y operación en una caída regional.
8. Red y seguridad: puerto 10000, TLS, Private Endpoint y zona DNS privada, sin firewall por IP; Entra ID con object id y ámbito del token, renovación del token, desactivar claves; IAM por plano (control y datos).
9. Patrones: cache-aside con jitter, caché negativa y estampida; sesión y carrito; idempotencia; limitador de tasa; bloqueo distribuido con token y sus límites; reserva atómica de stock con Lua; Streams y Pub/Sub; cuándo usar un broker en su lugar.
10. Observabilidad: métricas (memoria, serverLoad, aciertos y fallos, expulsiones, conexiones, latencia, geo-replicación), registro ConnectionEvents y consultas KQL.
11. Los 15 casos reales como historias con su lección: caché llena sin TTL, estampida de medianoche, CROSSSLOT en el carrito, errores cada hora por token vencido, KEYS en producción, clave de 1,5 GB, cierre diario duplicado, limitador bloqueado para siempre, stock perdido, cola de pedidos en Redis, caída que arrastra el servicio, política de clúster equivocada, carrito en dos regiones, datos personales en claves y clave filtrada.
12. Código Java: Entra ID con redis-authx-entraid y Lettuce, fábrica de conexiones para OSSCluster y EnterpriseCluster, Spring Cache con TTL y jitter, bloqueo con token y Lua, cache-aside con anti-estampida y caché negativa, limitador y stock con Lua, Streams con grupos y reclamo de pendientes, Pub/Sub para invalidar L1, WebFlux reactivo, Quarkus imperativo y Quarkus reactivo con Mutiny, pruebas.
13. Ejemplos de Terraform, CLI, redis-cli y Lua; qué hacer y qué NO hacer; límites, costos y versiones.
14. Tabla de troubleshooting por síntoma (NOAUTH, MOVED, CROSSSLOT, OOM, latencia, reconexión) y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
