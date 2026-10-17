# Oracle OCI · Datos · NoSQL · Repaso

## Preguntas
1. ¿Qué es la clave de shard?
2. ¿Qué modos de capacidad existen?
3. ¿Qué hace el TTL?
4. ¿Cómo evitas perder cambios concurrentes?
5. ¿Qué consistencias de lectura hay?
6. ¿Por qué una consulta sin clave es cara?
7. ¿Qué política necesita la app?
8. ¿Cuándo NO usar NoSQL?
9. ¿Qué es una fila caliente?
10. ¿Cómo empieza el diseño de una tabla?

## Respuestas
1. La parte de la clave que decide la partición física.
2. Provisionada (unidades) y bajo demanda.
3. Expira filas automáticamente.
4. Con escrituras condicionales por versión.
5. Eventual y absoluta.
6. Recorre muchas filas y consume muchas unidades.
7. `use nosql-rows`.
8. Para *joins*, transacciones amplias o reportes.
9. Una clave que concentra el tráfico.
10. Por los patrones de acceso.

## Ejercicios
1. Diseña la tabla de sesiones de ModaLima (clave, TTL, capacidad).
2. Escribe el bucle de reintento optimista del carrito.
3. Diseña la tabla de lecturas de sensores de las tostadoras de Café Andino.
