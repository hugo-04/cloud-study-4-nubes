# AWS · ElastiCache · Repaso

## Preguntas
1. ¿Qué es *cache-aside*?
   - *La app mira la caché; si falla, consulta el origen, guarda con TTL y responde.*
2. ¿Por qué todo debe llevar TTL?
   - *Sin él la caché crece sin control, sirve datos viejos y puede llenarse.*
3. ¿Qué es una avalancha y cómo se evita?
   - *Muchas claves venciendo a la vez; con TTL con azar (jitter).*
4. ¿Y una estampida?
   - *Muchas peticiones fallando a la vez en una clave; una sola recalcula y las demás esperan.*
5. ¿Modo clúster deshabilitado o habilitado?
   - *Deshabilitado: un shard, simple; habilitado: varios shards para más memoria y escritura (cuidado con CROSSSLOT).*
6. ¿Qué hace la política de expulsión?
   - *Decide qué borrar cuando se llena la RAM; para caché suele ser `allkeys-lru`.*
7. ¿Por qué un candado necesita token propio?
   - *Para no liberar un candado que ya es de otro tras vencer el tuyo.*
8. ¿Por qué un limitador usa un script?
   - *Para que `INCR` y `EXPIRE` sean una sola operación atómica.*
9. ¿Qué haces si la caché falla?
   - *Ir al origen: la caché es opcional.*
10. ¿Cuándo NO usar ElastiCache?
    - *Como fuente de verdad, cola con garantías, o para valores enormes.*

## Ejercicios
1. Implementa cache-aside con TTL ± 20 % y caché negativa; mide aciertos.
2. Crea un limitador de 100 peticiones por minuto y responde 429 con `Retry-After`.
3. Diseña claves de carrito y descuento que funcionen en modo clúster.
4. Simula un failover con `TestFailover` y observa cómo se recupera tu aplicación.

## Autoevaluación
- [ ] Todo lo que guardo tiene TTL.
- [ ] Mi app funciona (más lenta) si la caché cae.
- [ ] Sé evitar avalanchas, estampidas y `CROSSSLOT`.
- [ ] Mi cliente falla rápido y sigue al DNS en un failover.
- [ ] Sé cuándo usar Aurora, DynamoDB o SQS en vez de la caché.
