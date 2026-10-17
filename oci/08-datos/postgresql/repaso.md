# Oracle OCI · Datos · PostgreSQL · Repaso

## Preguntas
1. ¿Qué es el almacenamiento optimizado?
2. ¿Qué pasa en un *failover*?
3. ¿Qué endpoint usas para escribir?
4. ¿Qué es «leer lo que escribí»?
5. ¿Por qué pools pequeños?
6. ¿Qué `sslmode` recomiendas?
7. ¿Cómo se gestionan los cambios de esquema?
8. ¿Qué limita a un servicio administrado?
9. ¿Qué permiso necesita la app para descubrir el endpoint?
10. ¿Qué driver usa WebFlux?

## Respuestas
1. Una capa de almacenamiento replicada entre AD compartida por los nodos.
2. Una réplica es promovida a primario sin pérdida de datos.
3. El primario.
4. Que el usuario vea sus propios cambios inmediatamente, leyendo del primario.
5. Cada conexión consume memoria en PostgreSQL.
6. `verify-full`.
7. Con migraciones versionadas (Flyway) y un rol de migración.
8. Lista cerrada de extensiones y sin acceso al SO.
9. `read postgres-db-systems`.
10. `r2dbc-postgresql`.

## Ejercicios
1. Diseña la ventana de «leer lo que escribí» del historial de pedidos.
2. Escribe una migración en tres pasos para una columna obligatoria nueva.
3. Dimensiona pools para 3 servicios con 6 réplicas cada uno.
