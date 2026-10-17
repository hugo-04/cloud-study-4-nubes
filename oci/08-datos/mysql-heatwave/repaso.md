# Oracle OCI · Datos · MySQL HeatWave · Repaso

## Preguntas
1. ¿Qué es un DB system?
2. ¿Qué agrega HeatWave?
3. ¿Cómo funciona la alta disponibilidad?
4. ¿Para qué sirve el endpoint de lectura?
5. ¿Qué es PITR?
6. ¿Cómo dimensionas los pools?
7. ¿Qué permiso necesita la app para descubrir endpoints?
8. ¿Qué haces tras un *failover*?
9. ¿Cuándo no leer de una réplica?
10. ¿Cómo proteges contra borrado?

## Respuestas
1. La instancia MySQL administrada con su forma, almacenamiento y configuración.
2. Un clúster en memoria que acelera consultas analíticas sin ETL.
3. Tres instancias en distintos AD/FD con *failover* automático.
4. Repartir lecturas entre réplicas.
5. Recuperar la base a un instante pasado.
6. Repartiendo `max_connections` entre servicios y réplicas con reserva.
7. `read mysql-db-systems`.
8. Que el pool reconecte (validación y reintentos).
9. Justo después de una escritura que el usuario espera ver.
10. Con `deletion_policy` (protección y respaldo final).

## Ejercicios
1. Reparte 1.000 conexiones entre catálogo (8 réplicas), pedidos (6) y reportes (2).
2. Diseña qué consultas del reporte de ventas deben ir a HeatWave.
3. Escribe el procedimiento de prueba de PITR trimestral.
