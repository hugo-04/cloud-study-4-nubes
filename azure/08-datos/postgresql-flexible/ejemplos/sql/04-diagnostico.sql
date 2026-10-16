-- PostgreSQL Flexible Server · diagnóstico (ejecutar como administrador o con pg_monitor).
-- Requiere azure.extensions con pg_stat_statements y shared_preload_libraries que lo incluya.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 1) Consultas que más tiempo total consumen
SELECT left(query, 120) AS consulta, calls AS ejecuciones,
       round(total_exec_time::numeric, 1) AS total_ms,
       round(mean_exec_time::numeric, 2) AS promedio_ms,
       rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- 2) Conexiones por aplicación, estado y rol (¿quién abre tantas?)
SELECT usename, application_name, state, count(*) AS conexiones
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY usename, application_name, state
ORDER BY conexiones DESC;

-- 3) Transacciones abiertas hace mucho (retrasan autovacuum y bloquean)
SELECT pid, usename, application_name, state, now() - xact_start AS antiguedad, left(query, 100) AS ultima_consulta
FROM pg_stat_activity
WHERE xact_start IS NOT NULL AND now() - xact_start > interval '30 seconds'
ORDER BY xact_start;

-- 4) Quién bloquea a quién
SELECT bloqueado.pid AS pid_bloqueado, left(bloqueado.query, 80) AS consulta_bloqueada,
       bloqueador.pid AS pid_bloqueador, left(bloqueador.query, 80) AS consulta_bloqueadora
FROM pg_stat_activity AS bloqueado
JOIN LATERAL unnest(pg_blocking_pids(bloqueado.pid)) AS b (pid) ON true
JOIN pg_stat_activity AS bloqueador ON bloqueador.pid = b.pid;

-- 5) Tablas con más versiones muertas (necesitan autovacuum)
SELECT schemaname, relname, n_live_tup AS filas_vivas, n_dead_tup AS filas_muertas,
       round(100.0 * n_dead_tup / greatest(n_live_tup + n_dead_tup, 1), 1) AS pct_muertas,
       last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 10;

-- 6) Índices que no se usan (candidatos a eliminar: cuestan escrituras y espacio)
SELECT s.schemaname, s.relname AS tabla, s.indexrelname AS indice, s.idx_scan AS usos,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS tamano
FROM pg_stat_user_indexes AS s
JOIN pg_index AS i ON i.indexrelid = s.indexrelid
WHERE s.idx_scan = 0 AND NOT i.indisunique
ORDER BY pg_relation_size(s.indexrelid) DESC
LIMIT 10;

-- 7) Tamaño de las tablas e índices
SELECT n.nspname AS esquema, c.relname AS tabla,
       pg_size_pretty(pg_table_size(c.oid)) AS tabla_tamano,
       pg_size_pretty(pg_indexes_size(c.oid)) AS indices_tamano
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 10;

-- 8) Retraso de las réplicas (ejecutar en el primario)
SELECT application_name, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS bytes_de_retraso,
       replay_lag
FROM pg_stat_replication;

-- 9) Ratio de aciertos de caché (debería estar > 99 % en cargas típicas)
SELECT datname,
       round(100.0 * blks_hit / greatest(blks_hit + blks_read, 1), 2) AS pct_aciertos_cache
FROM pg_stat_database
WHERE datname = current_database();

-- 10) Plan de una consulta (el mejor primer paso ante lentitud)
-- EXPLAIN (ANALYZE, BUFFERS, VERBOSE) SELECT * FROM ventas.pedido WHERE cliente_id = 'u-42' ORDER BY id DESC LIMIT 50;
