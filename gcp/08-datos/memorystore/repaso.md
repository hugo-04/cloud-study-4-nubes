# Google Cloud · Datos · Memorystore · Repaso

## Preguntas
1. ¿Qué motores ofrece Memorystore?
2. ¿Cómo se accede a la red?
3. ¿Qué es cache-aside?
4. ¿Para qué sirve el jitter?
5. ¿Qué hacer si la caché falla?
6. ¿Por qué evitar `KEYS *`?
7. ¿Qué política de expulsión conviene a una caché?
8. ¿Qué error indica modo clúster mal configurado?
9. ¿Dónde guardar la cadena AUTH?
10. ¿Cuándo no es la herramienta?

## Respuestas
1. Valkey, Redis Cluster, Redis y Memcached *(verifica)*.
2. Solo por red privada (PSC o acceso privado a servicios).
3. Buscar en caché; si falta, cargar de la base y guardar.
4. Para evitar que muchas claves venzan juntas.
5. Degradar a la base con timeouts cortos.
6. Es O(n) y bloquea.
7. `allkeys-lru`.
8. `MOVED`.
9. En Secret Manager.
10. Como fuente de verdad.

## Ejercicios
1. Calcula el TTL con jitter para 600 s ±10 %.
2. Diseña el fallback de catálogo.
3. Elige tamaño para 2 GB de datos calientes con réplicas.
