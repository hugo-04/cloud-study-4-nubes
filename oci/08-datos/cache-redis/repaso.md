# Oracle OCI · Datos · OCI Cache · Repaso

## Preguntas
1. ¿Qué es cache-aside?
2. ¿Por qué TTL con jitter?
3. ¿Qué es una estampida?
4. ¿Cómo invalidas todo el catálogo sin borrar claves?
5. ¿Qué hace la app si la caché no responde?
6. ¿Qué endpoint usas en modo clúster?
7. ¿Por qué no `KEYS *`?
8. ¿Qué protocolo de conexión usas?
9. ¿Es la caché fuente de verdad?
10. ¿Qué permiso necesita la app para descubrir el endpoint?

## Respuestas
1. Buscar en caché y, si no está, leer de la base y guardar.
2. Para que las claves no expiren todas a la vez.
3. Muchas peticiones regenerando la misma clave al mismo tiempo.
4. Cambiando la versión en el nombre de las claves.
5. Degrada a la base con un *timeout* corto.
6. El de descubrimiento.
7. Bloquea el servidor mientras recorre todas las claves.
8. Redis con TLS (`rediss://`).
9. No.
10. `read redis-clusters`.

## Ejercicios
1. Diseña las claves y TTL del catálogo y de las sesiones de ModaLima.
2. Implementa un limitador de tasa con `INCR` y `EXPIRE`.
3. Calcula la memoria para 200.000 fichas de 4 KB con 30 % de margen.
