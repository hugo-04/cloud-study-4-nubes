-- Azure SQL Database · diagnóstico de rendimiento y bloqueos (T-SQL).
-- Ejecutar con un usuario con VIEW DATABASE STATE (o db_owner / administrador).

-- 1) Consultas que más CPU consumieron en las últimas horas (Query Store)
SELECT TOP (10)
    q.query_id,
    SUBSTRING(qt.query_sql_text, 1, 200)                         AS consulta,
    SUM(rs.count_executions)                                     AS ejecuciones,
    CAST(SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS decimal(18, 1)) AS cpu_total_ms,
    CAST(AVG(rs.avg_duration) / 1000.0 AS decimal(18, 1))        AS duracion_prom_ms
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS i ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE i.start_time > DATEADD(HOUR, -6, SYSUTCDATETIME())
GROUP BY q.query_id, SUBSTRING(qt.query_sql_text, 1, 200)
ORDER BY cpu_total_ms DESC;

-- 2) Consultas con más de un plan (candidatas a "plan regresado"; se puede forzar el bueno)
SELECT q.query_id, COUNT(DISTINCT p.plan_id) AS planes
FROM sys.query_store_query AS q
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
GROUP BY q.query_id
HAVING COUNT(DISTINCT p.plan_id) > 1
ORDER BY planes DESC;
-- EXEC sp_query_store_force_plan @query_id = 123, @plan_id = 456;

-- 3) Sesiones bloqueadas y quién las bloquea
SELECT r.session_id, r.blocking_session_id, r.wait_type, r.wait_time AS espera_ms,
       DB_NAME(r.database_id) AS base, SUBSTRING(t.text, 1, 200) AS sql_actual
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0;

-- 4) Transacciones abiertas hace mucho (suelen ser la causa de bloqueos)
SELECT s.session_id, s.login_name, s.host_name, s.program_name, t.transaction_begin_time,
       DATEDIFF(SECOND, t.transaction_begin_time, SYSUTCDATETIME()) AS segundos_abierta
FROM sys.dm_tran_active_transactions AS t
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = t.transaction_id
JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
WHERE t.transaction_begin_time < DATEADD(SECOND, -30, SYSUTCDATETIME())
ORDER BY t.transaction_begin_time;

-- 5) Índices que el motor sugiere (revisar antes de crear: cada índice cuesta en escrituras)
SELECT TOP (10)
    CAST(mid.statement AS nvarchar(300)) AS tabla,
    mid.equality_columns, mid.inequality_columns, mid.included_columns,
    migs.user_seeks, CAST(migs.avg_user_impact AS decimal(5, 1)) AS mejora_estimada_pct
FROM sys.dm_db_missing_index_details AS mid
JOIN sys.dm_db_missing_index_groups AS mig ON mig.index_handle = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats AS migs ON migs.group_handle = mig.index_group_handle
ORDER BY migs.user_seeks * migs.avg_user_impact DESC;

-- 6) Uso de recursos del último rato (cada 15 s): CPU, E/S de datos, E/S de registro, workers, sesiones
SELECT TOP (20) end_time, avg_cpu_percent, avg_data_io_percent, avg_log_write_percent,
       max_worker_percent, max_session_percent
FROM sys.dm_db_resource_stats
ORDER BY end_time DESC;

-- 7) Conexiones activas por aplicación/identidad (¿cuántas abre cada microservicio?)
SELECT login_name, program_name, host_name, COUNT(*) AS conexiones
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name, program_name, host_name
ORDER BY conexiones DESC;

-- 8) Tamaño de las tablas
SELECT s.name AS esquema, t.name AS tabla, SUM(ps.row_count) AS filas,
       CAST(SUM(ps.reserved_page_count) * 8 / 1024.0 AS decimal(18, 1)) AS mb
FROM sys.dm_db_partition_stats AS ps
JOIN sys.tables AS t ON t.object_id = ps.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE ps.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY mb DESC;
